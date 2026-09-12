package storage

import (
	"bufio"
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type DirectoryUsage struct {
	Path       string `json:"path"`
	SizeBytes  int64  `json:"size_bytes"`
	SizeHuman  string `json:"size_human"`
	Category   string `json:"category"` // "logs", "docker", "cache", "temp", "user"
	Reclaimable bool  `json:"reclaimable"`
}

type ReclaimableSummary struct {
	JournalLogsBytes int64  `json:"journal_logs_bytes"`
	JournalLogsHuman string `json:"journal_logs_human"`
	DockerCacheBytes int64  `json:"docker_cache_bytes"`
	DockerCacheHuman string `json:"docker_cache_human"`
	AptCacheBytes    int64  `json:"apt_cache_bytes"`
	AptCacheHuman    string `json:"apt_cache_human"`
	TotalPotential   int64  `json:"total_potential_bytes"`
	TotalHuman       string `json:"total_human"`
}

type StorageAnalysis struct {
	Timestamp   time.Time          `json:"timestamp"`
	Directories []DirectoryUsage   `json:"directories"`
	Reclaimable ReclaimableSummary `json:"reclaimable"`
}

type Analyzer struct{}

func NewAnalyzer() *Analyzer {
	return &Analyzer{}
}

func (a *Analyzer) Analyze(ctx context.Context) StorageAnalysis {
	res := StorageAnalysis{
		Timestamp:   time.Now().UTC(),
		Directories: []DirectoryUsage{},
	}

	// 1. Common critical directories to measure
	targets := []struct {
		path        string
		category    string
		reclaimable bool
	}{
		{"/var/log", "logs", true},
		{"/var/lib/docker", "docker", true},
		{"/var/cache/apt", "cache", true},
		{"/var/cache", "cache", true},
		{"/tmp", "temp", true},
		{"/var/tmp", "temp", true},
		{"/home", "user", false},
		{"/root", "user", false},
	}

	for _, t := range targets {
		if _, err := os.Stat(t.path); err == nil {
			size := getDirSize(ctx, t.path)
			if size > 0 {
				res.Directories = append(res.Directories, DirectoryUsage{
					Path:        t.path,
					SizeBytes:   size,
					SizeHuman:   FormatBytes(size),
					Category:    t.category,
					Reclaimable: t.reclaimable,
				})
			}
		}
	}

	// 2. Journal logs size
	journalSize := getJournalSize(ctx)
	res.Reclaimable.JournalLogsBytes = journalSize
	res.Reclaimable.JournalLogsHuman = FormatBytes(journalSize)

	// 3. Docker reclaimable size
	dockerReclaimable := getDockerReclaimable(ctx)
	res.Reclaimable.DockerCacheBytes = dockerReclaimable
	res.Reclaimable.DockerCacheHuman = FormatBytes(dockerReclaimable)

	// 4. Apt cache size
	aptSize := getDirSize(ctx, "/var/cache/apt/archives")
	res.Reclaimable.AptCacheBytes = aptSize
	res.Reclaimable.AptCacheHuman = FormatBytes(aptSize)

	totalPotential := journalSize + dockerReclaimable + aptSize
	res.Reclaimable.TotalPotential = totalPotential
	res.Reclaimable.TotalHuman = FormatBytes(totalPotential)

	return res
}

func getDirSize(ctx context.Context, path string) int64 {
	// Use `du -sb <path>` or `du -sk <path>` with 5s timeout
	execCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	cmd := exec.CommandContext(execCtx, "du", "-sk", path)
	out, err := cmd.Output()
	if err == nil {
		fields := strings.Fields(string(out))
		if len(fields) > 0 {
			if kb, err := strconv.ParseInt(fields[0], 10, 64); err == nil {
				return kb * 1024
			}
		}
	}

	// Fallback to walk if du fails or on macOS
	var total int64
	_ = filepath.Walk(path, func(_ string, info os.FileInfo, err error) error {
		if err == nil && info != nil && !info.IsDir() {
			total += info.Size()
		}
		return nil
	})
	return total
}

func getJournalSize(ctx context.Context) int64 {
	execCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()

	cmd := exec.CommandContext(execCtx, "journalctl", "--disk-usage")
	out, err := cmd.Output()
	if err != nil {
		return 0
	}

	// Output format: "Archived and active journals take up 120.0M in the file system."
	line := string(out)
	words := strings.Fields(line)
	for i, w := range words {
		if w == "up" && i+1 < len(words) {
			valStr := words[i+1]
			return parseHumanSize(valStr)
		}
	}
	return 0
}

func getDockerReclaimable(ctx context.Context) int64 {
	execCtx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()

	cmd := exec.CommandContext(execCtx, "docker", "system", "df", "--format", "{{.Reclaimable}}")
	out, err := cmd.Output()
	if err != nil {
		return 0
	}

	scanner := bufio.NewScanner(strings.NewReader(string(out)))
	var total int64
	for scanner.Scan() {
		line := scanner.Text()
		// Line can be "1.2GB (80%)"
		fields := strings.Fields(line)
		if len(fields) > 0 {
			total += parseHumanSize(fields[0])
		}
	}
	return total
}

func parseHumanSize(s string) int64 {
	s = strings.TrimSpace(strings.ToUpper(s))
	multiplier := int64(1)
	if strings.HasSuffix(s, "G") || strings.HasSuffix(s, "GB") {
		multiplier = 1024 * 1024 * 1024
		s = strings.TrimSuffix(strings.TrimSuffix(s, "GB"), "G")
	} else if strings.HasSuffix(s, "M") || strings.HasSuffix(s, "MB") {
		multiplier = 1024 * 1024
		s = strings.TrimSuffix(strings.TrimSuffix(s, "MB"), "M")
	} else if strings.HasSuffix(s, "K") || strings.HasSuffix(s, "KB") {
		multiplier = 1024
		s = strings.TrimSuffix(strings.TrimSuffix(s, "KB"), "K")
	} else if strings.HasSuffix(s, "B") {
		s = strings.TrimSuffix(s, "B")
	}

	f, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0
	}
	return int64(f * float64(multiplier))
}

func FormatBytes(bytes int64) string {
	const unit = 1024
	if bytes < unit {
		return strconv.FormatInt(bytes, 10) + " B"
	}
	div, exp := int64(unit), 0
	for n := bytes / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	units := []string{"KB", "MB", "GB", "TB"}
	return strconv.FormatFloat(float64(bytes)/float64(div), 'f', 1, 64) + " " + units[exp]
}
