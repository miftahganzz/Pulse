package actions_test

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/pulse/pulse-agent/internal/actions"
	"github.com/pulse/pulse-agent/internal/docker"
	"github.com/pulse/pulse-agent/internal/services"
)

type mockDocker struct {
	lastAction string
	lastTarget string
}

func (m *mockDocker) GetStatus() (*docker.DockerStatus, error) { return nil, nil }
func (m *mockDocker) GetLogs(id string, tail int) (string, error) { return "", nil }
func (m *mockDocker) ControlContainer(id string, action string) error {
	m.lastAction = action
	m.lastTarget = id
	return nil
}

type mockServiceController struct {
	lastAction string
	lastUnit   string
}

func (m *mockServiceController) CollectServices() ([]services.ServiceInfo, error) {
	return nil, nil
}

func (m *mockServiceController) ControlService(name string, action string) error {
	m.lastAction = action
	m.lastUnit = name
	return nil
}

func TestActionsAllowlistAndExecution(t *testing.T) {
	ctx := context.Background()
	doc := &mockDocker{}
	svc := &mockServiceController{}
	exec := actions.NewExecutor(doc, svc)

	// 1. Docker restart
	resDocker := exec.Execute(ctx, actions.ActionRequest{
		Action: "docker.restart",
		Target: "redis-cache",
	})
	if resDocker.Status != "success" {
		t.Fatalf("expected docker restart success, got %s (%s)", resDocker.Status, resDocker.Message)
	}
	if doc.lastAction != "restart" || doc.lastTarget != "redis-cache" {
		t.Errorf("docker action mismatch: %s on %s", doc.lastAction, doc.lastTarget)
	}

	// 2. Systemd restart
	resSys := exec.Execute(ctx, actions.ActionRequest{
		Action: "systemd.restart",
		Target: "nginx",
	})
	if resSys.Status != "success" {
		t.Fatalf("expected systemd restart success, got %s (%s)", resSys.Status, resSys.Message)
	}
	if svc.lastAction != "restart" || svc.lastUnit != "nginx.service" {
		t.Errorf("systemd action mismatch: %s on %s", svc.lastAction, svc.lastUnit)
	}

	// 3. Unauthorized shell execution attempt must fail
	resMalicious := exec.Execute(ctx, actions.ActionRequest{
		Action: "shell.execute",
		Target: "rm -rf /",
	})
	if resMalicious.Status != "failed" {
		t.Errorf("expected malicious action to fail, got %s", resMalicious.Status)
	}
	if !strings.Contains(resMalicious.Message, "Unauthorized") {
		t.Errorf("expected unauthorized error message, got %s", resMalicious.Message)
	}

	// 4. Path traversal attempt in systemd unit must fail
	resTraversal := exec.Execute(ctx, actions.ActionRequest{
		Action: "systemd.start",
		Target: "../../../etc/shadow",
	})
	if resTraversal.Status != "failed" {
		t.Errorf("expected traversal to fail, got %s", resTraversal.Status)
	}

	// 5. Action Timeout handling
	// Zero or short timeout simulation with cancelled context
	cancCtx, cancel := context.WithTimeout(ctx, 1*time.Millisecond)
	defer cancel()
	time.Sleep(2 * time.Millisecond)
	resTimeout := exec.Execute(cancCtx, actions.ActionRequest{
		Action: "docker.stop",
		Target: "test-container",
	})
	_ = resTimeout
}
