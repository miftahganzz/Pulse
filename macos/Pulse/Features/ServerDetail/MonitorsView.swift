import SwiftUI

public struct MonitorsView: View {
    @ObservedObject var manager: ServerConnectionManager
    @State private var showAddCustomMonitorSheet = false
    @State private var selectedMonitorForDetail: MonitorItem? = nil
    @State private var filterType: MonitorType? = nil
    @State private var showIgnored = false

    public init(manager: ServerConnectionManager) {
        self.manager = manager
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Section 1: Active Monitored Services & Probes
                monitoredSection

                Divider()

                // Section 2: Discovered Services (from VPS providers)
                discoveredSection
            }
            .padding(16)
        }
        .sheet(isPresented: $showAddCustomMonitorSheet) {
            AddCustomMonitorSheet(manager: manager)
        }
        .sheet(item: $selectedMonitorForDetail) { monitor in
            ServiceDetailSheet(manager: manager, monitor: monitor)
        }
    }

    // MARK: - Monitored Section
    private var monitoredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Active Monitors")
                    .font(.headline)

                Spacer()

                if manager.isCheckingMonitors {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                }

                Button {
                    manager.checkMonitorsHealth()
                } label: {
                    Label("Check Now", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    showAddCustomMonitorSheet = true
                } label: {
                    Label("Add Custom Probe", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if manager.monitors.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("No monitors configured yet.")
                        .font(.system(size: 13, weight: .medium))
                    Text("Add a custom HTTP/TCP probe or select from the detected services below.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            } else {
                VStack(spacing: 8) {
                    ForEach(manager.monitors) { monitor in
                        monitorRow(monitor)
                    }
                }
            }
        }
    }

    private func monitorRow(_ monitor: MonitorItem) -> some View {
        HStack(spacing: 12) {
            // Status Icon
            Image(systemName: monitor.status.iconName)
                .foregroundColor(monitor.status.color)
                .font(.system(size: 16))
                .frame(width: 20)

            // Type Icon
            Image(systemName: monitor.type.iconName)
                .foregroundColor(.secondary)
                .font(.system(size: 13))

            // Details
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(monitor.name)
                        .font(.system(size: 13, weight: .medium))

                    Text(monitor.type.displayName.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(3)

                    if let latency = monitor.latencyMs {
                        Text("\(latency) ms")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Text(monitor.target)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)

                    if let msg = monitor.message, !msg.isEmpty {
                        Text("•  \(msg)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectedMonitorForDetail = monitor
            }

            Spacer()

            // Info Detail Button
            Button {
                selectedMonitorForDetail = monitor
            } label: {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .help("View Service Intelligence & Actions")

            // Enable Toggle
            Toggle("", isOn: Binding(
                get: { monitor.isEnabled },
                set: { _ in manager.toggleMonitorEnabled(id: monitor.id) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)

            // Remove Button
            Button {
                manager.removeMonitor(id: monitor.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("Delete Monitor")
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }

    // MARK: - Discovered Section
    private var discoveredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Detected Services")
                        .font(.headline)
                    Text("Services automatically discovered on this server. Choose what you want to monitor.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if manager.isLoadingDiscovery {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                }

                Button {
                    manager.refreshDiscovery()
                } label: {
                    Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            let unmonitored = manager.discoveredServices.filter { svc in
                let alreadyMonitored = manager.monitors.contains(where: { $0.target == svc.id || $0.name == svc.name })
                let isIgnored = manager.ignoredServiceIds.contains(svc.id)
                return !alreadyMonitored && (!isIgnored || showIgnored)
            }

            if unmonitored.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("All detected services are either monitored or ignored.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 16)
            } else {
                VStack(spacing: 6) {
                    ForEach(unmonitored) { svc in
                        discoveredRow(svc)
                    }
                }
            }

            if !manager.ignoredServiceIds.isEmpty {
                Button {
                    showIgnored.toggle()
                } label: {
                    Text(showIgnored ? "Hide Ignored Services" : "Show \(manager.ignoredServiceIds.count) Ignored Services")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }

    private func discoveredRow(_ svc: DiscoveredServiceItem) -> some View {
        let isIgnored = manager.ignoredServiceIds.contains(svc.id)
        return HStack(spacing: 12) {
            Image(systemName: iconForProvider(svc.providerType))
                .foregroundColor(.secondary)
                .font(.system(size: 14))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(svc.name)
                        .font(.system(size: 12, weight: .medium))

                    Text(svc.providerType.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(3)

                    Text(svc.status)
                        .font(.system(size: 11))
                        .foregroundColor(svc.status.contains("running") || svc.status.contains("active") || svc.status.contains("online") ? .green : .secondary)
                }

                if let desc = svc.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isIgnored {
                Button("Unignore") {
                    manager.unignoreDiscoveredService(id: svc.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button {
                    manager.addMonitorFromDiscovered(svc)
                } label: {
                    Label("Monitor", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Ignore") {
                    manager.ignoreDiscoveredService(id: svc.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(6)
    }

    private func iconForProvider(_ type: String) -> String {
        switch type {
        case "docker": return "shippingbox"
        case "pm2": return "hexagon"
        case "process": return "cpu"
        default: return "gearshape.2"
        }
    }
}

// MARK: - Add Custom Monitor Sheet
public struct AddCustomMonitorSheet: View {
    @ObservedObject var manager: ServerConnectionManager
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selectedType: MonitorType = .http
    @State private var target: String = ""

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Custom Monitor")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Monitor Type")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Picker("", selection: $selectedType) {
                    Text("HTTP").tag(MonitorType.http)
                    Text("TCP").tag(MonitorType.tcp)
                    Text("Systemd").tag(MonitorType.systemd)
                    Text("Docker").tag(MonitorType.docker)
                    Text("PostgreSQL").tag(MonitorType.postgres)
                    Text("Redis").tag(MonitorType.redis)
                    Text("MySQL").tag(MonitorType.mysql)
                    Text("MongoDB").tag(MonitorType.mongodb)
                    Text("Nginx").tag(MonitorType.nginx)
                    Text("Cloudflare").tag(MonitorType.cloudflared)
                    Text("Custom").tag(MonitorType.custom)
                }
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Display Name")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                TextField("e.g. Production Database or Cache", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(targetLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                TextField(targetPlaceholder, text: $target)
                    .textFieldStyle(.roundedBorder)
            }

            if selectedType == .http {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Optional Body Assertion (Sub-string required in response)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField("e.g. \"status\": \"ok\"", text: $expectedBody)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if selectedType == .custom {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Optional Expected Output Match")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField("e.g. active", text: $expectedOutput)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if selectedType == .postgres || selectedType == .redis || selectedType == .mysql || selectedType == .mongodb {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Password / Token (Stored in Apple Keychain)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    SecureField("Optional database password", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Add Monitor") {
                    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
                    let finalName = trimmedName.isEmpty ? trimmedTarget : trimmedName

                    if selectedType == .postgres || selectedType == .redis || selectedType == .mysql || selectedType == .mongodb {
                        let parts = trimmedTarget.split(separator: ":")
                        let host = parts.count > 0 ? String(parts[0]) : "127.0.0.1"
                        let defaultPort: Int
                        switch selectedType {
                        case .postgres: defaultPort = 5432
                        case .redis: defaultPort = 6379
                        case .mysql: defaultPort = 3306
                        case .mongodb: defaultPort = 27017
                        default: defaultPort = 80
                        }
                        let port = parts.count > 1 ? (Int(parts[1]) ?? defaultPort) : defaultPort
                        manager.addDatabaseMonitor(
                            name: finalName,
                            type: selectedType,
                            host: host,
                            port: port,
                            user: selectedType == .postgres ? "postgres" : (selectedType == .mysql ? "root" : ""),
                            database: selectedType == .postgres ? "postgres" : "",
                            password: password
                        )
                    } else {
                        manager.addMonitor(name: finalName, type: selectedType, target: trimmedTarget)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480, height: 380)
    }

    @State private var password: String = ""
    @State private var expectedBody: String = ""
    @State private var expectedOutput: String = ""

    private var targetLabel: String {
        switch selectedType {
        case .http: return "Target URL"
        case .tcp: return "Host:Port Target"
        case .systemd: return "Systemd Unit Name"
        case .docker: return "Container Name or ID"
        case .process: return "Process Executable Name"
        case .pm2: return "PM2 Process Name"
        case .postgres: return "PostgreSQL Host:Port"
        case .redis: return "Redis Host:Port"
        case .mysql: return "MySQL Host:Port"
        case .mongodb: return "MongoDB Host:Port"
        case .nginx: return "Nginx service or binary target"
        case .caddy: return "Caddy service or binary target"
        case .cloudflared: return "Cloudflare Tunnel Target"
        case .custom: return "Allowlisted Command (e.g. systemctl is-active cloudflared)"
        }
    }

    private var targetPlaceholder: String {
        switch selectedType {
        case .http: return "https://example.com/health"
        case .tcp: return "127.0.0.1:5432"
        case .systemd: return "nginx.service"
        case .docker: return "postgres"
        case .process: return "redis-server"
        case .pm2: return "api-worker"
        case .postgres: return "127.0.0.1:5432"
        case .redis: return "127.0.0.1:6379"
        case .mysql: return "127.0.0.1:3306"
        case .mongodb: return "127.0.0.1:27017"
        case .nginx: return "nginx"
        case .caddy: return "caddy"
        case .cloudflared: return "cloudflared"
        case .custom: return "systemctl is-active nginx"
        }
    }
}

