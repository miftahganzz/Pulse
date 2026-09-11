import SwiftUI

public struct OnboardingView: View {
    var onAddServer: () -> Void

    public init(onAddServer: @escaping () -> Void) {
        self.onAddServer = onAddServer
    }

    public var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // App Icon Hero Tile
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 12, x: 0, y: 4)

                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(spacing: 8) {
                Text("Welcome to Pulse")
                    .font(.system(size: 26, weight: .bold))

                Text("Native infrastructure monitoring, engineered for macOS.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }

            // Feature Highlights Box
            VStack(alignment: .leading, spacing: 16) {
                FeatureHighlightRow(
                    icon: "lock.shield.fill",
                    iconColor: .blue,
                    title: "Zero Inbound Exposure",
                    description: "Mutual TLS & SHA-256 fingerprint pinning over direct, Tailscale, or Cloudflare Tunnels."
                )

                FeatureHighlightRow(
                    icon: "bell.badge.fill",
                    iconColor: .orange,
                    title: "Smart Flapping Protection",
                    description: "Suppresses alert storms during reboots and resolves downtime incidents automatically."
                )

                FeatureHighlightRow(
                    icon: "chart.xyaxis.line",
                    iconColor: .teal,
                    title: "Realtime Telemetry & Probes",
                    description: "Sub-second CPU, memory, Docker container health, and custom database monitors."
                )

                FeatureHighlightRow(
                    icon: "menubar.rectangle",
                    iconColor: .indigo,
                    title: "Menu Bar Integration",
                    description: "Inspect cluster health and active incidents at a glance without opening windows."
                )
            }
            .frame(maxWidth: 420)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )

            Button(action: onAddServer) {
                Label("Add Your First Server", systemImage: "plus.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 8)
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
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 28, height: 28)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

