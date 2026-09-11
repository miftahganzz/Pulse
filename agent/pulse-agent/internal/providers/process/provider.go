package process

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/pulse/pulse-agent/internal/processes"
	"github.com/pulse/pulse-agent/internal/providers"
)

type ProcessProvider struct {
	collector processes.Collector
}

func NewProvider(collector processes.Collector) *ProcessProvider {
	if collector == nil {
		collector = processes.NewCollector()
	}
	return &ProcessProvider{
		collector: collector,
	}
}

func (p *ProcessProvider) Type() string {
	return "process"
}

func (p *ProcessProvider) Capabilities() []providers.ProviderCapability {
	return []providers.ProviderCapability{
		providers.CapDiscovery,
		providers.CapHealth,
		providers.CapMetrics,
	}
}

// Well-known important infrastructure processes that warrant discovery if running
var importantProcesses = map[string]string{
	"nginx":       "Nginx Web Server",
	"caddy":       "Caddy Web Server",
	"apache2":     "Apache HTTP Server",
	"httpd":       "Apache HTTP Server",
	"postgres":    "PostgreSQL Database",
	"mysqld":      "MySQL Server",
	"mariadbd":    "MariaDB Server",
	"redis-server": "Redis In-Memory Data Store",
	"memcached":   "Memcached In-Memory Cache",
	"mongod":      "MongoDB Database",
	"cloudflared": "Cloudflare Tunnel",
	"tailscaled":  "Tailscale VPN",
	"haproxy":     "HAProxy Load Balancer",
	"node":        "Node.js Runtime",
	"python":      "Python Process",
	"python3":     "Python Process",
	"java":        "Java Application",
	"go":          "Go Application",
	"ruby":        "Ruby Application",
}

func (p *ProcessProvider) Discover(ctx context.Context) ([]providers.DiscoveredService, error) {
	procs, err := p.collector.CollectProcesses(200, "cpu")
	if err != nil {
		return nil, err
	}

	seen := make(map[string]bool)
	var results []providers.DiscoveredService

	for _, proc := range procs {
		pName := strings.ToLower(proc.Name)
		if desc, isImportant := importantProcesses[pName]; isImportant {
			if seen[pName] {
				continue
			}
			seen[pName] = true

			results = append(results, providers.DiscoveredService{
				ID:           fmt.Sprintf("process:%s", pName),
				ProviderType: "process",
				Name:         proc.Name,
				Description:  fmt.Sprintf("%s (PID %d)", desc, proc.PID),
				Status:       "running",
				Metadata: map[string]string{
					"pid": fmt.Sprintf("%d", proc.PID),
					"cmd": proc.Command,
				},
			})
		}
	}

	return results, nil
}

func (p *ProcessProvider) Health(ctx context.Context, target string) (providers.HealthResult, error) {
	now := time.Now().UTC()
	procs, err := p.collector.CollectProcesses(500, "cpu")
	if err != nil {
		return providers.HealthResult{
			ID:          target,
			Status:      "unknown",
			Message:     fmt.Sprintf("failed to list processes: %v", err),
			LastChecked: now,
		}, nil
	}

	normTarget := strings.TrimPrefix(target, "process:")
	for _, proc := range procs {
		if strings.EqualFold(proc.Name, normTarget) || strings.Contains(strings.ToLower(proc.Command), strings.ToLower(normTarget)) {
			return providers.HealthResult{
				ID:          target,
				Status:      "healthy",
				Message:     fmt.Sprintf("Process running (PID %d, CPU %.1f%%, RSS %d MB)", proc.PID, proc.CPUPercent, proc.MemoryRSSBytes/(1024*1024)),
				LastChecked: now,
			}, nil
		}
	}

	return providers.HealthResult{
		ID:          target,
		Status:      "down",
		Message:     fmt.Sprintf("No running process matching '%s'", normTarget),
		LastChecked: now,
	}, nil
}
