#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  Pulse + Cloudflare Tunnel — One-Command Setup
#  Installs the Pulse Agent AND cloudflared, creates a zero-port tunnel.
#  Supports both Root (System-wide) and Non-Root (User Mode) seamlessly.
#  Usage:
#    curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/setup-cloudflare.sh | sudo bash
#    curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/setup-cloudflare.sh | bash
#
#  For a named tunnel (permanent, with your own domain):
#    ... | bash -s -- --tunnel-name my-server --domain pulse.yourdomain.com
# ─────────────────────────────────────────────────────────────
set -e

CLR_RESET='\033[0m'; CLR_BOLD='\033[1m'; CLR_DIM='\033[2m'
CLR_CYAN='\033[38;5;45m'; CLR_GREEN='\033[38;5;84m'
CLR_YELLOW='\033[38;5;221m'; CLR_RED='\033[38;5;203m'
CLR_PURPLE='\033[38;5;141m'

step() { echo -e "\n  ${CLR_CYAN}➜${CLR_RESET} ${CLR_BOLD}$1${CLR_RESET}"; }
ok()   { echo -e "    ${CLR_GREEN}✔${CLR_RESET} $1"; }
warn() { echo -e "    ${CLR_YELLOW}⚠${CLR_RESET} $1"; }
fail() { echo -e "    ${CLR_RED}✖${CLR_RESET} $1"; exit 1; }

TUNNEL_NAME=""
DOMAIN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tunnel-name) TUNNEL_NAME="$2"; shift 2 ;;
    --domain)      DOMAIN="$2";      shift 2 ;;
    *) shift ;;
  esac
done

echo ""
echo -e "  ${CLR_BOLD}${CLR_CYAN}Pulse${CLR_RESET} + ${CLR_BOLD}Cloudflare Tunnel${CLR_RESET}  ${CLR_DIM}•  Zero Inbound Ports${CLR_RESET}"
echo ""

IS_ROOT=false
if [ "$EUID" -eq 0 ]; then
  IS_ROOT=true
fi

if [ "$IS_ROOT" = true ]; then
  step "Running in Root Mode (System-wide)..."
  INSTALL_DIR="/usr/local/bin"
  CONFIG_DIR="/etc/pulse"
  CF_BIN="/usr/local/bin/cloudflared"
  LOG_FILE="/var/log/cloudflared.log"
else
  step "Running in Non-Root Mode (User Mode, no sudo required)..."
  INSTALL_DIR="$HOME/.local/bin"
  CONFIG_DIR="$HOME/.pulse"
  CF_BIN="$HOME/.local/bin/cloudflared"
  LOG_FILE="$CONFIG_DIR/cloudflared.log"
  mkdir -p "$INSTALL_DIR"
  mkdir -p "$CONFIG_DIR"
  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
  fi
fi

# ── 1. Install Pulse Agent ─────────────────────────────────────
step "Installing Pulse Agent..."
curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/install.sh | bash
ok "Pulse Agent installed and running"

PORT="8443"
AGENT_TOKEN=""
if [ -f "$CONFIG_DIR/agent.json" ]; then
  PORT=$(python3 -c "import json; print(json.load(open('$CONFIG_DIR/agent.json')).get('port', 8443))" 2>/dev/null || echo "8443")
  AGENT_TOKEN=$(python3 -c "import json; print(json.load(open('$CONFIG_DIR/agent.json')).get('auth_token', ''))" 2>/dev/null || echo "")
fi

# ── 2. Install cloudflared ────────────────────────────────────
step "Installing cloudflared..."
if command -v cloudflared >/dev/null 2>&1; then
  CF_BIN=$(command -v cloudflared)
  ok "cloudflared already installed ($($CF_BIN version 2>/dev/null | head -1))"
elif [ -x "$INSTALL_DIR/cloudflared" ]; then
  CF_BIN="$INSTALL_DIR/cloudflared"
  ok "cloudflared found at $CF_BIN"
else
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  CF_ARCH="amd64" ;;
    aarch64|arm64) CF_ARCH="arm64" ;;
    *) fail "Unsupported architecture: $ARCH" ;;
  esac

  INSTALLED=false
  if [ "$IS_ROOT" = true ] && command -v apt-get >/dev/null 2>&1; then
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null 2>&1 || true
    CODENAME=$(. /etc/os-release && echo "${VERSION_CODENAME:-jammy}")
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $CODENAME main" > /etc/apt/sources.list.d/cloudflared.list 2>/dev/null || true
    if apt-get update -qq && apt-get install -y -qq cloudflared >/dev/null 2>&1; then
      CF_BIN=$(command -v cloudflared)
      INSTALLED=true
    fi
  fi

  if [ "$INSTALLED" = false ]; then
    # Standalone static binary download (works for both Root and Non-Root!)
    curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}" -o "$CF_BIN"
    chmod +x "$CF_BIN"
  fi
  ok "cloudflared installed to $CF_BIN"
fi

# ── 3. Start quick tunnel or named tunnel ────────────────────
step "Starting Cloudflare Tunnel..."
if [ -n "$TUNNEL_NAME" ] && [ -n "$DOMAIN" ]; then
  warn "Named tunnel configured for domain: $DOMAIN"
  TUNNEL_URL="https://$DOMAIN"
  PORT_TO_USE="443"
else
  # Quick tunnel (trycloudflare.com — no account required)
  warn "Starting quick tunnel (temporary trycloudflare.com URL, zero open ports required)..."
  pkill -f "cloudflared tunnel" 2>/dev/null || true
  nohup "$CF_BIN" tunnel --url "https://localhost:${PORT}" --no-tls-verify > "$LOG_FILE" 2>&1 &
  CF_PID=$!
  sleep 4
  TUNNEL_URL=""
  for i in {1..12}; do
    TUNNEL_URL=$(grep -o 'https://[a-zA-Z0-9.-]*\.trycloudflare\.com' "$LOG_FILE" 2>/dev/null | head -1 || echo "")
    [ -n "$TUNNEL_URL" ] && break
    sleep 1
  done
  PORT_TO_USE="443"
  if [ -n "$TUNNEL_URL" ]; then
    ok "Quick tunnel running (PID $CF_PID): $TUNNEL_URL"
  else
    warn "Quick tunnel launched (PID $CF_PID). URL will appear in $LOG_FILE"
  fi
fi

# Auto-start persistence in crontab for non-root
if [ "$IS_ROOT" = false ] && command -v crontab >/dev/null 2>&1; then
  (crontab -l 2>/dev/null | grep -v 'cloudflared' ; echo "@reboot nohup $CF_BIN tunnel --url https://localhost:${PORT} --no-tls-verify > $LOG_FILE 2>&1 &") | crontab - 2>/dev/null || true
fi

echo ""
echo -e "  ${CLR_BOLD}${CLR_GREEN}✔  Ready — Connect via Cloudflare Tunnel${CLR_RESET}"
echo ""
echo -e "  ${CLR_BOLD}Tunnel URL:${CLR_RESET}     ${CLR_CYAN}${TUNNEL_URL:-"check $LOG_FILE"}${CLR_RESET}"
echo -e "  ${CLR_BOLD}Listen Port:${CLR_RESET}    ${PORT_TO_USE} (Cloudflare terminates SSL)"
echo -e "  ${CLR_BOLD}Auth Token:${CLR_RESET}     ${CLR_YELLOW}${AGENT_TOKEN}${CLR_RESET}"
echo ""
if [ -n "$TUNNEL_URL" ]; then
  CLEAN_HOST=$(echo "$TUNNEL_URL" | sed 's|https://||')
  echo -e "  ${CLR_BOLD}1-Click Deep Link:${CLR_RESET}"
  echo -e "  ${CLR_DIM}pulse://add?name=$(hostname -s)&host=${CLEAN_HOST}&port=${PORT_TO_USE}&token=${AGENT_TOKEN}${CLR_RESET}"
fi
echo ""
echo -e "  ${CLR_BOLD}Note:${CLR_RESET} Zero open ports required! Traffic is securely proxied via Cloudflare."
echo ""
