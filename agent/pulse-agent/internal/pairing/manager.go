package pairing

import (
	"crypto/rand"
	"encoding/json"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/pulse/pulse-agent/internal/agent"
)

type PairSession struct {
	PairCode  string    `json:"pair_code"`
	AuthToken string    `json:"auth_token"`
	AgentID   string    `json:"agent_id"`
	Hostname  string    `json:"hostname"`
	CreatedAt time.Time `json:"created_at"`
	ExpiresAt time.Time `json:"expires_at"`
	IsClaimed bool      `json:"is_claimed"`
}

type Manager struct {
	configPath string
	activeCode string
	session    *PairSession
	mu         sync.RWMutex
}

var (
	GlobalManager *Manager
	once          sync.Once
)

func InitGlobalManager(configPath string) *Manager {
	once.Do(func() {
		GlobalManager = &Manager{
			configPath: configPath,
		}
	})
	return GlobalManager
}

func (m *Manager) sessionFilePaths() []string {
	var paths []string
	if m.configPath != "" {
		paths = append(paths, filepath.Join(filepath.Dir(m.configPath), "pairing.json"))
	}
	paths = append(paths, "/etc/pulse/pairing.json", "/tmp/pulse-pairing.json")
	return paths
}

func (m *Manager) saveSessionToFile(sess *PairSession) {
	data, err := json.Marshal(sess)
	if err != nil {
		return
	}
	for _, p := range m.sessionFilePaths() {
		_ = os.MkdirAll(filepath.Dir(p), 0755)
		_ = os.WriteFile(p, data, 0666)
	}
}

func (m *Manager) loadSessionFromFile() *PairSession {
	for _, p := range m.sessionFilePaths() {
		data, err := os.ReadFile(p)
		if err == nil {
			var sess PairSession
			if err := json.Unmarshal(data, &sess); err == nil {
				if time.Now().Before(sess.ExpiresAt) && !sess.IsClaimed {
					return &sess
				}
			}
		}
	}
	return nil
}

func (m *Manager) clearSessionFiles() {
	for _, p := range m.sessionFilePaths() {
		_ = os.Remove(p)
	}
}

// GenerateCode creates a XXX-XXX one-time pairing code valid for 10 minutes
func (m *Manager) GenerateCode(cfg *agent.Config, hostname string) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	n, err := rand.Int(rand.Reader, big.NewInt(900000))
	if err != nil {
		return "", err
	}
	digits := fmt.Sprintf("%06d", n.Int64()+100000)
	code := digits[:3] + "-" + digits[3:]

	now := time.Now()
	m.activeCode = code
	m.session = &PairSession{
		PairCode:  code,
		AuthToken: cfg.AuthToken,
		AgentID:   cfg.AgentID,
		Hostname:  hostname,
		CreatedAt: now,
		ExpiresAt: now.Add(10 * time.Minute),
		IsClaimed: false,
	}

	m.saveSessionToFile(m.session)

	return code, nil
}

// SetExplicitCode allows setting code via command line or API
func (m *Manager) SetExplicitCode(code string, cfg *agent.Config, hostname string) {
	m.mu.Lock()
	defer m.mu.Unlock()

	now := time.Now()
	m.activeCode = code
	m.session = &PairSession{
		PairCode:  code,
		AuthToken: cfg.AuthToken,
		AgentID:   cfg.AgentID,
		Hostname:  hostname,
		CreatedAt: now,
		ExpiresAt: now.Add(10 * time.Minute),
		IsClaimed: false,
	}

	m.saveSessionToFile(m.session)
}

// VerifyAndClaim verifies the code (with or without hyphens) and returns the auth token if valid
func (m *Manager) VerifyAndClaim(code string) (*PairSession, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	// If no in-memory session, attempt to read from disk (cross-process CLI pair)
	if m.session == nil {
		if fileSess := m.loadSessionFromFile(); fileSess != nil {
			m.session = fileSess
			m.activeCode = fileSess.PairCode
		}
	}

	if m.session == nil || m.activeCode == "" {
		return nil, fmt.Errorf("no active pairing session. Run 'pulse-agent pair' on VPS first")
	}

	if time.Now().After(m.session.ExpiresAt) {
		m.activeCode = ""
		m.session = nil
		m.clearSessionFiles()
		return nil, fmt.Errorf("pairing code has expired. Please generate a new code")
	}

	// Normalize comparison: ignore hyphens and whitespaces so both "788-504" and "788504" match
	cleanExpected := strings.ReplaceAll(m.session.PairCode, "-", "")
	cleanInput := strings.ReplaceAll(strings.TrimSpace(code), "-", "")

	if cleanExpected != cleanInput {
		return nil, fmt.Errorf("invalid pairing code")
	}

	if m.session.IsClaimed {
		return nil, fmt.Errorf("pairing code already used")
	}

	m.session.IsClaimed = true
	claimed := *m.session

	// Clear active session to prevent reuse
	m.activeCode = ""
	m.session = nil
	m.clearSessionFiles()

	return &claimed, nil
}

// GetStatus returns the current pairing state
func (m *Manager) GetStatus() (bool, time.Duration) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	if m.session == nil || time.Now().After(m.session.ExpiresAt) {
		if fileSess := m.loadSessionFromFile(); fileSess != nil {
			return true, time.Until(fileSess.ExpiresAt)
		}
		return false, 0
	}
	return true, time.Until(m.session.ExpiresAt)
}
