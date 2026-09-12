package main

import (
	"bytes"
	"crypto/tls"
	"encoding/json"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/pulse/pulse-agent/internal/agent"
	"github.com/pulse/pulse-agent/internal/cli"
	"github.com/pulse/pulse-agent/internal/doctor"
	"github.com/pulse/pulse-agent/internal/pairing"
	"github.com/pulse/pulse-agent/internal/security"
	"github.com/pulse/pulse-agent/internal/server"
	"github.com/pulse/pulse-agent/internal/tunnel"
)

func main() {
	defaultConfigPath := ""
	if os.Geteuid() == 0 {
		defaultConfigPath = "/etc/pulse/agent.json"
	} else {
		home, err := os.UserHomeDir()
		if err != nil {
			defaultConfigPath = "./agent.json"
		} else {
			defaultConfigPath = filepath.Join(home, ".pulse", "agent.json")
		}
	}

	// 1. Dispatch unified CLI subcommands
	if len(os.Args) > 1 {
		if cli.HandleCommand(os.Args[1:], defaultConfigPath) {
			return
		}
	} else if len(os.Args) == 1 {
		// Run without arguments: show status overview and quick commands
		if cli.HandleCommand([]string{}, defaultConfigPath) {
			return
		}
	}

	configPathFlag := flag.String("config", "", "path to agent.json config file")
	showTokenFlag := flag.Bool("show-token", false, "display agent ID and auth token, then exit")
	versionFlag := flag.Bool("version", false, "display agent version and exit")
	doctorFlag := flag.Bool("doctor", false, "run system and connectivity diagnostics")
	tunnelFlag := flag.Bool("tunnel", false, "display Zero-Port Private Network guide (Tailscale / Cloudflare Tunnel)")
	pairFlag := flag.String("pair", "", "generate or set 6-digit pairing code (use 'new' to generate or provide 6-digit code)")
	flag.Parse()

	// Handle subcommands if passed as first positional arg e.g. "pulse-agent pair", "pulse-agent doctor", "pulse-agent tunnel"
	args := flag.Args()
	if len(args) > 0 {
		switch args[0] {
		case "version":
			*versionFlag = true
		case "doctor":
			*doctorFlag = true
		case "tunnel":
			*tunnelFlag = true
		case "pair":
			if len(args) > 1 {
				*pairFlag = args[1]
			} else {
				*pairFlag = "new"
			}
		}
	}

	if *versionFlag {
		fmt.Printf("pulse-agent v%s\n", agent.CurrentAgentVersion)
		return
	}

	configPath := *configPathFlag
	if configPath == "" {
		if os.Geteuid() == 0 {
			configPath = "/etc/pulse/agent.json"
		} else {
			home, err := os.UserHomeDir()
			if err != nil {
				configPath = "./agent.json"
			} else {
				configPath = filepath.Join(home, ".pulse", "agent.json")
			}
		}
	}

	cfg, isNew, err := agent.LoadOrCreateConfig(configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error loading configuration: %v\n", err)
		os.Exit(1)
	}

	// Always ensure TLS Certificates exist upon config load
	_, _ = security.EnsureCertificate(cfg.CertFile, cfg.KeyFile, []string{"127.0.0.1", "localhost"})

	if *showTokenFlag {
		fmt.Printf("Agent ID:    %s\n", cfg.AgentID)
		fmt.Printf("Auth Token:  %s\n", cfg.AuthToken)
		fmt.Printf("Config File: %s\n", configPath)
		return
	}

	// 1. Run Doctor Diagnostics
	if *doctorFlag {
		fmt.Println("================================================================")
		fmt.Printf("🩺 Pulse Agent System Doctor (v%s)\n", agent.CurrentAgentVersion)
		fmt.Println("================================================================")
		report := doctor.RunDiagnostics(configPath, cfg)
		for _, item := range report.Items {
			var icon string
			switch item.Status {
			case doctor.StatusOK:
				icon = "✔"
			case doctor.StatusWarn:
				icon = "⚠"
			case doctor.StatusFail:
				icon = "✖"
			}
			fmt.Printf("[%s] %-26s : %s\n", icon, item.Name, item.Message)
		}
		fmt.Println("================================================================")
		return
	}

	// 2. Run Tunnel Guide (Tailscale / Cloudflare)
	if *tunnelFlag {
		tunnel.PrintTunnelGuide(cfg.Port)
		return
	}

	// Initialize Pairing Manager
	pm := pairing.InitGlobalManager(configPath)
	identity := agent.CollectIdentity(cfg.AgentID)

	// 2. Handle Pairing Command
	if *pairFlag != "" {
		var pairCode string
		if *pairFlag == "new" {
			pairCode, err = pm.GenerateCode(cfg, identity.Hostname)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Failed to generate pairing code: %v\n", err)
				os.Exit(1)
			}
		} else {
			pairCode = *pairFlag
			pm.SetExplicitCode(pairCode, cfg, identity.Hostname)
		}

		fmt.Println("================================================================")
		fmt.Println("🔗 Pulse Pairing Mode")
		fmt.Println("================================================================")
		fmt.Printf("Pairing Code: %s\n", pairCode)
		fmt.Printf("Server Host:  %s\n", identity.Hostname)
		fmt.Printf("Server Port:  %d\n", cfg.Port)
		fmt.Println("Expires in:   10 minutes")
		fmt.Println("----------------------------------------------------------------")
		fmt.Println("In your Mac Pulse App, choose '🔢 XXX-XXX Pair Code', then:")
		fmt.Printf("Enter this server's IP address and Pairing Code: %s\n", pairCode)
		fmt.Println("================================================================")

		// Notify active running daemon if listening locally
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

		return
	}

	// Setup structured JSON logger
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))

	logger.Info("starting pulse-agent",
		"version", agent.CurrentAgentVersion,
		"agent_id", cfg.AgentID,
		"config_path", configPath,
		"is_new_install", isNew,
	)

	// Ensure TLS Certificates exist
	fingerprint, err := security.EnsureCertificate(cfg.CertFile, cfg.KeyFile, []string{"127.0.0.1", "localhost"})
	if err != nil {
		logger.Error("failed to configure TLS certificate", "error", err)
		os.Exit(1)
	}
	logger.Info("TLS certificate ready", "cert_fingerprint_sha256", fingerprint)

	logger.Info("agent identity collected",
		"hostname", identity.Hostname,
		"os", identity.OS,
		"arch", identity.Architecture,
	)

	srv := server.NewServer(cfg, identity, logger)
	addr := fmt.Sprintf("%s:%d", cfg.ListenAddress, cfg.Port)

	tlsConfig := &tls.Config{
		MinVersion: tls.VersionTLS12,
	}

	httpServer := &http.Server{
		Addr:         addr,
		Handler:      srv.Handler(),
		TLSConfig:    tlsConfig,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Graceful shutdown handling
	stopChan := make(chan os.Signal, 1)
	signal.Notify(stopChan, os.Interrupt, syscall.SIGTERM)

	go func() {
		logger.Info("pulse-agent listening", "address", addr, "tls", true)
		if err := httpServer.ListenAndServeTLS(cfg.CertFile, cfg.KeyFile); err != nil && err != http.ErrServerClosed {
			logger.Error("server listener error", "error", err)
			os.Exit(1)
		}
	}()

	if isNew {
		fmt.Println("================================================================")
		fmt.Println("🎉 Pulse Agent Initialized Successfully!")
		fmt.Printf("Agent ID:    %s\n", cfg.AgentID)
		fmt.Printf("Auth Token:  %s\n", cfg.AuthToken)
		fmt.Printf("Listen Port: %d (HTTPS/WSS)\n", cfg.Port)
		fmt.Printf("Cert Hash:   %s\n", fingerprint)
		fmt.Println("Use this Auth Token when adding this server to your Pulse Mac App.")
		fmt.Println("================================================================")
	}

	<-stopChan
	logger.Info("shutting down pulse-agent gracefully...")
	_ = httpServer.Close()
	logger.Info("pulse-agent stopped")
}
