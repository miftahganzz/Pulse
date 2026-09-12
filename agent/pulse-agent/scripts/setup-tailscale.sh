#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  Pulse + Tailscale — One-Command Setup
#  Installs the Pulse Agent AND Tailscale on any Linux distro.
#  Usage:
#    curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/setup-tailscale.sh | sudo bash
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
echo -e "${CLR_PURPLE}  ┌──────────────────────────────────────────────────────────┐${CLR_RESET}"
echo -e "${CLR_PURPLE}  │${CLR_RESET}  ${CLR_BOLD}${CLR_CYAN}PULSE${CLR_RESET} + ${CLR_BOLD}TAILSCALE${CLR_RESET}  •  Private WireGuard Mesh Setup      ${CLR_PURPLE}│${CLR_RESET}"
echo -e "${CLR_PURPLE}  └──────────────────────────────────────────────────────────┘${CLR_RESET}"
echo ""

[ "$EUID" -ne 0 ] && fail "Run with sudo."

# ── 1. Install Pulse Agent ─────────────────────────────────────
step "Installing Pulse Agent..."
curl -fsSL https://raw.githubusercontent.com/miftahganzz/Pulse/main/agent/pulse-agent/scripts/install.sh | bash
ok "Pulse Agent installed and running"

# ── 2. Install Tailscale ───────────────────────────────────────
step "Installing Tailscale..."
if command -v tailscale >/dev/null 2>&1; then
  ok "Tailscale already installed ($(tailscale version | head -1))"
else
  curl -fsSL https://tailscale.com/install.sh | sh
  ok "Tailscale installed"
fi

# ── 3. Bring up Tailscale ──────────────────────────────────────
step "Bringing Tailscale up..."
tailscale up --accept-routes 2>/dev/null || true
ok "Tailscale connected"

TS_IP=$(tailscale ip -4 2>/dev/null || echo "")
TS_HOST=$(tailscale status --json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(list(d.get('Peer',{d['Self']['PublicKey']:d['Self']}).values())[0].get('DNSName','').rstrip('.'))" 2>/dev/null || echo "")

# ── 4. Lock down firewall to Tailscale only ────────────────────
step "Hardening firewall (allow port 8443 on tailscale0 only)..."
PORT=$(python3 -c "import json; print(json.load(open('/etc/pulse/agent.json'))['port'])" 2>/dev/null || echo "8443")
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow in on tailscale0 to any port "$PORT" proto tcp comment "Pulse via Tailscale" >/dev/null 2>&1 || true
  ufw deny "$PORT/tcp" >/dev/null 2>&1 || true
  ok "Firewall: port $PORT open on tailscale0, blocked on public interface"
else
  warn "UFW not active — consider restricting port $PORT to Tailscale only"
fi

# ── 5. Read agent token ────────────────────────────────────────
AGENT_TOKEN=$(python3 -c "import json; print(json.load(open('/etc/pulse/agent.json'))['auth_token'])" 2>/dev/null || echo "<token>")

echo ""
echo -e "${CLR_GREEN}  ┌──────────────────────────────────────────────────────────┐${CLR_RESET}"
echo -e "${CLR_GREEN}  │  ${CLR_BOLD}✔  Ready — Connect via Tailscale${CLR_RESET}                      ${CLR_GREEN}│${CLR_RESET}"
echo -e "${CLR_GREEN}  └──────────────────────────────────────────────────────────┘${CLR_RESET}"
echo ""
echo -e "  ${CLR_BOLD}Tailscale IP:${CLR_RESET}   ${CLR_CYAN}${TS_IP:-"run: tailscale ip -4"}${CLR_RESET}"
echo -e "  ${CLR_BOLD}Hostname:${CLR_RESET}       ${TS_HOST:-"see: tailscale status"}"
echo -e "  ${CLR_BOLD}Port:${CLR_RESET}           $PORT"
echo -e "  ${CLR_BOLD}Auth Token:${CLR_RESET}     ${CLR_YELLOW}${AGENT_TOKEN}${CLR_RESET}"
echo ""
echo -e "  ${CLR_BOLD}1-Click Deep Link:${CLR_RESET}"
echo -e "  ${CLR_DIM}pulse://add?name=$(hostname)&host=${TS_IP}&port=${PORT}&token=${AGENT_TOKEN}${CLR_RESET}"
echo ""
echo -e "  On your Mac: open Pulse → ⌘N → enter the Tailscale IP, port, and token above."
echo ""
