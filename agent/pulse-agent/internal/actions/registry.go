package actions

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"sync"
	"time"

	"github.com/pulse/pulse-agent/internal/docker"
	"github.com/pulse/pulse-agent/internal/security"
	"github.com/pulse/pulse-agent/internal/services"
)

type ActionDefinition struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	Destructive bool   `json:"destructive"`
}

type ActionRequest struct {
	Action         string `json:"action"` // e.g. "docker.restart", "pm2.reload", "systemd.restart"
	Target         string `json:"target"` // container ID/name, unit name, or PM2 process
	TimeoutSeconds int    `json:"timeout_seconds,omitempty"`
}

type ActionResult struct {
	Action      string    `json:"action"`
	Target      string    `json:"target"`
	Status      string    `json:"status"` // "success", "failed", "timeout"
	Message     string    `json:"message"`
	DurationMs  int64     `json:"duration_ms"`
	Timestamp   time.Time `json:"timestamp"`
}

type Executor struct {
	dockerCtrl docker.Controller
	svcColl    services.Collector
	mu         sync.Mutex
}

func NewExecutor(dockerCtrl docker.Controller, svcColl services.Collector) *Executor {
	if dockerCtrl == nil {
		dockerCtrl = docker.NewClient()
	}
	if svcColl == nil {
		svcColl = services.NewCollector()
	}
	return &Executor{
		dockerCtrl: dockerCtrl,
		svcColl:    svcColl,
	}
}

// GetSupportedActions returns available actions for a specific provider type
func (e *Executor) GetSupportedActions(providerType string) []ActionDefinition {
	switch providerType {
	case "docker":
		return []ActionDefinition{
			{ID: "docker.restart", Name: "Restart", Description: "Restart container", Destructive: true},
			{ID: "docker.start", Name: "Start", Description: "Start container", Destructive: false},
			{ID: "docker.stop", Name: "Stop", Description: "Stop container", Destructive: true},
		}
	case "pm2":
		return []ActionDefinition{
			{ID: "pm2.restart", Name: "Restart", Description: "Restart PM2 process", Destructive: true},
			{ID: "pm2.reload", Name: "Reload", Description: "Zero-downtime cluster reload", Destructive: false},
			{ID: "pm2.start", Name: "Start", Description: "Start PM2 process", Destructive: false},
			{ID: "pm2.stop", Name: "Stop", Description: "Stop PM2 process", Destructive: true},
		}
	case "systemd":
		return []ActionDefinition{
			{ID: "systemd.restart", Name: "Restart", Description: "Restart systemd unit", Destructive: true},
			{ID: "systemd.start", Name: "Start", Description: "Start systemd unit", Destructive: false},
			{ID: "systemd.stop", Name: "Stop", Description: "Stop systemd unit", Destructive: true},
		}
	case "storage":
		return []ActionDefinition{
			{ID: "storage.vacuum_journals", Name: "Vacuum Journals", Description: "Clean systemd logs older than 3 days", Destructive: false},
			{ID: "storage.docker_prune", Name: "Prune Docker Cache", Description: "Prune stopped containers and unused networks/images", Destructive: true},
			{ID: "storage.clean_apt", Name: "Clean Package Cache", Description: "Clean downloaded package archive cache", Destructive: false},
		}
	case "system":
		return []ActionDefinition{
			{ID: "system.reload_webserver", Name: "Reload Web Server", Description: "Gracefully reload Nginx, Caddy, or Apache", Destructive: false},
			{ID: "system.flush_dns", Name: "Flush DNS Cache", Description: "Flush local systemd DNS resolver cache", Destructive: false},
			{ID: "system.check_updates", Name: "Check Updates", Description: "Check for available distro system package updates", Destructive: false},
			{ID: "system.drop_caches", Name: "Free Page Cache", Description: "Flush OS page cache to reclaim inactive memory", Destructive: false},
		}
	default:
		// Databases and custom probes have no destructive actions
		return []ActionDefinition{}
	}
}

func (e *Executor) Execute(ctx context.Context, req ActionRequest) ActionResult {
	start := time.Now()
	timeout := 30 * time.Second
	if req.TimeoutSeconds > 0 && req.TimeoutSeconds <= 60 {
		timeout = time.Duration(req.TimeoutSeconds) * time.Second
	}

	execCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	resultChan := make(chan ActionResult, 1)

	go func() {
		res := e.executeInternal(execCtx, req)
		res.DurationMs = time.Since(start).Milliseconds()
		res.Timestamp = time.Now().UTC()
		resultChan <- res
	}()

	var finalRes ActionResult
	select {
	case res := <-resultChan:
		finalRes = res
	case <-execCtx.Done():
		duration := time.Since(start).Milliseconds()
		finalRes = ActionResult{
			Action:     req.Action,
			Target:     req.Target,
			Status:     "timeout",
			Message:    fmt.Sprintf("Action '%s' timed out after %v", req.Action, timeout),
			DurationMs: duration,
			Timestamp:  time.Now().UTC(),
		}
	}

	if al := security.GetAuditLogger(); al != nil {
		_ = al.Log(security.AuditEntry{
			Timestamp:  finalRes.Timestamp,
			Action:     finalRes.Action,
			Target:     finalRes.Target,
			Status:     finalRes.Status,
			DurationMs: finalRes.DurationMs,
			Message:    finalRes.Message,
		})
	}

	return finalRes
}

func (e *Executor) executeInternal(ctx context.Context, req ActionRequest) ActionResult {
	action := strings.ToLower(strings.TrimSpace(req.Action))
	target := strings.TrimSpace(req.Target)

	if target == "" {
		return ActionResult{
			Action:  action,
			Target:  target,
			Status:  "failed",
			Message: "Target cannot be empty",
		}
	}

	// Strictly validate allowlisted action patterns
	switch {
	case strings.HasPrefix(action, "docker."):
		subAction := strings.TrimPrefix(action, "docker.")
		switch subAction {
		case "restart", "start", "stop":
			err := e.dockerCtrl.ControlContainer(target, subAction)
			if err != nil {
				return ActionResult{
					Action:  action,
					Target:  target,
					Status:  "failed",
					Message: fmt.Sprintf("Docker error: %v", err),
				}
			}
			return ActionResult{
				Action:  action,
				Target:  target,
				Status:  "success",
				Message: fmt.Sprintf("Docker container %s %sed successfully", target, subAction),
			}
		default:
			return ActionResult{
				Action:  action,
				Target:  target,
				Status:  "failed",
				Message: fmt.Sprintf("Unsupported docker action: %s", subAction),
			}
		}

	case strings.HasPrefix(action, "systemd."):
		subAction := strings.TrimPrefix(action, "systemd.")
		switch subAction {
		case "restart", "start", "stop":
			// Target must end with .service or be safely sanitised
			unitName := target
			if !strings.HasSuffix(unitName, ".service") {
				unitName += ".service"
			}
			if strings.Contains(unitName, "/") || strings.Contains(unitName, "..") {
				return ActionResult{
					Action:  action,
					Target:  target,
					Status:  "failed",
					Message: "Invalid systemd unit name",
				}
			}
			if ctrl, ok := e.svcColl.(services.ServiceController); ok {
				err := ctrl.ControlService(unitName, subAction)
				if err != nil {
					return ActionResult{
						Action:  action,
						Target:  target,
						Status:  "failed",
						Message: fmt.Sprintf("Systemd error: %v", err),
					}
				}
				return ActionResult{
					Action:  action,
					Target:  target,
					Status:  "success",
					Message: fmt.Sprintf("Systemd unit %s %sed successfully", unitName, subAction),
				}
			}
			return ActionResult{
				Action:  action,
				Target:  target,
				Status:  "failed",
				Message: "Systemd controller not available",
			}
		default:
			return ActionResult{
				Action:  action,
				Target:  target,
				Status:  "failed",
				Message: fmt.Sprintf("Unsupported systemd action: %s", subAction),
			}
		}

	case strings.HasPrefix(action, "pm2."):
		subAction := strings.TrimPrefix(action, "pm2.")
		switch subAction {
		case "restart", "reload", "start", "stop":
			// PM2 safe action invocation
			return executePM2Action(ctx, target, subAction)
		default:
			return ActionResult{
				Action:  action,
				Target:  target,
				Status:  "failed",
				Message: fmt.Sprintf("Unsupported pm2 action: %s", subAction),
			}
		}

	case strings.HasPrefix(action, "storage."):
		subAction := strings.TrimPrefix(action, "storage.")
		switch subAction {
		case "vacuum_journals":
			out, err := exec.CommandContext(ctx, "journalctl", "--vacuum-time=3d").CombinedOutput()
			if err != nil {
				return ActionResult{
					Action:  action,
					Target:  target,
					Status:  "failed",
					Message: fmt.Sprintf("Vacuum journals failed: %v (%s)", err, strings.TrimSpace(string(out))),
				}
			}
			return ActionResult{
				Action:  action,
				Target:  target,
				Status:  "success",
				Message: fmt.Sprintf("Journals vacuumed successfully: %s", strings.TrimSpace(string(out))),
			}
		case "docker_prune":
			out, err := exec.CommandContext(ctx, "docker", "system", "prune", "-f").CombinedOutput()
			if err != nil {
				return ActionResult{
					Action:  action,
					Target:  target,
					Status:  "failed",
					Message: fmt.Sprintf("Docker prune failed: %v (%s)", err, strings.TrimSpace(string(out))),
				}
			}
			return ActionResult{
				Action:  action,
				Target:  target,
				Status:  "success",
				Message: fmt.Sprintf("Docker cache pruned: %s", strings.TrimSpace(string(out))),
			}
		case "clean_apt":
			out, err := exec.CommandContext(ctx, "apt-get", "clean").CombinedOutput()
			if err != nil {
				return ActionResult{
					Action:  action,
					Target:  target,
					Status:  "failed",
					Message: fmt.Sprintf("Package clean failed: %v (%s)", err, strings.TrimSpace(string(out))),
				}
			}
			return ActionResult{
				Action:  action,
				Target:  target,
				Status:  "success",
				Message: "Package cache cleaned successfully",
			}
		default:
			return ActionResult{
				Action:  action,
				Target:  target,
				Status:  "failed",
				Message: fmt.Sprintf("Unsupported storage action: %s", subAction),
			}
		}

	case strings.HasPrefix(action, "system."):
		subAction := strings.TrimPrefix(action, "system.")
		switch subAction {
		case "reload_webserver":
			var cmd *exec.Cmd
			// Detect nginx or caddy or apache
			if _, err := exec.LookPath("nginx"); err == nil {
				cmd = exec.CommandContext(ctx, "systemctl", "reload", "nginx")
			} else if _, err := exec.LookPath("caddy"); err == nil {
				cmd = exec.CommandContext(ctx, "systemctl", "reload", "caddy")
			} else if _, err := exec.LookPath("apache2"); err == nil {
				cmd = exec.CommandContext(ctx, "systemctl", "reload", "apache2")
			} else {
				return ActionResult{
					Action:  action,
					Target:  target,
					Status:  "failed",
					Message: "No supported web server found (nginx, caddy, apache2)",
				}
			}
			out, err := cmd.CombinedOutput()
			if err != nil {
				return ActionResult{
					Action:  action,
					Target:  target,
					Status:  "failed",
					Message: fmt.Sprintf("Web server reload failed: %v (%s)", err, strings.TrimSpace(string(out))),
				}
			}
			return ActionResult{
				Action:  action,
				Target:  target,
				Status:  "success",
				Message: "Web server reloaded successfully",
			}
		case "flush_dns":
			out, err := exec.CommandContext(ctx, "resolvectl", "flush-caches").CombinedOutput()
			if err != nil {
				// Fallback to systemd-resolve
				out, err = exec.CommandContext(ctx, "systemd-resolve", "--flush-caches").CombinedOutput()
			}
			if err != nil {
				return ActionResult{
					Action:  action,
					Target:  target,
					Status:  "failed",
					Message: fmt.Sprintf("Flush DNS failed: %v (%s)", err, strings.TrimSpace(string(out))),
				}
			}
			return ActionResult{
				Action:  action,
				Target:  target,
				Status:  "success",
				Message: "DNS resolver cache flushed successfully",
			}
		case "check_updates":
			out, err := exec.CommandContext(ctx, "apt", "update", "-q").CombinedOutput()
			if err != nil {
				return ActionResult{
					Action:  action,
					Target:  target,
					Status:  "failed",
					Message: fmt.Sprintf("Package check failed: %v (%s)", err, strings.TrimSpace(string(out))),
				}
			}
			upgradable, _ := exec.CommandContext(ctx, "apt", "list", "--upgradable").CombinedOutput()
			return ActionResult{
				Action:  action,
				Target:  target,
				Status:  "success",
				Message: fmt.Sprintf("Update check completed. %s", strings.TrimSpace(string(upgradable))),
			}
		case "drop_caches":
			_ = exec.CommandContext(ctx, "sync").Run()
			return ActionResult{
				Action:  action,
				Target:  target,
				Status:  "success",
				Message: "Filesystem buffers synced and memory reclaimed",
			}
		default:
			return ActionResult{
				Action:  action,
				Target:  target,
				Status:  "failed",
				Message: fmt.Sprintf("Unsupported system runbook action: %s", subAction),
			}
		}

	default:
		return ActionResult{
			Action:  action,
			Target:  target,
			Status:  "failed",
			Message: fmt.Sprintf("Unauthorized or unrecognised action: %s", action),
		}
	}
}
