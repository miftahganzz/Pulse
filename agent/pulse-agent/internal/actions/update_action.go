package actions

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

type githubReleaseInfo struct {
	TagName string `json:"tag_name"`
	Name    string `json:"name"`
}

func executeAgentUpdate(ctx context.Context) ActionResult {
	arch := runtime.GOARCH
	if arch != "amd64" && arch != "arm64" {
		return ActionResult{
			Action:  "system.update_agent",
			Target:  "pulse-agent",
			Status:  "failed",
			Message: fmt.Sprintf("Unsupported architecture for self-update: %s", arch),
		}
	}

	execPath, err := os.Executable()
	targetBin := "/usr/local/bin/pulse-agent"
	if err == nil && execPath != "" {
		if realPath, rErr := filepath.EvalSymlinks(execPath); rErr == nil {
			targetBin = realPath
		} else {
			targetBin = execPath
		}
	}

	// 1. Determine latest version
	latestTag := "latest"
	client := &http.Client{Timeout: 8 * time.Second}
	req, _ := http.NewRequestWithContext(ctx, "GET", "https://api.github.com/repos/miftahganzz/Pulse/releases/latest", nil)
	req.Header.Set("User-Agent", "pulse-agent-updater")

	if resp, err := client.Do(req); err == nil {
		if resp.StatusCode == http.StatusOK {
			var rel githubReleaseInfo
			if err := json.NewDecoder(resp.Body).Decode(&rel); err == nil && rel.TagName != "" {
				latestTag = rel.TagName
			}
		}
		_ = resp.Body.Close()
	}

	// 2. Download latest binary
	downloadURLs := []string{
		fmt.Sprintf("https://github.com/miftahganzz/Pulse/releases/download/%s/pulse-agent-linux-%s", latestTag, arch),
		fmt.Sprintf("https://github.com/miftahganzz/Pulse/releases/latest/download/pulse-agent-linux-%s", arch),
		fmt.Sprintf("https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/bin/pulse-agent-linux-%s", arch),
	}

	tmpFile := fmt.Sprintf("/tmp/pulse-agent-ota-%s-%d", arch, time.Now().Unix())
	defer func() {
		_ = os.Remove(tmpFile)
	}()

	var downloaded bool
	for _, dlURL := range downloadURLs {
		dlReq, err := http.NewRequestWithContext(ctx, "GET", dlURL, nil)
		if err != nil {
			continue
		}
		dlResp, err := client.Do(dlReq)
		if err != nil || dlResp.StatusCode != http.StatusOK {
			if dlResp != nil {
				_ = dlResp.Body.Close()
			}
			continue
		}

		out, err := os.OpenFile(tmpFile, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0755)
		if err != nil {
			_ = dlResp.Body.Close()
			continue
		}

		_, copyErr := io.Copy(out, dlResp.Body)
		_ = out.Close()
		_ = dlResp.Body.Close()

		if copyErr == nil {
			downloaded = true
			break
		}
	}

	if !downloaded {
		return ActionResult{
			Action:  "system.update_agent",
			Target:  "pulse-agent",
			Status:  "failed",
			Message: "Could not download updated pulse-agent binary from release sources",
		}
	}

	_ = os.Chmod(tmpFile, 0755)

	// 3. Smoke test the downloaded binary
	verTestCmd := exec.CommandContext(ctx, tmpFile, "version")
	verOut, err := verTestCmd.CombinedOutput()
	if err != nil {
		return ActionResult{
			Action:  "system.update_agent",
			Target:  "pulse-agent",
			Status:  "failed",
			Message: fmt.Sprintf("Downloaded binary failed smoke test: %v (%s)", err, strings.TrimSpace(string(verOut))),
		}
	}

	newVersionStr := strings.TrimSpace(string(verOut))

	// 4. Overwrite target binary
	replaceErr := os.Rename(tmpFile, targetBin)
	if replaceErr != nil {
		srcData, rErr := os.ReadFile(tmpFile)
		if rErr != nil {
			return ActionResult{
				Action:  "system.update_agent",
				Target:  "pulse-agent",
				Status:  "failed",
				Message: fmt.Sprintf("Failed to stage update binary: %v", rErr),
			}
		}
		wErr := os.WriteFile(targetBin, srcData, 0755)
		if wErr != nil {
			return ActionResult{
				Action:  "system.update_agent",
				Target:  "pulse-agent",
				Status:  "failed",
				Message: fmt.Sprintf("Failed to write to %s: %v (permission denied?)", targetBin, wErr),
			}
		}
	}

	// 5. Schedule background restart so WebSocket response can return first
	go func() {
		time.Sleep(1500 * time.Millisecond)
		if os.Geteuid() == 0 {
			_ = exec.Command("systemctl", "restart", "pulse-agent").Run()
		} else {
			_ = exec.Command("systemctl", "--user", "restart", "pulse-agent").Run()
		}
	}()

	return ActionResult{
		Action:  "system.update_agent",
		Target:  "pulse-agent",
		Status:  "success",
		Message: fmt.Sprintf("Successfully installed %s. Service restart initiated.", newVersionStr),
	}
}
