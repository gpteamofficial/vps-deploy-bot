#!/usr/bin/env bash
set -euo pipefail

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
