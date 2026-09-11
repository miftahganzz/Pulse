package doctor

import (
	"crypto/tls"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/pulse/pulse-agent/internal/agent"
)

type CheckStatus string

const (
	StatusOK   CheckStatus = "OK"
	StatusWarn CheckStatus = "WARN"
	StatusFail CheckStatus = "FAIL"
)

type DiagnosticItem struct {
	Name    string
	Status  CheckStatus
	Message string
}

type Report struct {
	Items []DiagnosticItem
}

func RunDiagnostics(configPath string, cfg *agent.Config) Report {
	var items []DiagnosticItem

	// 1. Binary Version
	items = append(items, DiagnosticItem{
		Name:    "Pulse Agent Version",
		Status:  StatusOK,
		Message: fmt.Sprintf("v%s", agent.CurrentAgentVersion),
	})

	// 2. Configuration file check
	if _, err := os.Stat(configPath); err == nil {
		items = append(items, DiagnosticItem{
			Name:    "Configuration File",
			Status:  StatusOK,
			Message: fmt.Sprintf("Found at %s (Agent ID: %s)", configPath, cfg.AgentID),
		})
	} else {
		items = append(items, DiagnosticItem{
			Name:    "Configuration File",
			Status:  StatusWarn,
			Message: fmt.Sprintf("Not found at %s: %v", configPath, err),
		})
	}

	// 3. TLS Certificates check
	certOk := true
	if _, err := os.Stat(cfg.CertFile); err != nil {
		certOk = false
	}
	if _, err := os.Stat(cfg.KeyFile); err != nil {
		certOk = false
	}
	if certOk {
		items = append(items, DiagnosticItem{
			Name:    "TLS Certificate & Key",
			Status:  StatusOK,
			Message: fmt.Sprintf("Cert: %s, Key: %s", cfg.CertFile, cfg.KeyFile),
		})
	} else {
		items = append(items, DiagnosticItem{
			Name:    "TLS Certificate & Key",
			Status:  StatusWarn,
			Message: "Certificate or Key missing. Will be automatically regenerated on startup.",
		})
	}

	// 4. Systemd Service check (if on Linux)
	if _, err := exec.LookPath("systemctl"); err == nil {
		out, err := exec.Command("systemctl", "is-active", "pulse-agent").Output()
		activeStatus := strings.TrimSpace(string(out))
		if err == nil && activeStatus == "active" {
			items = append(items, DiagnosticItem{
				Name:    "Systemd Service",
				Status:  StatusOK,
				Message: "pulse-agent.service is active and running",
			})
		} else {
			items = append(items, DiagnosticItem{
				Name:    "Systemd Service",
				Status:  StatusWarn,
				Message: fmt.Sprintf("pulse-agent.service status: %s", activeStatus),
			})
		}
	} else {
		items = append(items, DiagnosticItem{
			Name:    "Systemd Service",
			Status:  StatusOK,
			Message: "systemctl not available (non-systemd environment)",
		})
	}

	// 5. Port Listening Check
	targetAddr := fmt.Sprintf("127.0.0.1:%d", cfg.Port)
	conn, err := net.DialTimeout("tcp", targetAddr, 1*time.Second)
	if err == nil {
		_ = conn.Close()
		items = append(items, DiagnosticItem{
			Name:    fmt.Sprintf("Port %d Binding", cfg.Port),
			Status:  StatusOK,
			Message: fmt.Sprintf("pulse-agent is actively accepting TCP connections on port %d", cfg.Port),
		})

		// Test HTTPS endpoint response
		tr := &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		}
		client := &http.Client{Transport: tr, Timeout: 2 * time.Second}
		resp, httpErr := client.Get(fmt.Sprintf("https://127.0.0.1:%d/api/v1/info", cfg.Port))
		if httpErr == nil {
			_ = resp.Body.Close()
			if resp.StatusCode == http.StatusUnauthorized {
				items = append(items, DiagnosticItem{
					Name:    "HTTPS & Token Auth",
					Status:  StatusOK,
					Message: "Endpoint responds with TLS and enforces token authentication",
				})
			} else {
				items = append(items, DiagnosticItem{
					Name:    "HTTPS & Token Auth",
					Status:  StatusOK,
					Message: fmt.Sprintf("Endpoint responds with HTTP %d", resp.StatusCode),
				})
			}
		}
	} else {
		items = append(items, DiagnosticItem{
			Name:    fmt.Sprintf("Port %d Binding", cfg.Port),
			Status:  StatusWarn,
			Message: fmt.Sprintf("Port %d not listening or agent service is currently stopped", cfg.Port),
		})
	}

	// 6. Firewall Check (UFW / iptables)
	if _, err := exec.LookPath("ufw"); err == nil {
		out, err := exec.Command("ufw", "status").Output()
		if err == nil {
			ufwOut := string(out)
			if strings.Contains(ufwOut, "Status: active") {
				if strings.Contains(ufwOut, fmt.Sprintf("%d", cfg.Port)) {
					items = append(items, DiagnosticItem{
						Name:    "Firewall (UFW)",
						Status:  StatusOK,
						Message: fmt.Sprintf("Port %d is explicitly allowed in UFW", cfg.Port),
					})
				} else {
					items = append(items, DiagnosticItem{
						Name:    "Firewall (UFW)",
						Status:  StatusWarn,
						Message: fmt.Sprintf("UFW is active! Ensure port %d is allowed: 'sudo ufw allow %d/tcp'", cfg.Port, cfg.Port),
					})
				}
			} else {
				items = append(items, DiagnosticItem{
					Name:    "Firewall (UFW)",
					Status:  StatusOK,
					Message: "UFW is inactive (ports accessible)",
				})
			}
		}
	}

	return Report{Items: items}
}
