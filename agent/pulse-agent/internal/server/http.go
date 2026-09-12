package server

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
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
	"github.com/pulse/pulse-agent/internal/intelligence"
	"github.com/pulse/pulse-agent/internal/pairing"
	"github.com/pulse/pulse-agent/internal/security"
	"github.com/pulse/pulse-agent/internal/services"
	"github.com/pulse/pulse-agent/internal/transport"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
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

	return &Server{
		cfg:        cfg,
		identity:   identity,
		metricsCol: metrics.NewCollector(logger),
		procColl:   procCol,
		svcColl:    svcCol,
		dockerCtrl: dockerCli,
		registry:   reg,
		executor:   exec,
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
	mux.HandleFunc("/api/v1/intelligence/suggested-dependencies", s.handleSuggestedDependencies)
	mux.HandleFunc("/ws/v1/stream", s.handleStream)

	protectedHandler := security.TokenAuthMiddleware(s.cfg.AuthToken, mux)

	// Root mux with public pairing endpoint
	rootMux := http.NewServeMux()
	rootMux.HandleFunc("/api/v1/pair", s.handlePair)
	rootMux.HandleFunc("/api/v1/pair/register", s.handlePairRegister)
	rootMux.Handle("/", protectedHandler)

	return rootMux
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

	if err := conn.WriteJSON(helloEnv); err != nil {
		s.logger.Error("failed to write initial hello", "error", err)
		return
	}

	// 2. Send initial metrics.snapshot immediately
	initialMetrics := s.metricsCol.Collect()
	if metricsEnv, err := transport.NewEnvelope("metrics.snapshot", initialMetrics); err == nil {
		_ = conn.WriteJSON(metricsEnv)
	}

	// 3. Start streaming tickers: 10s default metrics interval, 5s heartbeat
	metricsTicker := time.NewTicker(10 * time.Second)
	defer metricsTicker.Stop()

	heartbeatTicker := time.NewTicker(5 * time.Second)
	defer heartbeatTicker.Stop()

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
			s.logger.Debug("received message from client", "bytes", len(message))
		}
	}()

	for {
		select {
		case <-done:
			s.logger.Info("client disconnected from stream", "remote_addr", r.RemoteAddr)
			return

		case <-metricsTicker.C:
			snapshot := s.metricsCol.Collect()
			metricsEnv, err := transport.NewEnvelope("metrics.snapshot", snapshot)
			if err != nil {
				s.logger.Error("failed to create metrics envelope", "error", err)
				continue
			}

			conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
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

			conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
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

	var req struct {
		PairCode string `json:"pair_code"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.PairCode == "" {
		http.Error(w, "invalid request body: pair_code required", http.StatusBadRequest)
		return
	}

	if pairing.GlobalManager == nil {
		http.Error(w, "pairing manager not initialized", http.StatusServiceUnavailable)
		return
	}

	session, err := pairing.GlobalManager.VerifyAndClaim(req.PairCode)
	if err != nil {
		s.logger.Warn("pairing claim failed", "pair_code", req.PairCode, "error", err)
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}

	s.logger.Info("pairing successful", "agent_id", session.AgentID, "hostname", session.Hostname)

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

