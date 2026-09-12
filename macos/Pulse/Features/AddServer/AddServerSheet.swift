import SwiftUI

public enum SetupMethod: String, CaseIterable, Identifiable {
    case oneLine  = "1-Line Command"
    case pairCode = "XXX-XXX Pair Code"

    public var id: String { rawValue }
}

public struct AddServerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ServerStore.shared

    @State private var setupMethod: SetupMethod = .oneLine
    @State private var step: SetupStep = .enterDetails
    @State private var name: String = ""
    @State private var address: String = ""
    @State private var portString: String = "8443"
    @State private var token: String = ""
    @State private var pairCode: String = ""
    @State private var errorMessage: String?
    @State private var selectedEnvironment: ServerEnvironment = .untagged

    public init(draft: ServerDraft? = nil) {
        if let draft = draft {
            _name = State(initialValue: draft.name)
            _address = State(initialValue: draft.host)
            _portString = State(initialValue: draft.port.isEmpty ? "8443" : draft.port)
            _token = State(initialValue: draft.token)
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

    private var installCommand: String {
        let cleanToken = token.isEmpty ? generatedToken : token
        return "curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/install.sh | sudo bash -s -- --port \(portString) --token \(cleanToken)"
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

            // Setup Method Switcher (only shown during initial steps)
            if step == .enterDetails || step == .agentGuide {
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
                case .agentGuide:
                    if setupMethod == .oneLine {
                        agentGuideOneLineView
                    } else {
                        agentGuidePairCodeView
                    }
                case .testingConnection:
                    testingConnectionView
                case .success:
                    successView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)

            Divider()

            // Footer Actions
            HStack {
                if step != .enterDetails && step != .success {
                    Button("Back") {
                        withAnimation {
                            if step == .agentGuide { step = .enterDetails }
                            else if step == .testingConnection { step = .agentGuide }
                        }
                    }
                }

                Spacer()

                switch step {
                case .enterDetails:
                    Button("Continue") {
                        applySmartNetworkDefaults()
                        if token.isEmpty {
                            token = generatedToken
                        }
                        withAnimation { step = .agentGuide }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty ||
                              address.trimmingCharacters(in: .whitespaces).isEmpty)

                case .agentGuide:
                    if setupMethod == .oneLine {
                        Button("Connect to Server") {
                            testConnection()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
                    } else {
                        let c = pairCode.trimmingCharacters(in: .whitespaces).count
                        Button("Verify & Pair") {
                            claimPairCode()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(c != 6 && c != 7)
                    }

                case .testingConnection:
                    ProgressView()
                        .controlSize(.small)

                case .success:
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 530, height: 490)
    }

    private var stepIcon: String {
        switch step {
        case .enterDetails: return "server.rack"
        case .agentGuide: return setupMethod == .oneLine ? "terminal.fill" : "number.circle.fill"
        case .testingConnection: return "arrow.triangle.2.circlepath"
        case .success: return "checkmark.seal.fill"
        }
    }

    private var stepTitle: String {
        switch step {
        case .enterDetails:       return "Add Linux VPS"
        case .agentGuide:         return setupMethod == .oneLine ? "1-Command Setup" : "XXX-XXX Pairing"
        case .testingConnection:  return "Connecting to Agent..."
        case .success:            return "Server Connected!"
        }
    }

    private var enterDetailsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Enter Your Server Address")
                    .font(.system(size: 14, weight: .bold))
                Text("Connect via Public IP, Tailscale private IP, or Cloudflare Tunnel.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Form {
                TextField("Server Name", text: $name, prompt: Text("e.g. Production Jakarta or My VPS"))

                VStack(alignment: .leading, spacing: 6) {
                    TextField("Host Address", text: $address, prompt: Text("e.g. 103.187.144.20, 100.x.y.z, or pulse.mycorp.com"))
                        .onChange(of: address) { _ in
                            checkAddressHints()
                        }

                    if isCloudflareDomain {
                        HStack(spacing: 6) {
                            Image(systemName: "cloud.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 10))
                            Text("Cloudflare Tunnel hostname detected. Port 443 HTTPS will be used.")
                                .font(.system(size: 11))
                                .foregroundColor(.blue)
                        }
                    } else if isTailscaleIP {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 10))
                            Text("Tailscale private network detected. Zero open public ports required.")
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                        }
                    }
                }

                TextField("Port", text: $portString)

                Picker("Environment", selection: $selectedEnvironment) {
                    ForEach(ServerEnvironment.allCases) { env in
                        Label(env.rawValue, systemImage: env.icon).tag(env)
                    }
                }
            }
            .formStyle(.grouped)

            Spacer()
        }
    }

    private func checkAddressHints() {
        let clean = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.hasPrefix("https://") && !clean.contains(":") {
            portString = "443"
        } else if isCloudflareDomain && portString == "8443" {
            portString = "443"
        }
    }

    private func applySmartNetworkDefaults() {
        let clean = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if (clean.hasPrefix("https://") || isCloudflareDomain) && portString == "8443" {
            portString = "443"
        }
    }

    // View for 1-Line Command Method
    private var agentGuideOneLineView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Run This Single Command on Your VPS:")
                    .font(.system(size: 13, weight: .bold))
                Text("Open SSH to \(normalizedHost.isEmpty ? "your VPS" : normalizedHost) and paste this line:")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // Command Box with One-Click Copy
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(installCommand)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(3)
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
                                .font(.system(size: 11))
                            Text(isCopied ? "Copied!" : "Copy")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isCopied ? .green : .accentColor)
                    .controlSize(.small)
                }
                .padding(12)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )

                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundColor(.purple)
                    Text("Auto-configures systemd, TLS certificates, firewall port, and starts agent.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Token input for manual / existing installations
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Agent Auth Token:")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text("Pre-filled from command")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                HStack {
                    SecureField("Token", text: $token)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))

                    Button("Regen") {
                        token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
                    }
                    .controlSize(.small)
                }
            }

            if let err = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
            }

            Spacer()
        }
    }

    // View for 6-Digit Pair Code Method
    private var agentGuidePairCodeView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Generate Pairing Code on VPS:")
                    .font(.system(size: 13, weight: .bold))
                Text("On your VPS terminal, run:")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("pulse-agent pair")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("pulse-agent pair", forType: .string)
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        isCopied = false
                    }
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                }
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Enter the XXX-XXX Code displayed on your VPS:")
                    .font(.system(size: 12, weight: .medium))

                TextField("XXX-XXX Code (e.g. 749-201)", text: $pairCode)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 240)
            }

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("Pairing codes are valid for 10 minutes and can only be used once.")
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
                }
            }

            Spacer()
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
                        // Now complete connection test with token
                        self.testConnection()
                    } else {
                        self.errorMessage = "Missing auth token in response"
                        withAnimation { self.step = .agentGuide }
                    }
                case .failure(let err):
                    let desc = err.localizedDescription
                    if desc.localizedCaseInsensitiveContains("timed out") {
                        self.errorMessage = "Connection timed out. Check that '\(cleanAddress)' is your server's public IP (run 'curl -4 ifconfig.me' on VPS) and port \(port) is open."
                    } else {
                        self.errorMessage = "Pairing failed: \(desc)"
                    }
                    withAnimation { self.step = .agentGuide }
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

        let client = PulseAgentClient(
            host: cleanAddress,
            port: port,
            token: token.trimmingCharacters(in: .whitespaces)
        )
        self.testingClient = client

        // Test probe info
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
                        withAnimation { self.step = .agentGuide }
                    }
                case .failure(let err):
                    self.errorMessage = "Connection failed: \(err.localizedDescription). Ensure the agent is running and port \(portString) is open."
                    withAnimation { self.step = .agentGuide }
                }
            }
        }
    }
}
