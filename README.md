<div align="center">

# Pulse

### Native, Lightning-Fast Infrastructure Monitoring & Auto-Remediation for macOS & Linux VPS

[![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue?logo=apple&style=flat-square)](https://apple.com)
[![Architecture](https://img.shields.io/badge/Architecture-Apple%20Silicon%20%7C%20Intel-success?style=flat-square)](#)
[![Go Agent](https://img.shields.io/badge/Go%20Agent-1.22+-00ADD8?logo=go&style=flat-square)](https://go.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)

*Pulse gives you total observability over your servers directly from your Mac menu bar and desktop dashboard — without heavy SaaS subscriptions, agent bloat, or cloud lock-in.*

[Quick Start](#-quick-start) • [Features](#-key-features) • [Installation Guide](#-installation--connection-methods) • [Diagnostics](#-pulse-doctor) • [Architecture](#-architecture) • [FAQ](#-frequently-asked-questions)

</div>

---

## ⚡️ Highlights

- **Direct End-to-End Encryption**: Zero intermediary third-party servers. Your Mac connects straight to your VPS over pinned TLS and bidirectional WebSockets.
- **Microscopic Footprint**: Single static Go binary on Linux (`< 15 MB RAM`, `< 0.1% CPU`), native Swift & SwiftUI app on macOS.
- **1-Command Zero-Touch Setup**: Run one command via SSH or use a 6-digit numeric pairing code — no manual token copying or firewall gymnastics.
- **Autonomous Remediation Engine**: Controlled operation safety gates (cooldowns, rate limits, maintenance mute, dry-run previews, and flapping protection).
- **Extensible Service Providers**: Live discovery and management for **Docker containers, Systemd units, PM2 processes, PostgreSQL, Redis, MySQL, MongoDB, Nginx/Caddy, Cloudflare Tunnels, and TCP/HTTP health probes**.
- **Deterministic Incident Intelligence**: Outage cascade correlation and heuristic root-cause analysis (e.g. *identifies PostgreSQL downtime as the true culprit behind API 502 failures*).

---

## 🚀 Quick Start

### 1. Download & Install Pulse for Mac
Download the latest prebuilt release installer:
- **[Pulse-0.7.0.dmg](https://github.com/miftahganzz/Pulse/releases/latest/download/Pulse-0.7.0.dmg)** (Recommended: Native drag-and-drop installer)
- **[Pulse-0.7.0.pkg](https://github.com/miftahganzz/Pulse/releases/latest/download/Pulse-0.7.0.pkg)** (Standard macOS package installer)

Open the `.dmg`, drag **Pulse.app** into your **Applications** folder, and launch it.

### 2. Connect Your Server
Press `⌘N` (or click **+ Add Server**) in Pulse, then choose either **1-Line Command** or **6-Digit Pair Code**.

---

## 🔌 Installation & Connection Methods

Pulse supports two seamless pairing methods designed for developer speed:

### Method A: ⚡️ 1-Line Command (Instant & Automated)

In the **Add Server** window on your Mac, enter your server IP and copy the generated one-line command:

```bash
curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/install.sh | sudo bash -s -- --port 8443 --token <YOUR_GENERATED_TOKEN>
```

**What the installer does automatically:**
1. Detects system architecture (`x86_64` or `arm64`).
2. Creates an isolated system user `pulse`.
3. Installs `/usr/local/bin/pulse-agent` with strictly permissioned configs (`chmod 600 /etc/pulse/agent.json`).
4. Generates unique self-signed TLS certificates locally.
5. Automatically opens port `8443/tcp` if `ufw` firewall is active.
6. Registers and starts the `pulse-agent.service` systemd daemon.
7. Signals your Mac app to immediately establish the encrypted telemetry stream.

---

### Method B: 🔢 6-Digit Pairing Code (No Long Token Pasting)

If `pulse-agent` is already installed on your server, simply run:

```bash
pulse-agent pair
```

Your server terminal will generate a temporary 6-digit code valid for 10 minutes:

```text
================================================================
🔗 Pulse 6-Digit Pairing Mode
================================================================
Pairing Code: 207906
Server Host:  vps.example.com
Server Port:  8443
Expires in:   10 minutes
----------------------------------------------------------------
In your Mac Pulse App, choose '6-Digit Pair Code', then:
Enter this server's IP address and Pairing Code: 207906
================================================================
```

In the Mac App:
1. Select the **"6-Digit Pair Code"** tab.
2. Enter your server's IP address and the 6-digit code (`207906`).
3. Click **"Verify & Pair"**.
4. The token is claimed, stored in your macOS Keychain, and real-time monitoring begins.

---

## 🩺 Pulse Doctor

Encountering firewall restrictions or closed ports? Run the built-in diagnostic tool on your server:

```bash
pulse-agent doctor
```

```text
================================================================
🩺 Pulse Agent System Doctor (v0.7.0)
================================================================
[✔] Pulse Agent Version        : v0.7.0
[✔] Configuration File         : Found at /etc/pulse/agent.json (Agent ID: pulse_e9a18d)
[✔] TLS Certificate & Key      : Cert: /etc/pulse/cert.pem, Key: /etc/pulse/key.pem
[✔] Systemd Service            : pulse-agent.service is active and running
[✔] Port 8443 Binding          : pulse-agent is actively accepting TCP connections on port 8443
[✔] HTTPS & Token Auth         : Endpoint responds with TLS and enforces token authentication
[✔] Firewall (UFW)             : Port 8443 is explicitly allowed in UFW
================================================================
```

---

## ✨ Key Features

### 🖥️ Native macOS Experience
- **Menu Bar Extra**: Pin real-time CPU, RAM, and alert badges directly in your macOS menu bar.
- **Detailed Server Inspector**: Full hardware utilization metrics, historical CPU/RAM charts, network throughput, disk space projection, and load averages.
- **System Service & Process Explorer**: Inspect top processes by CPU and memory; gracefully signal (`SIGTERM` / `SIGKILL`) unresponsive workloads.

### 🐳 Container & Infrastructure Ecosystem
- **Docker Integration**: Inspect container CPU, memory limits, health statuses, restart policies, and stream tail logs in real time.
- **Extensible Providers**: Native support for **Systemd, Docker, PM2, PostgreSQL, MySQL, MongoDB, Redis, Web Servers (Nginx/Apache/Caddy), Cloudflare Tunnels**, and synthetic HTTP/TCP probes.
- **Automatic Service Discovery**: Detects database ports, web proxies, and active background services on startup and prompts for one-click monitor creation.

### 🧠 Incident Correlation & Root-Cause Intelligence
- **Graph Dependency Mapping**: Link services together (e.g. `Backend API` $\rightarrow$ `PostgreSQL` $\rightarrow$ `VPS Host`).
- **Cascade Suppression**: If the host VPS goes down, child alerts for 20 containers and services are clustered into a single root-cause notification rather than spamming your phone.
- **Flapping Protection**: Prevents alert storms when services flicker up and down rapidly.

### 🛡️ Controlled Operation & Remediation Safety
- **Dry-Run & Impact Previews**: Review command implications before triggering container restarts or service reloads.
- **Automated Circuit Breaker**: Disables automated auto-remediation if an action fails 3 consecutive times, preventing boot loops.
- **Maintenance Windows**: Silence monitoring checks during planned software upgrades.

---

## 🏛 Architecture

```text
┌────────────────────────────────────────────────────────┐
│                   macOS (Pulse.app)                    │
│                                                        │
│  [MenuBar Extra]  [Fleet Dashboard]  [Remediation UI]  │
│  [Keychain Store] [Incident Graph]   [Telemetry Store] │
└───────────────────────────┬────────────────────────────┘
                            │
                            │ HTTPS / TLS (Mutual Identity / Pairing)
                            │ WSS (Encrypted Binary Telemetry Stream)
                            ▼
┌────────────────────────────────────────────────────────┐
│               Linux Host (pulse-agent)                 │
│                                                        │
│  [Pairing Manager] [System Collector] [Action Engine]  │
│  [Docker Client]   [Service Probes]   [Provider Reg]   │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
         Host Systemd, Containers, Databases, & Logs
```

---

## 🛠 Manual Build Instructions

### Building the macOS App
- **Requirements**: macOS 13.0+, Xcode 15+, Swift 5.9+

```bash
cd macos

# Run unit & integration test suites
swift test

# Build release application bundle
swift build -c release
cp -f .build/release/Pulse build/Pulse.app/Contents/MacOS/Pulse
codesign --force --deep --sign - build/Pulse.app

# Package as DMG & PKG
create-dmg dist/Pulse-0.7.0.dmg macos/build/Pulse.app
```

### Building the Linux Agent
- **Requirements**: Go 1.22+

```bash
cd agent/pulse-agent

# Build for all target architectures (Linux amd64/arm64, Darwin amd64/arm64)
make build-all
```

Binaries will be placed in `agent/pulse-agent/bin/`:
- `pulse-agent-linux-amd64`
- `pulse-agent-linux-arm64`
- `pulse-agent-darwin-amd64`
- `pulse-agent-darwin-arm64`

---

## ❓ Frequently Asked Questions

<details>
<summary><b>1. Do I need to register an account or pay for a cloud backend?</b></summary>
No. Pulse is 100% self-hosted, peer-to-peer, and local-first. Your metrics stream directly from your server to your Mac. No telemetry is ever uploaded to external cloud servers.
</details>

<details>
<summary><b>2. How is my connection secured?</b></summary>
Every agent automatically generates a cryptographic TLS certificate and a high-entropy authentication token on its first run. All HTTP and WebSocket traffic is encrypted over TLS. Credentials on macOS are safeguarded in the system's hardware-backed Keychain.
</details>

<details>
<summary><b>3. What ports do I need to open on my VPS?</b></summary>
Only one single port: **8443/tcp** (or whichever port you specify during configuration). Both HTTPS requests and WebSocket streams share this port.
</details>

<details>
<summary><b>4. Does the agent allow arbitrary command execution on my server?</b></summary>
No. The agent does not expose an arbitrary remote shell. Operations are constrained to explicitly whitelisted actions (such as `systemctl restart <unit>`, `docker restart <container>`, or database ping probes) that pass through strict safety verification.
</details>

<details>
<summary><b>5. How much RAM does the Linux agent consume?</b></summary>
The agent is compiled into a single static Go binary and typically uses less than **12 to 15 MB of RSS memory**, making it safe to run on even the smallest 512MB RAM VPS instances.
</details>

---

## 📄 License

Pulse is open-source software released under the **[MIT License](LICENSE)**.
