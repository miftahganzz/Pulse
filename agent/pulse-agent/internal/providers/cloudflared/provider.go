package cloudflared

import (
	"context"
	"fmt"
	"net/http"
	"os/exec"
	"strings"
	"time"

	"github.com/pulse/pulse-agent/internal/providers"
)

type CloudflaredProvider struct {
	client *http.Client
}

func NewProvider() *CloudflaredProvider {
	return &CloudflaredProvider{
		client: &http.Client{
			Timeout: 3 * time.Second,
		},
	}
}

func (p *CloudflaredProvider) Type() string {
	return "cloudflared"
}

func (p *CloudflaredProvider) Capabilities() []providers.ProviderCapability {
	return []providers.ProviderCapability{
		providers.CapDiscovery,
		providers.CapHealth,
		providers.CapMetrics,
		providers.CapLogs,
	}
}

func (p *CloudflaredProvider) Discover(ctx context.Context) ([]providers.DiscoveredService, error) {
	if _, err := exec.LookPath("cloudflared"); err != nil {
		return []providers.DiscoveredService{}, nil
	}

	version := "unknown"
	out, err := exec.CommandContext(ctx, "cloudflared", "version").CombinedOutput()
	if err == nil || len(out) > 0 {
		version = strings.TrimSpace(string(out))
		if idx := strings.Index(version, " "); idx != -1 {
			version = strings.TrimSpace(version[idx:])
		}
	}

	return []providers.DiscoveredService{
		{
			ID:           "cloudflared",
			ProviderType: "cloudflared",
			Name:         "Cloudflare Tunnel",
			Description:  version,
			Status:       "running",
			Metadata: map[string]string{
				"binary":  "cloudflared",
				"version": version,
			},
		},
	}, nil
}

func (p *CloudflaredProvider) Health(ctx context.Context, target string) (providers.HealthResult, error) {
	now := time.Now().UTC()
	start := time.Now()

	// 1. Probe local metrics/health endpoint if cloudflared runs with metrics (default localhost:20202 or :60123)
	// Try standard cloudflared metrics ports
	metricsPorts := []string{"20202", "60123"}
	for _, port := range metricsPorts {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, fmt.Sprintf("http://127.0.0.1:%s/ready", port), nil)
		if err == nil {
			resp, err := p.client.Do(req)
			if err == nil {
				defer resp.Body.Close()
				latency := time.Since(start).Milliseconds()
				if resp.StatusCode == http.StatusOK {
					return providers.HealthResult{
						ID:        target,
						Status:    "healthy",
						Message:   fmt.Sprintf("Tunnel connected and healthy via metrics :%s (%d ms)", port, latency),
						LatencyMs: latency,
						Metrics: map[string]any{
							"metrics_port": port,
							"status":       "ready",
						},
						LastChecked: now,
					}, nil
				}
			}
		}
	}

	// 2. Fallback: check if cloudflared is running in process or systemctl is-active
	out, err := exec.CommandContext(ctx, "pgrep", "-f", "cloudflared").CombinedOutput()
	latency := time.Since(start).Milliseconds()
	if err == nil && len(strings.TrimSpace(string(out))) > 0 {
		// Process is alive but metrics port isn't listening -> Connected (legacy mode)
		return providers.HealthResult{
			ID:        target,
			Status:    "healthy",
			Message:   fmt.Sprintf("Cloudflare Tunnel process active (%d ms)", latency),
			LatencyMs: latency,
			Metrics: map[string]any{
				"process_running": true,
			},
			LastChecked: now,
		}, nil
	}

	return providers.HealthResult{
		ID:          target,
		Status:      "down",
		Message:     "Cloudflare tunnel process is not running",
		LatencyMs:   latency,
		LastChecked: now,
	}, nil
}
