package mysql

import (
	"context"
	"fmt"
	"net"
	"strconv"
	"strings"
	"time"

	"github.com/pulse/pulse-agent/internal/providers"
	"github.com/pulse/pulse-agent/internal/providers/database"
)

type MySQLProvider struct{}

func NewProvider() *MySQLProvider {
	return &MySQLProvider{}
}

func (p *MySQLProvider) Type() string {
	return "mysql"
}

func (p *MySQLProvider) Capabilities() []providers.ProviderCapability {
	return []providers.ProviderCapability{
		providers.CapHealth,
		providers.CapMetrics,
	}
}

func (p *MySQLProvider) Discover(ctx context.Context) ([]providers.DiscoveredService, error) {
	return []providers.DiscoveredService{}, nil
}

func (p *MySQLProvider) Health(ctx context.Context, target string) (providers.HealthResult, error) {
	host := "127.0.0.1"
	port := 3306

	parts := strings.Split(target, ":")
	if len(parts) >= 2 {
		host = parts[0]
		if pNum, err := strconv.Atoi(parts[1]); err == nil {
			port = pNum
		}
	} else if len(parts) == 1 && parts[0] != "" {
		host = parts[0]
	}

	cfg := database.DatabaseConfig{
		Type: "mysql",
		Host: host,
		Port: port,
	}

	health, _, err := p.Probe(ctx, cfg)
	return health, err
}

func (p *MySQLProvider) Probe(ctx context.Context, cfg database.DatabaseConfig) (providers.HealthResult, *database.DatabaseMetrics, error) {
	now := time.Now().UTC()
	start := time.Now()

	host := cfg.Host
	if host == "" {
		host = "127.0.0.1"
	}
	port := cfg.Port
	if port == 0 {
		port = 3306
	}

	addr := fmt.Sprintf("%s:%d", host, port)
	dialer := net.Dialer{Timeout: 3 * time.Second}
	conn, err := dialer.DialContext(ctx, "tcp", addr)
	latency := time.Since(start).Milliseconds()

	if err != nil {
		return providers.HealthResult{
			ID:          addr,
			Status:      "down",
			Message:     fmt.Sprintf("MySQL connection failed: %v", err),
			LatencyMs:   latency,
			LastChecked: now,
		}, nil, nil
	}
	defer conn.Close()

	// Read initial MySQL Initial Handshake Packet
	_ = conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	buf := make([]byte, 256)
	n, err := conn.Read(buf)
	if err != nil || n < 5 {
		return providers.HealthResult{
			ID:          addr,
			Status:      "healthy",
			Message:     fmt.Sprintf("MySQL port reachable (%d ms)", latency),
			LatencyMs:   latency,
			LastChecked: now,
		}, &database.DatabaseMetrics{
			ResponseTimeMs: latency,
			Version:        "MySQL/MariaDB",
			LastChecked:    now,
			Metrics: map[string]any{
				"reachable": true,
			},
		}, nil
	}

	// In MySQL protocol, packet bytes 4 is protocol version (usually 10), then null-terminated server version string
	version := "MySQL 8.x"
	if n > 5 && buf[4] == 10 {
		nullIdx := 5
		for nullIdx < n && buf[nullIdx] != 0 {
			nullIdx++
		}
		if nullIdx > 5 {
			version = string(buf[5:nullIdx])
		}
	}

	return providers.HealthResult{
		ID:        addr,
		Status:    "healthy",
		Message:   fmt.Sprintf("MySQL connected (%s) in %d ms", version, latency),
		LatencyMs: latency,
		Metrics: map[string]any{
			"version": version,
		},
		LastChecked: now,
	}, &database.DatabaseMetrics{
		ResponseTimeMs: latency,
		Version:        version,
		LastChecked:    now,
		Metrics: map[string]any{
			"version":   version,
			"reachable": true,
		},
	}, nil
}
