package cli

import (
	"fmt"
	"runtime"

	"github.com/pulse/pulse-agent/internal/agent"
)

// ANSI Styling
const (
	Reset  = "\033[0m"
	Bold   = "\033[1m"
	Dim    = "\033[2m"
	Cyan   = "\033[38;5;45m"
	Blue   = "\033[38;5;39m"
	Purple = "\033[38;5;141m"
	Green  = "\033[38;5;84m"
	Yellow = "\033[38;5;221m"
	Red    = "\033[38;5;203m"
)

func PrintBanner() {
	fmt.Printf("\n  %sPulse%s %s(v%s)%s  •  Infrastructure Observability CLI\n\n", Bold, Reset, Dim, agent.CurrentAgentVersion, Reset)
}

func PrintHelp() {
	PrintBanner()
	fmt.Printf("  %sUsage:%s %spulse <command> [arguments]%s\n\n", Bold, Reset, Cyan, Reset)

	fmt.Printf("  %s%sCore Commands:%s\n", Bold, Yellow, Reset)
	fmt.Printf("    %sstatus%s        Check agent health, ports, IPs, and pairing status\n", Cyan, Reset)
	fmt.Printf("    %spair%s [code]   Generate or register a 6-digit pairing code (XXX-XXX)\n", Cyan, Reset)
	fmt.Printf("    %slogs%s [-n N]   Stream live agent logs in real time\n", Cyan, Reset)
	fmt.Printf("    %sdoctor%s        Run comprehensive system & network diagnostics\n", Cyan, Reset)
	fmt.Println()

	fmt.Printf("  %s%sNetworking & Tunnels:%s\n", Bold, Yellow, Reset)
	fmt.Printf("    %stailscale%s     One-command Tailscale setup or status verification\n", Cyan, Reset)
	fmt.Printf("    %scloudflare%s    Cloudflare Tunnel setup guide & ingress config\n", Cyan, Reset)
	fmt.Println()

	fmt.Printf("  %s%sService Management:%s\n", Bold, Yellow, Reset)
	fmt.Printf("    %sstart%s         Start pulse-agent daemon service\n", Cyan, Reset)
	fmt.Printf("    %sstop%s          Stop pulse-agent daemon service\n", Cyan, Reset)
	fmt.Printf("    %srestart%s       Restart pulse-agent daemon service\n", Cyan, Reset)
	fmt.Println()

	fmt.Printf("  %s%sMaintenance & Upgrades:%s\n", Bold, Yellow, Reset)
	fmt.Printf("    %supdate%s        Self-update pulse-agent to the latest release\n", Cyan, Reset)
	fmt.Printf("    %suninstall%s     Completely remove pulse-agent and its service\n", Cyan, Reset)
	fmt.Printf("    %sversion%s       Display installed agent version and architecture\n", Cyan, Reset)
	fmt.Printf("    %shelp%s          Show this help message\n", Cyan, Reset)
	fmt.Println()

	fmt.Printf("  %sQuick Connect (Mac):%s %spulse://add?name=<server>&host=<ip>&port=<port>&token=<token>%s\n\n", Dim, Reset, Dim, Reset)
}

// HandleCommand processes subcommands. Returns true if handled.
func HandleCommand(args []string, configPath string) bool {
	if len(args) == 0 {
		// If run without arguments, show concise status overview then help
		RunStatus(configPath, true)
		return true
	}

	cmd := args[0]
	subArgs := args[1:]

	switch cmd {
	case "help", "-h", "--help":
		PrintHelp()
		return true

	case "version", "-v", "--version":
		fmt.Printf("pulse-agent v%s (%s/%s)\n", agent.CurrentAgentVersion, runtime.GOOS, runtime.GOARCH)
		return true

	case "status", "info":
		RunStatus(configPath, false)
		return true

	case "pair":
		RunPair(configPath, subArgs)
		return true

	case "doctor":
		RunDoctor(configPath)
		return true

	case "tailscale":
		RunTailscale(configPath, subArgs)
		return true

	case "cloudflare":
		RunCloudflare(configPath, subArgs)
		return true

	case "update", "upgrade":
		RunUpdate(configPath, subArgs)
		return true

	case "logs", "log":
		RunLogs(subArgs)
		return true

	case "start":
		RunServiceAction("start")
		return true

	case "stop":
		RunServiceAction("stop")
		return true

	case "restart":
		RunServiceAction("restart")
		return true

	case "uninstall":
		RunUninstall(configPath)
		return true

	default:
		// Unknown subcommand or handled by legacy flags
		return false
	}
}
