#!/usr/bin/env bash
set -e

# Pulse Agent One-Line Installer & Configurator for Linux VPS
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/install.sh | sudo bash -s -- [--port 8443] [--token <auth-token>]

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

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

echo -e "${BOLD}${BLUE}======================================${NC}"
echo -e "${BOLD}${BLUE}       Pulse Agent Installer          ${NC}"
echo -e "${BOLD}${BLUE}======================================${NC}"

# 1. Check Root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Please run this installer as root (or with sudo).${NC}"
  exit 1
fi

# 2. Detect Architecture
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)
    PULSE_ARCH="amd64"
    ;;
  aarch64|arm64)
    PULSE_ARCH="arm64"
    ;;
  *)
    echo -e "${RED}Unsupported architecture: $ARCH${NC}"
    exit 1
    ;;
esac

echo -e "Detected Architecture: ${BOLD}${PULSE_ARCH}${NC}"

# 3. Create dedicated system user 'pulse' if not exists
if ! id "pulse" >/dev/null 2>&1; then
  echo -e "Creating system user: ${BOLD}pulse${NC}..."
  useradd -r -s /bin/false -d /etc/pulse pulse 2>/dev/null || true
fi

# 4. Setup directories
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/pulse"
mkdir -p "$CONFIG_DIR"

# 5. Check if binary already local or download from GitHub
if [ -f "./bin/pulse-agent-linux-${PULSE_ARCH}" ]; then
  echo -e "Installing from local binary..."
  cp "./bin/pulse-agent-linux-${PULSE_ARCH}" "$INSTALL_DIR/pulse-agent"
elif [ -f "./pulse-agent-linux-${PULSE_ARCH}" ]; then
  echo -e "Installing from local binary..."
  cp "./pulse-agent-linux-${PULSE_ARCH}" "$INSTALL_DIR/pulse-agent"
elif [ -f "/tmp/pulse-agent-linux-${PULSE_ARCH}" ]; then
  echo -e "Installing from /tmp binary..."
  cp "/tmp/pulse-agent-linux-${PULSE_ARCH}" "$INSTALL_DIR/pulse-agent"
else
  echo -e "Downloading Pulse Agent binary for ${PULSE_ARCH} from GitHub..."
  DOWNLOAD_URL="https://github.com/miftahganzz/Pulse/releases/latest/download/pulse-agent-linux-${PULSE_ARCH}"
  if ! curl -fsSL "$DOWNLOAD_URL" -o "$INSTALL_DIR/pulse-agent"; then
    echo -e "${YELLOW}Latest release download failed. Attempting repository raw download fallback...${NC}"
    RAW_URL="https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/bin/pulse-agent-linux-${PULSE_ARCH}"
    curl -fsSL "$RAW_URL" -o "$INSTALL_DIR/pulse-agent" || {
      echo -e "${RED}Error: Failed to download pulse-agent binary.${NC}"
      exit 1
    }
  fi
fi

chmod +x "$INSTALL_DIR/pulse-agent"

# 6. Initialize config & TLS certificates
if [ ! -f "$CONFIG_DIR/agent.json" ]; then
  echo -e "Initializing agent configuration..."
  "$INSTALL_DIR/pulse-agent" --config "$CONFIG_DIR/agent.json" --show-token > /dev/null 2>&1 || true
fi

# Update Port and Auth Token if supplied by 1-line command
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
fi

# Ensure correct permissions
chown -R pulse:pulse "$CONFIG_DIR" 2>/dev/null || true
chmod 700 "$CONFIG_DIR"
chmod 600 "$CONFIG_DIR"/agent.json 2>/dev/null || true

# 7. Configure Firewall if UFW is active
if command -v ufw >/dev/null 2>&1; then
  if ufw status | grep -q "Status: active"; then
    echo -e "Opening firewall port ${PORT}/tcp..."
    ufw allow "${PORT}/tcp" comment "Pulse Agent" >/dev/null 2>&1 || true
  fi
fi

# 8. Install Systemd Service
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
  systemctl enable pulse-agent
  systemctl restart pulse-agent
fi

# 9. Verify with Doctor
echo ""
echo -e "${BOLD}${GREEN}✔ Pulse Agent successfully installed and running!${NC}"
echo -e "--------------------------------------------------"
if [ -f "$INSTALL_DIR/pulse-agent" ]; then
  "$INSTALL_DIR/pulse-agent" --config "$CONFIG_DIR/agent.json" --show-token
fi
echo -e "Port:        ${PORT} (HTTPS / TLS)"
echo -e "--------------------------------------------------"
echo ""
echo -e "${BOLD}Steps to connect with Pulse Mac App:${NC}"
echo "1. Open Pulse on your Mac"
echo "2. In the Add Server window, choose:"
echo "   - '1-Line Command' (Automatic pairing), OR"
echo "   - '6-Digit Pair Code' (Run 'pulse-agent pair' in terminal)"
echo "3. Click 'Connect' -> Done!"
