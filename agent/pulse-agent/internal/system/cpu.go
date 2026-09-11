package system

import "runtime"

type CPUStats struct {
	UsagePercent  float64 `json:"usage_percent"`
	UserPercent   float64 `json:"user_percent"`
	SystemPercent float64 `json:"system_percent"`
	IdlePercent   float64 `json:"idle_percent"`
	StealPercent  float64 `json:"steal_percent"`
	Cores         int     `json:"cores"`
}

type LoadAvgStats struct {
	Load1  float64 `json:"load1"`
	Load5  float64 `json:"load5"`
	Load15 float64 `json:"load15"`
}

func NumCPU() int {
	n := runtime.NumCPU()
	if n < 1 {
		return 1
	}
	return n
}
