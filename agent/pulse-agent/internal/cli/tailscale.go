package cli

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/pulse/pulse-agent/internal/agent"
	"github.com/pulse/pulse-agent/internal/tunnel"
)

// RunTailscale manages Tailscale installation, status, and zero-port connectivity
func RunTailscale(configPath string, args []string) {
	PrintBanner()

	cfg, _, err := agent.LoadOrCreateConfig(configPath)
	if err != nil {
		fmt.Printf("  %s✖ Error loading config:%s %v\n\n", Red, Reset, err)
		return
	}

	identity := agent.CollectIdentity(cfg.AgentID)
	tInfo := tunnel.DetectPrivateNetworks(cfg.Port)

	// Check if user requested install / setup explicitly
	isInstallReq := false
	var authKey string
	for i, arg := range args {
		if arg == "install" || arg == "setup" {
			isInstallReq = true
		} else if strings.HasPrefix(arg, "--authkey=") {
			authKey = strings.TrimPrefix(arg, "--authkey=")
		} else if arg == "--authkey" && i+1 < len(args) {
			authKey = args[i+1]
		}
	}

	_, hasTailscaleCmd := exec.LookPath("tailscale")

	// If already installed and active:
	if tInfo.TailscaleActive && tInfo.TailscaleIP != "" {
		fmt.Printf("  %s%sTailscale WireGuard Mesh is Active%s\n\n", Bold, Green, Reset)
		fmt.Printf("  %sNode IP:%s        %s%s%s\n", Bold, Reset, Cyan, tInfo.TailscaleIP, Reset)

		// Get MagicDNS name
		dnsName := ""
		if out, err := exec.Command("tailscale", "status", "--json").Output(); err == nil {
			dnsName = parseJSONField(out, "MagicDNSSuffix")
		}
		if dnsName != "" {
			fmt.Printf("  %sMagicDNS:%s       %s.%s\n", Bold, Reset, identity.Hostname, dnsName)
		}
		fmt.Printf("  %sListen Port:%s    %d\n", Bold, Reset, cfg.Port)

		fmt.Println()
		fmt.Printf("  %s%sConnect from Pulse Mac App:%s\n", Bold, Yellow, Reset)
		fmt.Printf("  1. Ensure Tailscale is also running on your Mac.\n")
		fmt.Printf("  2. Click this 1-click link (or enter IP %s):\n", tInfo.TailscaleIP)
		fmt.Printf("     %spulse://add?name=%s&host=%s&port=%d&token=%s%s\n", Cyan, identity.Hostname, tInfo.TailscaleIP, cfg.Port, cfg.AuthToken, Reset)
		fmt.Println()
		return
	}

	// Tailscale is installed but not connected
	if hasTailscaleCmd == nil && (!tInfo.TailscaleActive || tInfo.TailscaleIP == "") {
		fmt.Printf("  %s%sTailscale is Installed but Inactive%s\n\n", Bold, Yellow, Reset)
		fmt.Println("  To authenticate this machine and join your Tailnet, run:")
		if authKey != "" {
			fmt.Printf("    %ssudo tailscale up --authkey=%s%s\n\n", Cyan, authKey, Reset)
			runCmd("tailscale", "up", "--authkey="+authKey)
		} else {
			fmt.Printf("    %ssudo tailscale up%s\n\n", Cyan, Reset)
		}
		return
	}

	// Tailscale is NOT installed
	fmt.Printf("  %s%sTailscale Zero-Port Setup%s\n\n", Bold, Purple, Reset)
	fmt.Println("  Tailscale creates a private, encrypted WireGuard mesh network.")
	fmt.Println("  Allows Pulse to connect to this server without opening ports in your firewall.")
	fmt.Println()

	if !isInstallReq && os.Geteuid() != 0 {
		fmt.Printf("  %sTo install Tailscale automatically, run:%s\n", Bold, Reset)
		fmt.Printf("    %ssudo pulse tailscale install%s\n\n", Cyan, Reset)
		fmt.Printf("  Or run the 1-line setup script:\n")
		fmt.Printf("    %sRoot:     curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/setup-tailscale.sh | sudo bash%s\n", Cyan, Reset)
		fmt.Printf("    %sNon-Root: curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/setup-tailscale.sh | bash%s\n\n", Cyan, Reset)
		return
	}

	// If root, perform automated installation
	fmt.Println("  [1/3] Downloading & installing Tailscale...")
	installCmd := exec.Command("sh", "-c", "curl -fsSL https://tailscale.com/install.sh | sh")
	installCmd.Stdout = os.Stdout
	installCmd.Stderr = os.Stderr
	if err := installCmd.Run(); err != nil {
		fmt.Printf("  %s✖ Tailscale installation failed:%s %v\n\n", Red, Reset, err)
		return
	}

	fmt.Println("  [2/3] Enabling tailscaled system service...")
	_ = exec.Command("systemctl", "enable", "--now", "tailscaled").Run()

	fmt.Println("  [3/3] Authenticating Tailscale node...")
	if authKey != "" {
		_ = exec.Command("tailscale", "up", "--authkey="+authKey).Run()
	} else {
		fmt.Println()
		fmt.Printf("  %sPlease complete login by running:%s %ssudo tailscale up%s\n\n", Yellow, Reset, Cyan, Reset)
	}
}

func runCmd(name string, args ...string) {
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	_ = cmd.Run()
}
