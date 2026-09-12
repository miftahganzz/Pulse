import SwiftUI

// MARK: - Docs Section Model

private enum DocsSection: String, CaseIterable, Identifiable {
    case whatIsPulse   = "What is Pulse"
    case connecting    = "Connecting a Server"
    case cli           = "Pulse CLI"
    case telegram      = "Telegram Alerts"
    case tools         = "Tools & Runbooks"
    case faq           = "FAQ"
    case about         = "About"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .whatIsPulse: return "waveform.path.ecg"
        case .connecting:  return "network"
        case .cli:         return "terminal.fill"
        case .telegram:    return "paperplane.fill"
        case .tools:       return "wrench.and.screwdriver.fill"
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
            .navigationSplitViewColumnWidth(190)
        } detail: {
            ScrollView {
                detailContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(28)
            }
        }
        .navigationTitle("Pulse Docs")
        .navigationSplitViewStyle(.balanced)
        .frame(width: 750, height: 540)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .whatIsPulse:  WhatIsPulseSection()
        case .connecting:   ConnectingSection()
        case .cli:          CLIDocsSection()
        case .telegram:     TelegramDocsSection()
        case .tools:        ToolsDocsSection()
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
                subtitle: "Pick your method below. All require the Pulse Agent running on the server."
            )

            // Quick setup table
            GroupBox("One-Command Setup — Pick Your Method") {
                VStack(alignment: .leading, spacing: 10) {
                    quickSetupRow("Direct IP / LAN (Root)",
                        "curl -fsSL .../install.sh | sudo bash")
                    Divider()
                    quickSetupRow("Direct IP / LAN (Non-Root User)",
                        "curl -fsSL .../install.sh | bash")
                    Divider()
                    quickSetupRow("Tailscale (Root)",
                        "curl -fsSL .../setup-tailscale.sh | sudo bash")
                    Divider()
                    quickSetupRow("Tailscale (Non-Root User)",
                        "curl -fsSL .../setup-tailscale.sh | bash")
                    Divider()
                    quickSetupRow("Cloudflare Tunnel (Root)",
                        "curl -fsSL .../setup-cloudflare.sh | sudo bash")
                    Divider()
                    quickSetupRow("Cloudflare Tunnel (Non-Root User)",
                        "curl -fsSL .../setup-cloudflare.sh | bash")
                    Text("All scripts auto-detect CPU arch (x86_64/arm64) and distro: Debian, Ubuntu, RHEL, CentOS, Fedora, Arch, Alpine, openSUSE, Void, and any systemd-based distro.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }

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
                        Text("For root servers (system-wide service):")
                            .font(.body)
                            .foregroundColor(.secondary)
                        codeBlock("curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/install.sh | sudo bash")
                        Text("For non-root users (no sudo required):")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        codeBlock("curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/install.sh | bash")
                        Text("The agent listens on port 8443 by default. It generates TLS credentials and prints the connection token and a pulse:// deep link on first run.")
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
                    "Install the Pulse Agent on the server (see command above)",
                    "Note the server's IP address (e.g. 192.168.1.10)",
                    "In Pulse, click + → enter the IP, port (default 8443), and the token printed by the agent",
                    "Click Connect — Pulse verifies the certificate fingerprint and connects"
                ]
            )

            // Method 2
            methodBlock(
                number: "2",
                title: "Tailscale (Recommended for Remote Servers)",
                description: "Tailscale creates a private WireGuard mesh between your devices. No open ports needed on the server. One-command setup: curl -fsSL .../setup-tailscale.sh | sudo bash (or | bash for non-root).",
                steps: [
                    "Install Tailscale on both your Mac and the server: tailscale.com/download",
                    "Run tailscale up on the server — it gets a 100.x.x.x IP or MagicDNS hostname",
                    "In Pulse, enter the Tailscale IP (e.g. 100.64.0.5) or MagicDNS hostname as the host",
                    "Use port 8443 and the agent token as usual",
                    "Connection is fully encrypted — WireGuard + mTLS layered on top"
                ]
            )

            // Method 3
            methodBlock(
                number: "3",
                title: "Cloudflare Tunnel (Zero Inbound Ports)",
                description: "Cloudflare Tunnel exposes your server via Cloudflare's edge — no firewall ports required. One-command setup: curl -fsSL .../setup-cloudflare.sh | sudo bash (or | bash for non-root).",
                steps: [
                    "Install cloudflared on the server (Debian/Ubuntu/RHEL/binary — the script handles this)",
                    "A quick tunnel gives you a temporary https://xyz.trycloudflare.com URL (no account needed)",
                    "For permanent URLs: run with --tunnel-name <name> --domain pulse.yourdomain.com",
                    "In Pulse, enter the Cloudflare URL as host, port 443",
                    "Cloudflare terminates public SSL; the agent communicates on localhost only"
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

            // Pairing code
            GroupBox("XXX-XXX Pairing Code") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Prefer not to paste tokens on the command line? Use the pairing code flow:")
                        .font(.body)
                    codeBlock("pulse pair")
                    Text("This prints a temporary XXX-XXX code (e.g. 653-557) valid for 10 minutes. In Pulse → Add Server, select Pair Code, enter the server IP and the code.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func quickSetupRow(_ label: String, _ command: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
            Text(command)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Pulse CLI

private struct CLIDocsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader(
                icon: "terminal.fill",
                title: "Pulse CLI Reference",
                subtitle: "Unified all-in-one command line tool for managing your Linux nodes, networking, and daemon."
            )

            Text("""
Every server running the Pulse agent includes the unified `pulse` command (symlinked to `/usr/local/bin/pulse` or `~/.local/bin/pulse`). \
You can manage pairing, check system metrics, stream logs, configure Tailscale or Cloudflare tunnels, \
and auto-update the binary with simple subcommands — supporting both root and non-root user modes seamlessly.
""")
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)

            GroupBox("Status & Diagnostics") {
                VStack(alignment: .leading, spacing: 12) {
                    cliCommandRow("pulse", "Displays quick system health summary, listening port, and IP addresses.")
                    cliCommandRow("pulse status", "Full status output including daemon state, LAN IP, Public IP, and active pairing codes.")
                    cliCommandRow("pulse doctor", "Runs complete connectivity, TLS certificate, firewall, and permission diagnostics.")
                }
                .padding(.vertical, 4)
            }

            GroupBox("Pairing & Zero-Config Setup") {
                VStack(alignment: .leading, spacing: 12) {
                    cliCommandRow("pulse pair", "Generates a temporary XXX-XXX pairing code (valid 10 mins) to connect from your Mac without pasting tokens.")
                    cliCommandRow("pulse pair <code>", "Explicitly sets a custom 6-digit pairing code on the server.")
                }
                .padding(.vertical, 4)
            }

            GroupBox("Mesh Networking & Tunnels") {
                VStack(alignment: .leading, spacing: 12) {
                    cliCommandRow("pulse tailscale", "Detects Tailscale status, shows MagicDNS hostname and Tailscale IP, or provides 1-command installer.")
                    cliCommandRow("sudo pulse tailscale install", "Automates Tailscale installation, login setup, and firewall hardening.")
                    cliCommandRow("pulse cloudflare", "Detects cloudflared status, generates ingress configuration, or guides 1-command tunnel setup.")
                }
                .padding(.vertical, 4)
            }

            GroupBox("Daemon & Maintenance") {
                VStack(alignment: .leading, spacing: 12) {
                    cliCommandRow("pulse logs -f", "Streams live agent logs via journalctl (supports both system and user service).")
                    cliCommandRow("pulse update", "Checks GitHub Releases for latest agent release, verifies CPU arch, and upgrades in place.")
                    cliCommandRow("pulse restart", "Restarts the background systemd daemon (or user systemd service).")
                    cliCommandRow("pulse stop / start", "Stops or starts the agent service.")
                    cliCommandRow("pulse uninstall", "Cleanly stops service, removes systemd units, binaries, and certificates.")
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func cliCommandRow(_ cmd: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            codeBlock(cmd)
            Text(desc)
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.leading, 2)
        }
    }
}

// MARK: - Telegram Alerts

private struct TelegramDocsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader(
                icon: "paperplane.fill",
                title: "Telegram Outbound Alerts",
                subtitle: "Direct push notification alerts sent to your phone or team chat via Telegram."
            )

            Text("""
Pulse can notify you via Telegram whenever critical incidents occur on your servers (high CPU/RAM, disk exhaustion, service or container crashes).

Alerts can be delivered directly from your server's Pulse Agent or from the macOS client directly to Telegram's Bot API. No external SaaS or intermediary proxy is involved.
""")
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)

            GroupBox("Setup in 3 Steps") {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Create your Telegram Bot")
                            .font(.headline)
                        Text("Open Telegram and message @BotFather. Send /newbot, follow the prompts, and copy your HTTP API Bot Token (e.g. 7123456789:AAFx...).")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("2. Get your Chat ID")
                            .font(.headline)
                        Text("To receive personal alerts, message @userinfobot to get your numeric ID (e.g. 123456789). For group alerts, add your bot to the group and copy the group chat ID (e.g. -100xxxxxxxxxx).")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("3. Configure in Pulse")
                            .font(.headline)
                        Text("In the server detail view, click the Alert Settings bell icon. Enable Telegram Outbound Alerts, paste your Bot Token, and enter your Chat IDs. Click 'Send Test Alert' to verify instant delivery.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox("Privacy & Direct Connection") {
                VStack(alignment: .leading, spacing: 8) {
                    featureRow("lock.shield", "End-to-end TLS: Notifications are dispatched directly from your host or Mac to https://api.telegram.org.")
                    featureRow("person.2", "Multi-recipient: You can broadcast to multiple admin user IDs and group channels simultaneously.")
                    featureRow("bolt.horizontal", "Cooldown & deduplication: Alert bursts and flapping events are automatically throttled to avoid spamming.")
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - Tools & Runbooks

private struct ToolsDocsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader(
                icon: "wrench.and.screwdriver.fill",
                title: "Tools & Runbooks",
                subtitle: "Live log streaming, disk diagnostics, safe cleaners, and 1-click maintenance."
            )

            GroupBox("Live Log Viewer") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Stream live logs with sub-second WebSocket updates from both Systemd services and Docker containers. Includes real-time keyword filtering, auto-scroll toggle, and 1-click clipboard export.")
                        .font(.body)
                        .foregroundColor(.secondary)
                    featureRow("list.bullet.rectangle", "Systemd: Streams journal logs (journalctl -f) with unit selection")
                    featureRow("shippingbox", "Docker: Streams container stdout/stderr with real-time timestamps")
                }
                .padding(.vertical, 4)
            }

            GroupBox("Disk Space Analyzer") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Break down disk usage by critical directories (/var/log, /var/lib/docker, /var/cache, /tmp). Safely reclaim gigabytes with built-in 1-click cleaners:")
                        .font(.body)
                        .foregroundColor(.secondary)
                    featureRow("trash", "Vacuum Journals: Prunes systemd logs older than 3 days")
                    featureRow("trash", "Docker Prune: Removes stopped containers, dangling images, and build cache")
                    featureRow("trash", "Clean APT Cache: Clears downloaded package archives safely")
                }
                .padding(.vertical, 4)
            }

            GroupBox("Maintenance Runbooks (⌘R)") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Run safe, pre-approved maintenance operations with live terminal output:")
                        .font(.body)
                        .foregroundColor(.secondary)
                    featureRow("bolt.fill", "Reload Nginx / Caddy without dropping active connections")
                    featureRow("bolt.fill", "Flush DNS cache (systemd-resolved / nscd)")
                    featureRow("bolt.fill", "Check available OS security package updates")
                    featureRow("bolt.fill", "Drop filesystem pagecache safely (echo 3 > /proc/sys/vm/drop_caches)")
                }
                .padding(.vertical, 4)
            }

            GroupBox("Process I/O & Menu Bar Metrics") {
                VStack(alignment: .leading, spacing: 8) {
                    featureRow("arrow.up.arrow.down", "Disk & Network I/O: Live read/write rates and open socket count per process")
                    featureRow("menubar.rectangle", "Menu Bar Ticker: Enable live CPU & RAM metrics directly in macOS status bar via Settings")
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - FAQ

private struct FAQSection: View {
    private let items: [(String, String)] = [
        (
            "Is there a Pulse Agent for Windows?",
            "Not yet. The agent currently supports Linux (Debian, Ubuntu, RHEL, CentOS, Fedora, Arch, Alpine, openSUSE, Void) and macOS. Windows support is on the roadmap."
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
                    infoRow("App Version", "1.0.2 (Build 12)")
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
