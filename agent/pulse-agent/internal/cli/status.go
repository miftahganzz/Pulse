package cli

import (
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os/exec"
	"strings"
	"time"

	"github.com/pulse/pulse-agent/internal/agent"
	"github.com/pulse/pulse-agent/internal/pairing"
	"github.com/pulse/pulse-agent/internal/tunnel"
)

// RunStatus displays comprehensive or compact agent status
func RunStatus(configPath string, compact bool) {
	PrintBanner()

	cfg, _, err := agent.LoadOrCreateConfig(configPath)
	if err != nil {
		fmt.Printf("  %s✖ Error loading config:%s %v\n\n", Red, Reset, err)
		return
	}

	identity := agent.CollectIdentity(cfg.AgentID)

	// 1. Service Status Check
	serviceState := "stopped"
	isServiceActive := false
	if out, err := exec.Command("systemctl", "is-active", "pulse-agent").Output(); err == nil {
		serviceState = strings.TrimSpace(string(out))
		if serviceState == "active" {
			isServiceActive = true
		}
	} else {
		// Fallback check pgrep
		if out, err := exec.Command("pgrep", "-x", "pulse-agent").Output(); err == nil && len(strings.TrimSpace(string(out))) > 0 {
			serviceState = "running (pid " + strings.Fields(string(out))[0] + ")"
			isServiceActive = true
		}
	}

	// 2. Local HTTPS Health Probe
	daemonResponsive := false
	tr := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	client := &http.Client{Transport: tr, Timeout: 1 * time.Second}
	resp, err := client.Get(fmt.Sprintf("https://127.0.0.1:%d/api/v1/agent/health", cfg.Port))
	if err == nil {
		daemonResponsive = (resp.StatusCode == http.StatusOK)
		_ = resp.Body.Close()
	}

	// 3. Network Discovery
	tInfo := tunnel.DetectPrivateNetworks(cfg.Port)
	lanIP := getLocalLANIP()
	publicIP := getPublicIP()

	// 4. Pairing Code Check
	pm := pairing.InitGlobalManager(configPath)
	activeSess := pm.GetActiveSession()
	var activeCode string
	var pairExpires time.Time
	isPairValid := false
	if activeSess != nil {
		activeCode = activeSess.PairCode
		pairExpires = activeSess.ExpiresAt
		isPairValid = true
	}

	// Status Line
	var statusBadge string
	if isServiceActive && daemonResponsive {
		statusBadge = fmt.Sprintf("%s● Active & Listening%s", Green, Reset)
	} else if isServiceActive {
		statusBadge = fmt.Sprintf("%s● Running (Starting up)%s", Yellow, Reset)
	} else {
		statusBadge = fmt.Sprintf("%s○ Inactive (%s)%s", Dim, serviceState, Reset)
	}

	fmt.Printf("  %sDaemon Status:%s   %s\n", Bold, Reset, statusBadge)
	fmt.Printf("  %sListen Port:%s     %s%d%s %s(TLS / HTTPS)%s\n", Bold, Reset, Cyan, cfg.Port, Reset, Dim, Reset)
	fmt.Printf("  %sHostname:%s        %s\n", Bold, Reset, identity.Hostname)
	fmt.Printf("  %sArchitecture:%s    %s (%s)\n", Bold, Reset, identity.Architecture, identity.OS)

	fmt.Println()
	fmt.Printf("  %s%sNetwork Addresses:%s\n", Bold, Yellow, Reset)
	if tInfo.TailscaleActive && tInfo.TailscaleIP != "" {
		fmt.Printf("    %s• Tailscale (P2P):%s  %s%s%s\n", Cyan, Reset, Bold, tInfo.TailscaleIP, Reset)
	}
	if lanIP != "" {
		fmt.Printf("    %s• LAN / Local IP:%s   %s%s%s\n", Cyan, Reset, Bold, lanIP, Reset)
	}
	if publicIP != "" {
		fmt.Printf("    %s• Public IPv4:%s      %s%s%s\n", Cyan, Reset, Bold, publicIP, Reset)
	}

	if isPairValid {
		minsLeft := int(time.Until(pairExpires).Minutes())
		fmt.Println()
		fmt.Printf("  %s%sActive Pairing Code:%s  %s%s%s %s(Expires in %dm)%s\n", Bold, Green, Reset, Bold, activeCode, Reset, Dim, minsLeft, Reset)
		fmt.Printf("  %sIn Pulse Mac App, add via XXX-XXX Pair Code with code %s%s%s\n", Dim, Bold, activeCode, Dim)
	}

	if !compact {
		fmt.Println()
		fmt.Printf("  %s%sAuthentication & Config:%s\n", Bold, Yellow, Reset)
		fmt.Printf("    %sAgent ID:%s     %s\n", Dim, Reset, cfg.AgentID)
		fmt.Printf("    %sConfig Path:%s  %s\n", Dim, Reset, configPath)
		fmt.Printf("    %sAuth Token:%s   %s%s%s\n", Dim, Reset, Yellow, cfg.AuthToken, Reset)

		fmt.Println()
		primaryHost := tInfo.TailscaleIP
		if primaryHost == "" {
			primaryHost = publicIP
		}
		if primaryHost == "" {
			primaryHost = lanIP
		}
		if primaryHost != "" {
			fmt.Printf("  %s1-Click Deep Link for Mac:%s\n", Bold, Reset)
			fmt.Printf("  %spulse://add?name=%s&host=%s&port=%d&token=%s%s\n", Cyan, identity.Hostname, primaryHost, cfg.Port, cfg.AuthToken, Reset)
		}
	} else {
		fmt.Println()
		fmt.Printf("  %sCommon Commands:%s\n", Dim, Reset)
		fmt.Printf("    %spulse status%s      Full details, token & connection deep-link\n", Cyan, Reset)
		fmt.Printf("    %spulse pair%s        Generate a new XXX-XXX pairing code\n", Cyan, Reset)
		fmt.Printf("    %spulse logs%s        Stream live daemon output\n", Cyan, Reset)
		fmt.Printf("    %spulse update%s      Update to latest release\n", Cyan, Reset)
		fmt.Printf("    %spulse help%s        List all available commands\n", Cyan, Reset)
	}
	fmt.Println()
}

func getLocalLANIP() string {
	addrs, err := net.InterfaceAddrs()
	if err != nil {
		return ""
	}
	for _, addr := range addrs {
		if ipnet, ok := addr.(*net.IPNet); ok && !ipnet.IP.IsLoopback() {
			if ipnet.IP.To4() != nil {
				ip := ipnet.IP.String()
				if strings.HasPrefix(ip, "192.168.") || strings.HasPrefix(ip, "10.") || strings.HasPrefix(ip, "172.16.") {
					return ip
				}
			}
		}
	}
	return ""
}

func getPublicIP() string {
	endpoints := []string{"https://api.ipify.org", "https://icanhazip.com", "https://ifconfig.me/ip"}
	ch := make(chan string, len(endpoints))
	client := &http.Client{Timeout: 1200 * time.Millisecond}

	for _, ep := range endpoints {
		go func(url string) {
			resp, err := client.Get(url)
			if err == nil && resp.StatusCode == http.StatusOK {
				body, _ := io.ReadAll(resp.Body)
				_ = resp.Body.Close()
				ip := strings.TrimSpace(string(body))
				if net.ParseIP(ip) != nil {
					ch <- ip
					return
				}
			}
			ch <- ""
		}(ep)
	}

	for i := 0; i < len(endpoints); i++ {
		select {
		case ip := <-ch:
			if ip != "" {
				return ip
			}
		case <-time.After(1200 * time.Millisecond):
			return ""
		}
	}
	return ""
}

func parseJSONField(data []byte, field string) string {
	var m map[string]interface{}
	if err := json.Unmarshal(data, &m); err == nil {
		if v, ok := m[field].(string); ok {
			return v
		}
	}
	return ""
}
