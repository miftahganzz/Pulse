package cli

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// RunServiceAction starts, stops, or restarts pulse-agent daemon
func RunServiceAction(action string) {
	if os.Geteuid() != 0 {
		fmt.Printf("  %s✖ Root privileges required.%s\n", Red, Reset)
		fmt.Printf("  Please run: %ssudo pulse %s%s\n\n", Cyan, action, Reset)
		return
	}

	if _, err := exec.LookPath("systemctl"); err != nil {
		fmt.Printf("  %s✖ systemctl not found on this system.%s\n\n", Red, Reset)
		return
	}

	fmt.Printf("  %s➜ %sing pulse-agent.service...%s\n", Cyan, strings.Title(action), Reset)
	out, err := exec.Command("systemctl", action, "pulse-agent").CombinedOutput()
	if err != nil {
		fmt.Printf("  %s✖ Failed to %s pulse-agent:%s\n  %s\n", Red, action, Reset, string(out))
		return
	}

	// Check final state
	statusOut, _ := exec.Command("systemctl", "is-active", "pulse-agent").Output()
	st := strings.TrimSpace(string(statusOut))

	if action == "stop" {
		fmt.Printf("  %s✔ pulse-agent service stopped (inactive)%s\n\n", Green, Reset)
	} else if st == "active" {
		fmt.Printf("  %s✔ pulse-agent service %sed successfully (active)%s\n\n", Green, action, Reset)
	} else {
		fmt.Printf("  %s⚠ pulse-agent service state: %s%s\n\n", Yellow, st, Reset)
	}
}

// RunLogs streams live logs from systemd journalctl
func RunLogs(args []string) {
	lines := "50"
	for i, arg := range args {
		if arg == "-n" && i+1 < len(args) {
			lines = args[i+1]
		}
	}

	if _, err := exec.LookPath("journalctl"); err == nil {
		fmt.Printf("%sStreaming pulse-agent logs (Ctrl+C to exit)...%s\n\n", Dim, Reset)
		cmd := exec.Command("journalctl", "-u", "pulse-agent.service", "-f", "-n", lines, "--no-pager")
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		cmd.Stdin = os.Stdin
		_ = cmd.Run()
		return
	}

	// Fallback to /var/log/pulse.log if present
	if _, err := os.Stat("/var/log/pulse.log"); err == nil {
		cmd := exec.Command("tail", "-f", "-n", lines, "/var/log/pulse.log")
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		_ = cmd.Run()
		return
	}

	fmt.Printf("  %s✖ journalctl or system log not found.%s\n\n", Red, Reset)
}

// RunUninstall removes pulse-agent service, binary, and configs
func RunUninstall(configPath string) {
	PrintBanner()

	if os.Geteuid() != 0 {
		fmt.Printf("  %s✖ Root privileges required.%s\n", Red, Reset)
		fmt.Printf("  Please run: %ssudo pulse uninstall%s\n\n", Cyan, Reset)
		return
	}

	fmt.Printf("  %s%sUninstalling Pulse Agent...%s\n\n", Bold, Red, Reset)
	fmt.Print("  Are you sure you want to completely remove pulse-agent? [y/N]: ")

	reader := bufio.NewReader(os.Stdin)
	ans, _ := reader.ReadString('\n')
	ans = strings.TrimSpace(strings.ToLower(ans))

	if ans != "y" && ans != "yes" {
		fmt.Println("  Uninstall aborted.")
		return
	}

	fmt.Println("  [1/4] Stopping and disabling pulse-agent service...")
	_ = exec.Command("systemctl", "stop", "pulse-agent").Run()
	_ = exec.Command("systemctl", "disable", "pulse-agent").Run()

	fmt.Println("  [2/4] Removing systemd service unit...")
	_ = os.Remove("/etc/systemd/system/pulse-agent.service")
	_ = exec.Command("systemctl", "daemon-reload").Run()

	fmt.Println("  [3/4] Removing binaries and symlinks...")
	_ = os.Remove("/usr/local/bin/pulse-agent")
	_ = os.Remove("/usr/local/bin/pulse")

	fmt.Print("  [4/4] Delete configuration & TLS certificates in /etc/pulse? [y/N]: ")
	ansCfg, _ := reader.ReadString('\n')
	ansCfg = strings.TrimSpace(strings.ToLower(ansCfg))
	if ansCfg == "y" || ansCfg == "yes" {
		_ = os.RemoveAll("/etc/pulse")
		fmt.Println("  Configuration directory deleted.")
	}

	fmt.Printf("\n  %s✔ Pulse Agent has been completely uninstalled.%s\n\n", Green, Reset)
}
