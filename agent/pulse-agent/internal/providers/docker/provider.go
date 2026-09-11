package docker

import (
	"context"
	"fmt"
	"strings"
	"time"

	dockerclient "github.com/pulse/pulse-agent/internal/docker"
	"github.com/pulse/pulse-agent/internal/providers"
)

type DockerProvider struct {
	client dockerclient.Controller
}

func NewProvider(client dockerclient.Controller) *DockerProvider {
	if client == nil {
		client = dockerclient.NewClient()
	}
	return &DockerProvider{
		client: client,
	}
}

func (p *DockerProvider) Type() string {
	return "docker"
}

func (p *DockerProvider) Capabilities() []providers.ProviderCapability {
	return []providers.ProviderCapability{
		providers.CapDiscovery,
		providers.CapHealth,
		providers.CapMetrics,
		providers.CapActions,
		providers.CapLogs,
	}
}

func (p *DockerProvider) Discover(ctx context.Context) ([]providers.DiscoveredService, error) {
	status, err := p.client.GetStatus()
	if err != nil {
		return nil, err
	}
	if !status.Available {
		return []providers.DiscoveredService{}, nil
	}

	var results []providers.DiscoveredService
	for _, c := range status.Containers {
		displayName := strings.TrimPrefix(c.Name, "/")

		results = append(results, providers.DiscoveredService{
			ID:           c.ID,
			ProviderType: "docker",
			Name:         displayName,
			Description:  fmt.Sprintf("Image: %s | State: %s", c.Image, c.State),
			Status:       c.State,
			Metadata: map[string]string{
				"container_id": c.ID,
				"image":        c.Image,
				"state":        c.State,
				"status":       c.Status,
			},
		})
	}

	return results, nil
}

func (p *DockerProvider) Health(ctx context.Context, target string) (providers.HealthResult, error) {
	now := time.Now().UTC()
	status, err := p.client.GetStatus()
	if err != nil {
		return providers.HealthResult{
			ID:          target,
			Status:      "unknown",
			Message:     fmt.Sprintf("failed to query docker: %v", err),
			LastChecked: now,
		}, nil
	}

	if !status.Available {
		return providers.HealthResult{
			ID:          target,
			Status:      "down",
			Message:     "Docker daemon not running or socket unavailable",
			LastChecked: now,
		}, nil
	}

	normTarget := strings.TrimPrefix(target, "/")
	for _, c := range status.Containers {
		cName := strings.TrimPrefix(c.Name, "/")
		if c.ID == target || strings.HasPrefix(c.ID, target) || cName == normTarget {
			switch strings.ToLower(c.State) {
			case "running":
				return providers.HealthResult{
					ID:          target,
					Status:      "healthy",
					Message:     fmt.Sprintf("Container is running (%s)", c.Status),
					LastChecked: now,
				}, nil
			case "paused", "restarting":
				return providers.HealthResult{
					ID:          target,
					Status:      "warning",
					Message:     fmt.Sprintf("Container is %s", c.State),
					LastChecked: now,
				}, nil
			case "exited", "dead":
				return providers.HealthResult{
					ID:          target,
					Status:      "down",
					Message:     fmt.Sprintf("Container is %s (%s)", c.State, c.Status),
					LastChecked: now,
				}, nil
			default:
				return providers.HealthResult{
					ID:          target,
					Status:      "unknown",
					Message:     fmt.Sprintf("Container state: %s", c.State),
					LastChecked: now,
				}, nil
			}
		}
	}

	return providers.HealthResult{
		ID:          target,
		Status:      "unknown",
		Message:     "Container not found",
		LastChecked: now,
	}, nil
}
