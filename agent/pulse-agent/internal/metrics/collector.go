package metrics

import (
	"log/slog"
	"time"

	"github.com/pulse/pulse-agent/internal/system"
)

type MetricsCollector struct {
	probe  system.SystemProbe
	logger *slog.Logger
}

func NewCollector(logger *slog.Logger) *MetricsCollector {
	return &MetricsCollector{
		probe:  system.NewProbe(),
		logger: logger,
	}
}

func (c *MetricsCollector) Collect() *MetricsSnapshot {
	now := time.Now().UTC().Truncate(time.Second)

	// Partial failure isolation: each probe runs independently
	cpu, err := c.probe.GetCPU()
	if err != nil {
		c.logger.Warn("partial metric failure: cpu", "error", err)
	}

	mem, err := c.probe.GetMemory()
	if err != nil {
		c.logger.Warn("partial metric failure: memory", "error", err)
	}

	disks, err := c.probe.GetDisks()
	if err != nil {
		c.logger.Warn("partial metric failure: disk", "error", err)
		disks = []system.DiskMountStats{}
	}

	netStats, err := c.probe.GetNetwork()
	if err != nil {
		c.logger.Warn("partial metric failure: network", "error", err)
	}

	loadAvg, err := c.probe.GetLoadAvg()
	if err != nil {
		c.logger.Warn("partial metric failure: loadavg", "error", err)
	}

	uptime, err := c.probe.GetUptime()
	if err != nil {
		c.logger.Warn("partial metric failure: uptime", "error", err)
	}

	return &MetricsSnapshot{
		Timestamp:     now,
		CPU:           cpu,
		Memory:        mem,
		Disks:         disks,
		Network:       netStats,
		LoadAvg:       loadAvg,
		UptimeSeconds: uptime,
	}
}
