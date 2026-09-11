//go:build linux

package services

import (
	"bufio"
	"os/exec"
	"strings"
)

type LinuxServiceCollector struct{}

func NewCollector() Collector {
	return &LinuxServiceCollector{}
}

func (c *LinuxServiceCollector) CollectServices() ([]ServiceInfo, error) {
	out, err := exec.Command("systemctl", "list-units", "--type=service", "--no-pager", "--all", "--plain").Output()
	if err != nil {
		return nil, err
	}

	var services []ServiceInfo
	scanner := bufio.NewScanner(strings.NewReader(string(out)))

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "UNIT ") || strings.HasPrefix(line, "LOAD ") || strings.HasPrefix(line, "To show all") {
			continue
		}

		fields := strings.Fields(line)
		if len(fields) < 5 {
			continue
		}

		unit := fields[0]
		if !strings.HasSuffix(unit, ".service") {
			continue
		}

		load := fields[1]
		active := fields[2]
		sub := fields[3]
		desc := strings.Join(fields[4:], " ")

		services = append(services, ServiceInfo{
			Name:        unit,
			Description: desc,
			LoadState:   load,
			ActiveState: active,
			SubState:    sub,
		})
	}

	return services, nil
}

func (c *LinuxServiceCollector) ControlService(name string, action string) error {
	if !strings.HasSuffix(name, ".service") {
		return exec.ErrNotFound
	}
	if strings.Contains(name, "/") || strings.Contains(name, "..") {
		return exec.ErrNotFound
	}

	switch action {
	case "start", "stop", "restart":
		cmd := exec.Command("systemctl", action, name)
		return cmd.Run()
	default:
		return exec.ErrNotFound
	}
}

