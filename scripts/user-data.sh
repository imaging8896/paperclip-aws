#!/usr/bin/env bash
# =============================================================================
# Paperclip bootstrap script for Amazon Linux 2023 ARM64 (t4g.micro)
# Runs once on first boot via EC2 User Data.
#
# After ~3-5 minutes the Paperclip UI will be available at:
#   http://localhost:3100  (forward the port with: ssh -N -L 3100:localhost:3100 ec2-user@<elastic-ip>)
# =============================================================================
set -euo pipefail

APP_USER="ec2-user"
APP_HOME="/home/${APP_USER}"
APP_DIR="${APP_HOME}/paperclip"
LOG="/var/log/paperclip-bootstrap.log"
PNPM_HOME="${APP_HOME}/.local/share/pnpm"

exec > >(tee -a "$LOG") 2>&1
echo "=== Paperclip bootstrap started at $(date) ==="

# ── Add 1 GB swap (helps during the npm/pnpm build on t4g.micro) ──────────
if [ ! -f /swapfile ]; then
  fallocate -l 1G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# ── System updates & prerequisites ────────────────────────────────────────
dnf update -y
dnf install -y git curl unzip tar

# ── Node.js 20 via NodeSource ──────────────────────────────────────────────
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
dnf install -y nodejs

node --version
npm --version

# ── pnpm (version pinned to match Paperclip's packageManager field) ────────
# Paperclip requires pnpm@9.15.4
export PNPM_HOME="${PNPM_HOME}"
export PATH="${PNPM_HOME}:${PATH}"

sudo -u "${APP_USER}" env HOME="${APP_HOME}" \
  npm install -g "pnpm@9.15.4"

# Verify
sudo -u "${APP_USER}" env HOME="${APP_HOME}" \
  PATH="${APP_HOME}/.local/share/pnpm:${PATH}" \
  pnpm --version

# ── Clone Paperclip ──────────────────────────────────────────────────────
if [ ! -d "${APP_DIR}" ]; then
  sudo -u "${APP_USER}" git clone \
    https://github.com/paperclipai/paperclip.git \
    "${APP_DIR}"
else
  echo "Paperclip repo already present — skipping clone."
fi

# ── Install dependencies & build ─────────────────────────────────────────
cd "${APP_DIR}"

sudo -u "${APP_USER}" env \
  HOME="${APP_HOME}" \
  PATH="${APP_HOME}/.local/share/pnpm:${PATH}" \
  pnpm install --frozen-lockfile

sudo -u "${APP_USER}" env \
  HOME="${APP_HOME}" \
  PATH="${APP_HOME}/.local/share/pnpm:${PATH}" \
  pnpm build

# Apply DB migrations once before starting the service
sudo -u "${APP_USER}" env \
  HOME="${APP_HOME}" \
  PATH="${APP_HOME}/.local/share/pnpm:${PATH}" \
  PAPERCLIP_MIGRATION_PROMPT=never \
  pnpm db:migrate || echo "db:migrate returned non-zero (may be first run — continuing)"

# ── systemd service ──────────────────────────────────────────────────────
# Use `pnpm dev:once` which starts API + UI without file-watching.
cat > /etc/systemd/system/paperclip.service <<'UNIT'
[Unit]
Description=Paperclip AI Agent Orchestrator
Documentation=https://github.com/paperclipai/paperclip
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/paperclip
Environment=HOME=/home/ec2-user
Environment=PATH=/home/ec2-user/.local/share/pnpm:/usr/local/bin:/usr/bin:/bin
Environment=NODE_ENV=production
Environment=PAPERCLIP_MIGRATION_PROMPT=never
ExecStart=/bin/bash -c 'pnpm dev:once'
Restart=on-failure
RestartSec=15
StandardOutput=journal
StandardError=journal
SyslogIdentifier=paperclip

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable paperclip
systemctl start paperclip

echo "=== Paperclip bootstrap finished at $(date) ==="
echo ""
echo "Paperclip service status:"
systemctl status paperclip --no-pager || true
echo ""
echo "Tail the service log with:  journalctl -fu paperclip"
