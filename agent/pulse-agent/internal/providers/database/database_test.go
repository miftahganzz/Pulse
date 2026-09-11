package database_test

import (
	"context"
	"fmt"
	"net"
	"strings"
	"testing"

	"github.com/pulse/pulse-agent/internal/providers/database"
	"github.com/pulse/pulse-agent/internal/providers/database/postgres"
	"github.com/pulse/pulse-agent/internal/providers/database/redis"
)

func TestRedisProbe(t *testing.T) {
	ctx := context.Background()

	// Setup mock RESP Redis server
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("failed to start mock tcp listener: %v", err)
	}
	defer l.Close()

	go func() {
		for {
			conn, err := l.Accept()
			if err != nil {
				return
			}
			go func(c net.Conn) {
				defer c.Close()
				buf := make([]byte, 1024)
				for {
					n, err := c.Read(buf)
					if err != nil {
						return
					}
					req := string(buf[:n])
					if strings.Contains(req, "PING") {
						c.Write([]byte("+PONG\r\n"))
					} else if strings.Contains(req, "INFO") {
						info := "# Server\r\nredis_version:7.2.4\r\nconnected_clients:12\r\nused_memory:50331648\r\nuptime_in_seconds:3600\r\n"
						resp := fmt.Sprintf("$%d\r\n%s\r\n", len(info), info)
						c.Write([]byte(resp))
					}
				}
			}(conn)
		}
	}()

	addr := l.Addr().(*net.TCPAddr)
	rP := redis.NewProvider()

	cfg := database.DatabaseConfig{
		Type: "redis",
		Host: addr.IP.String(),
		Port: addr.Port,
	}

	health, metrics, err := rP.Probe(ctx, cfg)
	if err != nil {
		t.Fatalf("probe returned unexpected err: %v", err)
	}
	if health.Status != "healthy" {
		t.Errorf("expected healthy redis status, got %s (%s)", health.Status, health.Message)
	}
	if metrics == nil {
		t.Fatalf("expected non-nil database metrics")
	}
	if metrics.Version != "7.2.4" {
		t.Errorf("expected redis_version 7.2.4, got %s", metrics.Version)
	}
}

func TestPostgresProbeUnavailable(t *testing.T) {
	ctx := context.Background()
	pP := postgres.NewProvider()

	// Port that is definitely not listening
	cfg := database.DatabaseConfig{
		Type: "postgres",
		Host: "127.0.0.1",
		Port: 54329,
	}

	health, metrics, err := pP.Probe(ctx, cfg)
	if err != nil {
		t.Fatalf("probe error: %v", err)
	}
	if health.Status != "down" {
		t.Errorf("expected down status for closed port, got %s", health.Status)
	}
	if metrics != nil {
		t.Errorf("expected nil metrics for down database")
	}
}
