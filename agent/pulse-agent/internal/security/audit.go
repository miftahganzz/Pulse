package security

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

type AuditEntry struct {
	Timestamp  time.Time `json:"timestamp"`
	ClientIP   string    `json:"client_ip,omitempty"`
	Action     string    `json:"action"`
	Target     string    `json:"target"`
	Status     string    `json:"status"`
	DurationMs int64     `json:"duration_ms"`
	Message    string    `json:"message,omitempty"`
	Operator   string    `json:"operator,omitempty"`
}

type AuditLogger struct {
	mu       sync.Mutex
	filePath string
}

var (
	GlobalAuditLogger *AuditLogger
	auditOnce         sync.Once
)

// InitAuditLogger initializes the global audit logger
func InitAuditLogger(configDir string) *AuditLogger {
	auditOnce.Do(func() {
		logPath := filepath.Join(configDir, "audit.log")
		GlobalAuditLogger = &AuditLogger{
			filePath: logPath,
		}
	})
	return GlobalAuditLogger
}

func GetAuditLogger() *AuditLogger {
	return GlobalAuditLogger
}

// Log records an action execution in the audit trail
func (al *AuditLogger) Log(entry AuditEntry) error {
	if al == nil || al.filePath == "" {
		return nil
	}

	al.mu.Lock()
	defer al.mu.Unlock()

	if entry.Timestamp.IsZero() {
		entry.Timestamp = time.Now().UTC()
	}

	data, err := json.Marshal(entry)
	if err != nil {
		return err
	}

	_ = os.MkdirAll(filepath.Dir(al.filePath), 0700)
	f, err := os.OpenFile(al.filePath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
	if err != nil {
		return fmt.Errorf("failed to open audit log: %w", err)
	}
	defer f.Close()

	_, err = f.WriteString(string(data) + "\n")
	return err
}
