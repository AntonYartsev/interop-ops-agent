#!/usr/bin/env bash
# Prepare a clean Ubuntu aarch64 VM: Docker Engine + compose plugin, ufw (22/80/443), 4G swap. Idempotent.
# Run: sudo ./bootstrap.sh
# OCI note: OCI Ubuntu images ship iptables rules with a REJECT rule in INPUT. ufw adds its own chains
# (ufw-before-input etc.), but a REJECT rule that sits BEFORE them still blocks 80/443.
# Check: `sudo iptables -L INPUT -n --line-numbers`. If a REJECT line precedes the ufw chains, delete it
# (`sudo iptables -D INPUT <n>`) and persist the change (`sudo netfilter-persistent save`, if installed).
# The OCI security list / NSG must also allow TCP 80 and 443 (see README).
set -euo pipefail

[ "$(uname -m)" = "aarch64" ] || { echo "ERROR: aarch64 required, got $(uname -m)" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "ERROR: run with sudo" >&2; exit 1; }

# Docker Engine + compose plugin from Docker's official apt repo
if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  apt-get update
  apt-get install -y ca-certificates curl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
  echo "Docker and compose plugin already present; skipping install."
fi
systemctl enable --now docker

# Invoking user -> docker group (re-login needed)
TARGET_USER="${SUDO_USER:-}"
if [ -n "$TARGET_USER" ] && [ "$TARGET_USER" != "root" ]; then
  usermod -aG docker "$TARGET_USER"
  echo "Added $TARGET_USER to group docker (re-login needed)."
fi

# Firewall: allow ssh first, so enabling ufw does not cut the session
apt-get install -y ufw
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# 4G swap, only if no swap is active
if [ -z "$(swapon --show --noheadings)" ]; then
  [ -f /swapfile ] || { fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile; }
  swapon /swapfile
fi
grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab

echo "Bootstrap done. docker: $(docker --version)"
