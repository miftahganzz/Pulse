import SwiftUI

public struct LiveLogView: View {
    @ObservedObject var manager: ServerConnectionManager

    @State private var logSource: LogSource = .systemd
    @State private var selectedTarget: String = ""
    @State private var tailCount: Int = 100
    @State private var searchText: String = ""
    @State private var isPaused: Bool = false
    @State private var logs: [LogEntryMessage] = []
    @State private var streamTask: URLSessionWebSocketTask?
    @State private var errorMessage: String? = nil
    @State private var isConnecting: Bool = false
    @State private var isConnected: Bool = false
    @State private var activeStreamTarget: String = ""
    @State private var activeStreamSource: LogSource? = nil

    @State private var copiedUpgradeCommand: Bool = false

    public enum LogSource: String, CaseIterable, Identifiable {
        case systemd = "Systemd"
        case docker = "Docker"

        public var id: String { rawValue }
        public var icon: String {
            switch self {
            case .systemd: return "gearshape.2"
            case .docker: return "shippingbox"
            }
        }
    }

    public init(manager: ServerConnectionManager) {
        self.manager = manager
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Control Header Bar (Fully Responsive)
            headerControls
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Main Terminal Console
            if manager.state.isOffline {
                offlineLogsView
            } else if let err = errorMessage {
                if isAgentVersionIncompatible {
                    agentUpgradeView
                } else {
                    genericErrorView(err)
                }
            } else if isConnecting && logs.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Connecting to \(logSource.rawValue) log stream for \(selectedTarget)...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if logs.isEmpty {
                emptyLogsView
            } else {
                logConsoleView
            }
        }
        .onAppear {
            if manager.services.isEmpty {
                manager.refreshServices()
            }
            if manager.dockerContainers.isEmpty {
                manager.refreshDocker()
            }
            setupInitialTarget()
            startStreaming()
        }
        .onDisappear {
            stopStreaming()
        }
        .onChange(of: manager.state) { newState in
            if newState.isConnected {
                if errorMessage != nil || streamTask == nil {
                    errorMessage = nil
                    setupInitialTarget()
                    startStreaming()
                }
            } else if newState.isOffline {
                stopStreaming()
            }
        }
        .onChange(of: logSource) { _ in
            stopStreaming()
            logs.removeAll()
            errorMessage = nil
            selectedTarget = ""
            setupInitialTarget()
            startStreaming()
        }
        .onChange(of: selectedTarget) { newTarget in
            if !newTarget.isEmpty && newTarget != activeStreamTarget {
                restartStreaming()
            }
        }
        .onChange(of: tailCount) { _ in
            restartStreaming()
        }
        .onChange(of: manager.services) { newServices in
            if logSource == .systemd && !newServices.isEmpty {
                let currentValid = newServices.contains(where: { $0.name == selectedTarget })
                if !currentValid {
                    setupInitialTarget()
                    if selectedTarget != activeStreamTarget {
                        restartStreaming()
                    }
                }
            }
        }
        .onChange(of: manager.dockerContainers) { newContainers in
            if logSource == .docker && !newContainers.isEmpty {
                let currentValid = newContainers.contains(where: { $0.id == selectedTarget })
                if !currentValid {
                    setupInitialTarget()
                    if selectedTarget != activeStreamTarget {
                        restartStreaming()
                    }
                }
            }
        }
    }

    // MARK: - Responsive Header Controls

    private var headerControls: some View {
        ViewThatFits(in: .horizontal) {
            singleRowControls
            twoRowControls
        }
    }

    private var singleRowControls: some View {
        HStack(spacing: 8) {
            // Source Picker
            sourcePicker
                .frame(width: 130)

            // Target Dropdown
            targetPicker
                .frame(minWidth: 110, idealWidth: 150, maxWidth: 200)

            // Tail count picker
            linesPicker
                .frame(width: 85)

            // Connection Indicator
            connectionStatusIndicator

            Spacer(minLength: 4)

            // Filter Search Field
            searchField
                .frame(minWidth: 80, idealWidth: 110, maxWidth: 140)

            // Action Buttons
            actionButtons
        }
    }

    private var twoRowControls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                sourcePicker
                    .frame(width: 130)

                targetPicker
                    .frame(minWidth: 100, maxWidth: .infinity)

                linesPicker
                    .frame(width: 85)

                connectionStatusIndicator
            }

            HStack(spacing: 8) {
                searchField
                    .frame(maxWidth: .infinity)

                actionButtons
            }
        }
    }

    private var sourcePicker: some View {
        Picker("", selection: $logSource) {
            Text("Systemd").tag(LogSource.systemd)
            Text("Docker").tag(LogSource.docker)
        }
        .pickerStyle(.segmented)
    }

    private var linesPicker: some View {
        Picker("", selection: $tailCount) {
            Text("50 lines").tag(50)
            Text("100 lines").tag(100)
            Text("250 lines").tag(250)
            Text("500 lines").tag(500)
        }
        .pickerStyle(.menu)
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 11))
            TextField("Filter logs...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            Button {
                isPaused.toggle()
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 11))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(isPaused ? "Resume auto-scroll" : "Pause stream")

            Button {
                logs.removeAll()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Clear console")

            Button {
                copyLogsToClipboard()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Copy logs to clipboard")
        }
    }

    private var connectionStatusIndicator: some View {
        HStack(spacing: 4) {
            if isConnecting {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
                Text("CONNECTING")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            } else if errorMessage != nil {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                Text("ERROR")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.red)
            } else if isConnected {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("LIVE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var targetPicker: some View {
        if logSource == .systemd {
            let services = manager.services
            if services.isEmpty {
                TextField("Service name (e.g. nginx)", text: $selectedTarget)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            } else {
                Picker("", selection: $selectedTarget) {
                    ForEach(services, id: \.id) { svc in
                        Text(svc.name).tag(svc.name)
                    }
                }
                .pickerStyle(.menu)
            }
        } else {
            let containers = manager.dockerContainers
            if containers.isEmpty {
                TextField("Container name/ID", text: $selectedTarget)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            } else {
                Picker("", selection: $selectedTarget) {
                    ForEach(containers, id: \.id) { c in
                        Text(c.cleanName).tag(c.id)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    // MARK: - Terminal Console

    private var logConsoleView: some View {
        let filtered = filteredLogs
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filtered) { entry in
                        logLineView(entry)
                            .id(entry.id)
                    }
                }
                .padding(12)
            }
            .background(Color(NSColor.textBackgroundColor))
            .onChange(of: logs.count) { _ in
                if !isPaused, let last = filtered.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func logLineView(_ entry: LogEntryMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.timestamp, style: .time)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)

            if entry.stream == "stderr" {
                Text("ERR")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.red.opacity(0.15))
                    .foregroundColor(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            Text(entry.line)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(colorForLine(entry.line))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func colorForLine(_ line: String) -> Color {
        let upper = line.uppercased()
        if upper.contains("ERROR") || upper.contains("FATAL") || upper.contains("CRITICAL") || upper.contains("FAIL") {
            return Color.red.opacity(0.9)
        } else if upper.contains("WARN") {
            return Color.orange.opacity(0.9)
        } else if upper.contains("INFO") {
            return Color.primary
        }
        return Color.secondary
    }

    private var filteredLogs: [LogEntryMessage] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return logs
        }
        return logs.filter { $0.line.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Incompatible Agent & Error Views

    private var isAgentVersionIncompatible: Bool {
        if let ver = manager.identity?.agentVersion {
            let parts = ver.split(separator: ".").compactMap { Int($0) }
            if let major = parts.first, major < 1 {
                return true
            }
        }
        if let err = errorMessage, err.contains("bad response") || err.contains("-1011") || err.contains("v1.0.0") || err.contains("404") {
            return true
        }
        return false
    }

    private var agentUpgradeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath.circle")
                .font(.system(size: 38))
                .foregroundColor(.secondary)

            VStack(spacing: 6) {
                Text("Pulse Agent Update Required")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                let currentVer = manager.identity?.agentVersion ?? "0.9.0"
                let name = manager.serverName.isEmpty ? "Server" : manager.serverName
                Text("Live log streaming was introduced in Pulse v1.0.0.\nServer \"\(name)\" is running pulse-agent v\(currentVer).")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Run this command on your server to update pulse-agent:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Text("sudo pulse update")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)

                    Spacer(minLength: 4)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("sudo pulse update", forType: .string)
                        copiedUpgradeCommand = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copiedUpgradeCommand = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedUpgradeCommand ? "checkmark" : "doc.on.doc")
                            Text(copiedUpgradeCommand ? "Copied" : "Copy")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .frame(maxWidth: 500)

            HStack(spacing: 10) {
                Button {
                    errorMessage = nil
                    startStreaming()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry Stream")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func genericErrorView(_ err: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundColor(.orange)
            Text(err)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Retry Stream") {
                errorMessage = nil
                startStreaming()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var offlineLogsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 36))
                .foregroundColor(.orange)

            Text("Offline — Please connect to network")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            Text("Live log streaming is unavailable while your device is disconnected from the network. Pulse will automatically reconnect and resume log streaming once your connection is restored.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }

    private var emptyLogsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.6))

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text("Live Stream Active")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                }

                Text("Waiting for new log entries from \(selectedTarget.isEmpty ? "target" : selectedTarget)...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Text("This service is active but currently idle. When new logs are emitted, they will stream here in real time.")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }

    // MARK: - Streaming Logic

    private func setupInitialTarget() {
        if logSource == .systemd {
            if selectedTarget.isEmpty || !manager.services.contains(where: { $0.name == selectedTarget }) {
                if let pulseAgent = manager.services.first(where: { $0.name.contains("pulse-agent") && $0.isRunning }) ?? manager.services.first(where: { $0.name.contains("pulse-agent") }) {
                    selectedTarget = pulseAgent.name
                } else if let firstRunning = manager.services.first(where: { $0.isRunning }) {
                    selectedTarget = firstRunning.name
                } else if let first = manager.services.first {
                    selectedTarget = first.name
                } else {
                    selectedTarget = "pulse-agent.service"
                }
            }
        } else {
            let containers = manager.dockerContainers
            if selectedTarget.isEmpty || !containers.contains(where: { $0.id == selectedTarget }) {
                if let runningContainer = containers.first(where: { $0.state.lowercased() == "running" }) {
                    selectedTarget = runningContainer.id
                } else if let first = containers.first {
                    selectedTarget = first.id
                } else {
                    selectedTarget = ""
                }
            }
        }
    }

    private func restartStreaming() {
        stopStreaming(clearActiveTarget: true)
        logs.removeAll()
        errorMessage = nil
        startStreaming()
    }

    private func startStreaming() {
        guard !selectedTarget.isEmpty else { return }

        // If server is not yet connected, stay in connecting state and wait for manager.state to become connected
        guard manager.state.isConnected else {
            isConnecting = true
            isConnected = false
            return
        }

        // If we are already streaming this exact target and source, avoid restarting
        if activeStreamTarget == selectedTarget && activeStreamSource == logSource && streamTask != nil {
            return
        }

        stopStreaming(clearActiveTarget: false)
        activeStreamTarget = selectedTarget
        activeStreamSource = logSource

        // Proactively detect older agent version before sending failing WebSocket request
        if let ver = manager.identity?.agentVersion {
            let parts = ver.split(separator: ".").compactMap { Int($0) }
            if let major = parts.first, major < 1 {
                self.errorMessage = "Live log streaming requires pulse-agent v1.0.0 or later (Server is running v\(ver))."
                self.isConnecting = false
                self.isConnected = false
                return
            }
        }

        isConnecting = true
        isConnected = false

        let typeStr = (logSource == .docker) ? "docker" : "systemd"
        streamTask = manager.streamLogs(
            type: typeStr,
            target: selectedTarget,
            tail: tailCount,
            onConnected: {
                DispatchQueue.main.async {
                    self.isConnecting = false
                    self.isConnected = true
                }
            },
            onLine: { entry in
                DispatchQueue.main.async {
                    self.isConnecting = false
                    self.isConnected = true
                    if !self.isPaused {
                        self.logs.append(entry)
                        if self.logs.count > 1000 {
                            self.logs.removeFirst(100)
                        }
                    }
                }
            },
            onError: { err in
                DispatchQueue.main.async {
                    let nsErr = err as NSError
                    if nsErr.code == NSURLErrorCancelled || nsErr.code == 89 || nsErr.code == -999 {
                        return
                    }
                    if err.localizedDescription.lowercased().contains("cancel") {
                        return
                    }
                    self.isConnecting = false
                    self.isConnected = false
                    if nsErr.code == -1011 || err.localizedDescription.contains("bad response") {
                        let currentVer = self.manager.identity?.agentVersion ?? "0.9.0"
                        self.errorMessage = "Live log streaming requires pulse-agent v1.0.0 or later (Server is running v\(currentVer))."
                    } else {
                        self.errorMessage = "Stream disconnected: \(err.localizedDescription)"
                    }
                }
            }
        )
    }

    private func stopStreaming(clearActiveTarget: Bool = true) {
        streamTask?.cancel(with: .goingAway, reason: nil)
        streamTask = nil
        if clearActiveTarget {
            activeStreamTarget = ""
            activeStreamSource = nil
        }
        isConnecting = false
        isConnected = false
    }

    private func copyLogsToClipboard() {
        let content = filteredLogs.map { "\($0.timestamp): \($0.line)" }.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(content, forType: .string)
    }
}
