package docker

type ContainerInfo struct {
	ID        string   `json:"id"`
	Name      string   `json:"name"`
	Image     string   `json:"image"`
	State     string   `json:"state"`
	Status    string   `json:"status"`
	CreatedAt        int64    `json:"created_at"`
	Ports            []string `json:"ports"`
	CPUPercent       float64  `json:"cpu_percent"`
	MemoryUsageBytes uint64   `json:"memory_usage_bytes"`
	MemoryLimitBytes uint64   `json:"memory_limit_bytes"`
}

type DockerStatus struct {
	Available  bool            `json:"available"`
	Version    string          `json:"version,omitempty"`
	Containers []ContainerInfo `json:"containers"`
}

type Controller interface {
	GetStatus() (*DockerStatus, error)
	ControlContainer(id string, action string) error
	GetLogs(id string, tail int) (string, error)
}
