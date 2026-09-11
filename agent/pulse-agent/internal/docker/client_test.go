package docker_test

import (
	"encoding/json"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"testing"

	"github.com/pulse/pulse-agent/internal/docker"
)

func TestDockerUnavailableGraceful(t *testing.T) {
	client := docker.NewClientWithPath("/tmp/nonexistent-docker-socket.sock")
	status, err := client.GetStatus()
	if err != nil {
		t.Fatalf("expected nil error on missing socket, got %v", err)
	}

	if status.Available {
		t.Error("expected status.Available to be false for non-existent socket")
	}
	if len(status.Containers) != 0 {
		t.Errorf("expected 0 containers, got %d", len(status.Containers))
	}
}

func TestDockerMockSocketParsing(t *testing.T) {
	// Create a temporary mock unix socket
	tmpDir, err := os.MkdirTemp("", "docker-mock-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	sockPath := filepath.Join(tmpDir, "docker.sock")
	listener, err := net.Listen("unix", sockPath)
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()

	mockMux := http.NewServeMux()
	mockMux.HandleFunc("/version", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{
			"Version": "24.0.7",
		})
	})

	mockMux.HandleFunc("/containers/json", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		containers := []map[string]any{
			{
				"Id":     "abcdef1234567890",
				"Names":  []string{"/web-nginx"},
				"Image":  "nginx:alpine",
				"State":  "running",
				"Status": "Up 2 hours",
				"Created": int64(1700000000),
				"Ports": []map[string]any{
					{
						"IP":          "0.0.0.0",
						"PrivatePort": 80,
						"PublicPort":  8080,
						"Type":        "tcp",
					},
				},
			},
		}
		_ = json.NewEncoder(w).Encode(containers)
	})

	mockMux.HandleFunc("/containers/abcdef123456/restart", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	})

	server := &http.Server{Handler: mockMux}
	go func() {
		_ = server.Serve(listener)
	}()
	defer server.Close()

	client := docker.NewClientWithPath(sockPath)
	status, err := client.GetStatus()
	if err != nil {
		t.Fatalf("GetStatus failed: %v", err)
	}

	if !status.Available {
		t.Fatal("expected status.Available to be true")
	}
	if status.Version != "24.0.7" {
		t.Errorf("expected version 24.0.7, got %s", status.Version)
	}
	if len(status.Containers) != 1 {
		t.Fatalf("expected 1 container, got %d", len(status.Containers))
	}

	c := status.Containers[0]
	if c.ID != "abcdef123456" {
		t.Errorf("expected short ID abcdef123456, got %s", c.ID)
	}
	if c.Name != "web-nginx" {
		t.Errorf("expected name web-nginx, got %s", c.Name)
	}
	if c.State != "running" {
		t.Errorf("expected state running, got %s", c.State)
	}
	if len(c.Ports) != 1 || c.Ports[0] != "0.0.0.0:8080->80/tcp" {
		t.Errorf("unexpected ports: %v", c.Ports)
	}

	// Test control action
	if err := client.ControlContainer("abcdef123456", "restart"); err != nil {
		t.Errorf("ControlContainer restart failed: %v", err)
	}
}
