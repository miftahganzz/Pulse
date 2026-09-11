package systemd

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/pulse/pulse-agent/internal/providers"
	"github.com/pulse/pulse-agent/internal/services"
)

type SystemdProvider struct {
	collector services.Collector
}

func NewProvider(collector services.Collector) *SystemdProvider {
	if collector == nil {
		collector = services.NewCollector()
	}
	return &SystemdProvider{
		collector: collector,
	}
}

func (p *SystemdProvider) Type() string {
	return "systemd"
}

func (p *SystemdProvider) Capabilities() []providers.ProviderCapability {
	return []providers.ProviderCapability{
		providers.CapDiscovery,
		providers.CapHealth,
		providers.CapActions,
		providers.CapLogs,
	}
}

func (p *SystemdProvider) Discover(ctx context.Context) ([]providers.DiscoveredService, error) {
	svcList, err := p.collector.CollectServices()
	if err != nil {
		return nil, err
	}

	var results []providers.DiscoveredService
	for _, s := range svcList {
		status := s.ActiveState
		if s.SubState != "" && s.SubState != "running" {
			status = fmt.Sprintf("%s (%s)", s.ActiveState, s.SubState)
		}

		results = append(results, providers.DiscoveredService{
			ID:           s.Name,
			ProviderType: "systemd",
			Name:         s.Name,
			Description:  s.Description,
			Status:       status,
			Metadata: map[string]string{
				"load_state":   s.LoadState,
				"active_state": s.ActiveState,
				"sub_state":    s.SubState,
			},
		})
	}

	return results, nil
}

func (p *SystemdProvider) Health(ctx context.Context, target string) (providers.HealthResult, error) {
	now := time.Now().UTC()
	svcList, err := p.collector.CollectServices()
	if err != nil {
		return providers.HealthResult{
			ID:          target,
			Status:      "unknown",
			Message:     fmt.Sprintf("failed to query services: %v", err),
			LastChecked: now,
		}, nil
	}

	for _, s := range svcList {
		if s.Name == target || s.Name == target+".service" || strings.TrimSuffix(s.Name, ".service") == target {
			switch s.ActiveState {
			case "active":
				msg := fmt.Sprintf("Service is active (%s)", s.SubState)
				return providers.HealthResult{
					ID:          target,
					Status:      "healthy",
					Message:     msg,
					LastChecked: now,
				}, nil
			case "failed":
				return providers.HealthResult{
					ID:          target,
					Status:      "critical",
					Message:     fmt.Sprintf("Service failed (%s)", s.SubState),
					LastChecked: now,
				}, nil
			default:
				status := "down"
				if s.ActiveState == "activating" || s.ActiveState == "reloading" {
					status = "warning"
				}
				return providers.HealthResult{
					ID:          target,
					Status:      status,
					Message:     fmt.Sprintf("Service is %s (%s)", s.ActiveState, s.SubState),
					LastChecked: now,
				}, nil
			}
		}
	}

	return providers.HealthResult{
		ID:          target,
		Status:      "unknown",
		Message:     "Service unit not found",
		LastChecked: now,
	}, nil
}
