package cli

import (
	"fmt"
	"strings"

	"github.com/pulse/pulse-agent/internal/agent"
	"github.com/pulse/pulse-agent/internal/tunnel"
)

// RunCloudflare guides Cloudflare Tunnel configuration for zero-open-port ingress
func RunCloudflare(configPath string, args []string) {
	PrintBanner()

	cfg, _, err := agent.LoadOrCreateConfig(configPath)
	if err != nil {
		fmt.Printf("  %s✖ Error loading config:%s %v\n\n", Red, Reset, err)
		return
	}

	tInfo := tunnel.DetectPrivateNetworks(cfg.Port)

	fmt.Printf("  %s%sCloudflare Tunnel (Zero-Port Exposure)%s\n\n", Bold, Purple, Reset)

	if tInfo.CloudflaredActive {
		fmt.Printf("  %sStatus:%s   %s● cloudflared service is running%s\n\n", Bold, Reset, Green, Reset)
	} else {
		fmt.Printf("  %sStatus:%s   %s○ cloudflared is not active%s\n\n", Bold, Reset, Dim, Reset)
	}

	var targetDomain string
	if len(args) > 0 && !strings.HasPrefix(args[0], "-") {
		targetDomain = args[0]
	} else {
		targetDomain = "pulse.yourdomain.com"
	}

	fmt.Println("  Cloudflare Tunnel securely proxies HTTPS traffic from Cloudflare's Edge")
	fmt.Println("  directly to your local Pulse agent without opening any inbound firewall ports.")
	fmt.Println()

	fmt.Printf("  %s1-Command Automated Tunnel Setup:%s\n", Bold, Reset)
	fmt.Printf("    %sRoot:     curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/setup-cloudflare.sh | sudo bash%s\n", Cyan, Reset)
	fmt.Printf("    %sNon-Root: curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/setup-cloudflare.sh | bash%s\n\n", Cyan, Reset)

	fmt.Printf("  %s%sManual Setup Steps:%s\n", Bold, Yellow, Reset)
	fmt.Println("  1. Install cloudflared:")
	fmt.Printf("     %scurl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null%s\n", Cyan, Reset)
	fmt.Printf("     %secho 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared jammy main' | sudo tee /etc/apt/sources.list.d/cloudflared.list%s\n", Cyan, Reset)
	fmt.Printf("     %ssudo apt-get update && sudo apt-get install -y cloudflared%s\n\n", Cyan, Reset)

	fmt.Println("  2. Authenticate tunnel:")
	fmt.Printf("     %scloudflared tunnel login%s\n", Cyan, Reset)
	fmt.Printf("     %scloudflared tunnel create pulse-tunnel%s\n\n", Cyan, Reset)

	fmt.Printf("  3. Save config to %s/etc/cloudflared/config.yml%s:\n", Bold, Reset)
	fmt.Printf("%s%s%s\n", Cyan, tunnel.GenerateCloudflareIngressConfig(targetDomain, cfg.Port), Reset)

	fmt.Println("  4. Start cloudflared system service:")
	fmt.Printf("     %ssudo cloudflared service install%s\n", Cyan, Reset)
	fmt.Printf("     %ssudo systemctl start cloudflared%s\n\n", Cyan, Reset)

	fmt.Printf("  %sConnect from Mac Pulse:%s %shttps://%s%s (Port 443, Token: %s%s%s)\n\n",
		Bold, Reset, Cyan, targetDomain, Reset, Yellow, cfg.AuthToken, Reset)
}
