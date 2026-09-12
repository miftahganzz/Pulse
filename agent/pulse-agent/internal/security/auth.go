package security

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"net/http"
	"strconv"
	"strings"
)

func GenerateToken(length int) (string, error) {
	bytes := make([]byte, length)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return hex.EncodeToString(bytes), nil
}

// TokenAuthMiddleware verifies authorization header or sec-websocket-protocol/query token
// with integrated brute-force and IP lockout protection.
func TokenAuthMiddleware(validToken string, next http.Handler) http.Handler {
	limiter := GetGlobalLimiter()
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip := ExtractIP(r)

		if banned, remaining := limiter.IsBanned(ip); banned {
			w.Header().Set("Retry-After", strconv.Itoa(int(remaining.Seconds())))
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusTooManyRequests)
			_, _ = w.Write([]byte(`{"error":"too_many_requests","message":"IP temporarily banned due to excessive authentication failures"}`))
			return
		}

		token := extractToken(r)
		if token == "" || subtle.ConstantTimeCompare([]byte(token), []byte(validToken)) != 1 {
			limiter.RecordFailure(ip)
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusUnauthorized)
			_, _ = w.Write([]byte(`{"error":"unauthorized","message":"invalid or missing auth token"}`))
			return
		}

		limiter.RecordSuccess(ip)
		next.ServeHTTP(w, r)
	})
}

func extractToken(r *http.Request) string {
	// 1. Authorization: Bearer <token>
	authHeader := r.Header.Get("Authorization")
	if strings.HasPrefix(strings.ToLower(authHeader), "bearer ") {
		return strings.TrimSpace(authHeader[7:])
	}

	// 2. Header X-Pulse-Token
	if customHeader := r.Header.Get("X-Pulse-Token"); customHeader != "" {
		return customHeader
	}

	// 3. Query parameter: ?token=<token>
	if queryToken := r.URL.Query().Get("token"); queryToken != "" {
		return queryToken
	}

	return ""
}
