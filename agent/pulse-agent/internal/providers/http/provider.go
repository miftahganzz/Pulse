package http

import (
	"context"
	"crypto/tls"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/pulse/pulse-agent/internal/providers"
)

type HTTPProvider struct {
	client *http.Client
}

func NewProvider() *HTTPProvider {
	return &HTTPProvider{
		client: &http.Client{
			Timeout: 10 * time.Second,
			Transport: &http.Transport{
				TLSClientConfig: &tls.Config{
					InsecureSkipVerify: false,
				},
			},
		},
	}
}

func (p *HTTPProvider) Type() string {
	return "http"
}

func (p *HTTPProvider) Capabilities() []providers.ProviderCapability {
	return []providers.ProviderCapability{
		providers.CapHealth,
		providers.CapMetrics,
	}
}

func (p *HTTPProvider) Discover(ctx context.Context) ([]providers.DiscoveredService, error) {
	return []providers.DiscoveredService{}, nil
}

func (p *HTTPProvider) Health(ctx context.Context, target string) (providers.HealthResult, error) {
	return p.CheckAdvanced(ctx, providers.MonitorRequest{
		Target: target,
	})
}

func (p *HTTPProvider) CheckAdvanced(ctx context.Context, req providers.MonitorRequest) (providers.HealthResult, error) {
	now := time.Now().UTC()
	url := req.Target
	if !strings.HasPrefix(url, "http://") && !strings.HasPrefix(url, "https://") {
		url = "http://" + url
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return providers.HealthResult{
			ID:          req.ID,
			Status:      "critical",
			Message:     fmt.Sprintf("Invalid URL: %v", err),
			LastChecked: now,
		}, nil
	}
	httpReq.Header.Set("User-Agent", "Pulse-Agent/2.0 (AdvancedHealthProbe)")

	// Apply custom headers if present
	for k, v := range req.Headers {
		httpReq.Header.Set(k, v)
	}

	start := time.Now()
	resp, err := p.client.Do(httpReq)
	latency := time.Since(start).Milliseconds()

	if err != nil {
		return providers.HealthResult{
			ID:          req.ID,
			Status:      "down",
			Message:     fmt.Sprintf("Connection failed: %v", err),
			LatencyMs:   latency,
			LastChecked: now,
		}, nil
	}
	defer resp.Body.Close()

	// Read limited body for assertion (up to 32KB)
	bodyBytes, _ := io.ReadAll(io.LimitReader(resp.Body, 32768))
	bodyStr := string(bodyBytes)

	tlsValid := resp.TLS != nil && len(resp.TLS.PeerCertificates) > 0

	metrics := map[string]any{
		"status_code": resp.StatusCode,
		"tls_valid":   tlsValid,
		"body_bytes":  len(bodyBytes),
	}

	// 1. Check custom status code assertion if requested
	if req.ExpectedCode > 0 && resp.StatusCode != req.ExpectedCode {
		return providers.HealthResult{
			ID:          req.ID,
			Status:      "critical",
			Message:     fmt.Sprintf("Expected HTTP %d, got %d (%d ms)", req.ExpectedCode, resp.StatusCode, latency),
			LatencyMs:   latency,
			Metrics:     metrics,
			LastChecked: now,
		}, nil
	}

	// 2. Check body assertion if requested
	if req.ExpectedBody != "" && !strings.Contains(bodyStr, req.ExpectedBody) {
		return providers.HealthResult{
			ID:          req.ID,
			Status:      "critical",
			Message:     fmt.Sprintf("HTTP %d OK but body missing assertion '%s' (%d ms)", resp.StatusCode, req.ExpectedBody, latency),
			LatencyMs:   latency,
			Metrics:     metrics,
			LastChecked: now,
		}, nil
	}

	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return providers.HealthResult{
			ID:          req.ID,
			Status:      "healthy",
			Message:     fmt.Sprintf("HTTP %d OK (%d ms)", resp.StatusCode, latency),
			LatencyMs:   latency,
			Metrics:     metrics,
			LastChecked: now,
		}, nil
	} else if resp.StatusCode >= 300 && resp.StatusCode < 400 {
		return providers.HealthResult{
			ID:          req.ID,
			Status:      "warning",
			Message:     fmt.Sprintf("HTTP %d Redirect (%d ms)", resp.StatusCode, latency),
			LatencyMs:   latency,
			Metrics:     metrics,
			LastChecked: now,
		}, nil
	} else {
		return providers.HealthResult{
			ID:          req.ID,
			Status:      "critical",
			Message:     fmt.Sprintf("HTTP %d %s (%d ms)", resp.StatusCode, http.StatusText(resp.StatusCode), latency),
			LatencyMs:   latency,
			Metrics:     metrics,
			LastChecked: now,
		}, nil
	}
}
