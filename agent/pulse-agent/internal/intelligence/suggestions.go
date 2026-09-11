package intelligence

import (
	"context"
	"fmt"
	"net"
	"strings"
	"time"

	"github.com/pulse/pulse-agent/internal/docker"
	"github.com/pulse/pulse-agent/internal/processes"
	"github.com/pulse/pulse-agent/internal/services"
)

// DependencyType describes whether it is a database, cache, proxy, or upstream dependency
type DependencyType string

const (
	DepDatabase DependencyType = "database"
	DepCache    DependencyType = "cache"
	DepProxy    DependencyType = "proxy"
	DepUpstream DependencyType = "upstream"
)

// SuggestedDependency represents a suggested edge between two discovered components
type SuggestedDependency struct {
	SourceID       string         `json:"source_id"`
	SourceName     string         `json:"source_name"`
	TargetID       string         `json:"target_id"`
	TargetName     string         `json:"target_name"`
	DependencyType DependencyType `json:"dependency_type"`
	Reason         string         `json:"reason"`
	Port           int            `json:"port"`
	Confidence     int            `json:"confidence"` // 0-100
}

// Detector analyzes running services and network listeners to propose dependencies
type Detector struct {
	dockerCtrl docker.Controller
	procColl   processes.Collector
	svcColl    services.Collector
}

// NewDetector creates an instance of Detector
func NewDetector(dockerCtrl docker.Controller, procColl processes.Collector, svcColl services.Collector) *Detector {
	return &Detector{
		dockerCtrl: dockerCtrl,
		procColl:   procColl,
		svcColl:    svcColl,
	}
}

// Common known service ports
var standardPorts = map[int]struct {
	name    string
	depType DependencyType
}{
	5432:  {name: "PostgreSQL", depType: DepDatabase},
	6379:  {name: "Redis", depType: DepCache},
	3306:  {name: "MySQL", depType: DepDatabase},
	33060: {name: "MySQL", depType: DepDatabase},
	27017: {name: "MongoDB", depType: DepDatabase},
	80:    {name: "HTTP / Web", depType: DepProxy},
	443:   {name: "HTTPS / Web", depType: DepProxy},
}

// DetectSuggestedDependencies scans open ports and correlates running containers/processes
func (d *Detector) DetectSuggestedDependencies(ctx context.Context) ([]SuggestedDependency, error) {
	var suggestions []SuggestedDependency

	// 1. Probe local ports to see what services are actually listening
	openPorts := make(map[int]bool)
	for port := range standardPorts {
		conn, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), 200*time.Millisecond)
		if err == nil {
			_ = conn.Close()
			openPorts[port] = true
		}
	}

	// 2. Inspect Docker containers
	var containers []docker.ContainerInfo
	if d.dockerCtrl != nil {
		if status, err := d.dockerCtrl.GetStatus(); err == nil && status != nil {
			containers = status.Containers
		}
	}

	// Find DB / Cache containers
	var dbContainers []docker.ContainerInfo
	var appContainers []docker.ContainerInfo

	for _, c := range containers {
		cNameLower := strings.ToLower(c.Name)
		cImgLower := strings.ToLower(c.Image)

		if strings.Contains(cNameLower, "postgres") || strings.Contains(cImgLower, "postgres") ||
			strings.Contains(cNameLower, "redis") || strings.Contains(cImgLower, "redis") ||
			strings.Contains(cNameLower, "mysql") || strings.Contains(cImgLower, "mysql") ||
			strings.Contains(cNameLower, "mongo") || strings.Contains(cImgLower, "mongo") {
			dbContainers = append(dbContainers, c)
		} else if strings.Contains(cNameLower, "api") || strings.Contains(cNameLower, "web") ||
			strings.Contains(cNameLower, "backend") || strings.Contains(cNameLower, "app") ||
			strings.Contains(cNameLower, "worker") {
			appContainers = append(appContainers, c)
		}
	}

	// Cross-correlate app containers to DB containers
	for _, app := range appContainers {
		for _, db := range dbContainers {
			dbLower := strings.ToLower(db.Name)
			depType := DepDatabase
			reason := fmt.Sprintf("Container %s typically connects to %s", app.Name, db.Name)
			port := 0

			if strings.Contains(dbLower, "redis") {
				depType = DepCache
				port = 6379
				reason = fmt.Sprintf("App %s detected alongside cache %s (port %d)", app.Name, db.Name, port)
			} else if strings.Contains(dbLower, "postgres") {
				depType = DepDatabase
				port = 5432
				reason = fmt.Sprintf("App %s detected alongside database %s (port %d)", app.Name, db.Name, port)
			} else if strings.Contains(dbLower, "mysql") {
				depType = DepDatabase
				port = 3306
				reason = fmt.Sprintf("App %s detected alongside database %s (port %d)", app.Name, db.Name, port)
			} else if strings.Contains(dbLower, "mongo") {
				depType = DepDatabase
				port = 27017
				reason = fmt.Sprintf("App %s detected alongside MongoDB %s (port %d)", app.Name, db.Name, port)
			}

			confidence := 80
			if port > 0 && openPorts[port] {
				confidence = 95
				reason += " [Port Active]"
			}

			suggestions = append(suggestions, SuggestedDependency{
				SourceID:       "docker:" + app.ID,
				SourceName:     app.Name,
				TargetID:       "docker:" + db.ID,
				TargetName:     db.Name,
				DependencyType: depType,
				Reason:         reason,
				Port:           port,
				Confidence:     confidence,
			})
		}
	}

	// 3. If local ports like Redis/Postgres are open but no container is mapped, check processes
	if d.procColl != nil {
		if procs, err := d.procColl.CollectProcesses(50, "cpu"); err == nil {
			for _, p := range procs {
				pNameLower := strings.ToLower(p.Name)
				if strings.Contains(pNameLower, "api") || strings.Contains(pNameLower, "node") || strings.Contains(pNameLower, "python") {
					if openPorts[5432] {
						suggestions = append(suggestions, SuggestedDependency{
							SourceID:       fmt.Sprintf("process:%d", p.PID),
							SourceName:     fmt.Sprintf("%s (pid %d)", p.Name, p.PID),
							TargetID:       "systemd:postgresql",
							TargetName:     "PostgreSQL",
							DependencyType: DepDatabase,
							Reason:         "Process running while PostgreSQL port 5432 is actively listening",
							Port:           5432,
							Confidence:     85,
						})
					}
					if openPorts[6379] {
						suggestions = append(suggestions, SuggestedDependency{
							SourceID:       fmt.Sprintf("process:%d", p.PID),
							SourceName:     fmt.Sprintf("%s (pid %d)", p.Name, p.PID),
							TargetID:       "systemd:redis-server",
							TargetName:     "Redis",
							DependencyType: DepCache,
							Reason:         "Process running while Redis port 6379 is actively listening",
							Port:           6379,
							Confidence:     85,
						})
					}
				}
			}
		}
	}

	return suggestions, nil
}
