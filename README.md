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

Prebuilt styled DMG installers with native Finder drag-and-drop:

- **[Pulse-1.0.4-arm64.dmg](https://github.com/miftahganzz/Pulse/releases/latest/download/Pulse-1.0.4-arm64.dmg)** — Apple Silicon Macs (M1 / M2 / M3 / M4)
- **[Pulse-1.0.4-x86_64.dmg](https://github.com/miftahganzz/Pulse/releases/latest/download/Pulse-1.0.4-x86_64.dmg)** — Intel 64-bit Macs
- **[Pulse-1.0.4-Universal.dmg](https://github.com/miftahganzz/Pulse/releases/latest/download/Pulse-1.0.4-Universal.dmg)** — Universal 2 (runs on all Macs)
- **[Pulse-1.0.4.dmg](https://github.com/miftahganzz/Pulse/releases/latest/download/Pulse-1.0.4.dmg)** — Default Universal installer

Open the `.dmg`, drag **Pulse** to `/Applications`, and open it.

<div align="center" style="margin: 16px 0;">
  <img src="docs/images/dmg-installer-preview.png" alt="Pulse DMG Installer Preview" width="580" style="border-radius: 8px; box-shadow: 0 4px 20px rgba(0,0,0,0.25);" />
</div>

### 2. Connect Your First Server

Press `⌘N` in Pulse, then pick one of the two pairing flows below.

---

## Installation Methods

### Quick Setup — One Command, Pick Your Method

| Connection Method | One-Command Setup (Root) | One-Command Setup (Non-Root User) |
|---|---|---|
| Direct IP / LAN | `curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/install.sh \| sudo bash` | `curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/install.sh \| bash` |
| Tailscale (zero open ports) | `curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/setup-tailscale.sh \| sudo bash` | `curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/setup-tailscale.sh \| bash` |
| Cloudflare Tunnel (zero open ports) | `curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/setup-cloudflare.sh \| sudo bash` | `curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/setup-cloudflare.sh \| bash` |

All scripts auto-detect CPU architecture (x86_64 / arm64) and distro: Debian, Ubuntu, RHEL, CentOS, Fedora, Arch, Alpine, openSUSE, Void Linux, and any systemd-based distro. Non-root mode installs to `~/.local/bin` and requires zero `sudo` permissions.

---

### Method 1: 1-Line Automated Command

The fastest way to install the daemon on a Linux server.

**Option 1: Root / System-wide (Default):**
```bash
curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/install.sh | sudo bash -s -- --port 8443 --token <YOUR_TOKEN>
```

**Option 2: Non-Root / User Mode (No `sudo` required):**
```bash
curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/install.sh | bash -s -- --port 8443 --token <YOUR_TOKEN>
```

The script:
1. Detects your CPU architecture (`x86_64` or `arm64`) and pulls the static binary.
2. **Root mode**: installs to `/usr/local/bin`, creates unprivileged `pulse` account, `/etc/pulse/agent.json`, and registers system systemd service.
3. **Non-root mode**: installs to `~/.local/bin`, configures `~/.pulse/agent.json`, and registers user-level systemd service (`systemctl --user`) or crontab `@reboot` autostart.
4. Generates TLS certificates and secures permissions (`chmod 600`).
5. Configures the firewall: UFW, firewalld, or iptables (when running as root).
6. Starts the background service (`pulse-agent`).
7. Prints the server's public IP, auth token, and a ready-to-use `pulse://` deep link.

**Supported distros**: Debian, Ubuntu, RHEL, CentOS, Fedora, Arch Linux, Alpine Linux, openSUSE, Void Linux — and any Linux distro.

---

### Method 2: XXX-XXX Pairing Code

If you prefer not to pass tokens over command-line arguments:

1. Install the agent on your server (as root or non-root):
   ```bash
   curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/install.sh | bash
   ```
2. Request a pairing code on your server terminal:
   ```bash
   pulse pair
   ```
   Output:
   ```text
   Pair Code Ready:  653-557
   Server Host:      ubuntu-srv
   Port:             8443
   Validity:         10 minutes (Single-use)
   ```
3. In Pulse on your Mac, select **XXX-XXX Pair Code**, enter your server's public IP and the code `653-557`, then click **Verify & Pair**.

---

## Unified Pulse CLI (`pulse`)

Every server running Pulse includes the unified `pulse` command (symlinked to `/usr/local/bin/pulse` or `~/.local/bin/pulse`). It provides a fast, intuitive terminal interface for managing the agent daemon, private mesh networking, pairing, logs, and upgrades:

```bash
pulse                     # Quick health status card & endpoints
pulse status              # Detailed daemon state, IP addresses & pairing code
pulse pair                # Generate temporary XXX-XXX pairing code (valid 10 mins)
pulse tailscale           # Detect Tailscale or auto-install mesh network
sudo pulse tailscale install  # 1-command Tailscale install & firewall lock down
pulse cloudflare          # Detect cloudflared tunnel & show ingress config
pulse logs -f             # Stream live daemon logs (system or user journal)
pulse update              # Auto-update binary from GitHub releases in place
pulse doctor              # Run full system, TLS, and port diagnostics
pulse restart             # Restart background daemon (root or user mode)
pulse stop / pulse start  # Stop or start the agent daemon
pulse uninstall           # Cleanly remove agent, systemd units, and configs
```

---

## Connecting Over Private Networks (Zero Open Ports)

If you do not want to expose port `8443` to the public internet, Pulse natively supports zero-trust and private mesh setups.

### Option A: Tailscale (Private WireGuard Mesh — Recommended)

Tailscale provides an encrypted, peer-to-peer WireGuard mesh without opening any inbound ports on your server firewall or router.

#### 1-Command Automated Setup
- **Root (sudo)**: `curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/setup-tailscale.sh | sudo bash`
- **Non-Root**: `curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/setup-tailscale.sh | bash`

#### Manual Steps:

1. **Install Tailscale on your server**:
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up
   ```
2. **Find your server's Tailscale IPv4 address**:
   ```bash
   tailscale ip -4
   # Example: 100.115.82.45
   ```
   *(Alternatively, use the server's MagicDNS name, e.g. `ubuntu-prod.tailnet-xyz.ts.net`).*
3. **Lock down server firewall (Optional but Recommended)**:
   Restrict agent access so only machines on your Tailscale network can reach port `8443`:
   ```bash
   # Allow traffic from Tailscale interface only
   sudo ufw allow in on tailscale0 to any port 8443 proto tcp
   # Block all public incoming traffic to 8443
   sudo ufw deny 8443/tcp
   ```
4. **Connect from your Mac**:
   Ensure your Mac has the Tailscale client running on the same tailnet.
   - In Pulse, click `⌘N` (Add Server).
   - Enter **Host**: `100.115.82.45` (or MagicDNS hostname) and **Port**: `8443`.
   - Paste your agent token and click **Connect Server**.
   - *Pro-tip*: You can also use a **1-click deep link**:
     ```text
     pulse://add?name=My-Tailscale-Node&host=100.115.82.45&port=8443&token=<YOUR_TOKEN>
     ```

---

### Option B: Cloudflare Tunnel (`cloudflared` — Zero Inbound Ports)

Cloudflare Tunnels create an outbound-only reverse tunnel from your VPS to Cloudflare's global edge network. This allows you to connect Pulse using a custom domain (e.g. `pulse.yourdomain.com`) or temporary `trycloudflare.com` URL over standard HTTPS/WSS port `443`, with zero incoming ports open on your firewall. It also works seamlessly behind NAT, CGNAT, or dynamic home IPs.

#### 1-Command Automated Setup (Zero Root, Zero Open Ports)
- **Root (sudo)**: `curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/setup-cloudflare.sh | sudo bash`
- **Non-Root**: `curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/setup-cloudflare.sh | bash`

*(Non-root mode downloads static `cloudflared` to `~/.local/bin`, starts user-mode tunnel, and registers crontab `@reboot` persistence with zero `sudo` required)*.

#### Manual Steps:

1. **Install `cloudflared` on your Linux host**:
   ```bash
   # Debian / Ubuntu:
   curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
   echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared jammy main' | sudo tee /etc/apt/sources.list.d/cloudflared.list
   sudo apt update && sudo apt install -y cloudflared
   ```
2. **Set up the tunnel in Cloudflare Zero Trust**:
   - Go to the **Cloudflare Zero Trust Dashboard** → **Networks** → **Tunnels** → **Create Tunnel**.
   - Select **Cloudflared** and run the provided connector command on your VPS.
   - Under the **Public Hostname** tab, configure:
     - **Subdomain**: `pulse`
     - **Domain**: `yourdomain.com` (your Cloudflare managed domain)
     - **Service Type**: `HTTPS`
     - **URL**: `127.0.0.1:8443`
   - In **Additional application settings** → **TLS**:
     - Enable **"No TLS Verify"** = `ON` (Pulse Agent uses self-signed local TLS; Cloudflare edge terminates valid public SSL to your Mac).
   - Click **Save Hostname**.
3. **Install & Run Pulse Agent**:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/install.sh | sudo bash -s -- --port 8443 --token <YOUR_TOKEN>
   ```
   *(Note: You do NOT need to open port 8443 in your firewall—cloudflared talks to it locally on `127.0.0.1`)*.
4. **Connect from Pulse on your Mac**:
   - In Pulse, press `⌘N` (Add Server).
   - Enter **Host**: `pulse.yourdomain.com`
   - Enter **Port**: `443`
   - Paste your agent token and click **Connect Server**.
   - *Pro-tip*: Use a **1-click deep link**:
     ```text
     pulse://add?name=Cloudflare-Node&host=pulse.yourdomain.com&port=443&token=<YOUR_TOKEN>
     ```
   - Cloudflare terminates public SSL on port 443 and streams encrypted WebSockets directly into Pulse.

---

### 1-Click Server Onboarding (`pulse://` Deep Linking)

Pulse registers the `pulse://` URL scheme on macOS. You can generate one-click onboarding links for your team or internal documentation:

```text
pulse://add?name=<SERVER_NAME>&host=<HOST_OR_DOMAIN>&port=<PORT>&token=<TOKEN>
```

When clicked in Safari, Slack, or terminal (`open "pulse://..."`), Pulse automatically pops open the Add Server sheet with the host, port, and security token pre-filled.

---

## Features

### Live Log Viewer & Streaming (v1.0.0)
- **Sub-second WebSocket log streaming**: Stream live logs directly to your Mac without SSH sessions.
- **Systemd journal integration**: Live tailing of unit services (`journalctl -u <unit> -f`) with custom unit selection.
- **Docker stdout/stderr**: Real-time streaming from active containers with ISO timestamp formatting.
- **Interactive console controls**: Instant keyword regex search, pause/resume auto-scroll, and 1-click clipboard export.

### Outbound Alerts: Telegram Integration (v1.0.0)
- **Zero-proxy notifications**: Direct push alerts sent straight to your Telegram from your server daemon or Mac app.
- **Simple 3-step setup**: Add Bot Token from `@BotFather`, enter recipient user/chat IDs, and test with one click.
- **Multi-chat broadcast**: Route critical server incidents simultaneously to personal admin IDs and team ops channels.
- **Intelligent throttling**: Built-in cooldowns prevent notification storms when services flap.

### Disk Space Analyzer & Safe Cleaners (v1.0.0)
- **"Where Did My Storage Go?"**: Immediate breakdown of `/var/log`, `/var/lib/docker`, `/var/cache`, `/tmp`, and journal storage.
- **1-Click Safe Cleaners**:
  - `Vacuum Journals`: Safely removes systemd journal logs older than 3 days.
  - `Docker Prune`: Cleans stopped containers, dangling images, and build caches without touching running services.
  - `Clean APT Cache`: Frees gigabytes from `/var/cache/apt/archives` on Debian/Ubuntu.

### Maintenance Runbooks (v1.0.0 — ⌘R)
- **Pre-approved operational tasks**: Trigger essential sysadmin routines directly from macOS.
  - Reload Webserver (`systemctl reload nginx / caddy`) without dropping connections.
  - Flush DNS resolver cache (`systemd-resolved` / `nscd`).
  - Check available OS security updates without installing.
  - Safely drop memory pagecache (`echo 3 > /proc/sys/vm/drop_caches`).
- **Live Terminal Console**: Review realtime stdout/stderr output and command exit codes.

### Process Network & Disk I/O (v1.0.0)
- **Per-process bandwidth**: Live disk read/write throughput (KB/s or MB/s) parsed directly from Linux `/proc/[pid]/io`.
- **Open socket auditing**: Displays active network file descriptors per process to spot connection leaks early.

### Menu Bar and Inspector
- **Live Menu Bar widget**: Shows real-time CPU, RAM, and alert badges without occupying dock space.
- **Menu Bar metrics ticker**: Optionally display live `CPU xx%  RAM xx%` metrics in macOS status bar.
- **Process manager**: Sort processes by CPU, memory, or disk I/O; send `SIGTERM` or `SIGKILL` directly from the UI.
- **Hardware telemetry**: Load averages, disk write spikes, network throughput, and memory pressure breakdown.

### Container and Service Discovery
- **Docker engine integration**: Track container status, inspect memory limits, and stream live stdout/stderr logs.
- **Supported providers**: Built-in modules for Systemd services, PM2 instances, PostgreSQL, Redis, MySQL, MongoDB, Nginx, Caddy, Cloudflare Tunnels, and TCP/HTTP health probes.
- **Automatic discovery**: Discovers active databases and web servers on startup with one-click monitor setup.

### Root-Cause Correlation
- **Dependency graphs**: Map relationships between your infrastructure layers (for example: `Frontend` depends on `API`, which depends on `PostgreSQL`).
- **Cascade suppression**: When a physical host goes down, child alerts for 20 running containers collapse into a single root-cause notification.
- **Flapping mitigation**: Suppresses alert storms when a service rapidly cycles between up and down states.

### Security Hardening & Zero-Trust Architecture
- **Brute-Force & Port Scanning Defense**: Built-in sliding-window rate limiter on the agent automatically blocks abusive IP addresses (HTTP 429) for 15 minutes after repeated failed authentication or pairing attempts.
- **Pairing Lockout Protection**: Pairing sessions are immediately revoked and destroyed after 5 failed PIN attempts.
- **Cross-Site WebSocket Hijacking (CSWSH) Defense**: Strict origin inspection prevents malicious browser origins from hijacking open WebSocket sessions.
- **Security Headers & Strict File Permissions**: Injects HSTS, CSP, and X-Content-Type headers; `pulse doctor` audits private keys (`0600`) and configuration permissions.
- **Tamper-Resistant Action Audit Trail**: Linux daemon records every executed runbook, container command, and action to an append-only `$PULSE_DIR/audit.log`.
- **TOFU TLS Certificate Pinning**: macOS app securely stores and validates server TLS certificates via Keychain on first connect; alerts instantly if MITM or certificate tampering occurs.
- **Biometric Security Gate (Touch ID)**: Protect high-impact server operations (rebooting, container deletion, process kill) behind Touch ID or Apple Watch authentication.
- **Clipboard Token Auto-Clearing**: Automatically clears copied bearer tokens and pairing codes from macOS clipboard after 60 seconds.
- **Socket & Port Inventory**: Real-time auditing of listening TCP/UDP sockets with process names, PIDs, and binding addresses.
- **Exposure Classification**: Distinguishes between `Public` (`0.0.0.0`), `Private` (`100.x.y.z` Tailscale / RFC 1918), and `Localhost` (`127.0.0.1`).
- **Sensitive Port Alerts**: Instantly flags exposed databases (Redis, Postgres, MySQL, MongoDB, Docker API) with actionable remediation steps.
- **Firewall Inspector**: Reports host firewall status (UFW, iptables, pf) and default incoming policy directly on your dashboard.

### Pro-Grade macOS Experience
- **Native Sparkle 2 Auto-Updates**: Seamless background update checks and one-click in-app upgrades.
- **Launch at Login (`SMAppService`)**: Deep integration with macOS 13+ native ServiceManagement.
- **Custom URL Scheme (`pulse://`)**: Friction-free server onboarding and deep routing from internal documentation.
- **Pixel-perfect Apple HIG design**: Native macOS typography, SF Symbols, multi-level shadows, and responsive split views.

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
Pulse Agent System Doctor (v1.0.4)
---------------------------------------------
 [✔] Pulse Agent Version        : v1.0.4
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
Each server generates a secure authentication token (stored in macOS Keychain). Pairing uses a temporary XXX-XXX code that expires in 10 minutes. Requests require a bearer token header, and tokens are stored in the macOS hardware-backed Keychain.

**Which ports need to be open on my server?**  
Only port `8443/tcp` (or whichever custom port you configure). Both HTTPS requests and WebSocket streams share this single port.

**Can the agent run arbitrary shell scripts?**  
No. The agent does not expose an open shell. Actions are restricted to pre-defined operations (such as `systemctl restart <unit>` or `docker restart <container>`) that pass through explicit safety checks.

**What are the minimum system requirements for the agent?**  
Linux kernel 3.10+, systemd, and at least 32 MB of free RAM. Binary size is roughly 7 MB.

---

## License

Pulse is open-source software licensed under the [MIT License](LICENSE).
