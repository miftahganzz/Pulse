package system

type SystemProbe interface {
	GetCPU() (CPUStats, error)
	GetMemory() (MemoryStats, error)
	GetDisks() ([]DiskMountStats, error)
	GetNetwork() (NetworkStats, error)
	GetLoadAvg() (LoadAvgStats, error)
	GetUptime() (int64, error)
}
