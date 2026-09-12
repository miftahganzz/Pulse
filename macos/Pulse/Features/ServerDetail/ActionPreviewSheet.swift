import SwiftUI

public struct ActionPreviewSheet: View {
    let preview: ActionPreviewDetails
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    public init(preview: ActionPreviewDetails, onConfirm: @escaping () -> Void) {
        self.preview = preview
        self.onConfirm = onConfirm
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Action Preview")
                        .font(.system(size: 16, weight: .bold))
                    Text("\(preview.serverName) · \(preview.targetName)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: preview.riskLevel.sfSymbol)
                        .font(.system(size: 11))
                    Text(preview.riskLevel.displayName)
                        .font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(preview.riskLevel.color.opacity(0.15))
                .foregroundColor(preview.riskLevel.color)
                .cornerRadius(4)
            }

            Divider()

            // Details Grid
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ACTION TO EXECUTE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Text(preview.actionName)
                            .font(.system(size: 14, weight: .bold))
                        Text("(\(preview.actionId))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("REASON")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(preview.reason)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("EXPECTED IMPACT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                            .padding(.top, 2)
                        Text(preview.expectedImpact)
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.06))
                    .cornerRadius(6)
                }

                HStack {
                    Text("Reversible:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(preview.isReversible ? "Yes (service can be restarted)" : "Potentially Irreversible")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(preview.isReversible ? .green : .orange)
                }
            }
            .padding(14)
            .background(Color.secondary.opacity(0.04))
            .cornerRadius(8)

            Spacer()

            // Action Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    if AppSettingsStore.shared.requireBiometricForDestructiveActions && preview.riskLevel == .high {
                        BiometricService.shared.authenticate(reason: "Authorize '\(preview.actionName)' on \(preview.serverName)") { success in
                            if success {
                                dismiss()
                                onConfirm()
                            }
                        }
                    } else {
                        dismiss()
                        onConfirm()
                    }
                } label: {
                    Label("Execute \(preview.actionName)", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(preview.riskLevel == .high ? .red : .accentColor)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440, height: 380)
    }
}
