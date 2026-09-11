package processes_test

import (
	"testing"

	"github.com/pulse/pulse-agent/internal/processes"
)

func TestCollectProcesses(t *testing.T) {
	c := processes.NewCollector()
	procs, err := c.CollectProcesses(20, "cpu")
	if err != nil {
		t.Fatalf("failed to collect processes: %v", err)
	}

	if len(procs) == 0 {
		t.Fatal("expected at least 1 process, got 0")
	}

	t.Logf("Found %d processes", len(procs))
	for i, p := range procs {
		if i < 5 {
			t.Logf("PID %d: %s (User: %s, CPU: %.1f%%, RSS: %d bytes, State: %s)",
				p.PID, p.Name, p.User, p.CPUPercent, p.MemoryRSSBytes, p.State)
		}
		if p.PID <= 0 {
			t.Errorf("invalid PID: %d", p.PID)
		}
	}
}

func TestKillProcessSafety(t *testing.T) {
	c := processes.NewCollector()
	ctrl, ok := c.(processes.ProcessController)
	if !ok {
		t.Skip("Collector does not implement ProcessController")
	}

	// PID 0 or PID 1 must be rejected
	if err := ctrl.KillProcess(0, "SIGTERM"); err == nil {
		t.Error("expected error killing PID 0, got nil")
	}
	if err := ctrl.KillProcess(1, "SIGKILL"); err == nil {
		t.Error("expected error killing PID 1, got nil")
	}

	// Invalid signal must be rejected
	if err := ctrl.KillProcess(999999, "SIGINVALID"); err == nil {
		t.Error("expected error with invalid signal, got nil")
	}
}

