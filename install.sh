#!/usr/bin/env bash
set -euo pipefail
set -Eeuo pipefail

# Simple logging helpers (ASCII-only)
log()  { printf "\n[INFO] %s\n" "$*"; }
warn() { printf "\n[WARN] %s\n" "$*"; }
die()  { printf "\n[ERROR] %s\n" "$*" >&2; exit 1; }

# Ensure running as root
if [ "$(id -u)" -ne 0 ]; then
  die "This script must be run as root. Use sudo."
fi

# Basic OS detection
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  source /etc/os-release
else
  die "/etc/os-release not readable. Aborting."
fi

if [[ "${ID:-}" != "ubuntu" || ! "${VERSION_ID:-}" =~ ^22\. ]]; then
  warn "Detected OS is not Ubuntu 22.xx. Proceed at your own risk."
fi

UBU_CODENAME="${VERSION_CODENAME:-jammy}"
ARCH="$(dpkg --print-architecture)"

# Default user to add to docker group (can be overridden by env var DOCKER_USER)
USER_NAME="${DOCKER_USER:-gphost}"

log "Updating apt cache"
apt-get update -y || warn "apt-get update failed (continuing)"

log "Removing possible old/ conflicting Docker packages"
apt-get remove -y docker.io docker-doc docker-compose docker-compose-plugin podman-docker containerd runc || true

log "Installing base packages"
apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https lxcfs || die "Failed to install base packages"

log "Enabling and starting system docker package (if present)"
systemctl enable --now docker 2>/dev/null || warn "systemctl enable --now docker failed (maybe package not installed yet)"

log "Creating apt keyrings directory"
install -m 0755 -d /etc/apt/keyrings

if [ ! -s /etc/apt/keyrings/docker.gpg ]; then
  log "Fetching Docker official GPG key"
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    || die "Failed to fetch Docker GPG key"
fi
chmod a+r /etc/apt/keyrings/docker.gpg || true

log "Adding Docker apt repository for ${ARCH}/${UBU_CODENAME}"
cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${UBU_CODENAME} stable
EOF

log "Updating apt cache after adding Docker repo"
apt-get update -y || die "apt-get update failed after adding Docker repo"

log "Installing Docker Engine and components"
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
  || die "Failed to install Docker Engine and components"

log "Writing recommended Docker daemon configuration to /etc/docker/daemon.json"
install -m 0755 -d /etc/docker
cat >/etc/docker/daemon.json <<'JSON'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "exec-opts": ["native.cgroupdriver=systemd"],
  "storage-driver": "overlay2",
  "features": { "buildkit": true },
  "live-restore": true
}
JSON

log "Reloading systemd and restarting docker"
systemctl daemon-reload
systemctl enable --now docker || warn "Failed to enable/start docker service"

if systemctl is-active --quiet docker; then
  log "[OK] Docker service is active"
else
  warn "[WARN] Docker service is not active; check 'systemctl status docker' for details"
fi

# Optional: containerd tuning
if [ ! -s /etc/containerd/config.toml ]; then
  if command -v containerd >/dev/null 2>&1; then
    log "Generating default containerd config at /etc/containerd/config.toml"
    containerd config default >/etc/containerd/config.toml || warn "containerd config default failed"
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml || true
    systemctl restart containerd || warn "Failed to restart containerd"
  else
    warn "containerd binary not found; skipping containerd config generation"
  fi
fi

# Add user to docker group if exists
if id -u "$USER_NAME" >/dev/null 2>&1; then
  log "Adding user '${USER_NAME}' to 'docker' group"
  if ! getent group docker >/dev/null 2>&1; then
    groupadd docker || warn "Could not create 'docker' group"
  fi
  usermod -aG docker "$USER_NAME" || warn "Failed to add ${USER_NAME} to docker group"
  log "[ INFO ] User '${USER_NAME}' added to docker group (logout/login required to apply)"
else
  warn "User '${USER_NAME}' does not exist; skipping group add"
fi

# UFW compatibility (if ufw is installed and active)
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  log "UFW is active — adjusting default forward policy and sysctl for docker networking"
  sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw || true
  if grep -q '^#\?net\/ipv4\/ip_forward' /etc/ufw/sysctl.conf 2>/dev/null; then
    sed -i 's/^#\?net\/ipv4\/ip_forward=.*/net\/ipv4\/ip_forward=1/' /etc/ufw/sysctl.conf || true
  else
    echo 'net/ipv4/ip_forward=1' >> /etc/ufw/sysctl.conf
  fi
  ufw reload || warn "ufw reload failed"
fi

# Quick smoke test (non-fatal)
log "Quick smoke test: pulling and running hello-world container"
if docker run --rm hello-world >/dev/null 2>&1; then
  log "[ OK ] hello-world ran successfully"
else
  warn "[ WARN ] hello-world did not run. This might be a network or registry issue. Try: docker run --rm hello-world"
fi

# Print summary
log "Summary:"
printf " - Docker version: " && docker --version || true
printf " - Daemon config: /etc/docker/daemon.json\n"
printf " - Buildx and Compose plugin enabled (if installed)\n"
printf " - User added to docker group: %s (if user existed)\n" "$USER_NAME"
printf "\n[ OK ] Installation and configuration steps finished.\n"
log "You may need to log out and back in for group changes to take effect."
clear
# ─────────────────────────────────────────────────────────────
# Branding
BRAND="Gp TEAM"
REPO_URL="https://github.com/gpteamofficial/vps-deploy-bot"
APP_DIR="/opt/vps-deploy-bot"
SERVICE_NAME="vps-bot"
PYTHON_BIN="/usr/bin/python3"
PIP_BIN="/usr/bin/pip3"
# ─────────────────────────────────────────────────────────────

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# sudo helper
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo -e "${RED}[!] Please run as root or install sudo.${NC}"
    exit 1
  fi
fi

clear
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════╗"
echo "║      VPS Deploy Bot Installer  🚀            ║"
echo "║         Produced by ${BRAND}                 ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"
sleep 1

# Spinner
spinner() {
  local pid=$!
  local delay=0.1
  local spin='|/-\'
  while kill -0 $pid 2>/dev/null; do
    for i in $(seq 0 3); do
      printf " [%c] " "${spin:$i:1}"
      sleep $delay
      printf "\r"
    done
  done
}

run_cmd() {
  local title="$1"; shift
  local cmd="$*"
  echo -ne "${YELLOW}[~] ${title}...${NC}\r"
  (bash -lc "$cmd") >/dev/null 2>&1 &
  spinner
  wait $! || { echo -e "\n${RED}[x] ${title} failed${NC}"; exit 1; }
  echo -e "${GREEN}[OK] ${title}${NC}"
}

# OS check (Debian/Ubuntu)
if ! command -v apt >/dev/null 2>&1; then
  echo -e "${RED}[!] This installer supports Debian/Ubuntu (apt) only.${NC}"
  exit 1
fi

# Network check
if ! ping -c1 -W2 github.com >/dev/null 2>&1; then
  echo -e "${YELLOW}[!] Network seems down or GitHub unreachable. Continuing may fail...${NC}"
fi

# ─────────────────────────────────────────────────────────────
# Installation Steps
# ─────────────────────────────────────────────────────────────
run_cmd "Updating system"                "$SUDO apt update -y && $SUDO apt upgrade -y"
run_cmd "Installing dependencies"        "$SUDO apt install -y curl git nano ca-certificates openssh-server docker.io python3 python3-pip"

# Enable/Start Docker
run_cmd "Enabling Docker service"        "$SUDO systemctl enable docker"
run_cmd "Restarting Docker"              "$SUDO systemctl restart docker"

# Add current user to docker group (optional quality-of-life)
if getent group docker >/dev/null 2>&1; then
  if [ -n "${SUDO_USER:-}" ]; then
    run_cmd "Adding ${SUDO_USER} to docker group" "$SUDO usermod -aG docker $SUDO_USER"
  fi
fi

# Clone / Update repo
if [ ! -d "$APP_DIR" ]; then
  run_cmd "Cloning repository (${REPO_URL})" "$SUDO git clone \"$REPO_URL\" \"$APP_DIR\""
else
  run_cmd "Updating repository" "$SUDO bash -lc 'cd \"$APP_DIR\" && git pull --ff-only'"
fi

# Python deps
if [ -f "$APP_DIR/requirements.txt" ]; then
  run_cmd "Installing Python requirements" "$SUDO $PIP_BIN install --upgrade pip && $SUDO $PIP_BIN install -r \"$APP_DIR/requirements.txt\""
else
  run_cmd "Installing Python modules" "$SUDO $PIP_BIN install --upgrade pip && $SUDO $PIP_BIN install discord.py docker psutil"
fi

# Build default images if Dockerfiles exist
cd "$APP_DIR"
[ -f Dockerfile.debian ] && run_cmd "Building Debian Docker image"  "$SUDO docker build -t debian-vps -f Dockerfile.debian ."
[ -f Dockerfile.ubuntu ] && run_cmd "Building Ubuntu Docker image"  "$SUDO docker build -t ubuntu-vps -f Dockerfile.ubuntu ."

# ─────────────────────────────────────────────────────────────
# User Config
# ─────────────────────────────────────────────────────────────
echo -e "${CYAN}\n[?] Enter your Discord Bot Token:${NC}"
read -r BOT_TOKEN
if [ -z "$BOT_TOKEN" ]; then
  echo -e "${RED}[!] Token cannot be empty.${NC}"; exit 1
fi

echo -e "${CYAN}[?] Enter Logs Channel ID (numbers only):${NC}"
read -r LOGS_CHANNEL
if ! [[ "$LOGS_CHANNEL" =~ ^[0-9]+$ ]]; then
  echo -e "${RED}[!] Logs Channel ID must be numeric.${NC}"; exit 1
fi

echo -e "${CYAN}[?] Enter Admin Role ID (numbers only):${NC}"
read -r ADMIN_ROLE
if ! [[ "$ADMIN_ROLE" =~ ^[0-9]+$ ]]; then
  echo -e "${RED}[!] Admin Role ID must be numeric.${NC}"; exit 1
fi

echo -e "${CYAN}[?] (Optional) Set RAM limit (e.g., 2g). Press Enter for default 2g:${NC}"
read -r RAM_LIMIT
RAM_LIMIT=${RAM_LIMIT:-2g}

echo -e "${CYAN}[?] (Optional) Max servers per user. Press Enter for default 12:${NC}"
read -r SERVER_LIMIT
SERVER_LIMIT=${SERVER_LIMIT:-12}

# Try to configure bot.py (safe-ish sed)
BOT_FILE="$APP_DIR/bot.py"
if [ -f "$BOT_FILE" ]; then
  run_cmd "Configuring bot.py" \
  "$SUDO sed -i \
    -e \"s|^TOKEN *= *.*|TOKEN = '${BOT_TOKEN}'|\" \
    -e \"s|^RAM_LIMIT *= *.*|RAM_LIMIT = '${RAM_LIMIT}'|\" \
    -e \"s|^SERVER_LIMIT *= *.*|SERVER_LIMIT = ${SERVER_LIMIT}|\" \
    -e \"s|^LOGS_CHANNEL_ID *= *.*|LOGS_CHANNEL_ID = ${LOGS_CHANNEL}|\" \
    -e \"s|^ADMIN_ROLE_ID *= *.*|ADMIN_ROLE_ID = ${ADMIN_ROLE}|\" \
    \"$BOT_FILE\""
else
  echo -e "${YELLOW}[i] bot.py not found. Skipping inline config. Configure manually later.${NC}"
fi

# Create .env (optional for future use)
ENV_FILE="$APP_DIR/.env"
cat <<EOF | $SUDO tee "$ENV_FILE" >/dev/null
# Generated by ${BRAND} installer
TOKEN=${BOT_TOKEN}
LOGS_CHANNEL_ID=${LOGS_CHANNEL}
ADMIN_ROLE_ID=${ADMIN_ROLE}
RAM_LIMIT=${RAM_LIMIT}
SERVER_LIMIT=${SERVER_LIMIT}
EOF
echo -e "${GREEN}[OK] Wrote $ENV_FILE${NC}"

# ─────────────────────────────────────────────────────────────
# Service Setup (systemd)
# ─────────────────────────────────────────────────────────────
echo -e "${CYAN}\n[?] Run the bot as a systemd service? (y/n)${NC}"
read -r RUN_SERVICE

if [[ "$RUN_SERVICE" =~ ^[Yy]$ ]]; then
  SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
  cat <<SERVICE | $SUDO tee "$SERVICE_FILE" >/dev/null
[Unit]
Description=VPS Deploy Discord Bot (${BRAND})
After=network.target docker.service
Requires=docker.service

[Service]
WorkingDirectory=${APP_DIR}
ExecStart=${PYTHON_BIN} ${APP_DIR}/bot.py
Restart=always
RestartSec=3
Environment=PYTHONUNBUFFERED=1

# If you rely on .env, you can load it via EnvironmentFile (optional)
# EnvironmentFile=${APP_DIR}/.env

[Install]
WantedBy=multi-user.target
SERVICE

  run_cmd "Enabling service" "$SUDO systemctl daemon-reload && $SUDO systemctl enable ${SERVICE_NAME}"
  run_cmd "Starting service"  "$SUDO systemctl start ${SERVICE_NAME}"

  echo -e "${GREEN}[✓] Service '${SERVICE_NAME}' created and started!${NC}"
  echo -e "${YELLOW}• View logs: ${NC}journalctl -u ${SERVICE_NAME} -f"
  echo -e "${YELLOW}• Status:    ${NC}systemctl status ${SERVICE_NAME}"
else
  echo -e "${YELLOW}[i] To run manually:${NC}"
  echo -e "   cd ${APP_DIR} && ${PYTHON_BIN} bot.py"
fi

echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════╗"
echo "║  Installation Complete! 🚀                   ║"
echo "║  Produced with ❤️ by ${BRAND}                ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"
log "You may need to log out and back in for group changes to take effect."
