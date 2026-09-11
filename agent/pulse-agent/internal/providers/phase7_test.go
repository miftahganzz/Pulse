package providers_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/pulse/pulse-agent/internal/providers"
	"github.com/pulse/pulse-agent/internal/providers/cloudflared"
	customprov "github.com/pulse/pulse-agent/internal/providers/custom"
	"github.com/pulse/pulse-agent/internal/providers/database/mongodb"
	"github.com/pulse/pulse-agent/internal/providers/database/mysql"
	httpprov "github.com/pulse/pulse-agent/internal/providers/http"
	"github.com/pulse/pulse-agent/internal/providers/tcp"
	"github.com/pulse/pulse-agent/internal/providers/webserver"
)

func TestProviderSystem2Capabilities(t *testing.T) {
	reg := providers.NewRegistry()
	reg.Register(webserver.NewProvider())
	reg.Register(cloudflared.NewProvider())
	reg.Register(mysql.NewProvider())
	reg.Register(mongodb.NewProvider())
	reg.Register(httpprov.NewProvider())
	reg.Register(tcp.NewProvider())
	reg.Register(customprov.NewProvider())

	list := reg.ListProviders()
	if len(list) != 7 {
		t.Fatalf("expected 7 registered providers, got %d", len(list))
	}

	foundNginx := false
	for _, p := range list {
		if p.Type == "nginx" {
			foundNginx = true
			if len(p.Capabilities) == 0 {
				t.Errorf("nginx provider missing capabilities")
			}
		}
	}
	if !foundNginx {
		t.Errorf("expected nginx provider in registry")
	}
}

func TestAdvancedHTTPCheckWithAssertions(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"ok","code":200,"service":"movnix-api"}`))
	}))
	defer ts.Close()

	p := httpprov.NewProvider()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	// 1. Success matching body
	req := providers.MonitorRequest{
		ID:           "test-1",
		Target:       ts.URL,
		ExpectedCode: 200,
		ExpectedBody: `"status":"ok"`,
	}
	res, err := p.CheckAdvanced(ctx, req)
	if err != nil || res.Status != "healthy" {
		t.Fatalf("expected healthy, got %s: %s", res.Status, res.Message)
	}

	// 2. Failure due to missing body assertion
	reqFail := providers.MonitorRequest{
		ID:           "test-2",
		Target:       ts.URL,
		ExpectedBody: `"non_existent_key"`,
	}
	resFail, _ := p.CheckAdvanced(ctx, reqFail)
	if resFail.Status != "critical" {
		t.Fatalf("expected critical status for missing body assertion, got %s", resFail.Status)
	}
}

func TestSecureCustomCheckSandboxing(t *testing.T) {
	p := customprov.NewProvider()
	ctx := context.Background()

	// 1. Command injection attempt with pipe should be rejected
	res, _ := p.CheckCustom(ctx, providers.MonitorRequest{
		Target: "uptime | cat /etc/passwd",
	})
	if res.Status != "critical" {
		t.Fatalf("expected critical security rejection for pipe injection, got %s", res.Status)
	}

	// 2. Command not in allowlist should be rejected
	resDisallowed, _ := p.CheckCustom(ctx, providers.MonitorRequest{
		Target: "reboot",
	})
	if resDisallowed.Status != "critical" {
		t.Fatalf("expected critical rejection for non-allowlisted command, got %s", resDisallowed.Status)
	}

	// 3. Safe allowlisted command (uname) should execute
	resSafe, _ := p.CheckCustom(ctx, providers.MonitorRequest{
		Target: "uname",
	})
	if resSafe.Status != "healthy" {
		t.Fatalf("expected healthy for uname check, got %s: %s", resSafe.Status, resSafe.Message)
	}
}
