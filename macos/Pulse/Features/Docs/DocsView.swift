import SwiftUI

// MARK: - Docs Section Model

private enum DocsSection: String, CaseIterable, Identifiable {
    case whatIsPulse   = "What is Pulse"
    case connecting    = "Connecting a Server"
    case faq           = "FAQ"
    case about         = "About"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .whatIsPulse: return "waveform.path.ecg"
        case .connecting:  return "network"
        case .faq:         return "questionmark.circle"
        case .about:       return "person.circle"
        }
    }
}

// MARK: - Main Docs View

public struct DocsView: View {
    @State private var selection: DocsSection = .whatIsPulse

    public init() {}

    public var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(DocsSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(180)
        } detail: {
            ScrollView {
                detailContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(28)
            }
        }
        .navigationTitle("Pulse Docs")
        .navigationSplitViewStyle(.balanced)
        .frame(width: 720, height: 520)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .whatIsPulse:  WhatIsPulseSection()
        case .connecting:   ConnectingSection()
        case .faq:          FAQSection()
        case .about:        AboutSection()
        }
    }
}

// MARK: - What is Pulse

private struct WhatIsPulseSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader(
                icon: "waveform.path.ecg",
                title: "What is Pulse",
                subtitle: "Real-time infrastructure monitoring for Linux and macOS — from your Mac."
            )

            Text("""
Pulse is a native macOS app that gives you a live view into your servers and infrastructure. \
It connects through the Pulse Agent — a lightweight daemon you run on each server — and \
streams telemetry back in real time with sub-second latency.

No third-party cloud dashboards. No public IPs required. Your data stays in your own network.
""")
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)

            GroupBox("What You Can Monitor") {
                VStack(alignment: .leading, spacing: 10) {
                    featureRow("chart.xyaxis.line", "CPU, memory, disk I/O, and network rates — updated every 5–10 seconds")
                    featureRow("shippingbox", "Docker containers with live log streaming and restart controls")
                    featureRow("shield.lefthalf.filled", "Open TCP/UDP ports with exposure risk classification")
                    featureRow("bell", "Smart incident alerts with root-cause hints, not just threshold breaches")
                    featureRow("menubar.rectangle", "Menu Bar extra showing live incident count — always visible")
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - Connecting a Server

private struct ConnectingSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            sectionHeader(
                icon: "network",
                title: "Connecting a Server",
                subtitle: "Three ways to connect. All require the Pulse Agent running on the server."
            )

            // Agent install note
            GroupBox {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "terminal")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Install the Pulse Agent first")
                            .font(.headline)
                        Text("On every server you want to monitor, run the one-line installer:")
                            .font(.body)
                            .foregroundColor(.secondary)
                        codeBlock("curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/install.sh | bash")
                        Text("The agent listens on port 8443 by default. It generates a mutual-TLS certificate and prints the connection token on first run.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Method 1
            methodBlock(
                number: "1",
                title: "Direct IP or Local Network",
                description: "Use this when your Mac and the server are on the same LAN, or the server has a public IP.",
                steps: [
                    "Install the Pulse Agent on the server",
                    "Note the server's IP address (e.g. 192.168.1.10)",
                    "In Pulse, click + → enter the IP, port (default 8443), and the token printed by the agent",
                    "Click Connect — Pulse verifies the certificate fingerprint and connects"
                ]
            )

            // Method 2
            methodBlock(
                number: "2",
                title: "Tailscale (Recommended for Remote Servers)",
                description: "Tailscale creates a private WireGuard mesh between your devices. No open ports needed on the server.",
                steps: [
                    "Install Tailscale on both your Mac and the server: tailscale.com/download",
                    "Run tailscale up on the server — it will get a 100.x.x.x IP or MagicDNS hostname",
                    "In Pulse, enter the Tailscale IP (e.g. 100.64.0.5) or hostname (e.g. my-server.tail12345.ts.net) as the host",
                    "Use port 8443 and the agent token as usual",
                    "Connection is fully encrypted — WireGuard + mTLS on top"
                ]
            )

            // Method 3
            methodBlock(
                number: "3",
                title: "Cloudflare Tunnel (Zero Inbound Ports)",
                description: "Cloudflare Tunnel lets you expose a server to the internet via Cloudflare's network without opening any firewall ports.",
                steps: [
                    "Install cloudflared on the server: brew install cloudflared or via pkg",
                    "Run: cloudflared tunnel --url https://localhost:8443",
                    "Cloudflare gives you a public HTTPS URL like https://xyz.trycloudflare.com",
                    "In Pulse, enter that URL as the host (without port — Cloudflare handles TLS termination at 443)",
                    "For a permanent tunnel, configure a named tunnel via cloudflared tunnel create and DNS routing"
                ]
            )

            // Deep link
            GroupBox("Quick Connect via URL Scheme") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("You can share a pulse:// URL to auto-fill the Add Server form:")
                        .font(.body)
                    codeBlock("pulse://add?name=My+Server&host=100.64.0.5&port=8443&token=your-token")
                    Text("Clicking this link on a Mac with Pulse installed opens the Add Server sheet pre-filled.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - FAQ

private struct FAQSection: View {
    private let items: [(String, String)] = [
        (
            "Is there a Pulse Agent for Windows?",
            "Not yet. The agent currently supports Linux (Debian/Ubuntu/RHEL/Arch) and macOS. Windows support is on the roadmap."
        ),
        (
            "Does Pulse send my server data to any cloud?",
            "No. All telemetry flows directly between the Pulse Agent on your server and the Pulse app on your Mac. No relay, no cloud storage, no third-party analytics."
        ),
        (
            "The agent connection shows 'Certificate Mismatch'. What do I do?",
            "This usually means the agent was reinstalled and generated a new certificate. Delete the server entry in Pulse and re-add it with the new token and fingerprint printed by the agent."
        ),
        (
            "Can I monitor more than one server?",
            "Yes. Add as many servers as you like via the + button. Each has an independent connection and certificate."
        ),
        (
            "How do I update the Pulse Agent?",
            "Re-run the one-line installer. It will detect an existing installation and update in place without changing your token or certificate."
        ),
        (
            "Does Pulse work on Apple Silicon (M1/M2/M3)?",
            "Yes. The app ships as a Universal binary — native on both Apple Silicon and Intel Macs."
        ),
        (
            "What happens to alerts when my Mac is sleeping?",
            "The agent continues running on the server. When your Mac wakes, Pulse reconnects automatically and backfills any incidents that occurred while you were asleep."
        ),
        (
            "I closed the window but the app is still running. Is that right?",
            "Yes — if 'Keep Pulse monitoring in background' is enabled in Settings, the app stays active to monitor servers and deliver notifications even with no window open. You can access it from the Menu Bar."
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader(
                icon: "questionmark.circle",
                title: "FAQ",
                subtitle: "Common questions about Pulse."
            )

            VStack(alignment: .leading, spacing: 16) {
                ForEach(items, id: \.0) { item in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.0)
                                .font(.headline)
                            Text(item.1)
                                .font(.body)
                                .foregroundColor(.primary.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
}

// MARK: - About

private struct AboutSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader(
                icon: "person.circle",
                title: "About",
                subtitle: "Who made this and what license it's under."
            )

            GroupBox("Developer") {
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Miftah")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("github.com/miftahganzz")
                            .font(.body)
                            .foregroundColor(.accentColor)
                            .onTapGesture {
                                NSWorkspace.shared.open(URL(string: "https://github.com/miftahganzz")!)
                            }
                        Text("Open to feedback and contributions.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
            }

            GroupBox("App") {
                VStack(alignment: .leading, spacing: 8) {
                    infoRow("App Version", "0.8.0 (Build 8)")
                    infoRow("Minimum macOS", "macOS 13 Ventura")
                    infoRow("License", "MIT — free to use and modify")
                    infoRow("Source", "github.com/miftahganzz/Pulse")
                }
                .padding(.vertical, 2)
            }

            GroupBox("Open Source Libraries") {
                VStack(alignment: .leading, spacing: 8) {
                    infoRow("Sparkle", "2.x — macOS auto-update framework (MIT)")
                }
                .padding(.vertical, 2)
            }

            Text("Pulse stores server tokens and TLS credentials exclusively in the Apple Keychain. No credentials are written to disk in plaintext.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Shared Helpers

private func sectionHeader(icon: String, title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.accentColor)
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
        }
        Text(subtitle)
            .font(.body)
            .foregroundColor(.secondary)
    }
}

private func featureRow(_ icon: String, _ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.accentColor)
            .frame(width: 18)
        Text(text)
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private func methodBlock(number: String, title: String, description: String, steps: [String]) -> some View {
    GroupBox {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(number)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.accentColor)
                    .clipShape(Circle())
                Text(title)
                    .font(.headline)
            }
            Text(description)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(i + 1).")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 18, alignment: .trailing)
                        Text(step)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 4)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func codeBlock(_ text: String) -> some View {
    Text(text)
        .font(.system(.footnote, design: .monospaced))
        .textSelection(.enabled)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
        )
}

private func infoRow(_ label: String, _ value: String) -> some View {
    HStack {
        Text(label)
            .foregroundColor(.secondary)
            .frame(width: 130, alignment: .leading)
        Text(value)
    }
    .font(.body)
}
