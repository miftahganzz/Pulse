package pm2_test

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/pulse/pulse-agent/internal/providers/pm2"
)

func TestPM2ProviderStatusesAndFallback(t *testing.T) {
	ctx := context.Background()

	// 1. Fallback when PM2 is not in path
	p := pm2.NewProvider()
	svcs, err := p.Discover(ctx)
	if err != nil {
		t.Fatalf("expected nil error on PM2 fallback, got %v", err)
	}
	_ = svcs

	// 2. Health check when binary not present returns unknown status gracefully
	h, err := p.Health(ctx, "app")
	if err != nil {
		t.Fatalf("expected nil error on Health fallback, got %v", err)
	}
	if h.Status != "unknown" {
		t.Errorf("expected unknown status when pm2 missing, got %s", h.Status)
	}

	// 3. Test PM2 parsing structures
	mockJSON := `[
		{
			"pid": 1234,
			"name": "api-gateway",
			"pm_id": 0,
			"monit": {
				"memory": 134217728,
				"cpu": 3.4
			},
			"pm2_env": {
				"status": "online",
				"restart_time": 1,
				"pm_uptime": 1700000000
			}
		},
		{
			"pid": 1235,
			"name": "worker",
			"pm_id": 1,
			"monit": {
				"memory": 67108864,
				"cpu": 0.0
			},
			"pm2_env": {
				"status": "errored",
				"restart_time": 5,
				"pm_uptime": 1700000000
			}
		}
	]`

	var procs []pm2.PM2Process
	if err := json.Unmarshal([]byte(mockJSON), &procs); err != nil {
		t.Fatalf("failed decoding mock PM2 json: %v", err)
	}
	if len(procs) != 2 {
		t.Fatalf("expected 2 processes, got %d", len(procs))
	}
	if procs[0].Monit.CPU != 3.4 {
		t.Errorf("expected 3.4 CPU, got %f", procs[0].Monit.CPU)
	}
	if procs[1].PM2Env.Status != "errored" {
		t.Errorf("expected errored status, got %s", procs[1].PM2Env.Status)
	}

	// 4. Create mock script to test fake pm2 execution
	tmpDir := t.TempDir()
	fakePM2Script := filepath.Join(tmpDir, "pm2")
	scriptContent := "#!/bin/sh\necho '" + mockJSON + "'\n"
	if err := os.WriteFile(fakePM2Script, []byte(scriptContent), 0755); err == nil {
		os.Setenv("PATH", tmpDir+":"+os.Getenv("PATH"))
		defer os.Setenv("PATH", os.Getenv("PATH"))

		pMock := pm2.NewProvider()
		found, err := pMock.Discover(ctx)
		if err == nil && len(found) == 2 {
			if found[0].Name != "api-gateway" || found[0].Status != "online" {
				t.Errorf("unexpected first service: %+v", found[0])
			}
			hOnline, _ := pMock.Health(ctx, "api-gateway")
			if hOnline.Status != "healthy" {
				t.Errorf("expected healthy for online process, got %s", hOnline.Status)
			}
			hError, _ := pMock.Health(ctx, "worker")
			if hError.Status != "critical" {
				t.Errorf("expected critical for errored process, got %s", hError.Status)
			}
		}
	}
}
