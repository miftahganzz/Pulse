<div align="center">

<img src="docs/images/pulse-icon.png" alt="Pulse App Icon" width="128" height="128" style="margin-bottom: 8px;" />

# Pulse

### Native, peer-to-peer infrastructure observability and remediation for macOS and Linux.

[![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue?logo=apple&style=flat-square)](https://apple.com)
[![Architecture](https://img.shields.io/badge/Architecture-Apple%20Silicon%20%7C%20Intel-success?style=flat-square)](#)
[![Go Agent](https://img.shields.io/badge/Go%20Agent-1.22+-00ADD8?logo=go&style=flat-square)](https://go.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)

Pulse connects your Mac directly to your servers over encrypted WebSockets and mutual TLS. No cloud accounts, no third-party telemetry, and no heavy Java or Python dependencies on your host machines.

[Quick Start](#quick-start) • [Installation Methods](#installation-methods) • [Features](#features) • [Diagnostics](#diagnostics) • [Architecture](#architecture) • [FAQ](#frequently-asked-questions)

</div>

---

## Overview

Most infrastructure monitoring tools force a choice between two bad options: expensive SaaS dashboards that send your server data to third parties, or clunky self-hosted setups that consume half a gigabyte of memory just to show CPU percentages.

Pulse takes a different approach:
- **Direct connection**: Your Mac opens an encrypted link directly to your server. No intermediary relay, no SaaS middleman.
- **Low memory footprint**: The Go daemon uses under 15 MB of RSS memory on Linux. It runs comfortably on 512 MB VPS instances.
- **Controlled operations**: Inspect Docker logs, restart crashed processes, or trigger safe remediation rules directly from your menu bar.

---

## Quick Start

### 1. Download Pulse for Mac

Prebuilt universal binaries run natively on both Apple Silicon (M1/M2/M3/M4) and Intel Macs:

- **[Download Pulse-0.8.0.dmg](https://github.com/miftahganzz/Pulse/releases/latest/download/Pulse-0.8.0.dmg)** (Drag-and-Drop installer)
- **[Download Pulse-0.8.0.pkg](https://github.com/miftahganzz/Pulse/releases/latest/download/Pulse-0.8.0.pkg)** (Standard macOS package)

Open the `.dmg`, drag **Pulse** to `/Applications`, and open it.

### 2. Connect Your First Server

Press `⌘N` in Pulse, then pick one of the two pairing flows below.

---

## Installation Methods

### Method 1: 1-Line Automated Command

The fastest way to install the daemon on a fresh Linux server:

```bash
curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/install.sh | sudo bash -s -- --port 8443 --token <YOUR_TOKEN>
```

The script:
1. Detects your CPU architecture (`x86_64` or `arm64`) and pulls the static binary.
2. Creates an unprivileged `pulse` system account.
3. Generates TLS certificates and configures permissions (`chmod 600`).
4. Adds a rule for port `8443/tcp` if UFW is enabled.
5. Starts the background systemd service (`pulse-agent.service`).
6. Displays the server's public IP address for quick entry into Pulse.

---

### Method 2: 6-Digit Pairing Code

If you prefer not to pass tokens over command-line arguments:

1. Install the agent on your server:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/install.sh | sudo bash
   ```
2. Request a pairing code on your server terminal:
   ```bash
   pulse-agent pair
   ```
   Output:
   ```text
   ┌────────────────────────────────────────────────────────┐
   │  Pulse 6-Digit Pairing Mode                            │
   │  Pairing Code: 653557                                  │
   │  Expires in:   10 minutes                              │
   └────────────────────────────────────────────────────────┘
   ```
3. In Pulse on your Mac, select **6-Digit Pair Code**, enter your server's public IP and the code `653557`, then click **Verify & Pair**.

---

## Features

### Menu Bar and Inspector
- **Live Menu Bar widget**: Shows real-time CPU, RAM, and alert badges without occupying dock space.
- **Process manager**: Sort processes by CPU or memory usage; send `SIGTERM` or `SIGKILL` directly from the UI.
- **Hardware telemetry**: Load averages, disk write spikes, network throughput, and memory pressure breakdown.

### Container and Service Discovery
- **Docker engine integration**: Track container status, inspect memory limits, and stream live stdout/stderr logs.
- **Supported providers**: Built-in modules for Systemd services, PM2 instances, PostgreSQL, Redis, MySQL, MongoDB, Nginx, Caddy, Cloudflare Tunnels, and TCP/HTTP health probes.
- **Automatic discovery**: Discovers active databases and web servers on startup with one-click monitor setup.

### Root-Cause Correlation
- **Dependency graphs**: Map relationships between your infrastructure layers (for example: `Frontend` depends on `API`, which depends on `PostgreSQL`).
- **Cascade suppression**: When a physical host goes down, child alerts for 20 running containers collapse into a single root-cause notification.
- **Flapping mitigation**: Suppresses alert storms when a service rapidly cycles between up and down states.

### Remediation Safety Gates
- **Dry-run previews**: Review command side-effects before restarting services.
- **Circuit breaker**: Automatically halts remediation rules if a command fails three consecutive times.
- **Maintenance windows**: Mute alert triggers during scheduled software upgrades.

---

## Diagnostics

To troubleshoot connectivity, port bindings, or systemd status directly on your server:

```bash
pulse-agent doctor
```

Sample output:

```text
┌────────────────────────────────────────────────────────┐
│  Pulse Agent System Doctor (v0.8.0)                    │
└────────────────────────────────────────────────────────┘
 [✔] Pulse Agent Version        : v0.8.0
 [✔] Configuration File         : Found at /etc/pulse/agent.json (Agent ID: pulse_05ae3c)
 [✔] TLS Certificate & Key      : Cert: /etc/pulse/cert.pem, Key: /etc/pulse/key.pem
 [✔] Systemd Service            : pulse-agent.service is active and running
 [✔] Port 8443 Binding          : pulse-agent is actively accepting TCP connections on port 8443
 [✔] HTTPS & Token Auth         : Endpoint responds with TLS and enforces token authentication
 [✔] Firewall (UFW)             : Port 8443 is explicitly allowed in UFW
```

---

## Architecture

```text
┌────────────────────────────────────────────────────────┐
│                    macOS (Pulse.app)                   │
│                                                        │
│  [MenuBar Extra]  [Fleet Dashboard]  [Remediation UI]  │
│  [Keychain Store] [Incident Graph]   [Telemetry Store] │
└───────────────────────────┬────────────────────────────┘
                            │
                            │ HTTPS / TLS (Mutual Identity / Pairing)
                            │ WSS (Encrypted Binary Telemetry Stream)
                            ▼
┌────────────────────────────────────────────────────────┐
│                Linux Host (pulse-agent)                │
│                                                        │
│  [Pairing Manager] [System Collector] [Action Engine]  │
│  [Docker Client]   [Service Probes]   [Provider Reg]   │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
         Host Systemd, Containers, Databases, & Logs
```

---

## Frequently Asked Questions

**Is any metric data sent to external cloud servers?**  
No. Pulse uses a direct peer-to-peer model. All metrics stream straight from your Linux host to your Mac.

**How does authentication work?**  
Each server generates a 32-character authentication token on first initialization. Requests require a bearer token header, and tokens are stored in the macOS hardware-backed Keychain.

**Which ports need to be open on my server?**  
Only port `8443/tcp` (or whichever custom port you configure). Both HTTPS requests and WebSocket streams share this single port.

**Can the agent run arbitrary shell scripts?**  
No. The agent does not expose an open shell. Actions are restricted to pre-defined operations (such as `systemctl restart <unit>` or `docker restart <container>`) that pass through explicit safety checks.

**What are the minimum system requirements for the agent?**  
Linux kernel 3.10+, systemd, and at least 32 MB of free RAM. Binary size is roughly 7 MB.

---

## License

Pulse is open-source software licensed under the [MIT License](LICENSE).
