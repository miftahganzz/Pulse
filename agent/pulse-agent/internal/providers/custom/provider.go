package custom

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/pulse/pulse-agent/internal/providers"
)

// Allowlisted command binaries that are safe for monitoring probes
var allowlistedCommands = map[string]bool{
	"systemctl": true,
	"curl":      true,
	"pgrep":     true,
	"docker":    true,
	"uptime":    true,
	"df":        true,
	"free":      true,
	"uname":     true,
	"ping":      true,
	"git":       true,
	"test":      true,
}

type CustomCheckProvider struct{}

func NewProvider() *CustomCheckProvider {
	return &CustomCheckProvider{}
}

func (p *CustomCheckProvider) Type() string {
	return "custom"
}

func (p *CustomCheckProvider) Capabilities() []providers.ProviderCapability {
	return []providers.ProviderCapability{
		providers.CapHealth,
		providers.CapMetrics,
	}
}

func (p *CustomCheckProvider) Discover(ctx context.Context) ([]providers.DiscoveredService, error) {
	return []providers.DiscoveredService{}, nil
}

func (p *CustomCheckProvider) Health(ctx context.Context, target string) (providers.HealthResult, error) {
	return p.CheckCustom(ctx, providers.MonitorRequest{
		Target: target,
	})
}

func (p *CustomCheckProvider) CheckCustom(ctx context.Context, req providers.MonitorRequest) (providers.HealthResult, error) {
	now := time.Now().UTC()
	rawCmd := strings.TrimSpace(req.Target)

	if rawCmd == "" {
		return providers.HealthResult{
			ID:          req.ID,
			Status:      "critical",
			Message:     "Custom command cannot be empty",
			LastChecked: now,
		}, nil
	}

	// Security: disallow command chaining / shell piping injection characters
	if strings.ContainsAny(rawCmd, ";|&`$><\n\r") {
		return providers.HealthResult{
			ID:          req.ID,
			Status:      "critical",
			Message:     "Security violation: shell chaining, piping, or redirection characters (; | & ` $ > <) are prohibited",
			LastChecked: now,
		}, nil
	}

	tokens := strings.Fields(rawCmd)
	if len(tokens) == 0 {
		return providers.HealthResult{
			ID:          req.ID,
			Status:      "critical",
			Message:     "Invalid command format",
			LastChecked: now,
		}, nil
	}

	bin := tokens[0]
	if !allowlistedCommands[bin] {
		return providers.HealthResult{
			ID:          req.ID,
			Status:      "critical",
			Message:     fmt.Sprintf("Command '%s' is not in the security allowlist", bin),
			LastChecked: now,
		}, nil
	}

	// Execution timeout: default 5s
	timeout := 5 * time.Second
	execCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	start := time.Now()
	var args []string
	if len(tokens) > 1 {
		args = tokens[1:]
	}

	cmd := exec.CommandContext(execCtx, bin, args...)
	out, err := cmd.CombinedOutput()
	latency := time.Since(start).Milliseconds()

	outputStr := strings.TrimSpace(string(out))
	if len(outputStr) > 8192 {
		outputStr = outputStr[:8192] + " [truncated]"
	}

	if err != nil {
		return providers.HealthResult{
			ID:          req.ID,
			Status:      "critical",
			Message:     fmt.Sprintf("Command failed with exit error: %v (output: %s)", err, outputStr),
			LatencyMs:   latency,
			Metrics: map[string]any{
				"exit_code": 1,
				"output":    outputStr,
			},
			LastChecked: now,
		}, nil
	}

	// Check expected output substring if specified
	if req.ExpectedOutput != "" {
		if !strings.Contains(outputStr, req.ExpectedOutput) {
			return providers.HealthResult{
				ID:          req.ID,
				Status:      "critical",
				Message:     fmt.Sprintf("Command output did not match expected '%s' (got: %s)", req.ExpectedOutput, outputStr),
				LatencyMs:   latency,
				Metrics: map[string]any{
					"output": outputStr,
				},
				LastChecked: now,
			}, nil
		}
	}

	return providers.HealthResult{
		ID:        req.ID,
		Status:    "healthy",
		Message:   fmt.Sprintf("Command succeeded: %s (%d ms)", outputStr, latency),
		LatencyMs: latency,
		Metrics: map[string]any{
			"output": outputStr,
		},
		LastChecked: now,
	}, nil
}
