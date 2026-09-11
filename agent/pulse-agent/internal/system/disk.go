package system

type DiskMountStats struct {
	MountPoint       string  `json:"mount_point"`
	Filesystem       string  `json:"filesystem"`
	TotalBytes       uint64  `json:"total_bytes"`
	UsedBytes        uint64  `json:"used_bytes"`
	FreeBytes        uint64  `json:"free_bytes"`
	UsagePercent     float64 `json:"usage_percent"`
	ReadBytesPerSec  float64 `json:"read_bytes_per_sec"`
	WriteBytesPerSec float64 `json:"write_bytes_per_sec"`
}
