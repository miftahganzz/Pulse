package pm2

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/pulse/pulse-agent/internal/providers"
)

type PM2Process struct {
	PID    int    `json:"pid"`
	Name   string `json:"name"`
	PMID   int    `json:"pm_id"`
	Monit  PM2Monit `json:"monit"`
	PM2Env PM2Env   `json:"pm2_env"`
}

type PM2Monit struct {
	Memory int64   `json:"memory"`
	CPU    float64 `json:"cpu"`
}

type PM2Env struct {
	Status      string `json:"status"` // online, stopping, stopped, launched, errored, one-launch-status
	RestartTime int    `json:"restart_time"`
	Uptime      int64  `json:"pm_uptime"`
}

type PM2Provider struct {
	// pm2Path overrides default pm2 binary lookup if specified
	pm2Path string
}

func NewProvider() *PM2Provider {
	return &PM2Provider{}
}

func (p *PM2Provider) Type() string {
	return "pm2"
}

func (p *PM2Provider) Capabilities() []providers.ProviderCapability {
	return []providers.ProviderCapability{
		providers.CapDiscovery,
		providers.CapHealth,
		providers.CapMetrics,
		providers.CapActions,
		providers.CapLogs,
	}
}

func (p *PM2Provider) getPM2Cmd() (string, error) {
	if p.pm2Path != "" {
		return p.pm2Path, nil
	}
	path, err := exec.LookPath("pm2")
	if err == nil {
		return path, nil
	}

	// Common fallback locations
	home, _ := os.UserHomeDir()
	fallbacks := []string{
		"/usr/local/bin/pm2",
		"/usr/bin/pm2",
		filepath.Join(home, ".nvm/versions/node", "*", "bin/pm2"),
		filepath.Join(home, ".npm-global/bin/pm2"),
	}
	for _, fb := range fallbacks {
		matches, err := filepath.Glob(fb)
		if err == nil && len(matches) > 0 {
			return matches[0], nil
		}
	}

	return "", fmt.Errorf("pm2 binary not found")
}

func (p *PM2Provider) listProcesses(ctx context.Context) ([]PM2Process, error) {
	cmdPath, err := p.getPM2Cmd()
	if err != nil {
		return nil, err
	}

	cmd := exec.CommandContext(ctx, cmdPath, "jlist")
	out, err := cmd.Output()
	if err != nil {
		return nil, err
	}

	var procs []PM2Process
	if err := json.Unmarshal(out, &procs); err != nil {
		return nil, err
	}
	return procs, nil
}

func (p *PM2Provider) Discover(ctx context.Context) ([]providers.DiscoveredService, error) {
	procs, err := p.listProcesses(ctx)
	if err != nil {
		// If PM2 is not installed or running, return empty slice gracefully
		return []providers.DiscoveredService{}, nil
	}

	var results []providers.DiscoveredService
	for _, proc := range procs {
		desc := fmt.Sprintf("PM2 ID: %d | Restarts: %d", proc.PMID, proc.PM2Env.RestartTime)
		results = append(results, providers.DiscoveredService{
			ID:           fmt.Sprintf("pm2:%d:%s", proc.PMID, proc.Name),
			ProviderType: "pm2",
			Name:         proc.Name,
			Description:  desc,
			Status:       proc.PM2Env.Status,
			Metadata: map[string]string{
				"pm_id":   fmt.Sprintf("%d", proc.PMID),
				"status":  proc.PM2Env.Status,
				"memory":  fmt.Sprintf("%d", proc.Monit.Memory),
				"cpu":     fmt.Sprintf("%.1f", proc.Monit.CPU),
				"uptime":  fmt.Sprintf("%d", proc.PM2Env.Uptime),
			},
		})
	}

	return results, nil
}

func (p *PM2Provider) Health(ctx context.Context, target string) (providers.HealthResult, error) {
	now := time.Now().UTC()
	procs, err := p.listProcesses(ctx)
	if err != nil {
		return providers.HealthResult{
			ID:          target,
			Status:      "unknown",
			Message:     fmt.Sprintf("pm2 not accessible: %v", err),
			LastChecked: now,
		}, nil
	}

	for _, proc := range procs {
		if proc.Name == target || fmt.Sprintf("%d", proc.PMID) == target || fmt.Sprintf("pm2:%d:%s", proc.PMID, proc.Name) == target {
			switch strings.ToLower(proc.PM2Env.Status) {
			case "online":
				return providers.HealthResult{
					ID:          target,
					Status:      "healthy",
					Message:     fmt.Sprintf("PM2 process online (CPU: %.1f%%, Mem: %d MB)", proc.Monit.CPU, proc.Monit.Memory/(1024*1024)),
					LastChecked: now,
				}, nil
			case "errored":
				return providers.HealthResult{
					ID:          target,
					Status:      "critical",
					Message:     fmt.Sprintf("PM2 process errored (restarts: %d)", proc.PM2Env.RestartTime),
					LastChecked: now,
				}, nil
			case "stopped":
				return providers.HealthResult{
					ID:          target,
					Status:      "down",
					Message:     "PM2 process is stopped",
					LastChecked: now,
				}, nil
			default:
				return providers.HealthResult{
					ID:          target,
					Status:      "warning",
					Message:     fmt.Sprintf("PM2 process status: %s", proc.PM2Env.Status),
					LastChecked: now,
				}, nil
			}
		}
	}

	return providers.HealthResult{
		ID:          target,
		Status:      "unknown",
		Message:     "PM2 process not found",
		LastChecked: now,
	}, nil
}
