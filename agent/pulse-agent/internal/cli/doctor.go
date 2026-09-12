package cli

import (
	"fmt"

	"github.com/pulse/pulse-agent/internal/agent"
	"github.com/pulse/pulse-agent/internal/doctor"
)

// RunDoctor runs system and network diagnostics
func RunDoctor(configPath string) {
	cfg, _, err := agent.LoadOrCreateConfig(configPath)
	if err != nil {
		fmt.Printf("  %s✖ Error loading config:%s %v\n\n", Red, Reset, err)
		return
	}

	fmt.Println()
	fmt.Printf("  %s🩺 Pulse Agent System Doctor (v%s)%s\n\n", Bold, agent.CurrentAgentVersion, Reset)
	report := doctor.RunDiagnostics(configPath, cfg)
	for _, item := range report.Items {
		var icon string
		switch item.Status {
		case doctor.StatusOK:
			icon = Green + "✔" + Reset
		case doctor.StatusWarn:
			icon = Yellow + "⚠" + Reset
		case doctor.StatusFail:
			icon = Red + "✖" + Reset
		}
		fmt.Printf("  [%s] %-26s : %s\n", icon, item.Name, item.Message)
	}
	fmt.Println()
}
