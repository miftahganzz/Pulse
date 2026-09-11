package server_test

import (
	"crypto/tls"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"github.com/pulse/pulse-agent/internal/agent"
	"github.com/pulse/pulse-agent/internal/security"
	"github.com/pulse/pulse-agent/internal/server"
	"github.com/pulse/pulse-agent/internal/transport"
)

func setupTestServer(t *testing.T) (*httptest.Server, *agent.Config) {
	tempDir := t.TempDir()
	certPath := filepath.Join(tempDir, "cert.pem")
	keyPath := filepath.Join(tempDir, "key.pem")

	_, err := security.EnsureCertificate(certPath, keyPath, []string{"127.0.0.1", "localhost"})
	if err != nil {
		t.Fatalf("failed to create certs: %v", err)
	}

	cfg := &agent.Config{
		AgentID:   "pulse_test123",
		AuthToken: "test_secret_token",
		Port:      8443,
		CertFile:  certPath,
		KeyFile:   keyPath,
	}

	identity := agent.Identity{
		AgentID:         cfg.AgentID,
		AgentVersion:    "0.1.0",
		Hostname:        "test-vps",
		OS:              "Ubuntu 24.04",
		Architecture:    "amd64",
		ProtocolVersion: 1,
	}

	logger := slog.New(slog.NewTextHandler(os.Stdout, nil))
	srv := server.NewServer(cfg, identity, logger)

	ts := httptest.NewTLSServer(srv.Handler())
	return ts, cfg
}

func TestUnauthorizedRequest(t *testing.T) {
	ts, _ := setupTestServer(t)
	defer ts.Close()

	client := ts.Client()
	resp, err := client.Get(ts.URL + "/api/v1/info")
	if err != nil {
		t.Fatalf("failed to make request: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusUnauthorized {
		t.Errorf("expected 401 Unauthorized, got %d", resp.StatusCode)
	}
}

func TestAuthorizedInfoRequest(t *testing.T) {
	ts, cfg := setupTestServer(t)
	defer ts.Close()

	client := ts.Client()
	req, err := http.NewRequest("GET", ts.URL+"/api/v1/info", nil)
	if err != nil {
		t.Fatalf("failed to create request: %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+cfg.AuthToken)

	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("request failed: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Errorf("expected 200 OK, got %d", resp.StatusCode)
	}

	body, _ := io.ReadAll(resp.Body)
	var env transport.Envelope
	if err := json.Unmarshal(body, &env); err != nil {
		t.Fatalf("invalid json response: %v", err)
	}

	if env.Type != "agent.hello" {
		t.Errorf("expected type agent.hello, got %s", env.Type)
	}

	var hello transport.HelloPayload
	if err := json.Unmarshal(env.Payload, &hello); err != nil {
		t.Fatalf("failed to parse hello payload: %v", err)
	}

	if hello.AgentID != "pulse_test123" || hello.OS != "Ubuntu 24.04" {
		t.Errorf("unexpected hello payload: %+v", hello)
	}
}

func TestWebSocketStreamingAndHeartbeat(t *testing.T) {
	ts, cfg := setupTestServer(t)
	defer ts.Close()

	wsURL := "wss" + strings.TrimPrefix(ts.URL, "https") + "/ws/v1/stream?token=" + cfg.AuthToken

	dialer := websocket.Dialer{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}

	conn, resp, err := dialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatalf("ws dial failed: %v", err)
	}
	defer conn.Close()
	defer resp.Body.Close()

	// 1. First message must be agent.hello
	var helloEnv transport.Envelope
	conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	if err := conn.ReadJSON(&helloEnv); err != nil {
		t.Fatalf("failed reading hello: %v", err)
	}

	if helloEnv.Type != "agent.hello" {
		t.Errorf("expected first message to be agent.hello, got %s", helloEnv.Type)
	}
}

func TestDiscoveryAndHealthEndpoints(t *testing.T) {
	ts, cfg := setupTestServer(t)
	defer ts.Close()

	client := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		},
	}

	// 1. GET /api/v1/discovery
	req, _ := http.NewRequest(http.MethodGet, ts.URL+"/api/v1/discovery", nil)
	req.Header.Set("Authorization", "Bearer "+cfg.AuthToken)
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("discovery request failed: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 OK for discovery, got %d", resp.StatusCode)
	}

	var discRes struct {
		Timestamp time.Time `json:"timestamp"`
		Services  []struct {
			ID           string `json:"id"`
			ProviderType string `json:"provider_type"`
			Name         string `json:"name"`
			Status       string `json:"status"`
		} `json:"services"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&discRes); err != nil {
		t.Fatalf("failed decoding discovery response: %v", err)
	}

	// 2. POST /api/v1/monitors/health
	monReqJSON := `[
		{"id": "test-http", "name": "Self Check", "type": "http", "target": "` + ts.URL + `/api/v1/info"}
	]`
	reqHealth, _ := http.NewRequest(http.MethodPost, ts.URL+"/api/v1/monitors/health", strings.NewReader(monReqJSON))
	reqHealth.Header.Set("Authorization", "Bearer "+cfg.AuthToken)
	reqHealth.Header.Set("Content-Type", "application/json")

	respHealth, err := client.Do(reqHealth)
	if err != nil {
		t.Fatalf("health check request failed: %v", err)
	}
	defer respHealth.Body.Close()

	if respHealth.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 OK for monitors health, got %d", respHealth.StatusCode)
	}

	var healthRes []struct {
		ID        string `json:"id"`
		Status    string `json:"status"`
		Message   string `json:"message"`
		LatencyMs int64  `json:"latency_ms"`
	}
	if err := json.NewDecoder(respHealth.Body).Decode(&healthRes); err != nil {
		t.Fatalf("failed decoding health check response: %v", err)
	}

	if len(healthRes) != 1 {
		t.Fatalf("expected 1 health result, got %d", len(healthRes))
	}
	if healthRes[0].ID != "test-http" {
		t.Errorf("expected test-http ID, got %s", healthRes[0].ID)
	}
}

