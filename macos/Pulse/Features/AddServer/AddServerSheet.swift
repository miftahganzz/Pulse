import SwiftUI

public enum SetupMethod: String, CaseIterable, Identifiable {
    case oneLine = "1-Line Command"
    case pairCode = "6-Digit Pair Code"

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
                    Label("6-Digit Pair Code", systemImage: "number.circle.fill").tag(SetupMethod.pairCode)
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
                        Button("Verify & Pair") {
                            claimPairCode()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(pairCode.trimmingCharacters(in: .whitespaces).count != 6)
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
        case .enterDetails: return "Add Linux VPS"
        case .agentGuide: return setupMethod == .oneLine ? "1-Command Setup" : "6-Digit Pairing"
        case .testingConnection: return "Connecting to Agent..."
        case .success: return "Server Connected!"
        }
    }

    private var enterDetailsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Enter Your Server Address")
                    .font(.system(size: 14, weight: .bold))
                Text("Pulse connects directly to the agent over secure HTTPS & WebSockets.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Form {
                TextField("Server Name", text: $name, prompt: Text("e.g. VPS Jakarta / Production"))
                TextField("IP Address or Domain", text: $address, prompt: Text("e.g. 103.187.144.20 or myvps.com"))
                TextField("Port (Default 8443)", text: $portString)
            }
            .formStyle(.grouped)

            Spacer()
        }
    }

    // View for 1-Line Command Method
    private var agentGuideOneLineView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Run This Single Command on Your VPS:")
                    .font(.system(size: 13, weight: .bold))
                Text("Open SSH to \(address.isEmpty ? "your VPS" : address) and paste this line:")
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
                Text("Enter the 6-Digit Code displayed on your VPS:")
                    .font(.system(size: 12, weight: .medium))

                TextField("6-Digit Code (e.g. 749201)", text: $pairCode)
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

        let cleanAddress = address.trimmingCharacters(in: .whitespaces)
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
                    self.errorMessage = "Pairing failed: \(err.localizedDescription)"
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

        let client = PulseAgentClient(
            host: address.trimmingCharacters(in: .whitespaces),
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
                            address: address.trimmingCharacters(in: .whitespaces),
                            port: port,
                            token: token.trimmingCharacters(in: .whitespaces)
                        )
                        withAnimation { self.step = .success }
                    } catch {
                        self.errorMessage = "Failed to save to Keychain: \(error.localizedDescription)"
                        withAnimation { self.step = .agentGuide }
                    }
                case .failure(let err):
                    self.errorMessage = "Connection failed: \(err.localizedDescription). Ensure the installer command completed on your VPS and port \(portString) is open."
                    withAnimation { self.step = .agentGuide }
                }
            }
        }
    }
}
