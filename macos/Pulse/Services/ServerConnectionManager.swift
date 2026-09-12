import Foundation
import Combine

@MainActor
public final class ServerConnectionManager: ObservableObject, PulseAgentClientDelegate {
    public let serverId: UUID
    @Published public private(set) var serverName: String
    @Published public private(set) var address: String
    @Published public private(set) var port: Int

    @Published public private(set) var state: ConnectionState = .disconnected
    @Published public private(set) var identity: AgentIdentity?
    @Published public private(set) var lastHeartbeat: HeartbeatPayload?
    @Published public private(set) var currentMetrics: MetricsSnapshot?
    @Published public private(set) var metricsHistory: [HistoricalDataPoint] = []
    @Published public private(set) var lastMetricsReceivedAt: Date?
    @Published public private(set) var isStale = false

    @Published public private(set) var processes: [ProcessItem] = []
    @Published public private(set) var services: [SystemServiceItem] = []
    @Published public private(set) var dockerContainers: [DockerContainerItem] = []
    @Published public private(set) var isDockerAvailable: Bool = false
    @Published public private(set) var dockerVersion: String? = nil
    @Published public private(set) var isLoadingProcesses = false
    @Published public private(set) var isLoadingServices = false
    @Published public private(set) var isLoadingDocker = false

    @Published public private(set) var monitors: [MonitorItem] = []
    @Published public private(set) var discoveredServices: [DiscoveredServiceItem] = []
    @Published public private(set) var ignoredServiceIds: Set<String> = []
    @Published public private(set) var auditLogs: [ActionAuditLogItem] = []
    @Published public private(set) var isLoadingDiscovery = false
    @Published public private(set) var isCheckingMonitors = false
    @Published public private(set) var isExecutingAction = false

    @Published public private(set) var incidents: [IncidentItem] = []
    @Published public private(set) var alertPolicy: IncidentAlertPolicy
    @Published public private(set) var dependencies: [ServiceDependency] = []
    @Published public private(set) var suggestedDependencies: [SuggestedDependencyDTO] = []
    @Published public private(set) var isLoadingSuggestions = false
    @Published public private(set) var remediationPolicies: [RemediationPolicy] = []
    @Published public private(set) var verificationStatuses: [String: VerificationStatus] = [:]
    @Published public var isDeploymentWindowActive: Bool = false
    @Published public private(set) var securitySnapshot: SecuritySnapshot?
    @Published public private(set) var isLoadingSecurity = false

    @Published public private(set) var lastError: String?

    @Published public var alertSettings: ServerAlertSettings

    private var client: PulseAgentClient?
    private var staleCheckTimer: Timer?
    private var monitorHealthTimer: Timer?
    private let staleThresholdSeconds: TimeInterval = 25.0

    private let incidentEngine: IncidentEngine
    private var cancellables = Set<AnyCancellable>()

    // Alert throttling: minimum 5 minutes between duplicate alerts
    private var lastCPUAlertAt: Date?
    private var lastMemoryAlertAt: Date?
    private var lastDiskAlertAt: Date?
    private var lastOfflineAlertAt: Date?
    private let alertCooldown: TimeInterval = 300.0

    public init(serverId: UUID, serverName: String, address: String, port: Int) {
        self.serverId = serverId
        self.serverName = serverName
        self.address = address
        self.port = port
        self.metricsHistory = MetricsHistoryStore.loadHistory(forServerId: serverId)
        self.alertSettings = AlertSettingsStore.loadSettings(forServerId: serverId)
        self.monitors = MonitorStore.loadMonitors(forServerId: serverId)
        self.ignoredServiceIds = MonitorStore.loadIgnored(forServerId: serverId)
        self.auditLogs = ActivityStore.loadAuditLogs(forServerId: serverId)
        self.dependencies = DependencyStore.loadDependencies(forServerId: serverId)
        self.remediationPolicies = RemediationStore.loadPolicies(forServerId: serverId)

        let loadedPolicy = IncidentStore.loadAlertPolicy(forServerId: serverId)
        self.alertPolicy = loadedPolicy
        self.incidents = IncidentStore.loadIncidents(forServerId: serverId)
        self.incidentEngine = IncidentEngine(serverId: serverId, serverName: serverName, policy: loadedPolicy)

        self.startStaleTimer()

        NetworkMonitor.shared.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                guard let self = self else { return }
                if !isConnected {
                    self.handleNetworkOffline()
                } else if case .offline(let reason) = self.state, reason == .noNetwork {
                    PulseLog.network.info("Network restored for \(self.serverName), attempting reconnect...")
                    self.connect()
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        staleCheckTimer?.invalidate()
        monitorHealthTimer?.invalidate()
    }

    public func updateConfig(name: String, address: String, port: Int) {
        let addressOrPortChanged = (self.address != address || self.port != port)
        if self.serverName != name {
            self.serverName = name
            self.incidentEngine.updateServerName(name)
        }
        if self.address != address {
            self.address = address
        }
        if self.port != port {
            self.port = port
        }
        if addressOrPortChanged && state.isConnected {
            disconnect()
            connect()
        }
    }

    public func updateAlertPolicy(_ newPolicy: IncidentAlertPolicy) {
        self.alertPolicy = newPolicy
        self.incidentEngine.updatePolicy(newPolicy)
        IncidentStore.saveAlertPolicy(newPolicy, forServerId: serverId)
    }

    public func muteServer(for duration: TimeInterval) {
        var updated = alertPolicy
        updated.isMuted = true
        updated.mutedUntil = Date().addingTimeInterval(duration)
        updateAlertPolicy(updated)
    }

    public func unmuteServer() {
        var updated = alertPolicy
        updated.isMuted = false
        updated.mutedUntil = nil
        updateAlertPolicy(updated)
    }

    public func clearIncidentsHistory() {
        incidents.removeAll { $0.status == .resolved }
        IncidentStore.saveIncidents(incidents, forServerId: serverId)
    }

    public func addDependency(sourceMonitorId: String, targetMonitorId: String, type: DependencyType) {
        let dep = ServiceDependency(serverId: serverId, sourceMonitorId: sourceMonitorId, targetMonitorId: targetMonitorId, type: type)
        self.dependencies = DependencyStore.addDependency(dep, forServerId: serverId)
    }

    public func removeDependency(id: String) {
        self.dependencies = DependencyStore.removeDependency(id: id, forServerId: serverId)
    }

    public func refreshSuggestedDependencies() {
        guard let client = client, state.isConnected else { return }
        isLoadingSuggestions = true
        client.fetchSuggestedDependencies { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isLoadingSuggestions = false
                switch result {
                case .success(let suggestions):
                    self.suggestedDependencies = suggestions
                case .failure(let err):
                    PulseLog.agent.error("Failed to fetch suggested dependencies: \(err.localizedDescription)")
                }
            }
        }
    }

    public func acceptSuggestedDependency(_ suggestion: SuggestedDependencyDTO) {
        // Map source and target to existing monitors if possible, or use IDs directly
        let dep = ServiceDependency(
            serverId: serverId,
            sourceMonitorId: suggestion.sourceId,
            targetMonitorId: suggestion.targetId,
            type: suggestion.dependencyType == "cache" ? .connectsTo : .requires
        )
        self.dependencies = DependencyStore.addDependency(dep, forServerId: serverId)
        self.suggestedDependencies.removeAll { $0.id == suggestion.id }
    }

    public func dismissSuggestedDependency(id: String) {
        self.suggestedDependencies.removeAll { $0.id == id }
    }

    public func connect() {
        guard NetworkMonitor.shared.isConnected else {
            self.state = .offline(reason: .noNetwork)
            return
        }

        guard let token = KeychainService.getToken(forServerId: serverId) else {
            self.lastError = "No authentication token found in Keychain."
            self.state = .disconnected
            return
        }

        self.lastError = nil
        client?.disconnect()
        let newClient = PulseAgentClient(host: address, port: port, token: token)
        newClient.delegate = self
        self.client = newClient
        newClient.connect()
    }

    public func handleNetworkOffline() {
        self.state = .offline(reason: .noNetwork)
        self.isStale = false
        self.stopMonitorHealthTimer()
    }

    public func disconnect() {
        client?.disconnect()
        client = nil
        self.state = .disconnected
        self.isStale = false
        self.processes = []
        self.services = []
        self.stopMonitorHealthTimer()
    }

    public func refreshDiscovery() {
        guard let client = client, state.isConnected else { return }
        isLoadingDiscovery = true
        client.fetchDiscovery { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isLoadingDiscovery = false
                switch result {
                case .success(let payload):
                    self.discoveredServices = payload.services
                case .failure(let err):
                    PulseLog.agent.error("Failed to fetch discovery: \(err.localizedDescription)")
                }
            }
        }
    }

    public func checkMonitorsHealth() {
        guard let client = client, state.isConnected else { return }
        let enabledMonitors = monitors.filter { $0.isEnabled }
        guard !enabledMonitors.isEmpty else { return }

        isCheckingMonitors = true
        let requests = enabledMonitors.map {
            MonitorHealthCheckRequest(id: $0.id, name: $0.name, type: $0.type.rawValue, target: $0.target)
        }

        client.checkMonitorsHealth(monitors: requests) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isCheckingMonitors = false
                switch result {
                case .success(let results):
                    let lookup = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
                    for i in 0..<self.monitors.count {
                        if let res = lookup[self.monitors[i].id] {
                            self.monitors[i].status = MonitorStatus(rawValue: res.status) ?? .unknown
                            self.monitors[i].message = res.message
                            self.monitors[i].latencyMs = res.latencyMs
                            self.monitors[i].lastChecked = res.lastChecked
                        }
                    }
                    MonitorStore.saveMonitors(self.monitors, forServerId: self.serverId)

                    // Evaluate incidents for enabled monitors
                    for monitor in self.monitors where monitor.isEnabled {
                        _ = self.incidentEngine.evaluateMonitorHealth(
                            monitor: monitor,
                            existingIncidents: &self.incidents
                        )
                        self.evaluateAutoRemediation(for: monitor)
                    }
                    IncidentStore.saveIncidents(self.incidents, forServerId: self.serverId)
                case .failure(let err):
                    PulseLog.agent.error("Failed to check monitor health: \(err.localizedDescription)")
                }
            }
        }
    }

    public func addMonitor(name: String, type: MonitorType, target: String) {
        let newMonitor = MonitorItem(
            serverId: serverId,
            name: name,
            type: type,
            target: target
        )
        monitors.append(newMonitor)
        MonitorStore.saveMonitors(monitors, forServerId: serverId)
        checkMonitorsHealth()
    }

    public func addMonitorFromDiscovered(_ service: DiscoveredServiceItem) {
        let type: MonitorType
        switch service.providerType {
        case "docker": type = .docker
        case "pm2": type = .pm2
        case "process": type = .process
        default: type = .systemd
        }

        let newMonitor = MonitorItem(
            serverId: serverId,
            name: service.name,
            type: type,
            target: service.id
        )
        monitors.append(newMonitor)
        MonitorStore.saveMonitors(monitors, forServerId: serverId)
        checkMonitorsHealth()
    }

    public func removeMonitor(id: String) {
        monitors.removeAll { $0.id == id }
        MonitorStore.saveMonitors(monitors, forServerId: serverId)
    }

    public func toggleMonitorEnabled(id: String) {
        if let index = monitors.firstIndex(where: { $0.id == id }) {
            monitors[index].isEnabled.toggle()
            MonitorStore.saveMonitors(monitors, forServerId: serverId)
            if monitors[index].isEnabled {
                checkMonitorsHealth()
            }
        }
    }

    public func ignoreDiscoveredService(id: String) {
        ignoredServiceIds.insert(id)
        MonitorStore.saveIgnored(ignoredServiceIds, forServerId: serverId)
    }

    public func unignoreDiscoveredService(id: String) {
        ignoredServiceIds.remove(id)
        MonitorStore.saveIgnored(ignoredServiceIds, forServerId: serverId)
    }

    public func executeAction(
        action: String,
        target: String,
        actor: String = "User",
        completion: (@Sendable (Result<String, Error>) -> Void)? = nil
    ) {
        executeServiceAction(action: action, target: target, actor: actor, completion: completion)
    }

    public func executeServiceAction(
        action: String,
        target: String,
        monitorId: String? = nil,
        actor: String = "User",
        completion: (@Sendable (Result<String, Error>) -> Void)? = nil
    ) {
        guard let client = client, state.isConnected else {
            completion?(.failure(PulseClientError.generic("Server not connected")))
            return
        }

        isExecutingAction = true
        let startTime = Date()

        if let mId = monitorId {
            verificationStatuses[mId] = .pending
        }

        client.executeAction(action: action, target: target) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isExecutingAction = false
                switch result {
                case .success(let payload):
                    let isSuccess = (payload.status == "success")
                    let logItem = ActionAuditLogItem(
                        serverId: self.serverId,
                        monitorId: monitorId,
                        actionName: action,
                        target: target,
                        status: payload.status,
                        message: payload.message,
                        durationMs: payload.durationMs,
                        timestamp: payload.timestamp,
                        actor: actor,
                        verification: isSuccess ? "Verifying..." : "Action Failed"
                    )
                    self.auditLogs = ActivityStore.appendAuditLog(logItem, forServerId: self.serverId)

                    if let mId = monitorId, let policy = self.remediationPolicies.first(where: { $0.monitorId == mId }) {
                        RemediationEngine.shared.recordExecutionResult(
                            monitorId: mId,
                            serverId: self.serverId,
                            success: isSuccess,
                            policy: policy
                        )
                    }

                    if isSuccess {
                        if let mId = monitorId {
                            self.runPostActionVerification(monitorId: mId, actionName: action, startTime: startTime)
                        } else {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                self.checkMonitorsHealth()
                            }
                        }
                        completion?(.success(payload.message))
                    } else {
                        if let mId = monitorId {
                            self.verificationStatuses[mId] = .failedStillDown(reason: payload.message)
                        }
                        completion?(.failure(PulseClientError.generic(payload.message)))
                    }

                case .failure(let err):
                    let logItem = ActionAuditLogItem(
                        serverId: self.serverId,
                        monitorId: monitorId,
                        actionName: action,
                        target: target,
                        status: "failed",
                        message: err.localizedDescription,
                        durationMs: 0,
                        timestamp: Date(),
                        actor: actor,
                        verification: "Network Error"
                    )
                    self.auditLogs = ActivityStore.appendAuditLog(logItem, forServerId: self.serverId)
                    if let mId = monitorId {
                        self.verificationStatuses[mId] = .failedStillDown(reason: err.localizedDescription)
                    }
                    completion?(.failure(err))
                }
            }
        }
    }

    private func runPostActionVerification(monitorId: String, actionName: String, startTime: Date) {
        verificationStatuses[monitorId] = .verifying(step: 1)

        // Probe 1: after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            self.checkMonitorsHealth()

            // Probe 2: after 8 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                guard let self = self else { return }
                self.checkMonitorsHealth()

                // Final check: after 12 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                    guard let self = self else { return }
                    self.checkMonitorsHealth()

                    if let mon = self.monitors.first(where: { $0.id == monitorId }) {
                        let duration = Date().timeIntervalSince(startTime)
                        if mon.status == .healthy {
                            self.verificationStatuses[monitorId] = .succeeded(duration: duration)
                            NotificationService.shared.sendAlert(
                                title: "✅ \(mon.name) Recovered",
                                body: "\(self.serverName) · Action '\(actionName)' confirmed healthy in \(String(format: "%.1f", duration))s",
                                identifier: "remediation.verified.\(monitorId)"
                            )
                        } else {
                            self.verificationStatuses[monitorId] = .failedStillDown(reason: mon.message ?? "Service still reporting \(mon.status.rawValue)")
                            NotificationService.shared.sendAlert(
                                title: "⚠️ \(mon.name) Still Down",
                                body: "\(self.serverName) · Action succeeded but service failed health check verification.",
                                identifier: "remediation.failed.\(monitorId)"
                            )
                        }
                    }
                }
            }
        }
    }

    public func evaluateAutoRemediation(for monitor: MonitorItem) {
        guard let policy = remediationPolicies.first(where: { $0.monitorId == monitor.id }), policy.enabled else {
            return
        }

        // Only trigger when monitor is down or critical
        guard monitor.status == .down || monitor.status == .critical else {
            return
        }

        // Must match consecutive failure count or active incident
        guard let incident = incidents.first(where: { $0.monitorId == monitor.id && $0.status != .resolved }),
              incident.consecutiveFailures >= 2 else {
            return
        }

        // Evaluate Safety Gates
        let gate = RemediationEngine.shared.canExecuteRemediation(
            for: monitor.id,
            serverId: serverId,
            policy: policy,
            isMaintenanceActive: alertPolicy.isEffectivelyMuted || isDeploymentWindowActive,
            isServerReachable: state.isConnected
        )

        guard gate.allowed else {
            PulseLog.agent.info("Auto-remediation blocked for \(monitor.name): \(gate.reason ?? "Gate rejected")")
            return
        }

        switch policy.approvalMode {
        case .manual:
            // Proactive notification suggesting action
            NotificationService.shared.sendAlert(
                title: "💡 Action Recommended: \(monitor.name)",
                body: "Service failed 2+ checks. Recommended action: \(policy.actionId)",
                identifier: "remediation.suggest.\(monitor.id)"
            )

        case .approved:
            // High-priority prompt asking for approval
            NotificationService.shared.sendAlert(
                title: "🛡️ Approve Action for \(monitor.name)?",
                body: "\(serverName) · Remediation policy proposes executing \(policy.actionId). Click to review.",
                identifier: "remediation.approve.\(monitor.id)"
            )

        case .automatic:
            // Execute automated remediation
            PulseLog.agent.info("Triggering automatic remediation \(policy.actionId) on \(monitor.name)")
            executeServiceAction(
                action: policy.actionId,
                target: monitor.target,
                monitorId: monitor.id,
                actor: "Automation"
            )
        }
    }

    public func saveRemediationPolicy(_ policy: RemediationPolicy) {
        RemediationStore.savePolicy(policy, forServerId: serverId)
        self.remediationPolicies = RemediationStore.loadPolicies(forServerId: serverId)
    }

    public func deleteRemediationPolicy(monitorId: String) {
        RemediationStore.deletePolicy(monitorId: monitorId, forServerId: serverId)
        self.remediationPolicies = RemediationStore.loadPolicies(forServerId: serverId)
    }

    public func resetCircuitBreaker(monitorId: String) {
        RemediationStore.resetBreaker(monitorId: monitorId, forServerId: serverId)
    }

    public func clearActivityLogs() {
        ActivityStore.clearAuditLogs(forServerId: serverId)
        auditLogs = []
    }

    public func addDatabaseMonitor(name: String, type: MonitorType, host: String, port: Int, user: String, database: String, password: String) {
        let monitorId = UUID().uuidString
        let target = "\(host):\(port)"

        if !password.isEmpty {
            try? KeychainService.saveDatabasePassword(password, forMonitorId: monitorId)
        }

        let newMonitor = MonitorItem(
            id: monitorId,
            serverId: serverId,
            name: name,
            type: type,
            target: target
        )
        monitors.append(newMonitor)
        MonitorStore.saveMonitors(monitors, forServerId: serverId)
        checkMonitorsHealth()
    }

    private func startMonitorHealthTimer() {

        stopMonitorHealthTimer()
        // Run immediately then every 30s
        checkMonitorsHealth()
        monitorHealthTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkMonitorsHealth()
            }
        }
    }

    private func stopMonitorHealthTimer() {
        monitorHealthTimer?.invalidate()
        monitorHealthTimer = nil
    }


    public func refreshProcesses(sortBy: String = "cpu") {
        guard let client = client, state.isConnected else { return }
        isLoadingProcesses = true
        client.fetchProcesses(limit: 50, sortBy: sortBy) { result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isLoadingProcesses = false
                switch result {
                case .success(let procs):
                    self.processes = procs
                case .failure(let err):
                    PulseLog.agent.error("Failed to fetch processes: \(err.localizedDescription)")
                }
            }
        }
    }

    public func refreshServices() {
        guard let client = client, state.isConnected else { return }
        isLoadingServices = true
        client.fetchServices { result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isLoadingServices = false
                switch result {
                case .success(let svcs):
                    self.services = svcs
                case .failure(let err):
                    PulseLog.agent.error("Failed to fetch services: \(err.localizedDescription)")
                }
            }
        }
    }

    public func refreshSecurity() {
        guard let client = client, state.isConnected else { return }
        isLoadingSecurity = true
        client.fetchSecurityPorts { result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isLoadingSecurity = false
                switch result {
                case .success(let snapshot):
                    self.securitySnapshot = snapshot
                case .failure(let err):
                    PulseLog.agent.error("Failed to fetch security ports: \(err.localizedDescription)")
                }
            }
        }
    }

    public func killProcess(pid: Int, signal: String, completion: (@Sendable (Result<String, Error>) -> Void)? = nil) {
        guard let client = client, state.isConnected else { return }
        client.killProcess(pid: pid, signal: signal) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch result {
                case .success(let msg):
                    PulseLog.agent.info("Process killed: \(msg)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.refreshProcesses()
                    }
                    completion?(.success(msg))
                case .failure(let err):
                    PulseLog.agent.error("Failed to kill process \(pid): \(err.localizedDescription)")
                    completion?(.failure(err))
                }
            }
        }
    }

    public func controlService(name: String, action: String, completion: (@Sendable (Result<String, Error>) -> Void)? = nil) {
        guard let client = client, state.isConnected else { return }
        client.controlService(name: name, action: action) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch result {
                case .success(let msg):
                    PulseLog.agent.info("Service control succeeded: \(msg)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.refreshServices()
                    }
                    completion?(.success(msg))
                case .failure(let err):
                    PulseLog.agent.error("Failed to control service \(name): \(err.localizedDescription)")
                    completion?(.failure(err))
                }
            }
        }
    }

    public func refreshDocker() {
        guard let client = client, state.isConnected else { return }
        isLoadingDocker = true
        client.fetchDockerContainers { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isLoadingDocker = false
                switch result {
                case .success(let status):
                    self.isDockerAvailable = status.available
                    self.dockerVersion = status.version
                    self.dockerContainers = status.containers
                case .failure(let err):
                    PulseLog.agent.error("Failed to fetch docker status: \(err.localizedDescription)")
                }
            }
        }
    }

    public func controlDockerContainer(id: String, action: String, completion: (@Sendable (Result<String, Error>) -> Void)? = nil) {
        guard let client = client, state.isConnected else { return }
        client.controlDockerContainer(id: id, action: action) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch result {
                case .success(let msg):
                    PulseLog.agent.info("Docker container action succeeded: \(msg)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.refreshDocker()
                    }
                    completion?(.success(msg))
                case .failure(let err):
                    PulseLog.agent.error("Failed to control container \(id): \(err.localizedDescription)")
                    completion?(.failure(err))
                }
            }
        }
    }

    public func fetchDockerLogs(id: String, tail: Int = 100, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        guard let client = client, state.isConnected else {
            completion(.failure(PulseClientError.generic("Not connected")))
            return
        }
        client.fetchDockerLogs(id: id, tail: tail, completion: completion)
    }

    public func streamLogs(
        type: String,
        target: String,
        tail: Int = 100,
        onConnected: (@Sendable () -> Void)? = nil,
        onLine: @escaping @Sendable (LogEntryMessage) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) -> URLSessionWebSocketTask? {
        guard let client = client, state.isConnected else {
            onError(PulseClientError.generic("Server not connected"))
            return nil
        }
        return client.streamLogs(type: type, target: target, tail: tail, onConnected: onConnected, onLine: onLine, onError: onError)
    }

    public func fetchStorageAnalysis(completion: @escaping @Sendable (Result<StorageAnalysis, Error>) -> Void) {
        guard let client = client, state.isConnected else {
            completion(.failure(PulseClientError.generic("Server not connected")))
            return
        }
        client.fetchStorageAnalysis(completion: completion)
    }

    public func testTelegram(botToken: String, chatID: String, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        guard let client = client, state.isConnected else {
            completion(.failure(PulseClientError.generic("Server not connected")))
            return
        }
        client.testTelegram(botToken: botToken, chatID: chatID, completion: completion)
    }

    public func updateTelegramConfig(_ config: TelegramConfig, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        guard let client = client, state.isConnected else {
            completion(.failure(PulseClientError.generic("Server not connected")))
            return
        }
        client.updateTelegramConfig(config, completion: completion)
    }

    private func startStaleTimer() {
        staleCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkStaleStatus()
            }
        }
    }

    private func checkStaleStatus() {
        if let last = self.lastMetricsReceivedAt, self.state.isConnected {
            self.isStale = Date().timeIntervalSince(last) > self.staleThresholdSeconds
        } else {
            self.isStale = false
        }
    }

    public func updateAlertSettings(_ newSettings: ServerAlertSettings) {
        self.alertSettings = newSettings
        AlertSettingsStore.saveSettings(newSettings, forServerId: self.serverId)
    }

    private func checkMetricAlerts(_ metrics: MetricsSnapshot) {
        guard alertSettings.isAlertsEnabled else { return }
        let now = Date()

        // 1. CPU Threshold
        if metrics.cpu.usagePercent >= alertSettings.cpuThresholdPercent {
            if lastCPUAlertAt == nil || now.timeIntervalSince(lastCPUAlertAt!) > alertCooldown {
                lastCPUAlertAt = now
                NotificationService.shared.sendAlert(
                    title: "⚠️ High CPU Usage: \(serverName)",
                    body: String(format: "CPU usage reached %.1f%% (threshold: %.0f%%)", metrics.cpu.usagePercent, alertSettings.cpuThresholdPercent),
                    identifier: "alert.cpu.\(serverId.uuidString)"
                )
            }
        }

        // 2. Memory Threshold
        if metrics.memory.usagePercent >= alertSettings.memoryThresholdPercent {
            if lastMemoryAlertAt == nil || now.timeIntervalSince(lastMemoryAlertAt!) > alertCooldown {
                lastMemoryAlertAt = now
                NotificationService.shared.sendAlert(
                    title: "⚠️ High Memory Usage: \(serverName)",
                    body: String(format: "Memory usage reached %.1f%% (%@ used)", metrics.memory.usagePercent, FormatUtils.bytes(metrics.memory.usedBytes)),
                    identifier: "alert.memory.\(serverId.uuidString)"
                )
            }
        }

        // 3. Disk Threshold (Check primary mount /)
        if let primary = metrics.primaryDisk, primary.usagePercent >= alertSettings.diskThresholdPercent {
            if lastDiskAlertAt == nil || now.timeIntervalSince(lastDiskAlertAt!) > alertCooldown {
                lastDiskAlertAt = now
                NotificationService.shared.sendAlert(
                    title: "⚠️ High Disk Usage: \(serverName)",
                    body: String(format: "Disk '%@' usage reached %.1f%% (%@ free)", primary.mountPoint, primary.usagePercent, FormatUtils.bytes(primary.freeBytes)),
                    identifier: "alert.disk.\(serverId.uuidString)"
                )
            }
        }
    }

    private func checkOfflineAlert() {
        guard alertSettings.isAlertsEnabled && alertSettings.notifyOnOffline else { return }
        let now = Date()
        if lastOfflineAlertAt == nil || now.timeIntervalSince(lastOfflineAlertAt!) > alertCooldown {
            lastOfflineAlertAt = now
            NotificationService.shared.sendAlert(
                title: "Server Offline: \(serverName)",
                body: "Pulse lost connection to \(serverName) (\(address):\(port)). Reconnecting...",
                identifier: "alert.offline.\(serverId.uuidString)"
            )
        }
    }

    // MARK: - PulseAgentClientDelegate
    nonisolated public func client(_ client: PulseAgentClient, didUpdateState state: ConnectionState) {
        Task { @MainActor in
            let previousState = self.state
            if !NetworkMonitor.shared.isConnected {
                self.state = .offline(reason: .noNetwork)
            } else {
                self.state = state
            }

            // Server-level incident handling
            _ = self.incidentEngine.handleServerConnectionState(
                isConnected: state.isConnected,
                isOffline: state.isOffline,
                existingIncidents: &self.incidents
            )
            IncidentStore.saveIncidents(self.incidents, forServerId: self.serverId)

            if state.isConnected {
                self.lastError = nil
                self.refreshProcesses()
                self.refreshServices()
                self.refreshDiscovery()
                self.refreshSuggestedDependencies()
                self.startMonitorHealthTimer()
            } else {
                self.isStale = false
                self.stopMonitorHealthTimer()
                if previousState.isConnected && state.isOffline {
                    self.checkOfflineAlert()
                }
            }
        }
    }

    nonisolated public func client(_ client: PulseAgentClient, didReceiveIdentity identity: AgentIdentity) {
        Task { @MainActor in
            self.identity = identity
            PulseLog.agent.info("Received identity for \(self.serverName): \(identity.hostname) (\(identity.os), \(identity.cpuCores) cores)")
        }
    }

    nonisolated public func client(_ client: PulseAgentClient, didReceiveHeartbeat heartbeat: HeartbeatPayload) {
        Task { @MainActor in
            self.lastHeartbeat = heartbeat
        }
    }

    nonisolated public func client(_ client: PulseAgentClient, didReceiveMetrics metrics: MetricsSnapshot) {
        Task { @MainActor in
            self.currentMetrics = metrics
            self.lastMetricsReceivedAt = Date()
            self.isStale = false
            self.metricsHistory = MetricsHistoryStore.appendSnapshot(metrics, forServerId: self.serverId)
            self.checkMetricAlerts(metrics)
        }
    }

    nonisolated public func client(_ client: PulseAgentClient, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastError = error.localizedDescription
            PulseLog.network.error("Client failed for \(self.serverName): \(error.localizedDescription)")
            self.checkOfflineAlert()
        }
    }
}
