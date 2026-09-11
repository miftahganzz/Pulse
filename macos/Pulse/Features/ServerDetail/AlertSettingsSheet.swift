import SwiftUI

public struct AlertSettingsSheet: View {
    @ObservedObject var manager: ServerConnectionManager
    @Environment(\.dismiss) private var dismiss

    @State private var isAlertsEnabled: Bool = true
    @State private var notifyOnOffline: Bool = true
    @State private var cpuThreshold: Double = 90
    @State private var memoryThreshold: Double = 90
    @State private var diskThreshold: Double = 90

    @State private var consecutiveFailures: Int = 2
    @State private var consecutiveSuccesses: Int = 2
    @State private var notifyOnRecovery: Bool = true
    @State private var notifyOnWarning: Bool = true

    public init(manager: ServerConnectionManager) {
        self.manager = manager
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Alert Settings")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Done") {
                    saveAndDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            Divider()

            Toggle("Enable Notifications for \(manager.serverName)", isOn: $isAlertsEnabled)
                .font(.system(size: 13, weight: .medium))

            if isAlertsEnabled {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Notify when server goes offline", isOn: $notifyOnOffline)
                        .font(.system(size: 12))

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("CPU Warning Threshold:")
                                .font(.system(size: 12))
                            Spacer()
                            Text("\(Int(cpuThreshold))%")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(cpuThreshold >= 90 ? .red : .primary)
                        }
                        Slider(value: $cpuThreshold, in: 50...99, step: 5)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Memory Warning Threshold:")
                                .font(.system(size: 12))
                            Spacer()
                            Text("\(Int(memoryThreshold))%")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(memoryThreshold >= 90 ? .red : .primary)
                        }
                        Slider(value: $memoryThreshold, in: 50...99, step: 5)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Disk Space Warning Threshold:")
                                .font(.system(size: 12))
                            Spacer()
                            Text("\(Int(diskThreshold))%")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(diskThreshold >= 90 ? .red : .primary)
                        }
                        Slider(value: $diskThreshold, in: 50...99, step: 5)
                    }

                    Divider()

                    // Phase 5: Incident Flapping & Suppression Controls
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Incident Flapping Protection")
                            .font(.system(size: 12, weight: .semibold))

                        HStack {
                            Text("Failures before incident:")
                                .font(.system(size: 12))
                            Spacer()
                            Picker("", selection: $consecutiveFailures) {
                                Text("1 check (Immediate)").tag(1)
                                Text("2 checks (Recommended)").tag(2)
                                Text("3 checks (Conservative)").tag(3)
                            }
                            .frame(width: 170)
                        }

                        HStack {
                            Text("Successes before recovery:")
                                .font(.system(size: 12))
                            Spacer()
                            Picker("", selection: $consecutiveSuccesses) {
                                Text("1 check").tag(1)
                                Text("2 checks (Recommended)").tag(2)
                                Text("3 checks").tag(3)
                            }
                            .frame(width: 170)
                        }

                        Toggle("Notify when service recovers", isOn: $notifyOnRecovery)
                            .font(.system(size: 12))

                        Toggle("Notify on warning / degraded state", isOn: $notifyOnWarning)
                            .font(.system(size: 12))
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 380)
        .onAppear {
            let current = manager.alertSettings
            self.isAlertsEnabled = current.isAlertsEnabled
            self.notifyOnOffline = current.notifyOnOffline
            self.cpuThreshold = current.cpuThresholdPercent
            self.memoryThreshold = current.memoryThresholdPercent
            self.diskThreshold = current.diskThresholdPercent

            let policy = manager.alertPolicy
            self.consecutiveFailures = policy.consecutiveFailuresThreshold
            self.consecutiveSuccesses = policy.consecutiveSuccessThreshold
            self.notifyOnRecovery = policy.notifyOnRecovery
            self.notifyOnWarning = policy.notifyOnWarning
        }
    }

    private func saveAndDismiss() {
        var updated = manager.alertSettings
        updated.isAlertsEnabled = isAlertsEnabled
        updated.notifyOnOffline = notifyOnOffline
        updated.cpuThresholdPercent = cpuThreshold
        updated.memoryThresholdPercent = memoryThreshold
        updated.diskThresholdPercent = diskThreshold
        manager.updateAlertSettings(updated)

        var updatedPolicy = manager.alertPolicy
        updatedPolicy.consecutiveFailuresThreshold = consecutiveFailures
        updatedPolicy.consecutiveSuccessThreshold = consecutiveSuccesses
        updatedPolicy.notifyOnRecovery = notifyOnRecovery
        updatedPolicy.notifyOnWarning = notifyOnWarning
        manager.updateAlertPolicy(updatedPolicy)

        dismiss()
    }
}
