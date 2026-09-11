package actions

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func executePM2Action(ctx context.Context, target string, action string) ActionResult {
	// Look for pm2 binary
	pm2Bin, err := findPM2Binary()
	if err != nil {
		return ActionResult{
			Action:  "pm2." + action,
			Target:  target,
			Status:  "failed",
			Message: fmt.Sprintf("PM2 is not installed or available in PATH: %v", err),
		}
	}

	// Sanitise target: only allow alphanumeric, dash, dot, colon, underscore
	for _, ch := range target {
		if !((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '-' || ch == '_' || ch == '.' || ch == ':') {
			return ActionResult{
				Action:  "pm2." + action,
				Target:  target,
				Status:  "failed",
				Message: "Target contains illegal characters",
			}
		}
	}

	normTarget := target
	if strings.HasPrefix(normTarget, "pm2:") {
		// format pm2:<pm_id>:<name>
		parts := strings.Split(normTarget, ":")
		if len(parts) >= 2 {
			normTarget = parts[1] // Use PMID
		}
	}

	cmd := exec.CommandContext(ctx, pm2Bin, action, normTarget)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return ActionResult{
			Action:  "pm2." + action,
			Target:  target,
			Status:  "failed",
			Message: fmt.Sprintf("pm2 %s failed: %v (%s)", action, err, strings.TrimSpace(string(out))),
		}
	}

	return ActionResult{
		Action:  "pm2." + action,
		Target:  target,
		Status:  "success",
		Message: fmt.Sprintf("PM2 process '%s' %sed successfully", normTarget, action),
	}
}

func findPM2Binary() (string, error) {
	path, err := exec.LookPath("pm2")
	if err == nil {
		return path, nil
	}

	home, _ := os.UserHomeDir()
	fallbacks := []string{
		"/usr/local/bin/pm2",
		"/usr/bin/pm2",
		filepath.Join(home, ".nvm/versions/node", "*", "bin/pm2"),
		filepath.Join(home, ".npm-global/bin/pm2"),
	}
	for _, fb := range fallbacks {
		matches, err := filepath.Glob(fb)
		if err == nil && len(matches) > 0 {
			return matches[0], nil
		}
	}

	return "", fmt.Errorf("pm2 binary not found")
}
