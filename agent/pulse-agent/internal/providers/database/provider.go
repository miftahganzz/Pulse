package database

import (
	"context"
	"time"

	"github.com/pulse/pulse-agent/internal/providers"
)

type DatabaseConfig struct {
	Type     string `json:"type"` // postgres, redis, mysql, etc.
	Host     string `json:"host"`
	Port     int    `json:"port"`
	User     string `json:"user,omitempty"`
	Password string `json:"password,omitempty"`
	Database string `json:"database,omitempty"`
	SSLMode  string `json:"ssl_mode,omitempty"`
}

type DatabaseMetrics struct {
	ResponseTimeMs int64          `json:"response_time_ms"`
	Version        string         `json:"version,omitempty"`
	Metrics        map[string]any `json:"metrics"`
	LastChecked    time.Time      `json:"last_checked"`
}

type DatabaseProvider interface {
	providers.Provider
	Probe(ctx context.Context, config DatabaseConfig) (providers.HealthResult, *DatabaseMetrics, error)
}
