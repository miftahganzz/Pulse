//go:build linux

package system

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
	"syscall"
	"time"
)

type LinuxSystemProbe struct {
	lastCPUTotal uint64
	lastCPUIdle  uint64
	lastCPUUser  uint64
	lastCPUSys   uint64
	lastCPUSteal uint64

	lastDiskReadBytes  uint64
	lastDiskWriteBytes uint64
	lastDiskTime       time.Time

	lastNetRxBytes uint64
	lastNetTxBytes uint64
	lastNetRxPkts  uint64
	lastNetTxPkts  uint64
	lastNetTime    time.Time
}

func NewProbe() *LinuxSystemProbe {
	p := &LinuxSystemProbe{}
	_, _ = p.GetCPU()
	_, _ = p.GetDisks()
	_, _ = p.GetNetwork()
	return p
}

func (p *LinuxSystemProbe) GetCPU() (CPUStats, error) {
	file, err := os.Open("/proc/stat")
	if err != nil {
		return CPUStats{}, err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "cpu ") {
			fields := strings.Fields(line)
			if len(fields) < 9 {
				return CPUStats{}, fmt.Errorf("malformed /proc/stat")
			}

			user, _ := strconv.ParseUint(fields[1], 10, 64)
			nice, _ := strconv.ParseUint(fields[2], 10, 64)
			sys, _ := strconv.ParseUint(fields[3], 10, 64)
			idle, _ := strconv.ParseUint(fields[4], 10, 64)
			iowait, _ := strconv.ParseUint(fields[5], 10, 64)
			irq, _ := strconv.ParseUint(fields[6], 10, 64)
			softirq, _ := strconv.ParseUint(fields[7], 10, 64)
			steal, _ := strconv.ParseUint(fields[8], 10, 64)

			total := user + nice + sys + idle + iowait + irq + softirq + steal
			idleTotal := idle + iowait

			deltaTotal := total - p.lastCPUTotal
			deltaIdle := idleTotal - p.lastCPUIdle
			deltaUser := user - p.lastCPUUser
			deltaSys := (sys + irq + softirq) - p.lastCPUSys
			deltaSteal := steal - p.lastCPUSteal

			p.lastCPUTotal = total
			p.lastCPUIdle = idleTotal
			p.lastCPUUser = user
			p.lastCPUSys = (sys + irq + softirq)
			p.lastCPUSteal = steal

			cores := NumCPU()
			if deltaTotal == 0 {
				return CPUStats{IdlePercent: 100, Cores: cores}, nil
			}

			usagePct := float64(deltaTotal-deltaIdle) / float64(deltaTotal) * 100.0
			userPct := float64(deltaUser) / float64(deltaTotal) * 100.0
			sysPct := float64(deltaSys) / float64(deltaTotal) * 100.0
			idlePct := float64(deltaIdle) / float64(deltaTotal) * 100.0
			stealPct := float64(deltaSteal) / float64(deltaTotal) * 100.0

			return CPUStats{
				UsagePercent:  clamp(usagePct),
				UserPercent:   clamp(userPct),
				SystemPercent: clamp(sysPct),
				IdlePercent:   clamp(idlePct),
				StealPercent:  clamp(stealPct),
				Cores:         cores,
			}, nil
		}
	}
	return CPUStats{}, fmt.Errorf("cpu stat not found")
}

func (p *LinuxSystemProbe) GetMemory() (MemoryStats, error) {
	file, err := os.Open("/proc/meminfo")
	if err != nil {
		return MemoryStats{}, err
	}
	defer file.Close()

	var totalKB, freeKB, availKB, swapTotalKB, swapFreeKB uint64
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		parts := strings.Fields(scanner.Text())
		if len(parts) < 2 {
			continue
		}
		val, _ := strconv.ParseUint(parts[1], 10, 64)
		switch parts[0] {
		case "MemTotal:":
			totalKB = val
		case "MemFree:":
			freeKB = val
		case "MemAvailable:":
			availKB = val
		case "SwapTotal:":
			swapTotalKB = val
		case "SwapFree:":
			swapFreeKB = val
		}
	}

	total := totalKB * 1024
	free := freeKB * 1024
	available := availKB * 1024
	if available == 0 {
		available = free
	}

	used := uint64(0)
	if total >= available {
		used = total - available
	}

	var usagePct float64
	if total > 0 {
		usagePct = float64(used) / float64(total) * 100.0
	}

	swapTotal := swapTotalKB * 1024
	swapFree := swapFreeKB * 1024
	swapUsed := uint64(0)
	if swapTotal >= swapFree {
		swapUsed = swapTotal - swapFree
	}

	return MemoryStats{
		TotalBytes:     total,
		UsedBytes:      used,
		AvailableBytes: available,
		FreeBytes:      free,
		UsagePercent:   clamp(usagePct),
		SwapTotalBytes: swapTotal,
		SwapUsedBytes:  swapUsed,
	}, nil
}

func (p *LinuxSystemProbe) GetDisks() ([]DiskMountStats, error) {
	mountsFile, err := os.Open("/proc/mounts")
	if err != nil {
		return nil, err
	}
	defer mountsFile.Close()

	readRate, writeRate := p.getDiskIORates()
	var mounts []DiskMountStats
	seenMounts := make(map[string]bool)

	scanner := bufio.NewScanner(mountsFile)
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) < 3 {
			continue
		}

		dev := fields[0]
		mountPoint := fields[1]
		fsType := fields[2]

		// Skip pseudo / virtual filesystems
		if !strings.HasPrefix(dev, "/dev/") {
			continue
		}
		if seenMounts[mountPoint] {
			continue
		}
		seenMounts[mountPoint] = true

		var stat syscall.Statfs_t
		if err := syscall.Statfs(mountPoint, &stat); err != nil {
			continue
		}

		total := stat.Blocks * uint64(stat.Bsize)
		free := stat.Bfree * uint64(stat.Bsize)
		avail := stat.Bavail * uint64(stat.Bsize)
		used := total - free

		if total == 0 {
			continue
		}

		usagePct := float64(total-avail) / float64(total) * 100.0

		// Associate I/O rates primarily with root /
		mReadRate := 0.0
		mWriteRate := 0.0
		if mountPoint == "/" {
			mReadRate = readRate
			mWriteRate = writeRate
		}

		mounts = append(mounts, DiskMountStats{
			MountPoint:       mountPoint,
			Filesystem:       fsType,
			TotalBytes:       total,
			UsedBytes:        used,
			FreeBytes:        avail,
			UsagePercent:     clamp(usagePct),
			ReadBytesPerSec:  mReadRate,
			WriteBytesPerSec: mWriteRate,
		})
	}

	return mounts, nil
}

func (p *LinuxSystemProbe) getDiskIORates() (float64, float64) {
	file, err := os.Open("/proc/diskstats")
	if err != nil {
		return 0, 0
	}
	defer file.Close()

	var totalReadBytes, totalWriteBytes uint64
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) < 14 {
			continue
		}
		devName := fields[2]
		if strings.HasPrefix(devName, "loop") || strings.HasPrefix(devName, "ram") {
			continue
		}
		readSectors, _ := strconv.ParseUint(fields[5], 10, 64)
		writeSectors, _ := strconv.ParseUint(fields[9], 10, 64)
		totalReadBytes += readSectors * 512
		totalWriteBytes += writeSectors * 512
	}

	now := time.Now()
	var readRate, writeRate float64
	if !p.lastDiskTime.IsZero() {
		elapsed := now.Sub(p.lastDiskTime).Seconds()
		if elapsed > 0 {
			if totalReadBytes >= p.lastDiskReadBytes {
				readRate = float64(totalReadBytes-p.lastDiskReadBytes) / elapsed
			}
			if totalWriteBytes >= p.lastDiskWriteBytes {
				writeRate = float64(totalWriteBytes-p.lastDiskWriteBytes) / elapsed
			}
		}
	}

	p.lastDiskReadBytes = totalReadBytes
	p.lastDiskWriteBytes = totalWriteBytes
	p.lastDiskTime = now

	return readRate, writeRate
}

func (p *LinuxSystemProbe) GetNetwork() (NetworkStats, error) {
	file, err := os.Open("/proc/net/dev")
	if err != nil {
		return NetworkStats{}, err
	}
	defer file.Close()

	var totalRxBytes, totalTxBytes uint64
	var totalRxPkts, totalTxPkts uint64
	var totalErrors uint64

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if !strings.Contains(line, ":") {
			continue
		}
		parts := strings.SplitN(line, ":", 2)
		iface := strings.TrimSpace(parts[0])
		if iface == "lo" {
			continue
		}

		fields := strings.Fields(parts[1])
		if len(fields) < 16 {
			continue
		}

		rxB, _ := strconv.ParseUint(fields[0], 10, 64)
		rxP, _ := strconv.ParseUint(fields[1], 10, 64)
		rxErr, _ := strconv.ParseUint(fields[2], 10, 64)
		txB, _ := strconv.ParseUint(fields[8], 10, 64)
		txP, _ := strconv.ParseUint(fields[9], 10, 64)
		txErr, _ := strconv.ParseUint(fields[10], 10, 64)

		totalRxBytes += rxB
		totalRxPkts += rxP
		totalTxBytes += txB
		totalTxPkts += txP
		totalErrors += rxErr + txErr
	}

	now := time.Now()
	var rxRate, txRate, rxPktRate, txPktRate float64

	if !p.lastNetTime.IsZero() {
		elapsed := now.Sub(p.lastNetTime).Seconds()
		if elapsed > 0 {
			if totalRxBytes >= p.lastNetRxBytes {
				rxRate = float64(totalRxBytes-p.lastNetRxBytes) / elapsed
			}
			if totalTxBytes >= p.lastNetTxBytes {
				txRate = float64(totalTxBytes-p.lastNetTxBytes) / elapsed
			}
			if totalRxPkts >= p.lastNetRxPkts {
				rxPktRate = float64(totalRxPkts-p.lastNetRxPkts) / elapsed
			}
			if totalTxPkts >= p.lastNetTxPkts {
				txPktRate = float64(totalTxPkts-p.lastNetTxPkts) / elapsed
			}
		}
	}

	p.lastNetRxBytes = totalRxBytes
	p.lastNetTxBytes = totalTxBytes
	p.lastNetRxPkts = totalRxPkts
	p.lastNetTxPkts = totalTxPkts
	p.lastNetTime = now

	return NetworkStats{
		RxBytesPerSec:   rxRate,
		TxBytesPerSec:   txRate,
		TotalRxBytes:    totalRxBytes,
		TotalTxBytes:    totalTxBytes,
		RxPacketsPerSec: rxPktRate,
		TxPacketsPerSec: txPktRate,
		Errors:          totalErrors,
	}, nil
}

func (p *LinuxSystemProbe) GetLoadAvg() (LoadAvgStats, error) {
	data, err := os.ReadFile("/proc/loadavg")
	if err != nil {
		return LoadAvgStats{}, err
	}
	fields := strings.Fields(string(data))
	if len(fields) < 3 {
		return LoadAvgStats{}, fmt.Errorf("malformed /proc/loadavg")
	}
	l1, _ := strconv.ParseFloat(fields[0], 64)
	l5, _ := strconv.ParseFloat(fields[1], 64)
	l15, _ := strconv.ParseFloat(fields[2], 64)

	return LoadAvgStats{
		Load1:  l1,
		Load5:  l5,
		Load15: l15,
	}, nil
}

func (p *LinuxSystemProbe) GetUptime() (int64, error) {
	data, err := os.ReadFile("/proc/uptime")
	if err != nil {
		return 0, err
	}
	fields := strings.Fields(string(data))
	if len(fields) < 1 {
		return 0, fmt.Errorf("malformed /proc/uptime")
	}
	secs, err := strconv.ParseFloat(fields[0], 64)
	if err != nil {
		return 0, err
	}
	return int64(secs), nil
}

func clamp(v float64) float64 {
	if v < 0 {
		return 0
	}
	if v > 100 {
		return 100
	}
	return v
}
