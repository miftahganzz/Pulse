package security

import (
	"testing"
	"time"
)

func TestRateLimiterLockout(t *testing.T) {
	rl := NewRateLimiter(3, 100*time.Millisecond, 200*time.Millisecond)
	defer rl.Stop()

	ip := "192.168.1.100"

	// 1st failure
	banned := rl.RecordFailure(ip)
	if banned {
		t.Fatalf("expected not banned on 1st failure")
	}

	// 2nd failure
	banned = rl.RecordFailure(ip)
	if banned {
		t.Fatalf("expected not banned on 2nd failure")
	}

	// 3rd failure -> should be banned!
	banned = rl.RecordFailure(ip)
	if !banned {
		t.Fatalf("expected banned on 3rd failure")
	}

	isBanned, remaining := rl.IsBanned(ip)
	if !isBanned || remaining <= 0 {
		t.Fatalf("expected IsBanned to be true with remaining > 0, got %v, %v", isBanned, remaining)
	}

	// Wait for ban to expire
	time.Sleep(250 * time.Millisecond)
	isBanned, _ = rl.IsBanned(ip)
	if isBanned {
		t.Fatalf("expected ban to expire after duration")
	}
}

func TestRateLimiterSuccessReset(t *testing.T) {
	rl := NewRateLimiter(3, 1*time.Minute, 1*time.Minute)
	defer rl.Stop()

	ip := "10.0.0.1"

	rl.RecordFailure(ip)
	rl.RecordFailure(ip)

	// Success should reset counter
	rl.RecordSuccess(ip)

	// 1 more failure should not ban since counter was reset
	banned := rl.RecordFailure(ip)
	if banned {
		t.Fatalf("expected counter reset after success, got banned")
	}
}
