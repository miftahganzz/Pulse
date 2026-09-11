package redis

import (
	"bufio"
	"context"
	"fmt"
	"net"
	"strconv"
	"strings"
	"time"

	"github.com/pulse/pulse-agent/internal/providers"
	"github.com/pulse/pulse-agent/internal/providers/database"
)

type RedisProvider struct{}

func NewProvider() *RedisProvider {
	return &RedisProvider{}
}

func (p *RedisProvider) Type() string {
	return "redis"
}

func (p *RedisProvider) Capabilities() []providers.ProviderCapability {
	return []providers.ProviderCapability{
		providers.CapHealth,
		providers.CapMetrics,
	}
}

func (p *RedisProvider) Discover(ctx context.Context) ([]providers.DiscoveredService, error) {
	// Probing Redis default local ports if available
	return []providers.DiscoveredService{}, nil
}

func (p *RedisProvider) Health(ctx context.Context, target string) (providers.HealthResult, error) {
	// Target format: host:port or just port or host:port:password
	host := "127.0.0.1"
	port := 6379
	pass := ""

	parts := strings.Split(target, ":")
	if len(parts) >= 2 {
		host = parts[0]
		if pNum, err := strconv.Atoi(parts[1]); err == nil {
			port = pNum
		}
		if len(parts) >= 3 {
			pass = parts[2]
		}
	} else if len(parts) == 1 && parts[0] != "" {
		if pNum, err := strconv.Atoi(parts[0]); err == nil {
			port = pNum
		} else {
			host = parts[0]
		}
	}

	cfg := database.DatabaseConfig{
		Type:     "redis",
		Host:     host,
		Port:     port,
		Password: pass,
	}

	h, _, err := p.Probe(ctx, cfg)
	return h, err
}

func (p *RedisProvider) Probe(ctx context.Context, cfg database.DatabaseConfig) (providers.HealthResult, *database.DatabaseMetrics, error) {
	now := time.Now().UTC()
	addr := fmt.Sprintf("%s:%d", cfg.Host, cfg.Port)

	dialer := net.Dialer{Timeout: 5 * time.Second}
	start := time.Now()
	conn, err := dialer.DialContext(ctx, "tcp", addr)
	if err != nil {
		return providers.HealthResult{
			ID:          addr,
			Status:      "down",
			Message:     fmt.Sprintf("Connection failed: %v", err),
			LastChecked: now,
		}, nil, nil
	}
	defer conn.Close()

	_ = conn.SetDeadline(time.Now().Add(5 * time.Second))
	reader := bufio.NewReader(conn)

	// If password provided, send AUTH
	if cfg.Password != "" {
		authCmd := fmt.Sprintf("*2\r\n$4\r\nAUTH\r\n$%d\r\n%s\r\n", len(cfg.Password), cfg.Password)
		if _, err := conn.Write([]byte(authCmd)); err != nil {
			return providers.HealthResult{
				ID:          addr,
				Status:      "critical",
				Message:     fmt.Sprintf("Auth write error: %v", err),
				LastChecked: now,
			}, nil, nil
		}
		authResp, err := reader.ReadString('\n')
		if err != nil || !strings.HasPrefix(authResp, "+OK") {
			return providers.HealthResult{
				ID:          addr,
				Status:      "critical",
				Message:     fmt.Sprintf("Authentication failed: %s", strings.TrimSpace(authResp)),
				LastChecked: now,
			}, nil, nil
		}
	}

	// Send PING
	if _, err := conn.Write([]byte("*1\r\n$4\r\nPING\r\n")); err != nil {
		return providers.HealthResult{
			ID:          addr,
			Status:      "critical",
			Message:     fmt.Sprintf("PING write error: %v", err),
			LastChecked: now,
		}, nil, nil
	}
	pingResp, err := reader.ReadString('\n')
	latency := time.Since(start).Milliseconds()

	if err != nil || !strings.HasPrefix(pingResp, "+PONG") {
		return providers.HealthResult{
			ID:          addr,
			Status:      "critical",
			Message:     fmt.Sprintf("Unexpected PING response: %s", strings.TrimSpace(pingResp)),
			LatencyMs:   latency,
			LastChecked: now,
		}, nil, nil
	}

	// Send INFO
	metricsData := make(map[string]any)
	version := "unknown"

	if _, err := conn.Write([]byte("*1\r\n$4\r\nINFO\r\n")); err == nil {
		infoRespHeader, err := reader.ReadString('\n')
		if err == nil && strings.HasPrefix(infoRespHeader, "$") {
			byteCount, _ := strconv.Atoi(strings.TrimSpace(infoRespHeader[1:]))
			if byteCount > 0 {
				buf := make([]byte, byteCount)
				totalRead := 0
				for totalRead < byteCount {
					n, rErr := reader.Read(buf[totalRead:])
					if rErr != nil {
						break
					}
					totalRead += n
				}
				infoText := string(buf[:totalRead])
				scanner := bufio.NewScanner(strings.NewReader(infoText))
				for scanner.Scan() {
					line := strings.TrimSpace(scanner.Text())
					if line == "" || strings.HasPrefix(line, "#") {
						continue
					}
					kv := strings.SplitN(line, ":", 2)
					if len(kv) == 2 {
						k := kv[0]
						v := kv[1]
						switch k {
						case "redis_version":
							version = v
						case "connected_clients":
							if num, err := strconv.Atoi(v); err == nil {
								metricsData["connected_clients"] = num
							}
						case "used_memory":
							if num, err := strconv.ParseInt(v, 10, 64); err == nil {
								metricsData["used_memory_bytes"] = num
								metricsData["used_memory_human"] = fmt.Sprintf("%.1f MB", float64(num)/(1024*1024))
							}
						case "used_memory_peak":
							if num, err := strconv.ParseInt(v, 10, 64); err == nil {
								metricsData["used_memory_peak_bytes"] = num
							}
						case "uptime_in_seconds":
							if num, err := strconv.ParseInt(v, 10, 64); err == nil {
								metricsData["uptime_seconds"] = num
							}
						}
						if strings.HasPrefix(k, "db") && strings.Contains(v, "keys=") {
							metricsData[k] = v
						}
					}
				}
			}
		}
	}

	metricsData["response_time_ms"] = latency
	metricsData["version"] = version

	clientCount := 0
	if c, ok := metricsData["connected_clients"].(int); ok {
		clientCount = c
	}

	memStr := ""
	if m, ok := metricsData["used_memory_human"].(string); ok {
		memStr = fmt.Sprintf(", Mem: %s", m)
	}

	msg := fmt.Sprintf("Redis %s healthy (%d ms, Clients: %d%s)", version, latency, clientCount, memStr)

	return providers.HealthResult{
		ID:          addr,
		Status:      "healthy",
		Message:     msg,
		LatencyMs:   latency,
		LastChecked: now,
	}, &database.DatabaseMetrics{
		ResponseTimeMs: latency,
		Version:        version,
		Metrics:        metricsData,
		LastChecked:    now,
	}, nil
}
