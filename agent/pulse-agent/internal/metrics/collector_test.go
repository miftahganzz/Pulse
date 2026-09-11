package metrics_test

import (
	"log/slog"
	"os"
	"testing"

	"github.com/pulse/pulse-agent/internal/metrics"
)

func TestMetricsCollector(t *testing.T) {
	logger := slog.New(slog.NewTextHandler(os.Stdout, nil))
	c := metrics.NewCollector(logger)
	snap := c.Collect()

	if snap == nil {
		t.Fatal("expected snapshot, got nil")
	}

	t.Logf("CPU Cores: %d, Usage: %.1f%%", snap.CPU.Cores, snap.CPU.UsagePercent)
	t.Logf("Memory Total: %d, Used: %d", snap.Memory.TotalBytes, snap.Memory.UsedBytes)
	t.Logf("Disks Count: %d", len(snap.Disks))
	for _, d := range snap.Disks {
		t.Logf("  Mount: %s, Total: %d, Used: %d (%.1f%%)", d.MountPoint, d.TotalBytes, d.UsedBytes, d.UsagePercent)
	}
	t.Logf("Network Total Rx: %d, Tx: %d", snap.Network.TotalRxBytes, snap.Network.TotalTxBytes)
	t.Logf("Uptime: %d seconds", snap.UptimeSeconds)

	if snap.CPU.Cores < 1 {
		t.Errorf("expected CPU.Cores >= 1, got %d", snap.CPU.Cores)
	}
	if snap.Memory.TotalBytes == 0 {
		t.Errorf("expected Memory.TotalBytes > 0")
	}
	if len(snap.Disks) == 0 {
		t.Errorf("expected at least 1 disk mount")
	}
}
