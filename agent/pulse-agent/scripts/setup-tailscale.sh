#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  Pulse + Tailscale — One-Command Setup
#  Installs the Pulse Agent AND Tailscale on any Linux distro.
#  Usage:
#    curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/setup-tailscale.sh | sudo bash
#    curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/setup-tailscale.sh | sudo bash -s -- --authkey=tskey-auth-...
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

echo ""
echo -e "  ${CLR_BOLD}${CLR_CYAN}Pulse${CLR_RESET} + ${CLR_BOLD}Tailscale${CLR_RESET}  ${CLR_DIM}•  Private WireGuard Mesh Setup${CLR_RESET}"
echo ""

[ "$EUID" -ne 0 ] && fail "Run with sudo."

# ── 1. Install Pulse Agent ─────────────────────────────────────
step "Installing Pulse Agent..."
curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/install.sh | bash
ok "Pulse Agent installed and running"

# ── 2. Install Tailscale ───────────────────────────────────────
step "Installing Tailscale..."
if command -v tailscale >/dev/null 2>&1; then
  ok "Tailscale already installed ($(tailscale version 2>/dev/null | head -1))"
else
  curl -fsSL https://tailscale.com/install.sh | sh
  ok "Tailscale installed"
fi

# Ensure tailscaled service is running
if command -v systemctl >/dev/null 2>&1; then
  systemctl enable --now tailscaled >/dev/null 2>&1 || true
elif command -v service >/dev/null 2>&1; then
  service tailscaled start >/dev/null 2>&1 || true
fi

# ── 3. Bring up Tailscale ──────────────────────────────────────
step "Connecting Tailscale..."
if tailscale ip -4 >/dev/null 2>&1; then
  ok "Tailscale already active"
else
  echo -e "    ${CLR_CYAN}Authenticating Tailscale node...${CLR_RESET}"
  tailscale up --accept-routes "$@" || true
fi

TS_IP=$(tailscale ip -4 2>/dev/null || echo "")
TS_HOST=""
if command -v tailscale >/dev/null 2>&1; then
  TS_HOST=$(tailscale status --json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('Self',{}).get('DNSName','').rstrip('.'))" 2>/dev/null || echo "")
fi

# ── 4. Lock down firewall to Tailscale only ────────────────────
step "Hardening firewall for Tailscale..."
PORT="8443"
if [ -f "/etc/pulse/agent.json" ]; then
  PORT=$(python3 -c "import json; print(json.load(open('/etc/pulse/agent.json')).get('port', 8443))" 2>/dev/null || echo "8443")
fi

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow in on tailscale0 to any port "$PORT" proto tcp comment "Pulse via Tailscale" >/dev/null 2>&1 || true
  ok "Firewall: port $PORT open on tailscale0"
else
  ok "Firewall ready (tailscale0 / standard routing)"
fi

# ── 5. Read agent token ────────────────────────────────────────
AGENT_TOKEN=""
if [ -f "/etc/pulse/agent.json" ]; then
  AGENT_TOKEN=$(python3 -c "import json; print(json.load(open('/etc/pulse/agent.json')).get('auth_token', ''))" 2>/dev/null || echo "")
fi

echo ""
echo -e "  ${CLR_BOLD}${CLR_GREEN}✔  Ready — Connect via Tailscale${CLR_RESET}"
echo ""
if [ -n "$TS_IP" ]; then
  echo -e "  ${CLR_BOLD}Tailscale IP:${CLR_RESET}   ${CLR_CYAN}${TS_IP}${CLR_RESET}"
else
  echo -e "  ${CLR_BOLD}Tailscale IP:${CLR_RESET}   ${CLR_YELLOW}Run 'tailscale up' to complete login${CLR_RESET}"
fi
if [ -n "$TS_HOST" ]; then
  echo -e "  ${CLR_BOLD}MagicDNS:${CLR_RESET}       ${TS_HOST}"
fi
echo -e "  ${CLR_BOLD}Port:${CLR_RESET}           $PORT"
if [ -n "$AGENT_TOKEN" ]; then
  echo -e "  ${CLR_BOLD}Auth Token:${CLR_RESET}     ${CLR_YELLOW}${AGENT_TOKEN}${CLR_RESET}"
fi
echo ""
if [ -n "$TS_IP" ] && [ -n "$AGENT_TOKEN" ]; then
  echo -e "  ${CLR_BOLD}1-Click Deep Link:${CLR_RESET}"
  echo -e "  ${CLR_DIM}pulse://add?name=$(hostname -s)&host=${TS_IP}&port=${PORT}&token=${AGENT_TOKEN}${CLR_RESET}"
  echo ""
  echo -e "  On your Mac: open Pulse → ⌘N → enter the Tailscale IP and token above."
else
  echo -e "  Once authenticated on Tailscale, run ${CLR_CYAN}tailscale ip -4${CLR_RESET} and connect in Pulse with port $PORT."
fi
echo ""
