package security

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"net/http"
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
func TokenAuthMiddleware(validToken string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := extractToken(r)
		if token == "" || subtle.ConstantTimeCompare([]byte(token), []byte(validToken)) != 1 {
			http.Error(w, `{"error":"unauthorized","message":"invalid or missing auth token"}`, http.StatusUnauthorized)
			return
		}
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
