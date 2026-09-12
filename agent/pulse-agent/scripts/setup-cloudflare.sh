#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  Pulse + Cloudflare Tunnel — One-Command Setup
#  Installs the Pulse Agent AND cloudflared, creates a quick tunnel.
#  Usage:
#    curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/setup-cloudflare.sh | sudo bash
#
#  For a named tunnel (permanent, with your own domain):
#    ... | sudo bash -s -- --tunnel-name my-server --domain pulse.yourdomain.com
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

[ "$EUID" -ne 0 ] && fail "Run with sudo."

# ── 1. Install Pulse Agent ─────────────────────────────────────
step "Installing Pulse Agent..."
curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/install.sh | bash
ok "Pulse Agent installed"

PORT=$(python3 -c "import json; print(json.load(open('/etc/pulse/agent.json'))['port'])" 2>/dev/null || echo "8443")
AGENT_TOKEN=$(python3 -c "import json; print(json.load(open('/etc/pulse/agent.json'))['auth_token'])" 2>/dev/null || echo "<token>")

# ── 2. Install cloudflared ────────────────────────────────────
step "Installing cloudflared..."
if command -v cloudflared >/dev/null 2>&1; then
  ok "cloudflared already installed ($(cloudflared version 2>/dev/null | head -1))"
else
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  CF_ARCH="amd64" ;;
    aarch64|arm64) CF_ARCH="arm64" ;;
    *) fail "Unsupported architecture: $ARCH" ;;
  esac

  # Detect package manager and install
  if command -v apt-get >/dev/null 2>&1; then
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
      | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
    CODENAME=$(. /etc/os-release && echo "${VERSION_CODENAME:-jammy}")
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $CODENAME main" \
      > /etc/apt/sources.list.d/cloudflared.list
    apt-get update -qq && apt-get install -y -qq cloudflared
  elif command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
    curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}.rpm" \
      -o /tmp/cloudflared.rpm
    (command -v dnf >/dev/null 2>&1 && dnf install -y /tmp/cloudflared.rpm) || \
    yum install -y /tmp/cloudflared.rpm
  else
    # Universal binary fallback
    curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}" \
      -o /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared
  fi
  ok "cloudflared installed"
fi

# ── 3. Start quick tunnel or named tunnel ────────────────────
step "Starting Cloudflare Tunnel..."
if [ -n "$TUNNEL_NAME" ] && [ -n "$DOMAIN" ]; then
  warn "Named tunnel requires 'cloudflared tunnel login' first — see CF Zero Trust dashboard."
  warn "Then run: cloudflared tunnel create $TUNNEL_NAME && cloudflared tunnel route dns $TUNNEL_NAME $DOMAIN"
  warn "Then start: cloudflared tunnel run $TUNNEL_NAME"
  TUNNEL_URL="https://$DOMAIN"
  PORT_TO_USE="443"
else
  # Quick tunnel (trycloudflare.com — no account required)
  warn "Starting quick tunnel (temporary URL, no login required)..."
  warn "For a permanent URL, re-run with: --tunnel-name <name> --domain <your.domain.com>"
  nohup cloudflared tunnel --url "https://localhost:${PORT}" \
    --no-tls-verify \
    > /tmp/cloudflared.log 2>&1 &
  CF_PID=$!
  sleep 4
  TUNNEL_URL=$(grep -o 'https://[a-zA-Z0-9.-]*\.trycloudflare\.com' /tmp/cloudflared.log 2>/dev/null | head -1 || echo "")
  PORT_TO_USE="443"
  ok "Quick tunnel running (PID $CF_PID)"
fi

echo ""
echo -e "  ${CLR_BOLD}${CLR_GREEN}✔  Ready — Connect via Cloudflare Tunnel${CLR_RESET}"
echo ""
echo -e "  ${CLR_BOLD}Tunnel URL:${CLR_RESET}     ${CLR_CYAN}${TUNNEL_URL:-"check /tmp/cloudflared.log"}${CLR_RESET}"
echo -e "  ${CLR_BOLD}Port:${CLR_RESET}           ${PORT_TO_USE} (Cloudflare terminates SSL)"
echo -e "  ${CLR_BOLD}Auth Token:${CLR_RESET}     ${CLR_YELLOW}${AGENT_TOKEN}${CLR_RESET}"
echo ""
if [ -n "$TUNNEL_URL" ]; then
  CLEAN_HOST=$(echo "$TUNNEL_URL" | sed 's|https://||')
  echo -e "  ${CLR_BOLD}1-Click Deep Link:${CLR_RESET}"
  echo -e "  ${CLR_DIM}pulse://add?name=$(hostname)&host=${CLEAN_HOST}&port=${PORT_TO_USE}&token=${AGENT_TOKEN}${CLR_RESET}"
fi
echo ""
echo -e "  ${CLR_BOLD}Note:${CLR_RESET} Quick tunnels reset on restart. Use --tunnel-name for permanent setup."
echo ""
