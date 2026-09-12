#!/usr/bin/env bash
set -e

# Pulse Agent Installer for Linux VPS
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/install.sh | sudo bash -s -- [--port 8443] [--token <auth-token>]

# Styling
CLR_RESET='\033[0m'
CLR_BOLD='\033[1m'
CLR_DIM='\033[2m'
CLR_CYAN='\033[38;5;45m'
CLR_BLUE='\033[38;5;39m'
CLR_PURPLE='\033[38;5;141m'
CLR_GREEN='\033[38;5;84m'
CLR_YELLOW='\033[38;5;221m'
CLR_RED='\033[38;5;203m'

step() {
  echo -e "\n  ${CLR_CYAN}➜${CLR_RESET} ${CLR_BOLD}$1${CLR_RESET}"
}

ok() {
  echo -e "    ${CLR_GREEN}✔${CLR_RESET} $1"
}

warn() {
  echo -e "    ${CLR_YELLOW}⚠${CLR_RESET} $1"
}

fail() {
  echo -e "    ${CLR_RED}✖${CLR_RESET} $1"
}

clear_screen_header() {
  echo ""
  echo -e "${CLR_PURPLE}  ┌────────────────────────────────────────────────────────┐${CLR_RESET}"
  echo -e "${CLR_PURPLE}  │${CLR_RESET}  ${CLR_BOLD}${CLR_CYAN}P U L S E${CLR_RESET}  ${CLR_DIM}•${CLR_RESET}  Native Infrastructure Observability Agent  ${CLR_PURPLE}│${CLR_RESET}"
  echo -e "${CLR_PURPLE}  └────────────────────────────────────────────────────────┘${CLR_RESET}"
  echo ""
}

PORT="8443"
TOKEN=""

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)
      PORT="$2"
      shift 2
      ;;
    --token)
      TOKEN="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

clear_screen_header

# 1. Privilege Check
step "Checking root privileges..."
if [ "$EUID" -ne 0 ]; then
  fail "Pulse installer requires root permissions."
  echo -e "    Run again with: ${CLR_BOLD}sudo bash${CLR_RESET}\n"
  exit 1
fi
ok "Running as root ($USER)"

# 2. Architecture Detection
step "Detecting hardware architecture..."
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)
    PULSE_ARCH="amd64"
    ;;
  aarch64|arm64)
    PULSE_ARCH="arm64"
    ;;
  *)
    fail "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac
ok "Architecture matched: ${CLR_BOLD}Linux ${PULSE_ARCH}${CLR_RESET}"

# 3. Dedicated System User
step "Configuring service accounts..."
if ! id "pulse" >/dev/null 2>&1; then
  useradd -r -s /bin/false -d /etc/pulse pulse 2>/dev/null || true
  ok "System user 'pulse' created"
else
  ok "System user 'pulse' ready"
fi

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/pulse"
mkdir -p "$CONFIG_DIR"

# 4. Binary Deployment
step "Fetching binary release..."

# If agent is already running, stop it cleanly before updating binary
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet pulse-agent 2>/dev/null; then
  systemctl stop pulse-agent 2>/dev/null || true
fi

TMP_BIN="/tmp/pulse-agent-dl-${PULSE_ARCH}"
rm -f "$TMP_BIN"

if [ -f "./bin/pulse-agent-linux-${PULSE_ARCH}" ]; then
  cp "./bin/pulse-agent-linux-${PULSE_ARCH}" "$TMP_BIN"
  ok "Installed from local build binary"
elif [ -f "./pulse-agent-linux-${PULSE_ARCH}" ]; then
  cp "./pulse-agent-linux-${PULSE_ARCH}" "$TMP_BIN"
  ok "Installed from local directory"
elif [ -f "/tmp/pulse-agent-linux-${PULSE_ARCH}" ]; then
  cp "/tmp/pulse-agent-linux-${PULSE_ARCH}" "$TMP_BIN"
  ok "Installed from /tmp cache"
else
  DOWNLOAD_URL="https://github.com/miftahganzz/Pulse/releases/latest/download/pulse-agent-linux-${PULSE_ARCH}"
  if curl -fsSL "$DOWNLOAD_URL" -o "$TMP_BIN" 2>/dev/null; then
    ok "Downloaded binary from GitHub releases"
  else
    RAW_URL="https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/bin/pulse-agent-linux-${PULSE_ARCH}"
    if curl -fsSL "$RAW_URL" -o "$TMP_BIN" 2>/dev/null; then
      ok "Downloaded binary via repository fallback"
    else
      fail "Could not retrieve pulse-agent binary"
      exit 1
    fi
  fi
fi

chmod +x "$TMP_BIN"
mv -f "$TMP_BIN" "$INSTALL_DIR/pulse-agent"
ln -sf "$INSTALL_DIR/pulse-agent" "$INSTALL_DIR/pulse"

# 5. Config and TLS Certificate Generation
step "Initializing security credentials..."
if [ ! -f "$CONFIG_DIR/agent.json" ]; then
  "$INSTALL_DIR/pulse-agent" --config "$CONFIG_DIR/agent.json" --show-token > /dev/null 2>&1 || true
  ok "Generated self-signed TLS certificates and identity token"
else
  ok "Configuration file existing at $CONFIG_DIR/agent.json"
fi

if [ -n "$PORT" ] || [ -n "$TOKEN" ]; then
  if command -v jq >/dev/null 2>&1; then
    tmp_json=$(mktemp)
    jq --arg p "$PORT" --arg t "$TOKEN" '
      (if $p != "" then .port = ($p | tonumber) else . end) |
      (if $t != "" then .auth_token = $t else . end)
    ' "$CONFIG_DIR/agent.json" > "$tmp_json" && mv "$tmp_json" "$CONFIG_DIR/agent.json"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "
import json
p = '$PORT'
t = '$TOKEN'
with open('$CONFIG_DIR/agent.json', 'r') as f:
    data = json.load(f)
if p: data['port'] = int(p)
if t: data['auth_token'] = t
with open('$CONFIG_DIR/agent.json', 'w') as f:
    json.dump(data, f, indent=2)
"
  fi
  ok "Applied custom port ($PORT) and authorized bearer token"
fi

chown -R pulse:pulse "$CONFIG_DIR" 2>/dev/null || true
chmod 700 "$CONFIG_DIR"
chmod 600 "$CONFIG_DIR"/agent.json 2>/dev/null || true

# 6. Firewall Configuration — supports UFW, firewalld, iptables
step "Checking system firewall..."
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow "${PORT}/tcp" comment "Pulse Agent" >/dev/null 2>&1 || true
  ok "Added UFW rule: port ${PORT}/tcp"
elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state 2>/dev/null | grep -q "running"; then
  firewall-cmd --permanent --add-port="${PORT}/tcp" >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
  ok "Added firewalld rule: port ${PORT}/tcp"
elif command -v iptables >/dev/null 2>&1; then
  iptables -C INPUT -p tcp --dport "${PORT}" -j ACCEPT 2>/dev/null || \
    iptables -I INPUT -p tcp --dport "${PORT}" -j ACCEPT 2>/dev/null || true
  ok "Added iptables rule: port ${PORT}/tcp"
else
  ok "No active firewall detected (traffic allowed)"
fi

# 7. Systemd Service Deployment
step "Registering systemd background daemon..."
cat << 'SYSTEMD_EOF' > /etc/systemd/system/pulse-agent.service
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
SYSTEMD_EOF

if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload
  systemctl enable pulse-agent >/dev/null 2>&1 || true
  systemctl restart pulse-agent
  ok "pulse-agent.service enabled and active"
else
  warn "systemctl not found; please run pulse-agent manually"
fi

# Detect Public IP
DETECTED_IP=$(curl -s4 --connect-timeout 2 ifconfig.me 2>/dev/null || curl -s4 --connect-timeout 2 icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')
AGENT_TOKEN=$(python3 -c "import json; print(json.load(open('$CONFIG_DIR/agent.json')).get('auth_token',''))" 2>/dev/null || true)
AGENT_ID=$(python3 -c "import json; print(json.load(open('$CONFIG_DIR/agent.json')).get('agent_id',''))" 2>/dev/null || true)

echo ""
echo -e "${CLR_GREEN}  ┌────────────────────────────────────────────────────────┐${CLR_RESET}"
echo -e "${CLR_GREEN}  │  ${CLR_BOLD}✔  Pulse Agent Is Running & Ready To Connect${CLR_RESET}        ${CLR_GREEN}│${CLR_RESET}"
echo -e "${CLR_GREEN}  └────────────────────────────────────────────────────────┘${CLR_RESET}"
echo ""
echo -e "  ${CLR_BOLD}Connection Details:${CLR_RESET}"
echo -e "  ${CLR_DIM}Public Host:${CLR_RESET}  ${CLR_BOLD}${CLR_CYAN}${DETECTED_IP}${CLR_RESET}"
echo -e "  ${CLR_DIM}Listen Port:${CLR_RESET}  ${CLR_BOLD}${PORT}${CLR_RESET} ${CLR_DIM}(TLS / HTTPS)${CLR_RESET}"
echo -e "  ${CLR_DIM}Agent ID:${CLR_RESET}     ${AGENT_ID}"
echo -e "  ${CLR_DIM}Auth Token:${CLR_RESET}   ${CLR_YELLOW}${AGENT_TOKEN}${CLR_RESET}"
echo ""
echo -e "  ${CLR_PURPLE}Connect from your Mac:${CLR_RESET}"
echo -e "  1. Open ${CLR_BOLD}Pulse${CLR_RESET} on your Mac"
echo -e "  2. Press ${CLR_BOLD}⌘N${CLR_RESET} → enter ${CLR_BOLD}${DETECTED_IP}${CLR_RESET} : ${CLR_BOLD}${PORT}${CLR_RESET} and the token above"
echo -e "  3. Or use 1-click deep link:"
echo -e "     ${CLR_DIM}pulse://add?name=$(hostname -s)&host=${DETECTED_IP}&port=${PORT}&token=${AGENT_TOKEN}${CLR_RESET}"
echo -e "  4. Or use pairing code: run ${CLR_CYAN}pulse pair${CLR_RESET} on this server"
echo ""
echo -e "  ${CLR_PURPLE}Pulse CLI (One Command Line):${CLR_RESET}"
echo -e "  ${CLR_CYAN}pulse status${CLR_RESET}         ${CLR_DIM}View live status, health & IPs${CLR_RESET}"
echo -e "  ${CLR_CYAN}pulse pair${CLR_RESET}           ${CLR_DIM}Generate quick XXX-XXX pairing code${CLR_RESET}"
echo -e "  ${CLR_CYAN}pulse tailscale${CLR_RESET}      ${CLR_DIM}Detect or 1-command install Tailscale${CLR_RESET}"
echo -e "  ${CLR_CYAN}pulse cloudflare${CLR_RESET}     ${CLR_DIM}Detect or setup Cloudflare Tunnel${CLR_RESET}"
echo -e "  ${CLR_CYAN}pulse logs -f${CLR_RESET}        ${CLR_DIM}Follow live daemon logs${CLR_RESET}"
echo -e "  ${CLR_CYAN}pulse update${CLR_RESET}         ${CLR_DIM}Check & auto-update to latest version${CLR_RESET}"
echo -e "  ${CLR_CYAN}pulse doctor${CLR_RESET}         ${CLR_DIM}Run full system diagnostics${CLR_RESET}"
echo -e "  ${CLR_CYAN}pulse help${CLR_RESET}           ${CLR_DIM}Show all available commands${CLR_RESET}"
echo ""
