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
APP_HOME="/home/$${APP_USER}"
APP_DIR="$${APP_HOME}/paperclip"
LOG="/var/log/paperclip-bootstrap.log"

exec > >(tee -a "$LOG") 2>&1
echo "=== Paperclip bootstrap started at $(date) ==="

# ── Add 4 GB swap (required for Vite build on t4g.micro with 1GB RAM) ────────
if [ ! -f /swapfile ]; then
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# ── Configure shared memory for PostgreSQL (required on t4g.micro) ───────────
# Increase shared memory limits to prevent PostgreSQL DSM errors
sysctl -w kernel.shmmax=536870912          # 512MB
sysctl -w kernel.shmall=131072             # 512MB / 4KB page size
echo 'kernel.shmmax=536870912' >> /etc/sysctl.conf
echo 'kernel.shmall=131072' >> /etc/sysctl.conf

# Increase POSIX shared memory (/dev/shm) for PostgreSQL dynamic shared memory
# Use 1GB to handle long-running workloads
mount -o remount,size=1G /dev/shm
# Remove any existing /dev/shm entry and add new one
sed -i '/\/dev\/shm/d' /etc/fstab
echo 'tmpfs /dev/shm tmpfs defaults,size=1G 0 0' >> /etc/fstab

# ── System updates & prerequisites ────────────────────────────────────────
dnf update -y
dnf install -y --allowerasing git curl unzip tar

# ── Node.js 20 via NodeSource ──────────────────────────────────────────────
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
dnf install -y --allowerasing nodejs

node --version
npm --version

# ── pnpm (version pinned to match Paperclip's packageManager field) ────────
# Paperclip requires pnpm@9.15.4
# Install pnpm globally using corepack (bundled with Node.js 20+)
corepack enable
corepack prepare pnpm@9.15.4 --activate

# Verify
pnpm --version

# ── Install Claude CLI (required by Paperclip) ───────────────────────────
npm install -g @anthropic-ai/claude-code
claude --version || echo "Claude CLI installed"

# ── Clone Paperclip ──────────────────────────────────────────────────────
if [ ! -d "$${APP_DIR}" ]; then
  sudo -u "$${APP_USER}" git clone \
    https://github.com/paperclipai/paperclip.git \
    "$${APP_DIR}"
else
  echo "Paperclip repo already present — skipping clone."
fi

# ── Install dependencies & build ─────────────────────────────────────────
cd "$${APP_DIR}"

# Set Node.js memory limit and reduce concurrency to avoid OOM on t4g.micro (1GB RAM)
export NODE_OPTIONS="--max-old-space-size=2048" # (2GB heap should be sufficient for pnpm install and build)

sudo -u "$${APP_USER}" env HOME="$${APP_HOME}" NODE_OPTIONS="$${NODE_OPTIONS}" pnpm install --no-frozen-lockfile

# Build packages one at a time to reduce memory pressure
sudo -u "$${APP_USER}" env HOME="$${APP_HOME}" NODE_OPTIONS="$${NODE_OPTIONS}" pnpm -r --workspace-concurrency=1 build

# Apply DB migrations once before starting the service
sudo -u "$${APP_USER}" env HOME="$${APP_HOME}" PAPERCLIP_MIGRATION_PROMPT=never \
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
Environment=PATH=/usr/local/bin:/usr/bin:/bin
Environment=NODE_ENV=production
Environment=PAPERCLIP_MIGRATION_PROMPT=never
Environment=ANTHROPIC_API_KEY=${anthropic_api_key}
Environment=PGOPTIONS=-c dynamic_shared_memory_type=mmap
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

# ── Fix PostgreSQL dynamic shared memory type ────────────────────────────────
# Wait for embedded PostgreSQL to initialize and create its config
sleep 30
PG_CONF="/home/ec2-user/.paperclip/instances/default/db/postgresql.conf"
if [ -f "$PG_CONF" ]; then
  # Change from posix to mmap to prevent DSM segment cleanup issues
  sed -i 's/dynamic_shared_memory_type = posix/dynamic_shared_memory_type = mmap/' "$PG_CONF"
  echo "Fixed PostgreSQL dynamic_shared_memory_type to mmap"
  systemctl restart paperclip
fi

# ── Add scheduled restart to prevent PostgreSQL DSM memory exhaustion ────────
# Restart paperclip service every 6 hours to clear shared memory
cat > /etc/systemd/system/paperclip-restart.service <<'RESTART_SVC'
[Unit]
Description=Restart Paperclip service

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl restart paperclip
RESTART_SVC

cat > /etc/systemd/system/paperclip-restart.timer <<'RESTART_TMR'
[Unit]
Description=Restart Paperclip every 6 hours

[Timer]
OnBootSec=6h
OnUnitActiveSec=6h

[Install]
WantedBy=timers.target
RESTART_TMR

systemctl daemon-reload
systemctl enable paperclip-restart.timer
systemctl start paperclip-restart.timer

echo "=== Paperclip bootstrap finished at $(date) ==="
echo ""
echo "Paperclip service status:"
systemctl status paperclip --no-pager || true
echo ""
echo "Tail the service log with:  journalctl -fu paperclip"
