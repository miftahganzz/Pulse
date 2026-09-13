package server

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"time"

	"github.com/gorilla/websocket"
	"github.com/pulse/pulse-agent/internal/actions"
	"github.com/pulse/pulse-agent/internal/agent"
	"github.com/pulse/pulse-agent/internal/docker"
	"github.com/pulse/pulse-agent/internal/metrics"
	"github.com/pulse/pulse-agent/internal/processes"
	"github.com/pulse/pulse-agent/internal/providers"
	"github.com/pulse/pulse-agent/internal/providers/database"
	postgresprov "github.com/pulse/pulse-agent/internal/providers/database/postgres"
	redisprov "github.com/pulse/pulse-agent/internal/providers/database/redis"
	mysqlprov "github.com/pulse/pulse-agent/internal/providers/database/mysql"
	mongodbprov "github.com/pulse/pulse-agent/internal/providers/database/mongodb"
	dockerprov "github.com/pulse/pulse-agent/internal/providers/docker"
	httpprov "github.com/pulse/pulse-agent/internal/providers/http"
	pm2prov "github.com/pulse/pulse-agent/internal/providers/pm2"
	procprov "github.com/pulse/pulse-agent/internal/providers/process"
	systemdprov "github.com/pulse/pulse-agent/internal/providers/systemd"
	tcpprov "github.com/pulse/pulse-agent/internal/providers/tcp"
	webserverprov "github.com/pulse/pulse-agent/internal/providers/webserver"
	cloudflaredprov "github.com/pulse/pulse-agent/internal/providers/cloudflared"
	customprov "github.com/pulse/pulse-agent/internal/providers/custom"
	"github.com/pulse/pulse-agent/internal/alerts"
	"github.com/pulse/pulse-agent/internal/intelligence"
	"github.com/pulse/pulse-agent/internal/logs"
	"github.com/pulse/pulse-agent/internal/pairing"
	"github.com/pulse/pulse-agent/internal/security"
	"github.com/pulse/pulse-agent/internal/services"
	"github.com/pulse/pulse-agent/internal/storage"
	"github.com/pulse/pulse-agent/internal/transport"
)

var upgrader = websocket.Upgrader{
	HandshakeTimeout: 15 * time.Second,
	CheckOrigin: func(r *http.Request) bool {
		origin := r.Header.Get("Origin")
		if origin == "" {
			// Native client (macOS app, curl, wscat) sends no Origin header
			return true
		}
		lower := strings.ToLower(origin)
		// Allow local development and pulse schemes
		if strings.Contains(lower, "localhost") || strings.Contains(lower, "127.0.0.1") || strings.HasPrefix(lower, "pulse://") {
			return true
		}
		// Block unverified external third-party web origins from hijacking the stream
		return false
	},
}

type Server struct {
	cfg        *agent.Config
	identity   agent.Identity
	metricsCol *metrics.MetricsCollector
	procColl   processes.Collector
	svcColl    services.Collector
	dockerCtrl docker.Controller
	registry   *providers.Registry
	executor   *actions.Executor
	streamer   *logs.Streamer
	analyzer   *storage.Analyzer
	telegram   *alerts.TelegramDispatcher
	tgCfg      alerts.TelegramConfig
	pgProv     *postgresprov.PostgresProvider
	redisProv  *redisprov.RedisProvider
	mysqlProv  *mysqlprov.MySQLProvider
	mongoProv  *mongodbprov.MongoDBProvider
	logger     *slog.Logger
	startTime  time.Time
	seq        atomic.Int64
}

func NewServer(cfg *agent.Config, identity agent.Identity, logger *slog.Logger) *Server {
	procCol := processes.NewCollector()
	svcCol := services.NewCollector()
	dockerCli := docker.NewClient()
	pgP := postgresprov.NewProvider()
	redisP := redisprov.NewProvider()
	myP := mysqlprov.NewProvider()
	mongoP := mongodbprov.NewProvider()
	webP := webserverprov.NewProvider()
	cfP := cloudflaredprov.NewProvider()
	customP := customprov.NewProvider()

	reg := providers.NewRegistry()
	reg.Register(systemdprov.NewProvider(svcCol))
	reg.Register(dockerprov.NewProvider(dockerCli))
	reg.Register(procprov.NewProvider(procCol))
	reg.Register(pm2prov.NewProvider())
	reg.Register(httpprov.NewProvider())
	reg.Register(tcpprov.NewProvider())
	reg.Register(pgP)
	reg.Register(redisP)
	reg.Register(myP)
	reg.Register(mongoP)
	reg.Register(webP)
	reg.Register(cfP)
	reg.Register(customP)

	exec := actions.NewExecutor(dockerCli, svcCol)

	if cfg != nil && cfg.CertFile != "" {
		security.InitAuditLogger(filepath.Dir(cfg.CertFile))
	}

	return &Server{
		cfg:        cfg,
		identity:   identity,
		metricsCol: metrics.NewCollector(logger),
		procColl:   procCol,
		svcColl:    svcCol,
		dockerCtrl: dockerCli,
		registry:   reg,
		executor:   exec,
		streamer:   logs.NewStreamer(dockerCli),
		analyzer:   storage.NewAnalyzer(),
		telegram:   alerts.NewTelegramDispatcher(),
		pgProv:     pgP,
		redisProv:  redisP,
		mysqlProv:  myP,
		mongoProv:  mongoP,
		logger:     logger,
		startTime:  time.Now(),
	}
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()

	// Protected endpoints (wrapped with token auth)
	mux.HandleFunc("/api/v1/info", s.handleInfo)
	mux.HandleFunc("/api/v1/metrics", s.handleMetrics)
	mux.HandleFunc("/api/v1/processes", s.handleProcesses)
	mux.HandleFunc("/api/v1/processes/", s.handleProcessAction)
	mux.HandleFunc("/api/v1/services", s.handleServices)
	mux.HandleFunc("/api/v1/services/", s.handleServiceAction)
	mux.HandleFunc("/api/v1/docker/containers", s.handleDockerContainers)
	mux.HandleFunc("/api/v1/docker/containers/", s.handleDockerContainerActionOrLogs)
	mux.HandleFunc("/api/v1/discovery", s.handleDiscovery)
	mux.HandleFunc("/api/v1/monitors/health", s.handleMonitorsHealth)
	mux.HandleFunc("/api/v1/monitors/probe-db", s.handleProbeDB)
	mux.HandleFunc("/api/v1/actions/execute", s.handleActionExecute)
	mux.HandleFunc("/api/v1/providers", s.handleProviders)
	mux.HandleFunc("/api/v1/agent/health", s.handleAgentHealth)
	mux.HandleFunc("/api/v1/security/ports", s.handleSecurityPorts)
	mux.HandleFunc("/ws/v1/stream", s.handleStream)
	mux.HandleFunc("/ws/v1/logs", s.handleLogsStream)
	mux.HandleFunc("/api/v1/storage/analyze", s.handleStorageAnalyze)
	mux.HandleFunc("/api/v1/alerts/telegram/test", s.handleTelegramTest)
	mux.HandleFunc("/api/v1/alerts/telegram/config", s.handleTelegramConfig)

	protectedHandler := security.TokenAuthMiddleware(s.cfg.AuthToken, mux)

	// Root mux with public pairing endpoint
	rootMux := http.NewServeMux()
	rootMux.HandleFunc("/api/v1/pair", s.handlePair)
	rootMux.HandleFunc("/api/v1/pair/register", s.handlePairRegister)
	rootMux.Handle("/", protectedHandler)

	return SecurityHeadersMiddleware(rootMux)
}

// SecurityHeadersMiddleware injects defense-in-depth security headers
func SecurityHeadersMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("X-XSS-Protection", "1; mode=block")
		w.Header().Set("Content-Security-Policy", "default-src 'none'")
		w.Header().Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		next.ServeHTTP(w, r)
	})
}

func (s *Server) handleInfo(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	env, err := transport.NewEnvelope("agent.hello", transport.HelloPayload{
		AgentID:         s.identity.AgentID,
		AgentVersion:    s.identity.AgentVersion,
		Hostname:        s.identity.Hostname,
		OS:              s.identity.OS,
		KernelVersion:   s.identity.KernelVersion,
		Architecture:    s.identity.Architecture,
		CPUCores:        s.identity.CPUCores,
		ProtocolVersion: s.identity.ProtocolVersion,
	})
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(env)
}

func (s *Server) handleMetrics(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	snapshot := s.metricsCol.Collect()
	env, err := transport.NewEnvelope("metrics.snapshot", snapshot)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(env)
}

func (s *Server) handleProcesses(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	limit := 30
	if lStr := r.URL.Query().Get("limit"); lStr != "" {
		if l, err := strconv.Atoi(lStr); err == nil && l > 0 && l <= 100 {
			limit = l
		}
	}

	sortBy := r.URL.Query().Get("sort")
	if sortBy != "memory" {
		sortBy = "cpu"
	}

	procs, err := s.procColl.CollectProcesses(limit, sortBy)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	env, err := transport.NewEnvelope("processes.snapshot", processes.ProcessesSnapshot{
		Processes: procs,
	})
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(env)
}

func (s *Server) handleServices(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	svcs, err := s.svcColl.CollectServices()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	env, err := transport.NewEnvelope("services.snapshot", services.ServicesSnapshot{
		Services: svcs,
	})
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(env)
}

func (s *Server) handleProcessAction(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Route format: /api/v1/processes/{pid}/kill
	parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	if len(parts) != 5 || parts[0] != "api" || parts[1] != "v1" || parts[2] != "processes" || parts[4] != "kill" {
		http.NotFound(w, r)
		return
	}

	pid, err := strconv.Atoi(parts[3])
	if err != nil || pid <= 0 {
		http.Error(w, "invalid process pid", http.StatusBadRequest)
		return
	}

	var req struct {
		Signal string `json:"signal"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		req.Signal = "SIGTERM"
	}
	if req.Signal == "" {
		req.Signal = "SIGTERM"
	}

	ctrl, ok := s.procColl.(processes.ProcessController)
	if !ok {
		http.Error(w, "process control unsupported on this platform", http.StatusNotImplemented)
		return
	}

	if err := ctrl.KillProcess(pid, req.Signal); err != nil {
		s.logger.Warn("failed to kill process", "pid", pid, "signal", req.Signal, "error", err)
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	s.logger.Info("process signaled successfully", "pid", pid, "signal", req.Signal)
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"success": true,
		"message": fmt.Sprintf("Process %d signaled with %s", pid, req.Signal),
	})
}

func (s *Server) handleServiceAction(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Route format: /api/v1/services/{name}/action
	parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	if len(parts) != 5 || parts[0] != "api" || parts[1] != "v1" || parts[2] != "services" || parts[4] != "action" {
		http.NotFound(w, r)
		return
	}

	name := parts[3]
	if !strings.HasSuffix(name, ".service") || strings.Contains(name, "/") || strings.Contains(name, "..") {
		http.Error(w, "invalid service unit name", http.StatusBadRequest)
		return
	}

	var req struct {
		Action string `json:"action"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	ctrl, ok := s.svcColl.(services.ServiceController)
	if !ok {
		http.Error(w, "service control unsupported on this platform", http.StatusNotImplemented)
		return
	}

	if err := ctrl.ControlService(name, req.Action); err != nil {
		s.logger.Warn("failed to control service", "service", name, "action", req.Action, "error", err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	s.logger.Info("service action executed successfully", "service", name, "action", req.Action)
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"success": true,
		"message": fmt.Sprintf("Service %s action %s succeeded", name, req.Action),
	})
}

func (s *Server) handleDockerContainers(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	status, err := s.dockerCtrl.GetStatus()
	if err != nil {
		s.logger.Warn("failed to fetch docker status", "error", err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(status)
}

func (s *Server) handleDockerContainerActionOrLogs(w http.ResponseWriter, r *http.Request) {
	parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	// Expected routes:
	// POST /api/v1/docker/containers/{id}/action
	// GET  /api/v1/docker/containers/{id}/logs
	if len(parts) != 6 || parts[0] != "api" || parts[1] != "v1" || parts[2] != "docker" || parts[3] != "containers" {
		http.NotFound(w, r)
		return
	}

	containerID := parts[4]
	actionType := parts[5]

	if actionType == "logs" && r.Method == http.MethodGet {
		tail := 100
		if tStr := r.URL.Query().Get("tail"); tStr != "" {
			if t, err := strconv.Atoi(tStr); err == nil && t > 0 && t <= 1000 {
				tail = t
			}
		}

		logs, err := s.dockerCtrl.GetLogs(containerID, tail)
		if err != nil {
			s.logger.Warn("failed to get container logs", "id", containerID, "error", err)
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"container_id": containerID,
			"logs":         logs,
		})
		return
	}

	if actionType == "action" && r.Method == http.MethodPost {
		var req struct {
			Action string `json:"action"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "invalid request body", http.StatusBadRequest)
			return
		}

		if err := s.dockerCtrl.ControlContainer(containerID, req.Action); err != nil {
			s.logger.Warn("failed to control container", "id", containerID, "action", req.Action, "error", err)
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		s.logger.Info("container action executed successfully", "id", containerID, "action", req.Action)
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"success": true,
			"message": fmt.Sprintf("Container %s action %s succeeded", containerID, req.Action),
		})
		return
	}

	http.NotFound(w, r)
}

func (s *Server) handleStream(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		s.logger.Error("websocket upgrade failed", "error", err, "remote_addr", r.RemoteAddr)
		return
	}
	defer conn.Close()

	s.logger.Info("client connected to stream", "remote_addr", r.RemoteAddr)

	const (
		writeWait  = 25 * time.Second
		pongWait   = 60 * time.Second
		pingPeriod = 20 * time.Second
	)

	conn.SetReadLimit(512 * 1024)
	_ = conn.SetReadDeadline(time.Now().Add(pongWait))
	conn.SetPongHandler(func(string) error {
		_ = conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})
	conn.SetPingHandler(func(appData string) error {
		_ = conn.SetReadDeadline(time.Now().Add(pongWait))
		return conn.WriteControl(websocket.PongMessage, []byte(appData), time.Now().Add(writeWait))
	})

	// 1. Send initial agent.hello
	helloEnv, err := transport.NewEnvelope("agent.hello", transport.HelloPayload{
		AgentID:         s.identity.AgentID,
		AgentVersion:    s.identity.AgentVersion,
		Hostname:        s.identity.Hostname,
		OS:              s.identity.OS,
		KernelVersion:   s.identity.KernelVersion,
		Architecture:    s.identity.Architecture,
		CPUCores:        s.identity.CPUCores,
		ProtocolVersion: s.identity.ProtocolVersion,
	})
	if err != nil {
		s.logger.Error("failed to create hello envelope", "error", err)
		return
	}

	conn.SetWriteDeadline(time.Now().Add(writeWait))
	if err := conn.WriteJSON(helloEnv); err != nil {
		s.logger.Error("failed to write initial hello", "error", err)
		return
	}

	// 2. Send initial metrics.snapshot immediately
	initialMetrics := s.metricsCol.Collect()
	if metricsEnv, err := transport.NewEnvelope("metrics.snapshot", initialMetrics); err == nil {
		conn.SetWriteDeadline(time.Now().Add(writeWait))
		_ = conn.WriteJSON(metricsEnv)
	}

	// 3. Start streaming tickers: 10s default metrics interval, 5s heartbeat, 20s ping
	metricsTicker := time.NewTicker(10 * time.Second)
	defer metricsTicker.Stop()

	heartbeatTicker := time.NewTicker(5 * time.Second)
	defer heartbeatTicker.Stop()

	pingTicker := time.NewTicker(pingPeriod)
	defer pingTicker.Stop()

	done := make(chan struct{})
	go func() {
		defer close(done)
		for {
			_, message, err := conn.ReadMessage()
			if err != nil {
				if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
					s.logger.Warn("stream read error", "error", err)
				}
				break
			}
			// Refresh read deadline on any incoming message from client
			_ = conn.SetReadDeadline(time.Now().Add(pongWait))
			s.logger.Debug("received message from client", "bytes", len(message))
		}
	}()

	for {
		select {
		case <-done:
			s.logger.Info("client disconnected from stream", "remote_addr", r.RemoteAddr)
			return

		case <-pingTicker.C:
			conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := conn.WriteControl(websocket.PingMessage, []byte{}, time.Now().Add(writeWait)); err != nil {
				s.logger.Warn("failed to send ping control frame, dropping connection", "error", err)
				return
			}

		case <-metricsTicker.C:
			snapshot := s.metricsCol.Collect()
			metricsEnv, err := transport.NewEnvelope("metrics.snapshot", snapshot)
			if err != nil {
				s.logger.Error("failed to create metrics envelope", "error", err)
				continue
			}

			conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := conn.WriteJSON(metricsEnv); err != nil {
				s.logger.Warn("failed to send metrics snapshot, dropping connection", "error", err)
				return
			}

		case <-heartbeatTicker.C:
			seq := s.seq.Add(1)
			uptime := int64(time.Since(s.startTime).Seconds())
			hbEnv, err := transport.NewEnvelope("agent.heartbeat", transport.HeartbeatPayload{
				AgentID:       s.identity.AgentID,
				UptimeSeconds: uptime,
				Sequence:      seq,
			})
			if err != nil {
				s.logger.Error("failed to create heartbeat envelope", "error", err)
				continue
			}

			conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := conn.WriteJSON(hbEnv); err != nil {
				s.logger.Warn("failed to send heartbeat, dropping connection", "error", err)
				return
			}
		}
	}
}

func (s *Server) handleDiscovery(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	res, err := s.registry.DiscoverAll(r.Context())
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(res)
}

func (s *Server) handleMonitorsHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var reqs []providers.MonitorRequest
	if err := json.NewDecoder(r.Body).Decode(&reqs); err != nil {
		http.Error(w, "invalid JSON payload", http.StatusBadRequest)
		return
	}

	results := s.registry.CheckBatchHealth(r.Context(), reqs)

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(results)
}

func (s *Server) handleActionExecute(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req actions.ActionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON payload", http.StatusBadRequest)
		return
	}

	res := s.executor.Execute(r.Context(), req)

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(res)
}

func (s *Server) handleProbeDB(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var cfg database.DatabaseConfig
	if err := json.NewDecoder(r.Body).Decode(&cfg); err != nil {
		http.Error(w, "invalid JSON payload", http.StatusBadRequest)
		return
	}

	var health providers.HealthResult
	var metrics *database.DatabaseMetrics
	var err error

	switch cfg.Type {
	case "redis":
		health, metrics, err = s.redisProv.Probe(r.Context(), cfg)
	case "postgres":
		health, metrics, err = s.pgProv.Probe(r.Context(), cfg)
	case "mysql", "mariadb":
		health, metrics, err = s.mysqlProv.Probe(r.Context(), cfg)
	case "mongodb":
		health, metrics, err = s.mongoProv.Probe(r.Context(), cfg)
	default:
		http.Error(w, fmt.Sprintf("unsupported database type: %s", cfg.Type), http.StatusBadRequest)
		return
	}

	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	resp := map[string]any{
		"health":  health,
		"metrics": metrics,
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}

func (s *Server) handleProviders(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	infos := s.registry.ListProviders()
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"providers": infos,
	})
}

func (s *Server) handleAgentHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	uptimeSec := int64(time.Since(s.startTime).Seconds())
	health := agent.GetSelfHealth(s.identity.AgentVersion, uptimeSec)

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(health)
}

func (s *Server) handleSuggestedDependencies(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	detector := intelligence.NewDetector(s.dockerCtrl, s.procColl, s.svcColl)
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	suggestions, err := detector.DetectSuggestedDependencies(ctx)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"suggestions": suggestions,
	})
}

func (s *Server) handlePair(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	ip := security.ExtractIP(r)
	limiter := security.GetGlobalLimiter()
	if banned, remaining := limiter.IsBanned(ip); banned {
		w.Header().Set("Retry-After", strconv.Itoa(int(remaining.Seconds())))
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusTooManyRequests)
		_, _ = w.Write([]byte(`{"error":"too_many_requests","message":"IP temporarily banned due to excessive pairing failures"}`))
		return
	}

	var req struct {
		PairCode string `json:"pair_code"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.PairCode == "" {
		limiter.RecordFailure(ip)
		http.Error(w, "invalid request body: pair_code required", http.StatusBadRequest)
		return
	}

	if pairing.GlobalManager == nil {
		http.Error(w, "pairing manager not initialized", http.StatusServiceUnavailable)
		return
	}

	session, err := pairing.GlobalManager.VerifyAndClaim(req.PairCode)
	if err != nil {
		limiter.RecordFailure(ip)
		s.logger.Warn("pairing claim failed", "pair_code", req.PairCode, "error", err, "ip", ip)
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}

	limiter.RecordSuccess(ip)
	s.logger.Info("pairing successful", "agent_id", session.AgentID, "hostname", session.Hostname, "ip", ip)

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"status":     "paired",
		"auth_token": session.AuthToken,
		"agent_id":   session.AgentID,
		"hostname":   session.Hostname,
	})
}

func (s *Server) handlePairRegister(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Only allow local connections or authenticated requests
	isLocal := strings.HasPrefix(r.RemoteAddr, "127.0.0.1:") || strings.HasPrefix(r.RemoteAddr, "[::1]:")
	authHeader := r.Header.Get("Authorization")
	hasValidToken := authHeader == "Bearer "+s.cfg.AuthToken

	if !isLocal && !hasValidToken {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	var req struct {
		PairCode string `json:"pair_code"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.PairCode == "" {
		http.Error(w, "invalid request body: pair_code required", http.StatusBadRequest)
		return
	}

	if pairing.GlobalManager != nil {
		pairing.GlobalManager.SetExplicitCode(req.PairCode, s.cfg, s.identity.Hostname)
		s.logger.Info("pairing code registered into daemon", "pair_code", req.PairCode)
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "registered", "pair_code": req.PairCode})
}

func (s *Server) handleSecurityPorts(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	snap := security.CollectPortsSnapshot()
	env, err := transport.NewEnvelope("security.ports_snapshot", snap)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(env)
}

func (s *Server) handleLogsStream(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		s.logger.Error("failed to upgrade log stream to websocket", "error", err)
		return
	}
	defer conn.Close()

	const (
		logWriteWait = 25 * time.Second
		logPongWait  = 60 * time.Second
	)

	conn.SetReadLimit(512 * 1024)
	_ = conn.SetReadDeadline(time.Now().Add(logPongWait))
	conn.SetPongHandler(func(string) error {
		_ = conn.SetReadDeadline(time.Now().Add(logPongWait))
		return nil
	})
	conn.SetPingHandler(func(appData string) error {
		_ = conn.SetReadDeadline(time.Now().Add(logPongWait))
		return conn.WriteControl(websocket.PongMessage, []byte(appData), time.Now().Add(logWriteWait))
	})

	sourceType := r.URL.Query().Get("type")
	target := r.URL.Query().Get("target")
	tailStr := r.URL.Query().Get("tail")
	follow := r.URL.Query().Get("follow") != "false"

	tail := 100
	if t, err := strconv.Atoi(tailStr); err == nil && t > 0 {
		tail = t
	}

	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()

	// Read loop to detect disconnect
	go func() {
		for {
			if _, _, err := conn.ReadMessage(); err != nil {
				cancel()
				return
			}
			_ = conn.SetReadDeadline(time.Now().Add(logPongWait))
		}
	}()

	outChan := make(chan logs.LogEntry, 256)

	if sourceType == "docker" {
		if err := s.streamer.StreamDocker(ctx, target, tail, follow, outChan); err != nil {
			conn.SetWriteDeadline(time.Now().Add(logWriteWait))
			_ = conn.WriteJSON(logs.LogEntry{
				Timestamp: time.Now().UTC(),
				Line:      fmt.Sprintf("Error starting docker log stream: %v", err),
				Stream:    "stderr",
			})
			return
		}
	} else {
		// default to systemd
		if err := s.streamer.StreamSystemd(ctx, target, tail, follow, outChan); err != nil {
			conn.SetWriteDeadline(time.Now().Add(logWriteWait))
			_ = conn.WriteJSON(logs.LogEntry{
				Timestamp: time.Now().UTC(),
				Line:      fmt.Sprintf("Error starting systemd log stream: %v", err),
				Stream:    "stderr",
			})
			return
		}
	}

	for {
		select {
		case <-ctx.Done():
			return
		case entry, ok := <-outChan:
			if !ok {
				return
			}
			conn.SetWriteDeadline(time.Now().Add(logWriteWait))
			if err := conn.WriteJSON(entry); err != nil {
				return
			}
		}
	}
}

func (s *Server) handleStorageAnalyze(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	analysis := s.analyzer.Analyze(r.Context())
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(analysis)
}

func (s *Server) handleTelegramTest(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		BotToken string `json:"bot_token"`
		ChatID   string `json:"chat_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.BotToken == "" || req.ChatID == "" {
		http.Error(w, "invalid payload: bot_token and chat_id required", http.StatusBadRequest)
		return
	}

	testMsg := fmt.Sprintf("✅ *Pulse Alert Test*\nSuccessfully connected to server `%s`!\nTimestamp: `%s`",
		s.identity.Hostname, time.Now().UTC().Format(time.RFC3339))

	if err := s.telegram.SendMessage(r.Context(), req.BotToken, req.ChatID, testMsg); err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]any{"success": false, "error": err.Error()})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"success": true, "message": "Test alert sent successfully"})
}

func (s *Server) handleTelegramConfig(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(s.tgCfg)
	case http.MethodPost:
		var cfg alerts.TelegramConfig
		if err := json.NewDecoder(r.Body).Decode(&cfg); err != nil {
			http.Error(w, "invalid json payload", http.StatusBadRequest)
			return
		}
		s.tgCfg = cfg
		s.logger.Info("updated telegram alert configuration", "enabled", cfg.Enabled, "chats", len(cfg.ChatIDs))
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"success": true, "config": s.tgCfg})
	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}


