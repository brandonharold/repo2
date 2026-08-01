#!/usr/bin/env bash
set -euo pipefail

ALLOWED_SSH_CIDR="${ALLOWED_SSH_CIDR:-0.0.0.0/0}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y \
  ufw fail2ban unattended-upgrades apt-listchanges \
  curl wget unzip zip jq git software-properties-common \
  logrotate

# --- OS patching: keep the underlying host patched even though the app
# layer (WordPress) is the intentional attack surface. ---
dpkg-reconfigure -f noninteractive unattended-upgrades
cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

# --- Firewall: egress-restricted. This is the main safety net if the
# WordPress layer is ever fully compromised — it limits what the box can
# reach outbound (no pivoting to attack other systems). ---
ufw --force reset
ufw default deny incoming
ufw default deny outgoing

ufw allow from "${ALLOWED_SSH_CIDR}" to any port 22 proto tcp
ufw allow 80/tcp
ufw allow 443/tcp

ufw allow out 53      # DNS
ufw allow out 123/udp # NTP
ufw allow out 80/tcp  # apt / plugin updates over HTTP redirects
ufw allow out 443/tcp # apt / WordPress.org / alert webhook

ufw logging on
ufw --force enable

mkdir -p "${HONEYPOT_LOG_DIR:-/var/log/wp-honeypot}"
chmod 750 "${HONEYPOT_LOG_DIR:-/var/log/wp-honeypot}"
