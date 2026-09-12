package logs

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"os/exec"
	"strings"
	"time"

	"github.com/pulse/pulse-agent/internal/docker"
)

type LogEntry struct {
	Timestamp time.Time `json:"timestamp"`
	Line      string    `json:"line"`
	Stream    string    `json:"stream"` // "stdout" or "stderr"
}

type Streamer struct {
	dockerCli docker.Controller
}

func NewStreamer(dockerCli docker.Controller) *Streamer {
	if dockerCli == nil {
		dockerCli = docker.NewClient()
	}
	return &Streamer{dockerCli: dockerCli}
}

// StreamSystemd streams journalctl lines for a given systemd unit.
func (s *Streamer) StreamSystemd(ctx context.Context, unit string, tail int, follow bool, out chan<- LogEntry) error {
	if tail <= 0 {
		tail = 100
	}
	if tail > 1000 {
		tail = 1000
	}

	// Clean unit name to prevent injection
	unit = strings.TrimSpace(unit)
	if !strings.HasSuffix(unit, ".service") && !strings.Contains(unit, ".") {
		unit += ".service"
	}

	args := []string{"-u", unit, "-n", fmt.Sprintf("%d", tail), "--no-pager", "-o", "short-iso"}
	if follow {
		args = append(args, "-f")
	}

	cmd := exec.CommandContext(ctx, "journalctl", args...)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return fmt.Errorf("failed to open stdout pipe: %w", err)
	}
	cmd.Stderr = cmd.Stdout // merge stderr

	if err := cmd.Start(); err != nil {
		return fmt.Errorf("failed to start journalctl: %w", err)
	}

	scanner := bufio.NewScanner(stdout)
	// Buffer up to 64KB per log line
	buf := make([]byte, 0, 64*1024)
	scanner.Buffer(buf, 64*1024)

	go func() {
		defer cmd.Wait() // ensure process is cleaned up
		for scanner.Scan() {
			select {
			case <-ctx.Done():
				return
			default:
				raw := scanner.Text()
				if strings.TrimSpace(raw) == "" {
					continue
				}

				entry := parseJournalLine(raw)
				select {
				case out <- entry:
				case <-ctx.Done():
					return
				}
			}
		}
	}()

	return nil
}

// StreamDocker streams logs from a Docker container.
func (s *Streamer) StreamDocker(ctx context.Context, containerID string, tail int, follow bool, out chan<- LogEntry) error {
	if tail <= 0 {
		tail = 100
	}
	if tail > 1000 {
		tail = 1000
	}

	containerID = strings.TrimSpace(containerID)

	args := []string{"logs", "--tail", fmt.Sprintf("%d", tail), "-t"}
	if follow {
		args = append(args, "-f")
	}
	args = append(args, containerID)

	cmd := exec.CommandContext(ctx, "docker", args...)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return fmt.Errorf("failed to open stdout pipe: %w", err)
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return fmt.Errorf("failed to open stderr pipe: %w", err)
	}

	if err := cmd.Start(); err != nil {
		return fmt.Errorf("failed to execute docker logs: %w", err)
	}

	readPipe := func(reader io.Reader, streamType string) {
		scanner := bufio.NewScanner(reader)
		buf := make([]byte, 0, 64*1024)
		scanner.Buffer(buf, 64*1024)

		for scanner.Scan() {
			select {
			case <-ctx.Done():
				return
			default:
				raw := scanner.Text()
				if strings.TrimSpace(raw) == "" {
					continue
				}
				entry := parseDockerLine(raw, streamType)
				select {
				case out <- entry:
				case <-ctx.Done():
					return
				}
			}
		}
	}

	go readPipe(stdout, "stdout")
	go readPipe(stderr, "stderr")

	go func() {
		_ = cmd.Wait()
	}()

	return nil
}

func parseJournalLine(raw string) LogEntry {
	fields := strings.Fields(raw)
	now := time.Now().UTC()
	if len(fields) > 0 {
		if t, err := time.Parse(time.RFC3339, fields[0]); err == nil {
			return LogEntry{
				Timestamp: t,
				Line:      raw,
				Stream:    "stdout",
			}
		}
	}
	return LogEntry{
		Timestamp: now,
		Line:      raw,
		Stream:    "stdout",
	}
}

func parseDockerLine(raw string, stream string) LogEntry {
	fields := strings.Fields(raw)
	now := time.Now().UTC()
	if len(fields) > 0 {
		if t, err := time.Parse(time.RFC3339Nano, fields[0]); err == nil {
			cleanLine := strings.TrimPrefix(raw, fields[0]+" ")
			return LogEntry{
				Timestamp: t,
				Line:      cleanLine,
				Stream:    stream,
			}
		}
	}
	return LogEntry{
		Timestamp: now,
		Line:      raw,
		Stream:    stream,
	}
}
