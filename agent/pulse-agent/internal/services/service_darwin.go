//go:build darwin

package services

import (
	"bufio"
	"os/exec"
	"strings"
)

type DarwinServiceCollector struct{}

func NewCollector() Collector {
	return &DarwinServiceCollector{}
}

func (c *DarwinServiceCollector) CollectServices() ([]ServiceInfo, error) {
	out, err := exec.Command("launchctl", "list").Output()
	if err != nil {
		return nil, err
	}

	var services []ServiceInfo
	scanner := bufio.NewScanner(strings.NewReader(string(out)))

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "PID\t") {
			continue
		}

		fields := strings.Fields(line)
		if len(fields) < 3 {
			continue
		}

		pid := fields[0]
		status := fields[1]
		label := fields[2]

		// Filter Apple private background services to keep list readable
		if strings.HasPrefix(label, "com.apple.") && !strings.Contains(label, "AirPlay") {
			continue
		}

		active := "inactive"
		sub := "dead"
		if pid != "-" {
			active = "active"
			sub = "running"
		} else if status == "0" {
			sub = "exited"
		} else {
			sub = "failed"
		}

		services = append(services, ServiceInfo{
			Name:        label,
			Description: label,
			LoadState:   "loaded",
			ActiveState: active,
			SubState:    sub,
		})
	}

	return services, nil
}

func (c *DarwinServiceCollector) ControlService(name string, action string) error {
	switch action {
	case "start", "stop", "restart":
	default:
		return exec.ErrNotFound
	}
	return nil
}

