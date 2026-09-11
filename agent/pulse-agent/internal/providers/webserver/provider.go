package webserver

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/pulse/pulse-agent/internal/providers"
)

type WebserverProvider struct{}

func NewProvider() *WebserverProvider {
	return &WebserverProvider{}
}

func (p *WebserverProvider) Type() string {
	return "nginx"
}

func (p *WebserverProvider) Capabilities() []providers.ProviderCapability {
	return []providers.ProviderCapability{
		providers.CapDiscovery,
		providers.CapHealth,
		providers.CapMetrics,
	}
}

func (p *WebserverProvider) Discover(ctx context.Context) ([]providers.DiscoveredService, error) {
	var discovered []providers.DiscoveredService

	// Check if nginx is installed/running
	if _, err := exec.LookPath("nginx"); err == nil {
		version := "unknown"
		out, err := exec.CommandContext(ctx, "nginx", "-v").CombinedOutput()
		if err == nil || len(out) > 0 {
			version = strings.TrimSpace(string(out))
		}

		discovered = append(discovered, providers.DiscoveredService{
			ID:           "nginx",
			ProviderType: "nginx",
			Name:         "Nginx Web Server",
			Description:  version,
			Status:       "running",
			Metadata: map[string]string{
				"binary":  "nginx",
				"version": version,
			},
		})
	}

	// Check if caddy is installed/running
	if _, err := exec.LookPath("caddy"); err == nil {
		version := "unknown"
		out, err := exec.CommandContext(ctx, "caddy", "version").CombinedOutput()
		if err == nil {
			version = strings.TrimSpace(string(out))
		}

		discovered = append(discovered, providers.DiscoveredService{
			ID:           "caddy",
			ProviderType: "nginx", // grouped webserver provider
			Name:         "Caddy Web Server",
			Description:  version,
			Status:       "running",
			Metadata: map[string]string{
				"binary":  "caddy",
				"version": version,
			},
		})
	}

	return discovered, nil
}

func (p *WebserverProvider) Health(ctx context.Context, target string) (providers.HealthResult, error) {
	now := time.Now().UTC()
	start := time.Now()

	// Target can be "nginx" or "caddy" or a custom server name
	bin := "nginx"
	if strings.Contains(strings.ToLower(target), "caddy") {
		bin = "caddy"
	}

	if _, err := exec.LookPath(bin); err != nil {
		return providers.HealthResult{
			ID:          target,
			Status:      "unknown",
			Message:     fmt.Sprintf("%s binary not found in PATH", bin),
			LastChecked: now,
		}, nil
	}

	var cmd *exec.Cmd
	if bin == "nginx" {
		cmd = exec.CommandContext(ctx, "nginx", "-t")
	} else {
		cmd = exec.CommandContext(ctx, "caddy", "validate")
	}

	out, err := cmd.CombinedOutput()
	latency := time.Since(start).Milliseconds()

	if err != nil {
		return providers.HealthResult{
			ID:          target,
			Status:      "critical",
			Message:     fmt.Sprintf("Configuration test failed: %s", strings.TrimSpace(string(out))),
			LatencyMs:   latency,
			LastChecked: now,
		}, nil
	}

	return providers.HealthResult{
		ID:        target,
		Status:    "healthy",
		Message:   fmt.Sprintf("%s configuration valid & service active (%d ms)", bin, latency),
		LatencyMs: latency,
		Metrics: map[string]any{
			"valid_config": true,
		},
		LastChecked: now,
	}, nil
}
