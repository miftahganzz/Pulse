package metrics

import (
	"time"

	"github.com/pulse/pulse-agent/internal/system"
)

type MetricsSnapshot struct {
	Timestamp     time.Time               `json:"timestamp"`
	CPU           system.CPUStats         `json:"cpu"`
	Memory        system.MemoryStats      `json:"memory"`
	Disks         []system.DiskMountStats `json:"disks"`
	Network       system.NetworkStats     `json:"network"`
	LoadAvg       system.LoadAvgStats     `json:"load_avg"`
	UptimeSeconds int64                   `json:"uptime_seconds"`
}
