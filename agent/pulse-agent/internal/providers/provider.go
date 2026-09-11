package providers

import (
	"context"
	"time"
)

type ProviderCapability string

const (
	CapDiscovery ProviderCapability = "discovery"
	CapHealth    ProviderCapability = "health"
	CapMetrics   ProviderCapability = "metrics"
	CapActions   ProviderCapability = "actions"
	CapLogs      ProviderCapability = "logs"
)

type ProviderState string

const (
	StateAvailable        ProviderState = "available"
	StateUnavailable      ProviderState = "unavailable"
	StatePermissionDenied ProviderState = "permission_denied"
	StateUnsupported      ProviderState = "unsupported"
	StateError            ProviderState = "error"
)

type DiscoveredService struct {
	ID           string            `json:"id"`
	ProviderType string            `json:"provider_type"`
	Name         string            `json:"name"`
	Description  string            `json:"description,omitempty"`
	Status       string            `json:"status"` // running, stopped, failed, online, etc.
	Metadata     map[string]string `json:"metadata,omitempty"`
}

type HealthResult struct {
	ID          string         `json:"id"`
	Status      string         `json:"status"` // healthy, warning, critical, down, unknown
	Message     string         `json:"message"`
	LatencyMs   int64          `json:"latency_ms,omitempty"`
	Metrics     map[string]any `json:"metrics,omitempty"`
	LastChecked time.Time      `json:"last_checked"`
}

type MonitorRequest struct {
	ID             string            `json:"id"`
	Name           string            `json:"name"`
	Type           string            `json:"type"`   // systemd, docker, pm2, process, http, tcp, mysql, mongodb, nginx, cloudflared, custom
	Target         string            `json:"target"` // URL, host:port, unit name, container id/name, process name, command
	ExpectedBody   string            `json:"expected_body,omitempty"`
	ExpectedCode   int               `json:"expected_code,omitempty"`
	ExpectedOutput string            `json:"expected_output,omitempty"`
	Headers        map[string]string `json:"headers,omitempty"`
}

type Provider interface {
	Type() string
	Capabilities() []ProviderCapability
	Discover(ctx context.Context) ([]DiscoveredService, error)
	Health(ctx context.Context, target string) (HealthResult, error)
}
