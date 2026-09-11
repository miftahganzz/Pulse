import SwiftUI

public struct OnboardingView: View {
    var onAddServer: () -> Void

    public init(onAddServer: @escaping () -> Void) {
        self.onAddServer = onAddServer
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 64, weight: .semibold))
                .foregroundColor(.accentColor)

            VStack(spacing: 8) {
                Text("Welcome to Pulse")
                    .font(.system(size: 26, weight: .bold))

                Text("Infrastructure, at a glance.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)

                Text("Realtime server metrics, process monitoring, Docker containers, database probes, and native incident tracking directly from your Mac.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            VStack(alignment: .leading, spacing: 14) {
                FeatureHighlightRow(
                    icon: "shield.checkered",
                    title: "Zero Inbound Exposure",
                    description: "Direct TLS connection with SHA-256 fingerprint pinning."
                )

                FeatureHighlightRow(
                    icon: "bell.badge",
                    title: "Flapping Protection",
                    description: "Native notifications without alert storms when servers reboot."
                )

                FeatureHighlightRow(
                    icon: "menubar.rectangle",
                    title: "Menu Bar Integration",
                    description: "Keep tabs on all your VPS health silently in the background."
                )
            }
            .frame(maxWidth: 380)
            .padding(.vertical, 8)

            Button(action: onAddServer) {
                Label("Add Your First Server", systemImage: "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FeatureHighlightRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
}
