package tunnel

import (
	"fmt"
	"net"
	"os/exec"
	"strings"
)

type TunnelInfo struct {
	TailscaleActive   bool
	TailscaleIP       string
	TailscaleDNS      string
	CloudflaredActive bool
	SuggestedHost     string
	SuggestedPort     int
}

// DetectPrivateNetworks detects Tailscale and Cloudflare Tunnel configurations
func DetectPrivateNetworks(agentPort int) TunnelInfo {
	info := TunnelInfo{
		SuggestedPort: agentPort,
	}

	// 1. Detect Tailscale
	if _, err := exec.LookPath("tailscale"); err == nil {
		out, err := exec.Command("tailscale", "ip", "-4").Output()
		if err == nil {
			tsIP := strings.TrimSpace(string(out))
			if tsIP != "" {
				info.TailscaleActive = true
				info.TailscaleIP = tsIP
				info.SuggestedHost = tsIP
			}
		}
	} else {
		// Fallback: check interfaces for 100.x.y.z
		ifaces, _ := net.Interfaces()
		for _, iface := range ifaces {
			if strings.HasPrefix(iface.Name, "tailscale") || strings.HasPrefix(iface.Name, "utun") {
				addrs, _ := iface.Addrs()
				for _, addr := range addrs {
					if ipnet, ok := addr.(*net.IPNet); ok && !ipnet.IP.IsLoopback() {
						ip := ipnet.IP.To4()
						if ip != nil && ip[0] == 100 && (ip[1] >= 64 && ip[1] <= 127) {
							info.TailscaleActive = true
							info.TailscaleIP = ip.String()
							info.SuggestedHost = ip.String()
							break
						}
					}
				}
			}
		}
	}

	// 2. Detect Cloudflared (Cloudflare Tunnel)
	if _, err := exec.LookPath("cloudflared"); err == nil {
		out, err := exec.Command("systemctl", "is-active", "cloudflared").Output()
		if err == nil && strings.TrimSpace(string(out)) == "active" {
			info.CloudflaredActive = true
		} else {
			pgrep, _ := exec.Command("pgrep", "cloudflared").Output()
			if len(strings.TrimSpace(string(pgrep))) > 0 {
				info.CloudflaredActive = true
			}
		}
	}

	return info
}

// GenerateCloudflareIngressConfig outputs ready-to-use ingress snippet
func GenerateCloudflareIngressConfig(domain string, agentPort int) string {
	cleanDomain := strings.TrimPrefix(strings.TrimPrefix(domain, "https://"), "http://")
	if cleanDomain == "" {
		cleanDomain = "pulse.yourdomain.com"
	}

	return fmt.Sprintf(`tunnel: <YOUR-TUNNEL-UUID>
credentials-file: /etc/cloudflared/<YOUR-TUNNEL-UUID>.json

ingress:
  # Pulse Agent Route (HTTPS with TLS Passthrough / Disabled Origin Verification for Self-Signed Certs)
  - hostname: %s
    service: https://127.0.0.1:%d
    originRequest:
      noTLSVerify: true
  - service: http_status:404
`, cleanDomain, agentPort)
}

// PrintTunnelGuide prints a helpful terminal guide
func PrintTunnelGuide(agentPort int) {
	info := DetectPrivateNetworks(agentPort)

	fmt.Println("================================================================")
	fmt.Println("🌐 Pulse Zero-Port & Private Network Guide")
	fmt.Println("================================================================")

	if info.TailscaleActive {
		fmt.Println("✔ Tailscale Detected!")
		fmt.Printf("  Tailscale IPv4: %s\n", info.TailscaleIP)
		fmt.Printf("  In Pulse Mac App, you can connect directly with zero open ports:\n")
		fmt.Printf("  • IP Address: %s\n", info.TailscaleIP)
		fmt.Printf("  • Port:       %d\n", agentPort)
		fmt.Println("----------------------------------------------------------------")
	} else {
		fmt.Println("Tailscale: Not detected on this machine.")
		fmt.Println("  Install Tailscale to connect securely without public ports:")
		fmt.Println("  curl -fsSL https://tailscale.com/install.sh | sh")
		fmt.Println("----------------------------------------------------------------")
	}

	if info.CloudflaredActive {
		fmt.Println("✔ Cloudflare Tunnel (cloudflared) Detected!")
	} else {
		fmt.Println("Cloudflare Tunnel (Zero Trust):")
	}
	fmt.Println("  Expose Pulse securely over standard port 443 with your domain:")
	fmt.Println("  1. Add DNS hostname in Cloudflare: e.g. pulse.yourdomain.com")
	fmt.Println("  2. In Cloudflare Zero Trust Dashboard, set Public Hostname:")
	fmt.Printf("     • Service Type: HTTPS\n")
	fmt.Printf("     • URL:          127.0.0.1:%d\n", agentPort)
	fmt.Println("     • TLS Settings: Enable 'No TLS Verify' (self-signed cert)")
	fmt.Println("  3. In Pulse Mac App, simply enter:")
	fmt.Println("     • Address: https://pulse.yourdomain.com")
	fmt.Println("     • Port:    443")
	fmt.Println("================================================================")
}
