package pairing

import (
	"testing"
	"time"

	"github.com/pulse/pulse-agent/internal/agent"
)

func TestPairingManagerLifecycle(t *testing.T) {
	mgr := &Manager{}
	cfg := &agent.Config{
		AgentID:   "test-agent-123",
		AuthToken: "secret-token-abc",
	}

	// 1. Initially no active session
	active, _ := mgr.GetStatus()
	if active {
		t.Fatal("expected inactive session initially")
	}

	_, err := mgr.VerifyAndClaim("123-456")
	if err == nil {
		t.Fatal("expected error claiming with no active session")
	}

	// 2. Generate XXX-XXX code (e.g. "653-557")
	code, err := mgr.GenerateCode(cfg, "vps-test")
	if err != nil {
		t.Fatalf("failed to generate code: %v", err)
	}

	// Format must be XXX-XXX: 7 chars total, hyphen at index 3
	if len(code) != 7 || code[3] != '-' {
		t.Fatalf("expected XXX-XXX format code, got: %s", code)
	}

	active, remaining := mgr.GetStatus()
	if !active || remaining <= 0 {
		t.Fatalf("expected active session with remaining time, got active=%v, remaining=%v", active, remaining)
	}

	// 3. Invalid code should fail
	_, err = mgr.VerifyAndClaim("000-000")
	if err == nil {
		t.Fatal("expected error claiming with invalid code")
	}

	// 4. Correct code claims session
	claimed, err := mgr.VerifyAndClaim(code)
	if err != nil {
		t.Fatalf("failed to claim with correct code: %v", err)
	}

	if claimed.AuthToken != cfg.AuthToken {
		t.Fatalf("expected token %s, got %s", cfg.AuthToken, claimed.AuthToken)
	}
	if claimed.AgentID != cfg.AgentID {
		t.Fatalf("expected agent ID %s, got %s", cfg.AgentID, claimed.AgentID)
	}

	// 5. Code cannot be reused
	_, err = mgr.VerifyAndClaim(code)
	if err == nil {
		t.Fatal("expected error attempting to reuse claimed code")
	}
}

func TestPairingExpiration(t *testing.T) {
	mgr := &Manager{}
	cfg := &agent.Config{
		AgentID:   "test-agent-exp",
		AuthToken: "token-exp",
	}

	code, err := mgr.GenerateCode(cfg, "vps-exp")
	if err != nil {
		t.Fatalf("failed to generate code: %v", err)
	}

	// Force expiration
	mgr.mu.Lock()
	mgr.session.ExpiresAt = time.Now().Add(-1 * time.Second)
	mgr.mu.Unlock()

	_, err = mgr.VerifyAndClaim(code)
	if err == nil {
		t.Fatal("expected error on expired code")
	}
}

func TestPairingCrossProcessAndNormalization(t *testing.T) {
	mgr1 := &Manager{}
	cfg := &agent.Config{
		AgentID:   "test-agent-cross",
		AuthToken: "token-cross-secret",
	}

	code, err := mgr1.GenerateCode(cfg, "vps-cross")
	if err != nil {
		t.Fatalf("failed to generate code: %v", err)
	}

	// mgr2 simulates a completely separate process (like the background daemon)
	mgr2 := &Manager{}

	// Test claiming without hyphen
	noHyphen := code[:3] + code[4:]
	claimed, err := mgr2.VerifyAndClaim(noHyphen)
	if err != nil {
		t.Fatalf("failed to claim without hyphen: %v", err)
	}

	if claimed.AuthToken != cfg.AuthToken {
		t.Fatalf("expected token %s, got %s", cfg.AuthToken, claimed.AuthToken)
	}
}
