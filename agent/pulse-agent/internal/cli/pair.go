package cli

import (
	"bytes"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/pulse/pulse-agent/internal/agent"
	"github.com/pulse/pulse-agent/internal/pairing"
	"github.com/pulse/pulse-agent/internal/tunnel"
)

// RunPair handles generation and registration of 6-digit (XXX-XXX) pairing codes
func RunPair(configPath string, args []string) {
	PrintBanner()

	cfg, _, err := agent.LoadOrCreateConfig(configPath)
	if err != nil {
		fmt.Printf("  %s✖ Error loading config:%s %v\n\n", Red, Reset, err)
		return
	}

	pm := pairing.InitGlobalManager(configPath)
	identity := agent.CollectIdentity(cfg.AgentID)

	var pairCode string
	if len(args) > 0 && args[0] != "new" {
		pairCode = args[0]
		pm.SetExplicitCode(pairCode, cfg, identity.Hostname)
	} else {
		pairCode, err = pm.GenerateCode(cfg, identity.Hostname)
		if err != nil {
			fmt.Printf("  %s✖ Failed to generate pairing code:%s %v\n\n", Red, Reset, err)
			return
		}
	}

	// Notify active daemon if running locally
	tr := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	client := &http.Client{Transport: tr, Timeout: 1 * time.Second}
	body, _ := json.Marshal(map[string]string{"pair_code": pairCode})
	req, reqErr := http.NewRequest("POST", fmt.Sprintf("https://127.0.0.1:%d/api/v1/pair/register", cfg.Port), bytes.NewReader(body))
	if reqErr == nil {
		req.Header.Set("Authorization", "Bearer "+cfg.AuthToken)
		req.Header.Set("Content-Type", "application/json")
		if resp, err := client.Do(req); err == nil {
			_ = resp.Body.Close()
		}
	}

	tInfo := tunnel.DetectPrivateNetworks(cfg.Port)
	portToUse := cfg.Port
	var hostLabel string = "Suggested IP:"
	hostIP := ""
	if tInfo.CloudflareURL != "" {
		hostIP = tInfo.CloudflareURL
		portToUse = 443
		hostLabel = "Tunnel Host: "
	} else if tInfo.TailscaleIP != "" {
		hostIP = tInfo.TailscaleIP
		hostLabel = "Tailscale IP:"
	} else {
		hostIP = getPublicIP()
		if hostIP == "" {
			hostIP = getLocalLANIP()
		}
	}

	fmt.Printf("  %s%sPair Code Ready:%s  %s%s%s\n\n", Bold, Green, Reset, Bold, pairCode, Reset)
	fmt.Printf("  %sServer Host:%s      %s\n", Bold, Reset, identity.Hostname)
	fmt.Printf("  %s%s     %s%s%s\n", Bold, hostLabel, Cyan, hostIP, Reset)
	fmt.Printf("  %sPort:%s             %d\n", Bold, Reset, portToUse)
	fmt.Printf("  %sValidity:%s         10 minutes (Single-use)\n", Bold, Reset)

	fmt.Println()
	fmt.Printf("  %s%sHow to Pair with Pulse Mac App:%s\n", Bold, Yellow, Reset)
	fmt.Printf("  1. Open %sPulse%s on your Mac and click %sAdd Server (+) / ⌘N%s\n", Bold, Reset, Cyan, Reset)
	fmt.Printf("  2. Select %s'🔢 XXX-XXX Pair Code'%s tab\n", Bold, Reset)
	fmt.Printf("  3. Enter Host: %s%s%s (Port: %d)\n", Cyan, hostIP, Reset, portToUse)
	fmt.Printf("  4. Enter Pairing Code: %s%s%s\n", Bold, pairCode, Reset)
	fmt.Printf("  5. Click %s'Pair & Connect'%s — Pulse will securely retrieve and store the auth token!\n", Bold, Reset)
	fmt.Println()
	_ = os.Stdout
}
