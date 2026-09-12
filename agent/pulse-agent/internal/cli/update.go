package cli

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"time"

	"github.com/pulse/pulse-agent/internal/agent"
)

type githubRelease struct {
	TagName string `json:"tag_name"`
	Name    string `json:"name"`
	Body    string `json:"body"`
}

// RunUpdate performs self-update from GitHub Releases
func RunUpdate(configPath string, args []string) {
	PrintBanner()

	force := false
	for _, arg := range args {
		if arg == "--force" || arg == "-f" {
			force = true
		}
	}

	if os.Geteuid() != 0 {
		fmt.Printf("  %s✖ Root privileges required.%s\n", Red, Reset)
		fmt.Printf("  Please run: %ssudo pulse update%s\n\n", Cyan, Reset)
		return
	}

	fmt.Printf("  %s%sChecking for pulse-agent updates...%s\n", Bold, Cyan, Reset)
	fmt.Printf("  Current version: %sv%s%s (%s/%s)\n\n", Bold, agent.CurrentAgentVersion, Reset, runtime.GOOS, runtime.GOARCH)

	// 1. Fetch latest release info from GitHub API
	client := &http.Client{Timeout: 5 * time.Second}
	req, _ := http.NewRequest("GET", "https://api.github.com/repos/miftahganzz/Pulse/releases/latest", nil)
	req.Header.Set("User-Agent", "pulse-agent-updater")

	resp, err := client.Do(req)
	var latestTag string
	if err == nil && resp.StatusCode == http.StatusOK {
		var rel githubRelease
		if err := json.NewDecoder(resp.Body).Decode(&rel); err == nil {
			latestTag = rel.TagName
		}
		_ = resp.Body.Close()
	}

	if latestTag == "" {
		// Fallback: check raw tag or assume current if network fails
		latestTag = "v" + agent.CurrentAgentVersion
	}

	cleanLatestVer := strings.TrimPrefix(latestTag, "v")
	cleanCurrentVer := strings.TrimPrefix(agent.CurrentAgentVersion, "v")

	if !force && cleanLatestVer == cleanCurrentVer {
		fmt.Printf("  %s✔ pulse-agent is already up to date!%s (v%s)\n\n", Green, Reset, cleanCurrentVer)
		return
	}

	fmt.Printf("  New version available: %s%s%s\n", Bold, latestTag, Reset)
	fmt.Println("  [1/3] Downloading latest binary for " + runtime.GOARCH + "...")

	arch := runtime.GOARCH
	if arch != "amd64" && arch != "arm64" {
		fmt.Printf("  %s✖ Unsupported architecture for auto-update: %s%s\n\n", Red, arch, Reset)
		return
	}

	downloadURL := fmt.Sprintf("https://github.com/miftahganzz/Pulse/releases/download/%s/pulse-agent-linux-%s", latestTag, arch)
	tmpFile := fmt.Sprintf("/tmp/pulse-agent-update-%s", arch)

	dlResp, err := http.Get(downloadURL)
	if err != nil || dlResp.StatusCode != http.StatusOK {
		// Try generic latest download URL
		downloadURL = fmt.Sprintf("https://github.com/miftahganzz/Pulse/releases/latest/download/pulse-agent-linux-%s", arch)
		dlResp, err = http.Get(downloadURL)
		if err != nil || dlResp.StatusCode != http.StatusOK {
			fmt.Printf("  %s✖ Failed to download update binary from GitHub:%s %v\n\n", Red, Reset, err)
			return
		}
	}
	defer dlResp.Body.Close()

	out, err := os.OpenFile(tmpFile, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0755)
	if err != nil {
		fmt.Printf("  %s✖ Could not create temporary binary file:%s %v\n\n", Red, Reset, err)
		return
	}
	_, err = io.Copy(out, dlResp.Body)
	_ = out.Close()
	if err != nil {
		fmt.Printf("  %s✖ Download failed:%s %v\n\n", Red, Reset, err)
		return
	}

	// 2. Validate downloaded binary
	fmt.Println("  [2/3] Verifying binary integrity...")
	checkCmd := exec.Command(tmpFile, "-version")
	checkOut, err := checkCmd.Output()
	if err != nil || !strings.Contains(string(checkOut), "pulse-agent") {
		fmt.Printf("  %s✖ Downloaded binary failed integrity check:%s %v\n\n", Red, Reset, err)
		_ = os.Remove(tmpFile)
		return
	}

	// 3. Swap binary
	fmt.Println("  [3/3] Replacing /usr/local/bin/pulse-agent and restarting daemon...")
	targetBin := "/usr/local/bin/pulse-agent"
	if err := os.Rename(tmpFile, targetBin); err != nil {
		// If rename fails (e.g. across mount points), copy and remove
		if copyErr := exec.Command("cp", "-f", tmpFile, targetBin).Run(); copyErr != nil {
			fmt.Printf("  %s✖ Failed to install binary to %s:%s %v\n\n", Red, targetBin, Reset, copyErr)
			return
		}
		_ = os.Remove(tmpFile)
	}
	_ = os.Chmod(targetBin, 0755)

	// Ensure /usr/local/bin/pulse symlink
	_ = os.Symlink(targetBin, "/usr/local/bin/pulse")

	// Restart systemd service if available
	if _, err := exec.LookPath("systemctl"); err == nil {
		_ = exec.Command("systemctl", "daemon-reload").Run()
		_ = exec.Command("systemctl", "restart", "pulse-agent").Run()
	}

	fmt.Printf("\n  %s%s✔ pulse-agent successfully updated to %s!%s\n\n", Bold, Green, latestTag, Reset)
}
