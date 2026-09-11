//go:build linux

package processes

import (
	"fmt"
	"os"
	"os/user"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
)

type LinuxProcessCollector struct {
	lastCPUTotal uint64
	lastProcCPUs map[int]uint64
	lastTime     time.Time
}

func NewCollector() Collector {
	return &LinuxProcessCollector{
		lastProcCPUs: make(map[int]uint64),
	}
}

func (c *LinuxProcessCollector) CollectProcesses(limit int, sortBy string) ([]ProcessInfo, error) {
	if limit <= 0 {
		limit = 30
	}

	d, err := os.Open("/proc")
	if err != nil {
		return nil, err
	}
	defer d.Close()

	names, err := d.Readdirnames(-1)
	if err != nil {
		return nil, err
	}

	var procs []ProcessInfo
	pageSize := uint64(os.Getpagesize())

	for _, name := range names {
		pid, err := strconv.Atoi(name)
		if err != nil {
			continue // Not a PID folder
		}

		pInfo, err := readProcess(pid, pageSize)
		if err != nil {
			continue
		}
		procs = append(procs, pInfo)
	}

	// Sort
	if sortBy == "memory" {
		sort.Slice(procs, func(i, j int) bool {
			return procs[i].MemoryRSSBytes > procs[j].MemoryRSSBytes
		})
	} else {
		// default sort by CPU
		sort.Slice(procs, func(i, j int) bool {
			return procs[i].CPUPercent > procs[j].CPUPercent
		})
	}

	if len(procs) > limit {
		procs = procs[:limit]
	}

	return procs, nil
}

func readProcess(pid int, pageSize uint64) (ProcessInfo, error) {
	statPath := filepath.Join("/proc", strconv.Itoa(pid), "stat")
	data, err := os.ReadFile(statPath)
	if err != nil {
		return ProcessInfo{}, err
	}

	str := string(data)
	// Process name is inside parentheses: pid (name) state ...
	openIdx := strings.Index(str, "(")
	closeIdx := strings.LastIndex(str, ")")
	if openIdx == -1 || closeIdx == -1 || closeIdx <= openIdx {
		return ProcessInfo{}, fmt.Errorf("malformed stat")
	}

	comm := str[openIdx+1 : closeIdx]
	after := strings.Fields(str[closeIdx+1:])
	if len(after) < 22 {
		return ProcessInfo{}, fmt.Errorf("short stat")
	}

	state := after[0]
	ppid, _ := strconv.Atoi(after[1])
	utime, _ := strconv.ParseUint(after[11], 10, 64)
	stime, _ := strconv.ParseUint(after[12], 10, 64)
	rssPages, _ := strconv.ParseUint(after[21], 10, 64)
	rssBytes := rssPages * pageSize

	// Get UID from file ownership
	var uid string
	if fi, err := os.Stat(statPath); err == nil {
		if stat, ok := fi.Sys().(*syscall.Stat_t); ok {
			u, err := user.LookupId(strconv.Itoa(int(stat.Uid)))
			if err == nil {
				uid = u.Username
			} else {
				uid = strconv.Itoa(int(stat.Uid))
			}
		}
	}

	// Read cmdline
	cmdline := comm
	if cmdData, err := os.ReadFile(filepath.Join("/proc", strconv.Itoa(pid), "cmdline")); err == nil && len(cmdData) > 0 {
		cmdline = strings.ReplaceAll(string(cmdData), "\x00", " ")
		cmdline = strings.TrimSpace(cmdline)
		if len(cmdline) > 120 {
			cmdline = cmdline[:120] + "..."
		}
	}

	totalTicks := utime + stime
	cpuPercent := float64(totalTicks % 100) / 2.0

	return ProcessInfo{
		PID:            pid,
		PPID:           ppid,
		Name:           comm,
		User:           uid,
		CPUPercent:     cpuPercent,
		MemoryRSSBytes: rssBytes,
		State:          mapLinuxState(state),
		Command:        cmdline,
	}, nil
}

func mapLinuxState(s string) string {
	switch s {
	case "R":
		return "Running"
	case "S":
		return "Sleeping"
	case "D":
		return "Disk Sleep"
	case "Z":
		return "Zombie"
	case "T":
		return "Stopped"
	case "t":
		return "Tracing"
	case "X", "x":
		return "Dead"
	case "K":
		return "Wakekill"
	case "W":
		return "Waking"
	case "P":
		return "Parked"
	case "I":
		return "Idle"
	default:
		return s
	}
}

func (c *LinuxProcessCollector) KillProcess(pid int, signalName string) error {
	if pid <= 1 {
		return fmt.Errorf("refusing to kill protected system process (PID %d)", pid)
	}
	if pid == os.Getpid() {
		return fmt.Errorf("refusing to kill pulse-agent process (PID %d)", pid)
	}

	var sig syscall.Signal
	switch strings.ToUpper(signalName) {
	case "SIGTERM", "TERM":
		sig = syscall.SIGTERM
	case "SIGKILL", "KILL":
		sig = syscall.SIGKILL
	default:
		return fmt.Errorf("unsupported signal %s (only SIGTERM and SIGKILL are allowed)", signalName)
	}

	p, err := os.FindProcess(pid)
	if err != nil {
		return err
	}
	return p.Signal(sig)
}

