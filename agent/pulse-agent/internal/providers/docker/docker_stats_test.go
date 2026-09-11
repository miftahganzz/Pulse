package docker_test

import (
	"context"
	"testing"

	"github.com/pulse/pulse-agent/internal/docker"
	dockerprov "github.com/pulse/pulse-agent/internal/providers/docker"
)

type mockStatsDocker struct {
	status *docker.DockerStatus
}

func (m *mockStatsDocker) GetStatus() (*docker.DockerStatus, error) {
	return m.status, nil
}
func (m *mockStatsDocker) ControlContainer(id string, action string) error { return nil }
func (m *mockStatsDocker) GetLogs(id string, tail int) (string, error)      { return "", nil }

func TestDockerRunningAndStoppedContainers(t *testing.T) {
	ctx := context.Background()

	mock := &mockStatsDocker{
		status: &docker.DockerStatus{
			Available: true,
			Version:   "24.0.7",
			Containers: []docker.ContainerInfo{
				{
					ID:        "c_run_123",
					Name:      "movnix-api",
					Image:     "movnix/api:v1.2",
					State:     "running",
					Status:    "Up 3 days",
					CreatedAt: 1700000000,
					Ports:     []string{"0.0.0.0:3000->3000/tcp"},
				},
				{
					ID:        "c_stop_456",
					Name:      "movnix-worker",
					Image:     "movnix/worker:v1.2",
					State:     "exited",
					Status:    "Exited (1) 2 hours ago",
					CreatedAt: 1700000000,
					Ports:     []string{},
				},
			},
		},
	}

	p := dockerprov.NewProvider(mock)

	// 1. Discover
	svcs, err := p.Discover(ctx)
	if err != nil || len(svcs) != 2 {
		t.Fatalf("expected 2 discovered containers, got %d", len(svcs))
	}

	// 2. Health running
	hRun, _ := p.Health(ctx, "movnix-api")
	if hRun.Status != "healthy" {
		t.Errorf("expected healthy for running container, got %s", hRun.Status)
	}

	// 3. Health stopped / exited
	hStop, _ := p.Health(ctx, "c_stop_456")
	if hStop.Status != "down" {
		t.Errorf("expected down for stopped container, got %s", hStop.Status)
	}

	// 4. Docker unavailable handling
	mockUnavail := &mockStatsDocker{
		status: &docker.DockerStatus{
			Available:  false,
			Containers: []docker.ContainerInfo{},
		},
	}
	pUnavail := dockerprov.NewProvider(mockUnavail)
	hUnavail, _ := pUnavail.Health(ctx, "movnix-api")
	if hUnavail.Status != "down" {
		t.Errorf("expected down when docker is unavailable, got %s", hUnavail.Status)
	}
}
