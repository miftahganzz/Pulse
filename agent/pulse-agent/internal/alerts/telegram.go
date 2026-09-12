package alerts

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
)

type TelegramConfig struct {
	Enabled          bool     `json:"enabled"`
	BotToken         string   `json:"bot_token"`
	ChatIDs          []string `json:"chat_ids"`
	NotifyOnWarning  bool     `json:"notify_on_warning"`
	NotifyOnCritical bool     `json:"notify_on_critical"`
	NotifyOnRecovery bool     `json:"notify_on_recovery"`
}

type TelegramDispatcher struct {
	client *http.Client
}

func NewTelegramDispatcher() *TelegramDispatcher {
	return &TelegramDispatcher{
		client: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

type telegramPayload struct {
	ChatID    string `json:"chat_id"`
	Text      string `json:"text"`
	ParseMode string `json:"parse_mode,omitempty"`
}

// SendMessage sends a markdown message to a specific Telegram chat/user.
func (d *TelegramDispatcher) SendMessage(ctx context.Context, botToken, chatID, text string) error {
	botToken = strings.TrimSpace(botToken)
	chatID = strings.TrimSpace(chatID)
	if botToken == "" || chatID == "" {
		return fmt.Errorf("bot_token and chat_id are required")
	}

	url := fmt.Sprintf("https://api.telegram.org/bot%s/sendMessage", botToken)
	payload := telegramPayload{
		ChatID:    chatID,
		Text:      text,
		ParseMode: "Markdown",
	}

	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewBuffer(bodyBytes))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := d.client.Do(req)
	if err != nil {
		return fmt.Errorf("telegram request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		var errResp struct {
			Description string `json:"description"`
		}
		_ = json.NewDecoder(resp.Body).Decode(&errResp)
		if errResp.Description != "" {
			return fmt.Errorf("telegram API error (HTTP %d): %s", resp.StatusCode, errResp.Description)
		}
		return fmt.Errorf("telegram API returned HTTP %d", resp.StatusCode)
	}

	return nil
}

// Broadcast sends a message to all configured chat IDs.
func (d *TelegramDispatcher) Broadcast(ctx context.Context, cfg TelegramConfig, text string) []error {
	if !cfg.Enabled || cfg.BotToken == "" || len(cfg.ChatIDs) == 0 {
		return nil
	}

	var errors []error
	for _, chatID := range cfg.ChatIDs {
		if err := d.SendMessage(ctx, cfg.BotToken, chatID, text); err != nil {
			errors = append(errors, fmt.Errorf("chat %s: %w", chatID, err))
		}
	}
	return errors
}

// FormatIncidentMessage formats a clean Markdown incident alert.
func FormatIncidentMessage(serverName, severity, title, detail string) string {
	icon := "⚠️"
	if strings.ToUpper(severity) == "CRITICAL" || strings.ToUpper(severity) == "OUTAGE" {
		icon = "🚨"
	} else if strings.ToUpper(severity) == "RESOLVED" || strings.ToUpper(severity) == "OK" {
		icon = "✅"
	}

	timestamp := time.Now().UTC().Format("2006-01-02 15:04:05 UTC")
	return fmt.Sprintf("%s *[%s] %s*\n*Server:* `%s`\n*Details:* %s\n*Time:* `%s`",
		icon, strings.ToUpper(severity), title, serverName, detail, timestamp)
}
