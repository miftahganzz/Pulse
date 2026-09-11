package pairing

import (
	"crypto/rand"
	"fmt"
	"math/big"
	"sync"
	"time"

	"github.com/pulse/pulse-agent/internal/agent"
)

type PairSession struct {
	PairCode    string    `json:"pair_code"`
	AuthToken   string    `json:"auth_token"`
	AgentID     string    `json:"agent_id"`
	Hostname    string    `json:"hostname"`
	CreatedAt   time.Time `json:"created_at"`
	ExpiresAt   time.Time `json:"expires_at"`
	IsClaimed   bool      `json:"is_claimed"`
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

// GenerateCode creates a 6-digit one-time pairing code valid for 10 minutes
func (m *Manager) GenerateCode(cfg *agent.Config, hostname string) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	n, err := rand.Int(rand.Reader, big.NewInt(900000))
	if err != nil {
		return "", err
	}
	code := fmt.Sprintf("%06d", n.Int64()+100000)

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
}

// VerifyAndClaim verifies the 6-digit code and returns the auth token if valid
func (m *Manager) VerifyAndClaim(code string) (*PairSession, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.session == nil || m.activeCode == "" {
		return nil, fmt.Errorf("no active pairing session. Run 'pulse-agent pair' on VPS first")
	}

	if time.Now().After(m.session.ExpiresAt) {
		m.activeCode = ""
		m.session = nil
		return nil, fmt.Errorf("pairing code has expired. Please generate a new code")
	}

	if m.session.PairCode != code {
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

	return &claimed, nil
}

// GetStatus returns the current pairing state
func (m *Manager) GetStatus() (bool, time.Duration) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	if m.session == nil || time.Now().After(m.session.ExpiresAt) {
		return false, 0
	}
	return true, time.Until(m.session.ExpiresAt)
}
