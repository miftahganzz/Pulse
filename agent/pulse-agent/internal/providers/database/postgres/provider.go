package postgres

import (
	"bytes"
	"context"
	"crypto/md5"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"net"
	"strconv"
	"strings"
	"time"

	"github.com/pulse/pulse-agent/internal/providers"
	"github.com/pulse/pulse-agent/internal/providers/database"
)

type PostgresProvider struct{}

func NewProvider() *PostgresProvider {
	return &PostgresProvider{}
}

func (p *PostgresProvider) Type() string {
	return "postgres"
}

func (p *PostgresProvider) Capabilities() []providers.ProviderCapability {
	return []providers.ProviderCapability{
		providers.CapHealth,
		providers.CapMetrics,
	}
}

func (p *PostgresProvider) Discover(ctx context.Context) ([]providers.DiscoveredService, error) {
	return []providers.DiscoveredService{}, nil
}

func (p *PostgresProvider) Health(ctx context.Context, target string) (providers.HealthResult, error) {
	host := "127.0.0.1"
	port := 5432
	user := "postgres"
	db := "postgres"

	parts := strings.Split(target, ":")
	if len(parts) >= 2 {
		host = parts[0]
		if pNum, err := strconv.Atoi(parts[1]); err == nil {
			port = pNum
		}
	} else if len(parts) == 1 && parts[0] != "" {
		if pNum, err := strconv.Atoi(parts[0]); err == nil {
			port = pNum
		} else {
			host = parts[0]
		}
	}

	cfg := database.DatabaseConfig{
		Type:     "postgres",
		Host:     host,
		Port:     port,
		User:     user,
		Database: db,
	}

	h, _, err := p.Probe(ctx, cfg)
	return h, err
}

func (p *PostgresProvider) Probe(ctx context.Context, cfg database.DatabaseConfig) (providers.HealthResult, *database.DatabaseMetrics, error) {
	now := time.Now().UTC()
	if cfg.Host == "" {
		cfg.Host = "127.0.0.1"
	}
	if cfg.Port == 0 {
		cfg.Port = 5432
	}
	if cfg.User == "" {
		cfg.User = "postgres"
	}
	if cfg.Database == "" {
		cfg.Database = cfg.User
	}
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

	// 1. Send StartupMessage (Postgres protocol 3.0: 196608)
	var startupBuf bytes.Buffer
	// Protocol version 3.0: int32(196608)
	binary.Write(&startupBuf, binary.BigEndian, int32(196608))
	// Key-value params
	startupBuf.WriteString("user\x00")
	startupBuf.WriteString(cfg.User + "\x00")
	startupBuf.WriteString("database\x00")
	startupBuf.WriteString(cfg.Database + "\x00")
	startupBuf.WriteString("application_name\x00Pulse-Agent\x00\x00")

	msgLen := int32(startupBuf.Len() + 4)
	var packet bytes.Buffer
	binary.Write(&packet, binary.BigEndian, msgLen)
	packet.Write(startupBuf.Bytes())

	if _, err := conn.Write(packet.Bytes()); err != nil {
		return providers.HealthResult{
			ID:          addr,
			Status:      "critical",
			Message:     fmt.Sprintf("Startup message failed: %v", err),
			LastChecked: now,
		}, nil, nil
	}

	// 2. Read server response loop until ReadyForQuery ('Z') or ErrorResponse ('E')
	metricsData := make(map[string]any)
	version := "PostgreSQL"
	authSuccess := false

	header := make([]byte, 5)
	for {
		_, err := conn.Read(header)
		if err != nil {
			break
		}
		msgType := header[0]
		length := int(binary.BigEndian.Uint32(header[1:5])) - 4
		payload := make([]byte, length)
		if length > 0 {
			total := 0
			for total < length {
				n, err := conn.Read(payload[total:])
				if err != nil {
					break
				}
				total += n
			}
		}

		if msgType == 'R' { // Authentication
			authType := binary.BigEndian.Uint32(payload[:4])
			if authType == 0 { // Auth OK
				authSuccess = true
			} else if authType == 3 { // Cleartext password
				if cfg.Password == "" {
					return providers.HealthResult{
						ID:          addr,
						Status:      "critical",
						Message:     "Authentication required password",
						LastChecked: now,
					}, nil, nil
				}
				// Send PasswordMessage ('p')
				pMsg := []byte(cfg.Password + "\x00")
				pLen := int32(len(pMsg) + 4)
				var pPacket bytes.Buffer
				pPacket.WriteByte('p')
				binary.Write(&pPacket, binary.BigEndian, pLen)
				pPacket.Write(pMsg)
				_, _ = conn.Write(pPacket.Bytes())
			} else if authType == 5 { // MD5 Password
				salt := payload[4:8]
				h1 := md5.Sum([]byte(cfg.Password + cfg.User))
				h1Hex := hex.EncodeToString(h1[:])
				h2 := md5.Sum(append([]byte(h1Hex), salt...))
				h2Hex := "md5" + hex.EncodeToString(h2[:]) + "\x00"

				pLen := int32(len(h2Hex) + 4)
				var pPacket bytes.Buffer
				pPacket.WriteByte('p')
				binary.Write(&pPacket, binary.BigEndian, pLen)
				pPacket.WriteString(h2Hex)
				_, _ = conn.Write(pPacket.Bytes())
			}
		} else if msgType == 'S' { // ParameterStatus
			// Format: key\x00value\x00
			parts := bytes.Split(payload, []byte{0})
			if len(parts) >= 2 {
				k := string(parts[0])
				v := string(parts[1])
				if k == "server_version" {
					version = v
					metricsData["version"] = v
				}
			}
		} else if msgType == 'K' { // BackendKeyData
			authSuccess = true
		} else if msgType == 'Z' { // ReadyForQuery
			break
		} else if msgType == 'E' { // ErrorResponse
			errMsg := parsePostgresError(payload)
			latency := time.Since(start).Milliseconds()
			return providers.HealthResult{
				ID:          addr,
				Status:      "critical",
				Message:     fmt.Sprintf("Postgres error: %s", errMsg),
				LatencyMs:   latency,
				LastChecked: now,
			}, nil, nil
		}
	}

	latency := time.Since(start).Milliseconds()
	if !authSuccess {
		return providers.HealthResult{
			ID:          addr,
			Status:      "warning",
			Message:     fmt.Sprintf("PostgreSQL reachable (%d ms) but authentication not completed", latency),
			LatencyMs:   latency,
			LastChecked: now,
		}, nil, nil
	}

	metricsData["response_time_ms"] = latency
	metricsData["version"] = version

	// 3. Send SELECT 1 query: 'Q' packet
	queryPacket := []byte("Q\x00\x00\x00\x0eSELECT 1;\x00")
	_, _ = conn.Write(queryPacket)

	// Consume until ReadyForQuery
	for {
		_, err := conn.Read(header)
		if err != nil {
			break
		}
		length := int(binary.BigEndian.Uint32(header[1:5])) - 4
		if length > 0 {
			buf := make([]byte, length)
			_, _ = conn.Read(buf)
		}
		if header[0] == 'Z' || header[0] == 'E' {
			break
		}
	}

	msg := fmt.Sprintf("PostgreSQL %s healthy (%d ms, DB: %s)", version, latency, cfg.Database)

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

func parsePostgresError(payload []byte) string {
	var parts []string
	idx := 0
	for idx < len(payload) {
		fieldCode := payload[idx]
		if fieldCode == 0 {
			break
		}
		idx++
		nullIdx := bytes.IndexByte(payload[idx:], 0)
		if nullIdx == -1 {
			break
		}
		val := string(payload[idx : idx+nullIdx])
		idx += nullIdx + 1
		if fieldCode == 'M' { // Primary message
			parts = append(parts, val)
		}
	}
	if len(parts) > 0 {
		return strings.Join(parts, "; ")
	}
	return "unknown error"
}
