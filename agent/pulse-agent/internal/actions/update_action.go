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

	targetDir := filepath.Dir(targetBin)

	// 1. Determine latest version
	latestTag := "latest"
	apiClient := &http.Client{Timeout: 10 * time.Second}
	req, _ := http.NewRequestWithContext(ctx, "GET", "https://api.github.com/repos/miftahganzz/Pulse/releases/latest", nil)
	req.Header.Set("User-Agent", "pulse-agent-updater")

	if resp, err := apiClient.Do(req); err == nil {
		if resp.StatusCode == http.StatusOK {
			var rel githubReleaseInfo
			if err := json.NewDecoder(resp.Body).Decode(&rel); err == nil && rel.TagName != "" {
				latestTag = rel.TagName
			}
		}
		_ = resp.Body.Close()
	}

	// 2. Download latest binary with 90s timeout
	downloadURLs := []string{
		fmt.Sprintf("https://github.com/miftahganzz/Pulse/releases/latest/download/pulse-agent-linux-%s", arch),
		fmt.Sprintf("https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/pulse-agent-linux-%s", arch),
	}
	if latestTag != "" && latestTag != "latest" {
		downloadURLs = append([]string{
			fmt.Sprintf("https://github.com/miftahganzz/Pulse/releases/download/%s/pulse-agent-linux-%s", latestTag, arch),
		}, downloadURLs...)
	}

	// Create staging file in same directory first (for atomic rename), fallback to /tmp
	tmpFile := filepath.Join(targetDir, fmt.Sprintf(".pulse-agent-ota-%d", time.Now().UnixNano()))
	testFile, testErr := os.OpenFile(tmpFile, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0755)
	if testErr != nil {
		tmpFile = fmt.Sprintf("/tmp/pulse-agent-ota-%s-%d", arch, time.Now().UnixNano())
	} else {
		_ = testFile.Close()
		_ = os.Remove(tmpFile)
	}

	defer func() {
		_ = os.Remove(tmpFile)
	}()

	dlClient := &http.Client{Timeout: 90 * time.Second}
	var downloaded bool
	var lastDlErr error

	for _, dlURL := range downloadURLs {
		dlReq, err := http.NewRequestWithContext(ctx, "GET", dlURL, nil)
		if err != nil {
			lastDlErr = err
			continue
		}
		dlResp, err := dlClient.Do(dlReq)
		if err != nil || dlResp.StatusCode != http.StatusOK {
			if dlResp != nil {
				_ = dlResp.Body.Close()
			}
			lastDlErr = fmt.Errorf("HTTP %v", err)
			continue
		}

		out, err := os.OpenFile(tmpFile, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0755)
		if err != nil {
			_ = dlResp.Body.Close()
			lastDlErr = err
			continue
		}

		_, copyErr := io.Copy(out, dlResp.Body)
		_ = out.Close()
		_ = dlResp.Body.Close()

		if copyErr == nil {
			// Verify minimum plausible size (> 2MB)
			if fi, sErr := os.Stat(tmpFile); sErr == nil && fi.Size() > 2*1024*1024 {
				downloaded = true
				break
			}
		}
	}

	if !downloaded {
		return ActionResult{
			Action:  "system.update_agent",
			Target:  "pulse-agent",
			Status:  "failed",
			Message: fmt.Sprintf("Could not download updated pulse-agent binary from release sources: %v", lastDlErr),
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

	// 4. Overwrite target binary atomically without ETXTBSY
	// In Linux, writing directly to an active binary returns ETXTBSY (text file busy).
	// Moving the running binary unlinks its inode and allows safe replacement.
	backupBin := targetBin + ".old"
	_ = os.Remove(backupBin)
	_ = os.Rename(targetBin, backupBin)

	replaceErr := os.Rename(tmpFile, targetBin)
	if replaceErr != nil {
		// If cross-device move, copy tmpFile to targetBin
		srcData, rErr := os.ReadFile(tmpFile)
		if rErr != nil {
			_ = os.Rename(backupBin, targetBin)
			return ActionResult{
				Action:  "system.update_agent",
				Target:  "pulse-agent",
				Status:  "failed",
				Message: fmt.Sprintf("Failed to stage update binary: %v", rErr),
			}
		}
		wErr := os.WriteFile(targetBin, srcData, 0755)
		if wErr != nil {
			_ = os.Rename(backupBin, targetBin)
			return ActionResult{
				Action:  "system.update_agent",
				Target:  "pulse-agent",
				Status:  "failed",
				Message: fmt.Sprintf("Failed to write to %s: %v (permission denied?)", targetBin, wErr),
			}
		}
	}
	_ = os.Remove(backupBin)

	// 5. Schedule background restart
	go func() {
		time.Sleep(1500 * time.Millisecond)
		// 1. Try systemd root
		if os.Geteuid() == 0 {
			if err := exec.Command("systemctl", "restart", "pulse-agent").Run(); err == nil {
				return
			}
		}
		// 2. Try systemd user
		if err := exec.Command("systemctl", "--user", "restart", "pulse-agent").Run(); err == nil {
			return
		}
		// 3. Try service command
		if err := exec.Command("service", "pulse-agent", "restart").Run(); err == nil {
			return
		}
		// 4. Fallback for standalone/nohup/crontab: spawn new process and exit
		cfgPath := "/etc/pulse/agent.json"
		if home, hErr := os.UserHomeDir(); hErr == nil {
			userCfg := filepath.Join(home, ".pulse", "agent.json")
			if _, sErr := os.Stat(userCfg); sErr == nil {
				cfgPath = userCfg
			}
		}
		cmd := exec.Command(targetBin, "--config", cfgPath)
		_ = cmd.Start()
		time.Sleep(500 * time.Millisecond)
		os.Exit(0)
	}()

	return ActionResult{
		Action:  "system.update_agent",
		Target:  "pulse-agent",
		Status:  "success",
		Message: fmt.Sprintf("Successfully installed %s. Service restart initiated.", newVersionStr),
	}
}
