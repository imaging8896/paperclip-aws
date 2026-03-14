#!/usr/bin/env bash
# =============================================================================
# Paperclip Docker bootstrap script for Amazon Linux 2023
# Runs once on first boot via EC2 User Data.
#
# Uses the official Dockerfile and docker-compose.yml from the Paperclip repo,
# running the production server + a dedicated PostgreSQL container.
#
# After ~10-15 minutes the Paperclip UI will be available at:
#   http://localhost:3100  (forward the port with: ssh -N -L 3100:localhost:3100 ec2-user@<elastic-ip>)
# =============================================================================
set -euo pipefail

APP_USER="ec2-user"
APP_HOME="/home/${APP_USER}"
APP_DIR="${APP_HOME}/paperclip"
LOG="/var/log/paperclip-bootstrap.log"

exec > >(tee -a "$LOG") 2>&1
echo "=== Paperclip Docker bootstrap started at $(date) ==="

# ── Add 2 GB swap (Docker image builds are memory-intensive) ──────────────
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# ── System updates & Docker ────────────────────────────────────────────────
dnf update -y
dnf install -y git curl openssl

# Install Docker CE from Docker's official RHEL repository.
# Amazon Linux 2023 is RHEL 9-compatible, so Docker's RHEL repo is the
# recommended source for Docker CE + the docker-compose-plugin package.
dnf install -y dnf-plugins-core
dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl enable --now docker
usermod -aG docker "${APP_USER}"

# ── Clone Paperclip ──────────────────────────────────────────────────────
if [ ! -d "${APP_DIR}" ]; then
  sudo -u "${APP_USER}" git clone \
    https://github.com/paperclipai/paperclip.git \
    "${APP_DIR}"
else
  echo "Paperclip repo already present — skipping clone."
fi

# ── Generate secrets & configuration ─────────────────────────────────────
BETTER_AUTH_SECRET=$(openssl rand -hex 32)

cat > "${APP_DIR}/.env" <<EOF
BETTER_AUTH_SECRET=${BETTER_AUTH_SECRET}
PAPERCLIP_PUBLIC_URL=http://localhost:3100
EOF

chmod 600 "${APP_DIR}/.env"
chown "${APP_USER}:${APP_USER}" "${APP_DIR}/.env"

# ── Build & start containers ──────────────────────────────────────────────
# docker compose build + up runs as root here since the Docker socket is root-owned
# before the ec2-user group membership takes effect in this session.
cd "${APP_DIR}"
docker compose up --build -d

# ── systemd service ───────────────────────────────────────────────────────
# Ensures containers restart after instance stop/start.
cat > /etc/systemd/system/paperclip.service <<'UNIT'
[Unit]
Description=Paperclip AI Agent Orchestrator (Docker Compose)
Documentation=https://github.com/paperclipai/paperclip
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=root
WorkingDirectory=/home/ec2-user/paperclip
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
StandardOutput=journal
StandardError=journal
SyslogIdentifier=paperclip

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable paperclip

echo "=== Paperclip Docker bootstrap finished at $(date) ==="
echo ""
echo "Container status:"
docker compose ps
echo ""
echo "Tail the server log with:  cd ~/paperclip && docker compose logs -f server"
