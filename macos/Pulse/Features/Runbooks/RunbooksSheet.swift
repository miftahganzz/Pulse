import SwiftUI

public struct RunbooksSheet: View {
    @ObservedObject var manager: ServerConnectionManager
    @Environment(\.dismiss) private var dismiss

    @State private var runningActionId: String? = nil
    @State private var outputMessage: String? = nil
    @State private var isSuccess: Bool = true
    @State private var customCommand: String = ""

    public struct RunbookPreset: Identifiable {
        public let id: String
        public let title: String
        public let description: String
        public let icon: String
        public let action: String
        public let target: String
    }

    private let presets: [RunbookPreset] = [
        RunbookPreset(
            id: "reload_web",
            title: "Reload Web Server",
            description: "Gracefully reloads Nginx, Caddy, or Apache without dropping connections.",
            icon: "arrow.triangle.2.circlepath",
            action: "system.reload_webserver",
            target: "web"
        ),
        RunbookPreset(
            id: "flush_dns",
            title: "Flush DNS Cache",
            description: "Flushes local systemd-resolved DNS cache to resolve domain changes immediately.",
            icon: "network",
            action: "system.flush_dns",
            target: "system"
        ),
        RunbookPreset(
            id: "check_updates",
            title: "Check System Updates",
            description: "Runs package manager update check to discover pending security patches.",
            icon: "arrow.down.circle",
            action: "system.check_updates",
            target: "system"
        ),
        RunbookPreset(
            id: "drop_caches",
            title: "Free Page Cache",
            description: "Syncs filesystem buffers and reclaims inactive Linux page cache.",
            icon: "memorychip",
            action: "system.drop_caches",
            target: "system"
        )
    ]

    public init(manager: ServerConnectionManager) {
        self.manager = manager
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Maintenance Runbooks")
                            .font(.system(size: 15, weight: .semibold))
                        Text(manager.serverName)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            Divider()

            // Presets List
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(presets) { preset in
                        presetCard(preset)
                    }
                }
                .padding(.bottom, 6)
            }

            // Output Drawer
            if let output = outputMessage {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(isSuccess ? .green : .red)
                        Text(isSuccess ? "Runbook Succeeded" : "Runbook Failed")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Button {
                            outputMessage = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Text(output)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isSuccess ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 1)
                )
            }
        }
        .padding(20)
        .frame(width: 480, height: 460)
    }

    private func presetCard(_ preset: RunbookPreset) -> some View {
        let isRunning = (runningActionId == preset.id)

        return HStack(spacing: 12) {
            Image(systemName: preset.icon)
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(preset.title)
                    .font(.system(size: 13, weight: .medium))
                Text(preset.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                executePreset(preset)
            } label: {
                if isRunning {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 40)
                } else {
                    Text("Run")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 40)
                }
            }
            .buttonStyle(.bordered)
            .disabled(runningActionId != nil)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func executePreset(_ preset: RunbookPreset) {
        runningActionId = preset.id
        outputMessage = nil

        manager.executeAction(action: preset.action, target: preset.target, actor: "Runbook")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.runningActionId = nil
            if let latest = self.manager.auditLogs.last {
                self.isSuccess = (latest.status == "success")
                self.outputMessage = latest.message
            } else {
                self.isSuccess = true
                self.outputMessage = "Action dispatched successfully."
            }
        }
    }
}
