//go:build darwin

package processes

import (
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strconv"
	"strings"
	"syscall"
)

type DarwinProcessCollector struct{}

func NewCollector() Collector {
	return &DarwinProcessCollector{}
}

func (c *DarwinProcessCollector) CollectProcesses(limit int, sortBy string) ([]ProcessInfo, error) {
	if limit <= 0 {
		limit = 30
	}

	// ps -eo pid,ppid,user,%cpu,rss,state,comm
	out, err := exec.Command("ps", "-eo", "pid,ppid,user,%cpu,rss,state,comm").Output()
	if err != nil {
		return nil, err
	}

	lines := strings.Split(string(out), "\n")
	var procs []ProcessInfo

	for i, line := range lines {
		if i == 0 || strings.TrimSpace(line) == "" {
			continue // Skip header
		}

		fields := strings.Fields(line)
		if len(fields) < 7 {
			continue
		}

		pid, _ := strconv.Atoi(fields[0])
		ppid, _ := strconv.Atoi(fields[1])
		user := fields[2]
		cpu, _ := strconv.ParseFloat(fields[3], 64)
		rssKB, _ := strconv.ParseUint(fields[4], 10, 64)
		state := fields[5]
		comm := strings.Join(fields[6:], " ")
		nameParts := strings.Split(comm, "/")
		name := nameParts[len(nameParts)-1]

		procs = append(procs, ProcessInfo{
			PID:            pid,
			PPID:           ppid,
			Name:           name,
			User:           user,
			CPUPercent:     cpu,
			MemoryRSSBytes: rssKB * 1024,
			State:          mapDarwinState(state),
			Command:        comm,
		})
	}

	if sortBy == "memory" {
		sort.Slice(procs, func(i, j int) bool {
			return procs[i].MemoryRSSBytes > procs[j].MemoryRSSBytes
		})
	} else {
		sort.Slice(procs, func(i, j int) bool {
			return procs[i].CPUPercent > procs[j].CPUPercent
		})
	}

	if len(procs) > limit {
		procs = procs[:limit]
	}

	return procs, nil
}

func mapDarwinState(s string) string {
	if strings.Contains(s, "R") {
		return "Running"
	}
	if strings.Contains(s, "S") {
		return "Sleeping"
	}
	if strings.Contains(s, "U") {
		return "Disk Sleep"
	}
	if strings.Contains(s, "Z") {
		return "Zombie"
	}
	if strings.Contains(s, "T") {
		return "Stopped"
	}
	if strings.Contains(s, "I") {
		return "Idle"
	}
	return s
}

func (c *DarwinProcessCollector) KillProcess(pid int, signalName string) error {
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

