package tcp

import (
	"context"
	"fmt"
	"net"
	"time"

	"github.com/pulse/pulse-agent/internal/providers"
)

type TCPProvider struct {
	dialer *net.Dialer
}

func NewProvider() *TCPProvider {
	return &TCPProvider{
		dialer: &net.Dialer{
			Timeout: 5 * time.Second,
		},
	}
}

func (p *TCPProvider) Type() string {
	return "tcp"
}

func (p *TCPProvider) Capabilities() []providers.ProviderCapability {
	return []providers.ProviderCapability{
		providers.CapHealth,
		providers.CapMetrics,
	}
}

func (p *TCPProvider) Discover(ctx context.Context) ([]providers.DiscoveredService, error) {
	// TCP monitors are defined as user probes
	return []providers.DiscoveredService{}, nil
}

func (p *TCPProvider) Health(ctx context.Context, target string) (providers.HealthResult, error) {
	now := time.Now().UTC()
	start := time.Now()

	conn, err := p.dialer.DialContext(ctx, "tcp", target)
	latency := time.Since(start).Milliseconds()

	if err != nil {
		return providers.HealthResult{
			ID:          target,
			Status:      "down",
			Message:     fmt.Sprintf("TCP connect failed: %v", err),
			LatencyMs:   latency,
			LastChecked: now,
		}, nil
	}
	defer conn.Close()

	return providers.HealthResult{
		ID:          target,
		Status:      "healthy",
		Message:     fmt.Sprintf("TCP port reachable (%d ms)", latency),
		LatencyMs:   latency,
		LastChecked: now,
	}, nil
}
