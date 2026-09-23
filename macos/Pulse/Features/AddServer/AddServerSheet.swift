import SwiftUI

public enum SetupMethod: String, CaseIterable, Identifiable {
    case oneLine  = "1-Line Command"
    case pairCode = "XXX-XXX Pair Code"

    public var id: String { rawValue }
}

public enum ConnectionNetwork: String, CaseIterable, Identifiable {
    case direct = "Direct IP"
    case cloudflare = "Cloudflare Tunnel"
    case tailscale = "Tailscale"

    public var id: String { rawValue }
    public var icon: String {
        switch self {
        case .direct: return "network"
        case .cloudflare: return "cloud.fill"
        case .tailscale: return "lock.shield.fill"
        }
    }
}

public struct AddServerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ServerStore.shared

    @State private var setupMethod: SetupMethod = .oneLine
    @State private var connectionNetwork: ConnectionNetwork = .direct
    @State private var step: SetupStep = .enterDetails
    @State private var name: String = ""
    @State private var address: String = ""
    @State private var portString: String = "8443"
    @State private var token: String = ""
    @State private var pairCode: String = ""
    @State private var errorMessage: String?
    @State private var selectedEnvironment: ServerEnvironment = .untagged
    @State private var isNonRoot: Bool = false

    public init(draft: ServerDraft? = nil) {
        if let draft = draft {
            _name = State(initialValue: draft.name)
            _address = State(initialValue: draft.host)
            _portString = State(initialValue: draft.port.isEmpty ? "8443" : draft.port)
            _token = State(initialValue: draft.token)
            let lower = draft.host.lowercased()
            if lower.contains("trycloudflare.com") {
                _connectionNetwork = State(initialValue: .cloudflare)
                if draft.port.isEmpty { _portString = State(initialValue: "443") }
            } else if lower.hasPrefix("100.") || lower.contains(".ts.net") {
                _connectionNetwork = State(initialValue: .tailscale)
            }
        }
    }

    @State private var testingClient: PulseAgentClient?
    @State private var isConnecting = false
    @State private var connectedIdentity: AgentIdentity?
    @State private var isCopied = false

    enum SetupStep {
        case enterDetails
        case agentGuide
        case testingConnection
        case success
    }

    private var generatedToken: String {
        if token.isEmpty {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }
        return token
    }

    private var normalizedHost: String {
        var str = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("https://") {
            str = String(str.dropFirst(8))
        } else if str.hasPrefix("http://") {
            str = String(str.dropFirst(7))
        }
        if let slashIdx = str.firstIndex(of: "/") {
            str = String(str[..<slashIdx])
        }
        return str
    }

    private var isCloudflareDomain: Bool {
        let h = normalizedHost.lowercased()
        return (h.contains(".") && !h.contains(":") && !isIPAddress(h))
    }

    private var isTailscaleIP: Bool {
        let h = normalizedHost
        return h.hasPrefix("100.") || h.hasSuffix(".ts.net")
    }

    private func isIPAddress(_ str: String) -> Bool {
        let parts = str.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { Int($0) != nil }
    }

    private var hostPromptText: String {
        switch connectionNetwork {
        case .direct:
            return "e.g. 103.187.144.20"
        case .cloudflare:
            return "e.g. abc-xyz.trycloudflare.com or pulse.domain.com"
        case .tailscale:
            return "e.g. 100.115.82.45 or ubuntu.ts.net"
        }
    }

    private var installCommand: String {
        let cleanToken = token.isEmpty ? generatedToken : token
        switch connectionNetwork {
        case .direct:
            if isNonRoot {
                return "curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/install.sh | bash -s -- --port \(portString) --token \(cleanToken)"
            } else {
                return "curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/install.sh | sudo bash -s -- --port \(portString) --token \(cleanToken)"
            }
        case .cloudflare:
            if isNonRoot {
                return "curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/setup-cloudflare.sh | bash"
            } else {
                return "curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/setup-cloudflare.sh | sudo bash"
            }
        case .tailscale:
            if isNonRoot {
                return "curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/setup-tailscale.sh | bash"
            } else {
                return "curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/setup-tailscale.sh | sudo bash"
            }
        }
    }

    private var methodHelpIcon: String {
        switch connectionNetwork {
        case .direct: return isNonRoot ? "person.badge.shield.checkmark.fill" : "sparkles"
        case .cloudflare: return "cloud.fill"
        case .tailscale: return "lock.shield.fill"
        }
    }

    private var methodHelpColor: Color {
        switch connectionNetwork {
        case .direct: return isNonRoot ? .blue : .purple
        case .cloudflare: return .orange
        case .tailscale: return .green
        }
    }

    private var methodHelpText: String {
        switch (connectionNetwork, isNonRoot) {
        case (.direct, false):
            return "Root: Installs systemd service, auto TLS certs, and opens firewall port \(portString)."
        case (.direct, true):
            return "Non-Root: Installs to ~/.local/bin. Ensure port \(portString) is open in cloud VPS firewall."
        case (.cloudflare, false):
            return "Root: Installs cloudflared & sets up HTTPS tunnel. Zero open ports required on your VPS!"
        case (.cloudflare, true):
            return "Non-Root: 100% Zero-Root, Zero-Port! Runs cloudflared in user mode with crontab persistence."
        case (.tailscale, false):
            return "Root: Installs Tailscale, joins WireGuard mesh, and locks down firewall to tailscale0."
        case (.tailscale, true):
            return "Non-Root: Connects to existing Tailscale network or userspace node (zero open ports)."
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: stepIcon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.accentColor)
                    Text(stepTitle)
                        .font(.system(size: 15, weight: .bold))
                }

                Spacer()

                Button("Cancel") {
                    testingClient?.disconnect()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Setup Method Switcher (only shown during input step)
            if step == .enterDetails {
                Picker("Setup Method", selection: $setupMethod) {
                    Label("1-Line Command", systemImage: "terminal.fill").tag(SetupMethod.oneLine)
                    Label("XXX-XXX Pair Code", systemImage: "number.circle.fill").tag(SetupMethod.pairCode)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 6)
            }

            // Content per step
            VStack {
                switch step {
                case .enterDetails:
                    enterDetailsView
                case .testingConnection:
                    testingConnectionView
                case .success:
                    successView
                case .agentGuide:
                    enterDetailsView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()

            // Footer Actions
            HStack {
                if step == .testingConnection {
                    Button("Cancel") {
                        testingClient?.disconnect()
                        step = .enterDetails
                    }
                } else if step == .success {
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") {
                        testingClient?.disconnect()
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    if setupMethod == .oneLine {
                        Button("Connect to Server") {
                            if token.isEmpty {
                                token = generatedToken
                            }
                            testConnection()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  address.trimmingCharacters(in: .whitespaces).isEmpty)
                    } else {
                        let c = pairCode.trimmingCharacters(in: .whitespaces).count
                        Button("Verify & Pair") {
                            claimPairCode()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  address.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  (c != 6 && c != 7))
                    }
                }
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 580, height: 575)
    }

    private var stepIcon: String {
        switch step {
        case .enterDetails, .agentGuide: return "server.rack"
        case .testingConnection: return "arrow.triangle.2.circlepath"
        case .success: return "checkmark.seal.fill"
        }
    }

    private var stepTitle: String {
        switch step {
        case .enterDetails, .agentGuide: return "Add Linux VPS"
        case .testingConnection:  return "Connecting to Agent..."
        case .success:            return "Server Connected!"
        }
    }

    private var enterDetailsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if setupMethod == .oneLine {
                oneLineSetupContentView
            } else {
                pairCodeSetupContentView
            }
        }
    }

    // MARK: - 1-Line Command Unified Setup View
    private var oneLineSetupContentView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Method & Mode Pickers
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Text("Method:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 55, alignment: .leading)

                    Picker("Network", selection: $connectionNetwork) {
                        ForEach(ConnectionNetwork.allCases) { net in
                            Label(net.rawValue, systemImage: net.icon).tag(net)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: connectionNetwork) { newNet in
                        if newNet == .cloudflare && portString == "8443" {
                            portString = "443"
                        } else if (newNet == .direct || newNet == .tailscale) && portString == "443" {
                            portString = "8443"
                        }
                    }
                }

                HStack(spacing: 10) {
                    Text("Mode:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 55, alignment: .leading)

                    Picker("Privilege", selection: $isNonRoot) {
                        Text("Root (sudo)").tag(false)
                        Text("Non-Root (User Mode)").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)

            // 1-Line Command Box
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top) {
                    Text(installCommand)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(installCommand, forType: .string)
                        isCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            isCopied = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc.fill")
                                .font(.system(size: 10))
                            Text(isCopied ? "Copied!" : "Copy")
                                .font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isCopied ? .green : .accentColor)
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )

                HStack(spacing: 6) {
                    Image(systemName: methodHelpIcon)
                        .font(.system(size: 10))
                        .foregroundColor(methodHelpColor)
                    Text(methodHelpText)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            // Connection Details Form
            Form {
                TextField("Server Name", text: $name, prompt: Text("e.g. Production Jakarta or My VPS"))

                TextField("Host Address", text: $address, prompt: Text(hostPromptText))
                    .onChange(of: address) { _ in
                        checkAddressHints()
                    }

                HStack(spacing: 12) {
                    TextField("Port", text: $portString)
                        .frame(width: 80)

                    SecureField("Auth Token", text: $token, prompt: Text(connectionNetwork == .direct ? "Generated token" : "Token printed by script"))
                        .font(.system(size: 11, design: .monospaced))

                    if connectionNetwork == .direct {
                        Button("Regen") {
                            token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
                        }
                        .controlSize(.small)
                    }
                }

                Picker("Environment", selection: $selectedEnvironment) {
                    ForEach(ServerEnvironment.allCases) { env in
                        Label(env.rawValue, systemImage: env.icon).tag(env)
                    }
                }
            }
            .formStyle(.grouped)

            if connectionNetwork == .cloudflare {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 11))
                    Text("Cloudflare Tunnel uses the *.trycloudflare.com domain from the script, NOT your server IP.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)
            }

            if let err = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
    }

    // MARK: - XXX-XXX Pair Code Setup View
    private var pairCodeSetupContentView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Generate Pairing Code on VPS:")
                    .font(.system(size: 13, weight: .bold))
                Text("On your VPS terminal, run:")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                HStack {
                    Text("pulse pair")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("pulse pair", forType: .string)
                        isCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            isCopied = false
                        }
                    } label: {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    }
                    .controlSize(.small)
                }
            }

            Form {
                TextField("Server Name", text: $name, prompt: Text("e.g. My VPS"))
                TextField("Host Address", text: $address, prompt: Text("e.g. 103.187.144.20 or 100.x.y.z"))
                    .onChange(of: address) { _ in
                        checkAddressHints()
                    }
                TextField("Port", text: $portString)
                    .frame(width: 80)
                TextField("Pair Code (e.g. 653-557)", text: $pairCode)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
            }
            .formStyle(.grouped)

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("Pairing codes are valid for 10 minutes and single-use.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if let err = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
    }

    private func checkAddressHints() {
        let clean = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.hasPrefix("https://") && !clean.contains(":") {
            portString = "443"
            connectionNetwork = .cloudflare
        } else if isCloudflareDomain {
            if portString == "8443" { portString = "443" }
            connectionNetwork = .cloudflare
        } else if isTailscaleIP {
            connectionNetwork = .tailscale
        }
    }

    private var testingConnectionView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Verifying TLS certificate and authentication...")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxHeight: .infinity)
    }

    private var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            VStack(spacing: 4) {
                Text(name)
                    .font(.system(size: 18, weight: .bold))
                if let id = connectedIdentity {
                    Text("\(id.hostname) · \(id.os) (\(id.architecture))")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Pinned TLS Certificate Handshake Verified", systemImage: "lock.shield.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))
                Label("Live WebSocket Telemetry Stream Ready", systemImage: "bolt.horizontal.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))
                Label("Service Discovery & Remediation Engine Active", systemImage: "sparkles")
                    .foregroundColor(.green)
                    .font(.system(size: 12))
            }
            .padding(12)
            .background(Color.green.opacity(0.08))
            .cornerRadius(8)
        }
        .frame(maxHeight: .infinity)
    }

    private func claimPairCode() {
        guard let port = Int(portString), port > 0, port <= 65535 else {
            errorMessage = "Invalid port number"
            return
        }

        errorMessage = nil
        withAnimation { step = .testingConnection }

        let cleanAddress = normalizedHost
        let cleanCode = pairCode.trimmingCharacters(in: .whitespaces)

        PulseAgentClient.pairWithCode(host: cleanAddress, port: port, pairCode: cleanCode) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let dict):
                    if let authToken = dict["auth_token"] as? String {
                        self.token = authToken
                        self.testConnection()
                    } else {
                        self.errorMessage = "Missing auth token in response"
                        withAnimation { self.step = .enterDetails }
                    }
                case .failure(let err):
                    let desc = err.localizedDescription
                    if desc.localizedCaseInsensitiveContains("timed out") {
                        self.errorMessage = "Connection timed out. Check that '\(cleanAddress)' is your server's public IP and port \(port) is open."
                    } else {
                        self.errorMessage = "Pairing failed: \(desc)"
                    }
                    withAnimation { self.step = .enterDetails }
                }
            }
        }
    }

    private func testConnection() {
        guard let port = Int(portString), port > 0, port <= 65535 else {
            errorMessage = "Invalid port number"
            return
        }

        errorMessage = nil
        withAnimation { step = .testingConnection }

        let cleanAddress = normalizedHost

        if connectionNetwork == .cloudflare && isIPAddress(cleanAddress) {
            errorMessage = "Cloudflare Tunnel requires your *.trycloudflare.com tunnel domain (or custom domain), not an IP address. Switch Method to 'Direct IP' if connecting directly via IP."
            withAnimation { step = .enterDetails }
            return
        }

        let client = PulseAgentClient(
            host: cleanAddress,
            port: port,
            token: token.trimmingCharacters(in: .whitespaces)
        )
        self.testingClient = client

        client.fetchIdentity { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let ident):
                    self.connectedIdentity = ident
                    do {
                        try store.addServer(
                            name: name.trimmingCharacters(in: .whitespaces),
                            address: cleanAddress,
                            port: port,
                            token: token.trimmingCharacters(in: .whitespaces),
                            environment: selectedEnvironment
                        )
                        withAnimation { self.step = .success }
                    } catch {
                        self.errorMessage = "Failed to save to Keychain: \(error.localizedDescription)"
                        withAnimation { self.step = .enterDetails }
                    }
                case .failure(let err):
                    if connectionNetwork == .cloudflare {
                        self.errorMessage = "Connection failed: \(err.localizedDescription). Check that Cloudflare Tunnel is running on your VPS (run 'pulse cloudflare') and port is 443."
                    } else {
                        self.errorMessage = "Connection failed: \(err.localizedDescription). Ensure the agent is running and port \(portString) is open."
                    }
                    withAnimation { self.step = .enterDetails }
                }
            }
        }
    }
}
