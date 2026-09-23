package tunnel

import (
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
)

type TunnelInfo struct {
	TailscaleActive   bool
	TailscaleIP       string
	TailscaleDNS      string
	CloudflaredActive bool
	CloudflareURL     string
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

	if info.CloudflaredActive {
		info.CloudflareURL = findCloudflareURL()
		if info.CloudflareURL != "" {
			if info.SuggestedHost == "" {
				info.SuggestedHost = info.CloudflareURL
				info.SuggestedPort = 443
			}
		}
	}

	return info
}

// findCloudflareURL attempts to find active quick tunnel or named domain
func findCloudflareURL() string {
	// 1. Scan live cloudflared logs for the latest active trycloudflare.com URL
	logPaths := []string{"/var/log/cloudflared.log"}
	if home, err := os.UserHomeDir(); err == nil {
		logPaths = append([]string{filepath.Join(home, ".pulse", "cloudflared.log")}, logPaths...)
	}
	re := regexp.MustCompile(`https://([a-zA-Z0-9.-]+\.trycloudflare\.com)`)
	for _, lp := range logPaths {
		if data, err := os.ReadFile(lp); err == nil {
			matches := re.FindAllStringSubmatch(string(data), -1)
			if len(matches) > 0 {
				last := matches[len(matches)-1]
				if len(last) > 1 && last[1] != "" {
					activeURL := last[1]
					// Sync to tunnel_url state file
					tunnelFile := filepath.Join(filepath.Dir(lp), "tunnel_url")
					_ = os.WriteFile(tunnelFile, []byte(activeURL), 0644)
					return activeURL
				}
			}
		}
	}

	// 2. Fallback to tunnel_url state files
	urlPaths := []string{"/etc/pulse/tunnel_url"}
	if home, err := os.UserHomeDir(); err == nil {
		urlPaths = append([]string{filepath.Join(home, ".pulse", "tunnel_url")}, urlPaths...)
	}
	for _, p := range urlPaths {
		if data, err := os.ReadFile(p); err == nil {
			clean := strings.TrimSpace(string(data))
			clean = strings.TrimPrefix(clean, "https://")
			clean = strings.TrimPrefix(clean, "http://")
			clean = strings.TrimRight(clean, "/")
			if clean != "" {
				return clean
			}
		}
	}

	return ""
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
		if info.CloudflareURL != "" {
			fmt.Printf("  Active Tunnel URL: https://%s\n", info.CloudflareURL)
			fmt.Printf("  • Address in Mac Pulse: %s\n", info.CloudflareURL)
			fmt.Println("  • Port:                 443")
			fmt.Println("----------------------------------------------------------------")
		}
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
