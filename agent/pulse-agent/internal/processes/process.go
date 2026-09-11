package processes

type ProcessInfo struct {
	PID            int     `json:"pid"`
	PPID           int     `json:"ppid"`
	Name           string  `json:"name"`
	User           string  `json:"user"`
	CPUPercent     float64 `json:"cpu_percent"`
	MemoryRSSBytes uint64  `json:"memory_rss_bytes"`
	State          string  `json:"state"`
	Command        string  `json:"command"`
}

type ProcessesSnapshot struct {
	Processes []ProcessInfo `json:"processes"`
}

type Collector interface {
	CollectProcesses(limit int, sortBy string) ([]ProcessInfo, error)
}

type ProcessController interface {
	KillProcess(pid int, signalName string) error
}

