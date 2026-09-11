package providers_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/pulse/pulse-agent/internal/docker"
	"github.com/pulse/pulse-agent/internal/processes"
	"github.com/pulse/pulse-agent/internal/providers"
	dockerprov "github.com/pulse/pulse-agent/internal/providers/docker"
	httpprov "github.com/pulse/pulse-agent/internal/providers/http"
	pm2prov "github.com/pulse/pulse-agent/internal/providers/pm2"
	procprov "github.com/pulse/pulse-agent/internal/providers/process"
	systemdprov "github.com/pulse/pulse-agent/internal/providers/systemd"
	tcpprov "github.com/pulse/pulse-agent/internal/providers/tcp"
	"github.com/pulse/pulse-agent/internal/services"
)

// Mock services.Collector
type mockServicesCollector struct {
	svcs []services.ServiceInfo
}

func (m *mockServicesCollector) CollectServices() ([]services.ServiceInfo, error) {
	return m.svcs, nil
}

// Mock docker.Controller
type mockDockerController struct {
	status *docker.DockerStatus
}

func (m *mockDockerController) GetStatus() (*docker.DockerStatus, error) {
	return m.status, nil
}
func (m *mockDockerController) ControlContainer(id string, action string) error { return nil }
func (m *mockDockerController) GetLogs(id string, tail int) (string, error)      { return "", nil }

// Mock processes.Collector
type mockProcessesCollector struct {
	procs []processes.ProcessInfo
}

func (m *mockProcessesCollector) CollectProcesses(limit int, sortBy string) ([]processes.ProcessInfo, error) {
	return m.procs, nil
}

func TestProvidersAndRegistry(t *testing.T) {
	ctx := context.Background()

	// 1. Systemd Provider
	mockSvc := &mockServicesCollector{
		svcs: []services.ServiceInfo{
			{Name: "nginx.service", Description: "Nginx Server", ActiveState: "active", SubState: "running"},
			{Name: "redis.service", Description: "Redis Cache", ActiveState: "failed", SubState: "failed"},
		},
	}
	sysP := systemdprov.NewProvider(mockSvc)
	sysSvcs, err := sysP.Discover(ctx)
	if err != nil || len(sysSvcs) != 2 {
		t.Fatalf("expected 2 discovered services, got %d, err: %v", len(sysSvcs), err)
	}
	h1, _ := sysP.Health(ctx, "nginx")
	if h1.Status != "healthy" {
		t.Errorf("expected healthy for nginx, got %s", h1.Status)
	}
	h2, _ := sysP.Health(ctx, "redis.service")
	if h2.Status != "critical" {
		t.Errorf("expected critical for redis, got %s", h2.Status)
	}

	// 2. Docker Provider
	mockDoc := &mockDockerController{
		status: &docker.DockerStatus{
			Available: true,
			Version:   "24.0.5",
			Containers: []docker.ContainerInfo{
				{ID: "c1234567890", Name: "/postgres-db", Image: "postgres:15", State: "running", Status: "Up 2 hours"},
				{ID: "c9876543210", Name: "/old-redis", Image: "redis:alpine", State: "exited", Status: "Exited (0) 5m ago"},
			},
		},
	}
	docP := dockerprov.NewProvider(mockDoc)
	docSvcs, err := docP.Discover(ctx)
	if err != nil || len(docSvcs) != 2 {
		t.Fatalf("expected 2 docker containers, got %d", len(docSvcs))
	}
	hDoc1, _ := docP.Health(ctx, "postgres-db")
	if hDoc1.Status != "healthy" {
		t.Errorf("expected healthy for postgres-db, got %s", hDoc1.Status)
	}
	hDoc2, _ := docP.Health(ctx, "c9876543210")
	if hDoc2.Status != "down" {
		t.Errorf("expected down for exited container, got %s", hDoc2.Status)
	}

	// 3. Process Provider
	mockProc := &mockProcessesCollector{
		procs: []processes.ProcessInfo{
			{PID: 1234, Name: "nginx", Command: "nginx: master process", CPUPercent: 0.5, MemoryRSSBytes: 20 * 1024 * 1024},
		},
	}
	procP := procprov.NewProvider(mockProc)
	pSvcs, err := procP.Discover(ctx)
	if err != nil || len(pSvcs) != 1 {
		t.Fatalf("expected 1 process discovered, got %d", len(pSvcs))
	}
	hProc, _ := procP.Health(ctx, "nginx")
	if hProc.Status != "healthy" {
		t.Errorf("expected healthy for process nginx, got %s", hProc.Status)
	}

	// 4. HTTP Provider
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	}))
	defer ts.Close()

	httpP := httpprov.NewProvider()
	hHTTP, err := httpP.Health(ctx, ts.URL)
	if err != nil || hHTTP.Status != "healthy" {
		t.Errorf("expected healthy for http server, got %s, err: %v", hHTTP.Status, err)
	}

	// 5. TCP Provider
	tcpP := tcpprov.NewProvider()
	// ts.Listener.Addr().String() gives host:port
	hTCP, err := tcpP.Health(ctx, ts.Listener.Addr().String())
	if err != nil || hTCP.Status != "healthy" {
		t.Errorf("expected healthy for tcp test server, got %s, err: %v", hTCP.Status, err)
	}

	// 6. PM2 Provider (graceful if binary not found)
	pm2P := pm2prov.NewProvider()
	if pm2P.Type() != "pm2" {
		t.Errorf("expected pm2 type, got %s", pm2P.Type())
	}
	pm2Svcs, err := pm2P.Discover(ctx)
	if err != nil {
		t.Errorf("expected nil error on discover fallback, got %v", err)
	}
	_ = pm2Svcs

	// 7. Registry Integration
	reg := providers.NewRegistry()
	reg.Register(sysP)
	reg.Register(docP)
	reg.Register(procP)
	reg.Register(httpP)
	reg.Register(tcpP)
	reg.Register(pm2P)

	discRes, err := reg.DiscoverAll(ctx)
	if err != nil {
		t.Fatalf("DiscoverAll failed: %v", err)
	}
	if len(discRes.Services) < 5 {
		t.Errorf("expected at least 5 services across providers, got %d", len(discRes.Services))
	}

	batchReqs := []providers.MonitorRequest{
		{ID: "m1", Name: "Nginx Service", Type: "systemd", Target: "nginx"},
		{ID: "m2", Name: "Postgres", Type: "docker", Target: "postgres-db"},
		{ID: "m3", Name: "Web Test", Type: "http", Target: ts.URL},
	}
	batchRes := reg.CheckBatchHealth(ctx, batchReqs)
	if len(batchRes) != 3 {
		t.Fatalf("expected 3 health results, got %d", len(batchRes))
	}
	for _, res := range batchRes {
		if res.Status != "healthy" {
			t.Errorf("expected healthy for %s, got %s (%s)", res.ID, res.Status, res.Message)
		}
	}
}
