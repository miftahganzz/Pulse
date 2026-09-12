import SwiftUI

public struct TelegramSettingsView: View {
    @ObservedObject var manager: ServerConnectionManager
    @ObservedObject private var telegramService = TelegramAlertService.shared

    @State private var botToken: String = ""
    @State private var chatIDs: [String] = []
    @State private var newChatID: String = ""
    @State private var isEnabled: Bool = false
    @State private var notifyOnCritical: Bool = true
    @State private var notifyOnWarning: Bool = false
    @State private var notifyOnRecovery: Bool = true

    @State private var isTesting: Bool = false
    @State private var testResult: String? = nil
    @State private var isTestSuccess: Bool = true

    public init(manager: ServerConnectionManager) {
        self.manager = manager
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Telegram Alert Integration", systemImage: "paperplane.fill")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle("", isOn: $isEnabled)
                    .toggleStyle(.switch)
            }

            Text("Receive instant push alerts on Telegram 24/7, even when your Mac is sleeping or closed.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            if isEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    // Bot Token
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bot Token (from @BotFather):")
                            .font(.system(size: 11, weight: .medium))
                        SecureField("123456789:ABCDefGhIJKlmNoPQRstuVWXyz", text: $botToken)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                    }

                    // Chat IDs
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recipient Chat IDs / User IDs:")
                            .font(.system(size: 11, weight: .medium))

                        HStack {
                            TextField("Enter Chat ID (e.g. 12345678 or @channel)", text: $newChatID)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                            Button("Add") {
                                addChatID()
                            }
                            .buttonStyle(.bordered)
                            .disabled(newChatID.trimmingCharacters(in: .whitespaces).isEmpty)
                        }

                        if !chatIDs.isEmpty {
                            FlowChatIDLayout(chatIDs: chatIDs) { removed in
                                chatIDs.removeAll(where: { $0 == removed })
                                saveConfig()
                            }
                            .padding(.top, 4)
                        }
                    }

                    // Event Toggles
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Trigger Events:")
                            .font(.system(size: 11, weight: .medium))

                        HStack(spacing: 16) {
                            Toggle("Critical / Outage", isOn: $notifyOnCritical)
                                .font(.system(size: 11))
                            Toggle("Warnings", isOn: $notifyOnWarning)
                                .font(.system(size: 11))
                            Toggle("Resolved", isOn: $notifyOnRecovery)
                                .font(.system(size: 11))
                        }
                    }

                    Divider()

                    // Test Alert Button & Result
                    HStack {
                        Button {
                            sendTestAlert()
                        } label: {
                            HStack(spacing: 5) {
                                if isTesting {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                } else {
                                    Image(systemName: "paperplane")
                                        .font(.system(size: 11))
                                }
                                Text("Send Test Alert")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(botToken.isEmpty || chatIDs.isEmpty || isTesting)

                        Spacer()

                        if let res = testResult {
                            HStack(spacing: 4) {
                                Image(systemName: isTestSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(isTestSuccess ? .green : .red)
                                Text(res)
                                    .font(.system(size: 11))
                                    .foregroundColor(isTestSuccess ? .primary : .red)
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .onAppear {
            loadFromService()
        }
        .onChange(of: isEnabled) { _ in saveConfig() }
        .onChange(of: botToken) { _ in saveConfig() }
        .onChange(of: notifyOnCritical) { _ in saveConfig() }
        .onChange(of: notifyOnWarning) { _ in saveConfig() }
        .onChange(of: notifyOnRecovery) { _ in saveConfig() }
    }

    private func loadFromService() {
        let cfg = telegramService.config
        self.isEnabled = cfg.enabled
        self.botToken = cfg.botToken
        self.chatIDs = cfg.chatIDs
        self.notifyOnCritical = cfg.notifyOnCritical
        self.notifyOnWarning = cfg.notifyOnWarning
        self.notifyOnRecovery = cfg.notifyOnRecovery
    }

    private func addChatID() {
        let clean = newChatID.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        if !chatIDs.contains(clean) {
            chatIDs.append(clean)
            newChatID = ""
            saveConfig()
        }
    }

    private func saveConfig() {
        let cfg = TelegramConfig(
            enabled: isEnabled,
            botToken: botToken.trimmingCharacters(in: .whitespaces),
            chatIDs: chatIDs,
            notifyOnWarning: notifyOnWarning,
            notifyOnCritical: notifyOnCritical,
            notifyOnRecovery: notifyOnRecovery
        )
        telegramService.updateConfig(cfg)

        // Also sync to agent if connected
        manager.updateTelegramConfig(cfg) { _ in }
    }

    private func sendTestAlert() {
        guard let firstChat = chatIDs.first else { return }
        isTesting = true
        testResult = nil

        Task {
            do {
                let msg = try await telegramService.sendTestMessage(token: botToken, chatID: firstChat)
                DispatchQueue.main.async {
                    self.isTesting = false
                    self.isTestSuccess = true
                    self.testResult = msg
                }
            } catch {
                DispatchQueue.main.async {
                    self.isTesting = false
                    self.isTestSuccess = false
                    self.testResult = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Flow Chat ID Chips Layout

private struct FlowChatIDLayout: View {
    let chatIDs: [String]
    let onRemove: (String) -> Void

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 90, maximum: 180), spacing: 6)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(chatIDs, id: \.self) { chatID in
                HStack(spacing: 5) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 9))
                    Text(chatID)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                    Button {
                        onRemove(chatID)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12))
                .foregroundColor(.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }
}
