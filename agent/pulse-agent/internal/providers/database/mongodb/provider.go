package mongodb

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

type MongoDBProvider struct{}

func NewProvider() *MongoDBProvider {
	return &MongoDBProvider{}
}

func (p *MongoDBProvider) Type() string {
	return "mongodb"
}

func (p *MongoDBProvider) Capabilities() []providers.ProviderCapability {
	return []providers.ProviderCapability{
		providers.CapHealth,
		providers.CapMetrics,
	}
}

func (p *MongoDBProvider) Discover(ctx context.Context) ([]providers.DiscoveredService, error) {
	return []providers.DiscoveredService{}, nil
}

func (p *MongoDBProvider) Health(ctx context.Context, target string) (providers.HealthResult, error) {
	host := "127.0.0.1"
	port := 27017

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
		Type: "mongodb",
		Host: host,
		Port: port,
	}

	health, _, err := p.Probe(ctx, cfg)
	return health, err
}

func (p *MongoDBProvider) Probe(ctx context.Context, cfg database.DatabaseConfig) (providers.HealthResult, *database.DatabaseMetrics, error) {
	now := time.Now().UTC()
	start := time.Now()

	host := cfg.Host
	if host == "" {
		host = "127.0.0.1"
	}
	port := cfg.Port
	if port == 0 {
		port = 27017
	}

	addr := fmt.Sprintf("%s:%d", host, port)
	dialer := net.Dialer{Timeout: 3 * time.Second}
	conn, err := dialer.DialContext(ctx, "tcp", addr)
	latency := time.Since(start).Milliseconds()

	if err != nil {
		return providers.HealthResult{
			ID:          addr,
			Status:      "down",
			Message:     fmt.Sprintf("MongoDB connection failed: %v", err),
			LatencyMs:   latency,
			LastChecked: now,
		}, nil, nil
	}
	defer conn.Close()

	// Pure Go wire protocol `isMaster` / `hello` OP_MSG or basic TCP port reachability
	version := "MongoDB"

	return providers.HealthResult{
		ID:        addr,
		Status:    "healthy",
		Message:   fmt.Sprintf("MongoDB port reachable (%d ms)", latency),
		LatencyMs: latency,
		Metrics: map[string]any{
			"version":   version,
			"reachable": true,
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
