package agent

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/pulse/pulse-agent/internal/system"
)

const CurrentAgentVersion = "1.0.6"

type Config struct {
	AgentID       string `json:"agent_id"`
	AuthToken     string `json:"auth_token"`
	ListenAddress string `json:"listen_address"`
	Port          int    `json:"port"`
	CertFile      string `json:"cert_file"`
	KeyFile       string `json:"key_file"`
}

type Identity struct {
	AgentID         string `json:"agent_id"`
	AgentVersion    string `json:"agent_version"`
	Hostname        string `json:"hostname"`
	OS              string `json:"os"`
	KernelVersion   string `json:"kernel_version"`
	Architecture    string `json:"architecture"`
	CPUCores        int    `json:"cpu_cores"`
	ProtocolVersion int    `json:"protocol_version"`
}

type AgentHealth struct {
	AgentVersion   string  `json:"agent_version"`
	Status         string  `json:"status"` // "healthy", "degraded"
	UptimeSeconds  int64   `json:"uptime_seconds"`
	MemoryAllocMB  float64 `json:"memory_alloc_mb"`
	MemorySysMB    float64 `json:"memory_sys_mb"`
	NumGoroutines  int     `json:"num_goroutines"`
	NumGC          uint32  `json:"num_gc"`
}

func GetSelfHealth(version string, uptimeSeconds int64) AgentHealth {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)

	allocMB := float64(m.Alloc) / 1024.0 / 1024.0
	sysMB := float64(m.Sys) / 1024.0 / 1024.0

	status := "healthy"
	if allocMB > 150.0 {
		status = "degraded"
	}

	return AgentHealth{
		AgentVersion:  version,
		Status:        status,
		UptimeSeconds: uptimeSeconds,
		MemoryAllocMB: allocMB,
		MemorySysMB:   sysMB,
		NumGoroutines: runtime.NumGoroutine(),
		NumGC:         m.NumGC,
	}
}

func LoadOrCreateConfig(configPath string) (*Config, bool, error) {
	isNew := false
	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		isNew = true
		cfg, err := generateDefaultConfig(configPath)
		if err != nil {
			return nil, false, err
		}
		if err := saveConfig(configPath, cfg); err != nil {
			return nil, false, err
		}
		return cfg, isNew, nil
	}

	data, err := os.ReadFile(configPath)
	if err != nil {
		return nil, false, fmt.Errorf("failed to read config file: %w", err)
	}

	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, false, fmt.Errorf("failed to parse config json: %w", err)
	}

	// Defensive path correction for non-root environments or missing paths
	baseDir := filepath.Dir(configPath)
	modified := false
	if os.Geteuid() != 0 {
		if strings.HasPrefix(cfg.CertFile, "/etc/pulse") || cfg.CertFile == "" {
			cfg.CertFile = filepath.Join(baseDir, "cert.pem")
			modified = true
		}
		if strings.HasPrefix(cfg.KeyFile, "/etc/pulse") || cfg.KeyFile == "" {
			cfg.KeyFile = filepath.Join(baseDir, "key.pem")
			modified = true
		}
	} else {
		if cfg.CertFile == "" {
			cfg.CertFile = filepath.Join(baseDir, "cert.pem")
			modified = true
		}
		if cfg.KeyFile == "" {
			cfg.KeyFile = filepath.Join(baseDir, "key.pem")
			modified = true
		}
	}
	if modified {
		_ = saveConfig(configPath, &cfg)
	}

	return &cfg, false, nil
}

func generateDefaultConfig(configPath string) (*Config, error) {
	agentIDBytes := make([]byte, 10)
	if _, err := rand.Read(agentIDBytes); err != nil {
		return nil, err
	}
	agentID := fmt.Sprintf("pulse_%s", hex.EncodeToString(agentIDBytes))

	tokenBytes := make([]byte, 24)
	if _, err := rand.Read(tokenBytes); err != nil {
		return nil, err
	}
	authToken := hex.EncodeToString(tokenBytes)

	baseDir := filepath.Dir(configPath)
	return &Config{
		AgentID:       agentID,
		AuthToken:     authToken,
		ListenAddress: "0.0.0.0",
		Port:          8443,
		CertFile:      filepath.Join(baseDir, "cert.pem"),
		KeyFile:       filepath.Join(baseDir, "key.pem"),
	}, nil
}

func saveConfig(configPath string, cfg *Config) error {
	if err := os.MkdirAll(filepath.Dir(configPath), 0755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(configPath, data, 0600)
}

func CollectIdentity(agentID string) Identity {
	hostname, err := os.Hostname()
	if err != nil || hostname == "" {
		hostname = "unknown-host"
	}

	osName := getPrettyOSName()
	kernel := getKernelVersion()
	arch := runtime.GOARCH
	cores := system.NumCPU()

	return Identity{
		AgentID:         agentID,
		AgentVersion:    CurrentAgentVersion,
		Hostname:        hostname,
		OS:              osName,
		KernelVersion:   kernel,
		Architecture:    arch,
		CPUCores:        cores,
		ProtocolVersion: 1,
	}
}

func getPrettyOSName() string {
	switch runtime.GOOS {
	case "linux":
		if data, err := os.ReadFile("/etc/os-release"); err == nil {
			lines := strings.Split(string(data), "\n")
			for _, line := range lines {
				if strings.HasPrefix(line, "PRETTY_NAME=") {
					name := strings.TrimPrefix(line, "PRETTY_NAME=")
					return strings.Trim(name, `"'`)
				}
			}
		}
		return "Linux"
	case "darwin":
		out, err := exec.Command("sw_vers", "-productVersion").Output()
		if err == nil {
			return fmt.Sprintf("macOS %s", strings.TrimSpace(string(out)))
		}
		return "macOS"
	default:
		return runtime.GOOS
	}
}

func getKernelVersion() string {
	out, err := exec.Command("uname", "-r").Output()
	if err == nil {
		return strings.TrimSpace(string(out))
	}
	return "unknown"
}
