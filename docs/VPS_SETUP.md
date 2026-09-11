# Pulse Agent Setup Guide for Linux VPS (Ubuntu / Debian / AlmaLinux / CentOS)

The Pulse Agent (`pulse-agent`) is engineered as a **single static binary** that is exceptionally lightweight (< 15 MB RAM) with zero external dependencies (no Node.js, Python, or external runtimes required).

---

## Quick Summary (TL;DR)

1. Upload or install the `pulse-agent` binary on your VPS.
2. Place it into `/usr/local/bin/pulse-agent`.
3. Run it as a `systemd` service.
4. Connect using either the **1-Line Command** or the **6-Digit Pairing Code** in the **Pulse Mac App**.

---

## Method 1 — 1-Line Automated Installer (Recommended)

From your Mac app's **Add Server** dialog (`⌘N`), copy the generated single line command and run it on your VPS terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/pulse-monitoring/pulse/main/install.sh | sudo bash -s -- --port 8443 --token <your-token>
```

This automated installer:
- Creates a dedicated `pulse` system user.
- Installs the binary to `/usr/local/bin/pulse-agent`.
- Sets up `/etc/pulse/agent.json` and generates local self-signed TLS certificates.
- Automatically permits port `8443/tcp` if UFW firewall is enabled.
- Registers and starts the `systemd` service (`pulse-agent.service`).
- Pre-injects the authentication token so your Mac app connects immediately.

---

## Method 2 — 6-Digit Pairing Code (No Long Token Pasting)

If `pulse-agent` is already running or installed on your VPS:

1. In your VPS terminal, execute:
   ```bash
   pulse-agent pair
   ```
2. The agent outputs a single-use 6-digit code valid for 10 minutes:
   ```text
   ================================================================
   🔗 Pulse 6-Digit Pairing Mode
   ================================================================
   Pairing Code: 207906
   Server Host:  my-vps.example.com
   Server Port:  8443
   Expires in:   10 minutes
   ================================================================
   ```
3. In **Pulse.app** on macOS, select **"6-Digit Pair Code"**, enter your server IP and `207906`, then click **"Verify & Pair"**.
4. The client securely claims the authentication token and saves it to Keychain.

---

## Diagnostics & Troubleshooting (`pulse-agent doctor`)

To inspect agent service status, port bindings, TLS certificates, and firewall availability at any time:

```bash
pulse-agent doctor
```

Example diagnostic report:
```text
================================================================
🩺 Pulse Agent System Doctor (v0.8.0)
================================================================
[✔] Pulse Agent Version        : v0.8.0
[✔] Configuration File         : Found at /etc/pulse/agent.json (Agent ID: pulse_xxx)
[✔] TLS Certificate & Key      : Cert: /etc/pulse/cert.pem, Key: /etc/pulse/key.pem
[✔] Systemd Service            : pulse-agent.service is active and running
[✔] Port 8443 Binding          : pulse-agent is actively accepting TCP connections on port 8443
[✔] HTTPS & Token Auth         : Endpoint responds with TLS and enforces token authentication
[✔] Firewall (UFW)             : Port 8443 is explicitly allowed in UFW
================================================================
```

---

## Manual Step-by-Step Setup

If you prefer full manual configuration:

### 1. Upload Binary to VPS
Precompiled binaries for x86_64 and ARM64 are located in `agent/pulse-agent/bin/`:
```bash
# Intel / AMD VPS:
scp agent/pulse-agent/bin/pulse-agent-linux-amd64 root@IP_OF_VPS:/usr/local/bin/pulse-agent
chmod +x /usr/local/bin/pulse-agent
```

### 2. Generate Initial Credentials & Configuration
```bash
mkdir -p /etc/pulse
/usr/local/bin/pulse-agent --config /etc/pulse/agent.json --show-token
```

### 3. Create Systemd Service File
Create `/etc/systemd/system/pulse-agent.service`:
```ini
[Unit]
Description=Pulse Monitoring Agent
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/pulse-agent --config /etc/pulse/agent.json
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
```

### 4. Enable and Start the Service
```bash
systemctl daemon-reload
systemctl enable pulse-agent
systemctl start pulse-agent

# Inspect service status:
systemctl status pulse-agent
```

### 5. Open Firewall Port 8443
Ensure port `8443` (HTTPS/TLS) accepts inbound connections from your Mac:
- **UFW (Ubuntu/Debian)**:
  ```bash
  ufw allow 8443/tcp comment "Pulse Agent"
  ```
- **Firewalld (AlmaLinux/CentOS)**:
  ```bash
  firewall-cmd --permanent --add-port=8443/tcp
  firewall-cmd --reload
  ```
- **Cloud Security Group (AWS EC2 / DigitalOcean Droplets / GCP)**:
  Ensure your Inbound Rules allow TCP port `8443`.
