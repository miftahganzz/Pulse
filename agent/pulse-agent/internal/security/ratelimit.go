package security

import (
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

type ipRecord struct {
	failedAttempts int
	lastFailedAt   time.Time
	bannedUntil    time.Time
}

// RateLimiter manages failed authentication attempts and blocks offending IPs
type RateLimiter struct {
	mu           sync.Mutex
	records      map[string]*ipRecord
	maxAttempts  int
	window       time.Duration
	banDuration  time.Duration
	cleanupEvery time.Duration
	stopChan     chan struct{}
}

var (
	GlobalLimiter *RateLimiter
	limiterOnce   sync.Once
)

// GetGlobalLimiter returns the shared rate limiter singleton
func GetGlobalLimiter() *RateLimiter {
	limiterOnce.Do(func() {
		GlobalLimiter = NewRateLimiter(5, 1*time.Minute, 15*time.Minute)
	})
	return GlobalLimiter
}

// NewRateLimiter creates a new rate limiter instance.
// Default: 5 failed attempts in 1 minute triggers a 15-minute ban.
func NewRateLimiter(maxAttempts int, window, banDuration time.Duration) *RateLimiter {
	if maxAttempts <= 0 {
		maxAttempts = 5
	}
	if window <= 0 {
		window = 1 * time.Minute
	}
	if banDuration <= 0 {
		banDuration = 15 * time.Minute
	}

	rl := &RateLimiter{
		records:      make(map[string]*ipRecord),
		maxAttempts:  maxAttempts,
		window:       window,
		banDuration:  banDuration,
		cleanupEvery: 5 * time.Minute,
		stopChan:     make(chan struct{}),
	}

	go rl.cleanupLoop()
	return rl
}

func (rl *RateLimiter) Stop() {
	close(rl.stopChan)
}

func (rl *RateLimiter) cleanupLoop() {
	ticker := time.NewTicker(rl.cleanupEvery)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			rl.mu.Lock()
			now := time.Now()
			for ip, rec := range rl.records {
				if now.After(rec.bannedUntil) && now.Sub(rec.lastFailedAt) > rl.window {
					delete(rl.records, ip)
				}
			}
			rl.mu.Unlock()
		case <-rl.stopChan:
			return
		}
	}
}

// IsBanned checks if the IP is currently banned. Returns true and remaining ban duration if banned.
func (rl *RateLimiter) IsBanned(ip string) (bool, time.Duration) {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	rec, exists := rl.records[ip]
	if !exists {
		return false, 0
	}

	now := time.Now()
	if now.Before(rec.bannedUntil) {
		return true, rec.bannedUntil.Sub(now)
	}

	return false, 0
}

// RecordFailure records a failed auth/pairing attempt for the IP.
// Returns true if the IP is now banned as a result of this failure.
func (rl *RateLimiter) RecordFailure(ip string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	rec, exists := rl.records[ip]
	if !exists {
		rec = &ipRecord{}
		rl.records[ip] = rec
	}

	// Reset attempts if outside the window and not banned
	if now.Sub(rec.lastFailedAt) > rl.window && now.After(rec.bannedUntil) {
		rec.failedAttempts = 0
	}

	rec.failedAttempts++
	rec.lastFailedAt = now

	if rec.failedAttempts >= rl.maxAttempts {
		rec.bannedUntil = now.Add(rl.banDuration)
		return true
	}

	return false
}

// RecordSuccess resets the failure count on successful authentication
func (rl *RateLimiter) RecordSuccess(ip string) {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	delete(rl.records, ip)
}

// ExtractIP extracts the client's real IP address from HTTP request
func ExtractIP(r *http.Request) string {
	// 1. CF-Connecting-IP (if behind Cloudflare)
	if cfIP := strings.TrimSpace(r.Header.Get("CF-Connecting-IP")); cfIP != "" {
		return cfIP
	}

	// 2. X-Real-IP
	if realIP := strings.TrimSpace(r.Header.Get("X-Real-IP")); realIP != "" {
		return realIP
	}

	// 3. X-Forwarded-For (take the first client IP)
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		parts := strings.Split(xff, ",")
		if len(parts) > 0 {
			ip := strings.TrimSpace(parts[0])
			if ip != "" {
				return ip
			}
		}
	}

	// 4. RemoteAddr
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil {
		return host
	}
	return r.RemoteAddr
}
