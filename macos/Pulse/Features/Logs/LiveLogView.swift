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
            // Control Header Bar
            headerControls
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Main Terminal Console
            if let err = errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundColor(.orange)
                    Text(err)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Button("Retry Stream") {
                        startStreaming()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if logs.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Connecting to \(logSource.rawValue) log stream for \(selectedTarget)...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                logConsoleView
            }
        }
        .onAppear {
            setupInitialTarget()
            startStreaming()
        }
        .onDisappear {
            stopStreaming()
        }
        .onChange(of: logSource) { _ in
            setupInitialTarget()
            restartStreaming()
        }
        .onChange(of: selectedTarget) { _ in
            restartStreaming()
        }
        .onChange(of: tailCount) { _ in
            restartStreaming()
        }
    }

    // MARK: - Header Controls

    private var headerControls: some View {
        HStack(spacing: 12) {
            // Source Picker
            Picker("", selection: $logSource) {
                ForEach(LogSource.allCases) { source in
                    Label(source.rawValue, systemImage: source.icon).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 190)

            // Target Dropdown
            targetPicker
                .frame(minWidth: 140, maxWidth: 220)

            // Tail count picker
            Picker("Lines", selection: $tailCount) {
                Text("50").tag(50)
                Text("100").tag(100)
                Text("250").tag(250)
                Text("500").tag(500)
            }
            .pickerStyle(.menu)
            .frame(width: 90)

            Spacer()

            // Filter Search Field
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
            .frame(width: 140)

            // Action Buttons
            HStack(spacing: 6) {
                Button {
                    isPaused.toggle()
                } label: {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .help(isPaused ? "Resume auto-scroll" : "Pause stream")

                Button {
                    logs.removeAll()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .help("Clear console")

                Button {
                    copyLogsToClipboard()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .help("Copy logs to clipboard")
            }
        }
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

    // MARK: - Streaming Logic

    private func setupInitialTarget() {
        if logSource == .systemd {
            if selectedTarget.isEmpty || !manager.services.contains(where: { $0.name == selectedTarget }) {
                if let first = manager.services.first(where: { $0.isRunning }) ?? manager.services.first {
                    selectedTarget = first.name
                } else {
                    selectedTarget = "pulse-agent"
                }
            }
        } else {
            let containers = manager.dockerContainers
            if selectedTarget.isEmpty || !containers.contains(where: { $0.id == selectedTarget }) {
                if let first = containers.first {
                    selectedTarget = first.id
                } else {
                    selectedTarget = ""
                }
            }
        }
    }

    private func restartStreaming() {
        stopStreaming()
        logs.removeAll()
        errorMessage = nil
        startStreaming()
    }

    private func startStreaming() {
        guard !selectedTarget.isEmpty else { return }

        let typeStr = (logSource == .docker) ? "docker" : "systemd"
        streamTask = manager.streamLogs(
            type: typeStr,
            target: selectedTarget,
            tail: tailCount,
            onLine: { entry in
                DispatchQueue.main.async {
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
                    self.errorMessage = "Stream disconnected: \(err.localizedDescription)"
                }
            }
        )
    }

    private func stopStreaming() {
        streamTask?.cancel(with: .goingAway, reason: nil)
        streamTask = nil
    }

    private func copyLogsToClipboard() {
        let content = filteredLogs.map { "\($0.timestamp): \($0.line)" }.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(content, forType: .string)
    }
}
