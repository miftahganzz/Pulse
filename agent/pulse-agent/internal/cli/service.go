package cli

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// RunServiceAction starts, stops, or restarts pulse-agent daemon (supports root & user mode)
func RunServiceAction(action string) {
	isRoot := (os.Geteuid() == 0)

	if _, err := exec.LookPath("systemctl"); err == nil {
		var cmdArgs []string
		serviceLabel := "pulse-agent.service"

		if isRoot {
			cmdArgs = []string{action, "pulse-agent"}
		} else {
			// Check if user service exists or is active
			if testOut, testErr := exec.Command("systemctl", "--user", "is-active", "pulse-agent").Output(); testErr == nil || strings.TrimSpace(string(testOut)) != "" {
				cmdArgs = []string{"--user", action, "pulse-agent"}
				serviceLabel = "pulse-agent.service (user mode)"
			} else {
				// System service exists but user is not root
				fmt.Printf("  %s✖ Root privileges required for system service.%s\n", Red, Reset)
				fmt.Printf("  Please run: %ssudo pulse %s%s\n\n", Cyan, action, Reset)
				return
			}
		}

		fmt.Printf("  %s➜ %sing %s...%s\n", Cyan, strings.Title(action), serviceLabel, Reset)
		out, err := exec.Command("systemctl", cmdArgs...).CombinedOutput()
		if err != nil {
			fmt.Printf("  %s✖ Failed to %s pulse-agent:%s\n  %s\n", Red, action, Reset, string(out))
			return
		}

		// Check final state
		checkArgs := []string{"is-active", "pulse-agent"}
		if !isRoot {
			checkArgs = []string{"--user", "is-active", "pulse-agent"}
		}
		statusOut, _ := exec.Command("systemctl", checkArgs...).Output()
		st := strings.TrimSpace(string(statusOut))

		if action == "stop" {
			fmt.Printf("  %s✔ pulse-agent service stopped (inactive)%s\n\n", Green, Reset)
		} else if st == "active" {
			fmt.Printf("  %s✔ pulse-agent service %sed successfully (active)%s\n\n", Green, action, Reset)
		} else {
			fmt.Printf("  %s⚠ pulse-agent service state: %s%s\n\n", Yellow, st, Reset)
		}
		return
	}

	// Fallback when systemctl is unavailable (e.g. containers or non-systemd distros)
	if action == "stop" || action == "restart" {
		if out, err := exec.Command("pkill", "-f", "pulse-agent").CombinedOutput(); err == nil {
			fmt.Printf("  %s✔ Stopped running pulse-agent process%s\n", Green, Reset)
		} else {
			_ = out
		}
	}
	if action == "start" || action == "restart" {
		home, _ := os.UserHomeDir()
		cfgPath := "/etc/pulse/agent.json"
		binPath := "/usr/local/bin/pulse-agent"
		if !isRoot {
			cfgPath = home + "/.pulse/agent.json"
			binPath = home + "/.local/bin/pulse-agent"
		}
		cmd := exec.Command(binPath, "--config", cfgPath)
		if err := cmd.Start(); err == nil {
			fmt.Printf("  %s✔ Started pulse-agent in background (PID: %d)%s\n\n", Green, cmd.Process.Pid, Reset)
		} else {
			fmt.Printf("  %s✖ Failed to start process:%s %v\n\n", Red, Reset, err)
		}
	}
}

// RunLogs streams live logs from systemd journalctl (root & user mode)
func RunLogs(args []string) {
	lines := "50"
	for i, arg := range args {
		if arg == "-n" && i+1 < len(args) {
			lines = args[i+1]
		}
	}

	if _, err := exec.LookPath("journalctl"); err == nil {
		fmt.Printf("%sStreaming pulse-agent logs (Ctrl+C to exit)...%s\n\n", Dim, Reset)

		var cmd *exec.Cmd
		if os.Geteuid() != 0 {
			// Check if user journal has logs for pulse-agent
			if testErr := exec.Command("journalctl", "--user", "-u", "pulse-agent.service", "-n", "1").Run(); testErr == nil {
				cmd = exec.Command("journalctl", "--user", "-u", "pulse-agent.service", "-f", "-n", lines, "--no-pager")
			}
		}
		if cmd == nil {
			cmd = exec.Command("journalctl", "-u", "pulse-agent.service", "-f", "-n", lines, "--no-pager")
		}

		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		cmd.Stdin = os.Stdin
		_ = cmd.Run()
		return
	}

	// Fallback to log file if present
	home, _ := os.UserHomeDir()
	logPaths := []string{"/var/log/pulse.log", home + "/.pulse/agent.log"}
	for _, lp := range logPaths {
		if _, err := os.Stat(lp); err == nil {
			cmd := exec.Command("tail", "-f", "-n", lines, lp)
			cmd.Stdout = os.Stdout
			cmd.Stderr = os.Stderr
			_ = cmd.Run()
			return
		}
	}

	fmt.Printf("  %s✖ journalctl or agent log file not found.%s\n\n", Red, Reset)
}

// RunUninstall removes pulse-agent service, binary, and configs
func RunUninstall(configPath string) {
	PrintBanner()

	isRoot := (os.Geteuid() == 0)
	modeStr := "System-wide"
	if !isRoot {
		modeStr = "User Mode (Non-Root)"
	}

	fmt.Printf("  %s%sUninstalling Pulse Agent (%s)...%s\n\n", Bold, Red, modeStr, Reset)
	fmt.Print("  Are you sure you want to completely remove pulse-agent? [y/N]: ")

	reader := bufio.NewReader(os.Stdin)
	ans, _ := reader.ReadString('\n')
	ans = strings.TrimSpace(strings.ToLower(ans))

	if ans != "y" && ans != "yes" {
		fmt.Println("  Uninstall aborted.")
		return
	}

	if isRoot {
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
	} else {
		home, _ := os.UserHomeDir()
		fmt.Println("  [1/4] Stopping and disabling user service...")
		_ = exec.Command("systemctl", "--user", "stop", "pulse-agent").Run()
		_ = exec.Command("systemctl", "--user", "disable", "pulse-agent").Run()

		fmt.Println("  [2/4] Removing user systemd unit...")
		_ = os.Remove(home + "/.config/systemd/user/pulse-agent.service")
		_ = exec.Command("systemctl", "--user", "daemon-reload").Run()

		fmt.Println("  [3/4] Removing user binaries and symlinks...")
		_ = os.Remove(home + "/.local/bin/pulse-agent")
		_ = os.Remove(home + "/.local/bin/pulse")

		fmt.Printf("  [4/4] Delete configuration & TLS certificates in %s/.pulse? [y/N]: ", home)
		ansCfg, _ := reader.ReadString('\n')
		ansCfg = strings.TrimSpace(strings.ToLower(ansCfg))
		if ansCfg == "y" || ansCfg == "yes" {
			_ = os.RemoveAll(home + "/.pulse")
			fmt.Println("  Configuration directory deleted.")
		}
	}

	fmt.Printf("\n  %s✔ Pulse Agent has been completely uninstalled.%s\n\n", Green, Reset)
}
