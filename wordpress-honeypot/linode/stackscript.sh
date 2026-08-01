#!/bin/bash
# WordPress honeypot — Linode StackScript
#
# Paste this into Linode Cloud Manager → StackScripts → Create, targeting the
# Ubuntu 24.04 LTS (and/or 22.04 LTS) images. It runs as root on first boot
# and performs the whole build described in ../README.md.
#
# <UDF name="HP_DOMAIN" label="Domain or hostname for the honeypot site" example="honeypot.example.com" />
# <UDF name="HP_SITE_TITLE" label="Site title (keep it generic/plausible)" default="Summit Business Solutions" />
# <UDF name="HP_ADMIN_EMAIL" label="Your security contact email (never shown on the site)" example="security-team@example.com" />
# <UDF name="HP_ALLOWED_SSH_CIDR" label="CIDR allowed to reach SSH — narrow this to your admin network/VPN" default="0.0.0.0/0" />
# <UDF name="HP_ALERT_WEBHOOK_URL" label="Alert webhook URL (Slack/Discord/generic JSON POST). Leave blank to log locally only." default="" />
# <UDF name="HP_REPO_URL" label="Git URL of this repository" default="https://github.com/brandonharold/repo2.git" />
# <UDF name="HP_REPO_BRANCH" label="Branch to deploy" default="claude/wordpress-honeypot-ubuntu-bs6ao2" />

set -euo pipefail
exec > >(tee -a /var/log/wp-honeypot-stackscript.log) 2>&1

echo "==> WordPress honeypot StackScript starting $(date -Is)"

# Optional UDFs arrive unset (not empty) when left blank in Cloud Manager;
# under `set -u` that would abort the build on first boot. Normalize first.
HP_SITE_TITLE="${HP_SITE_TITLE:-Summit Business Solutions}"
HP_ALLOWED_SSH_CIDR="${HP_ALLOWED_SSH_CIDR:-0.0.0.0/0}"
HP_ALERT_WEBHOOK_URL="${HP_ALERT_WEBHOOK_URL:-}"
HP_REPO_URL="${HP_REPO_URL:-https://github.com/brandonharold/repo2.git}"
HP_REPO_BRANCH="${HP_REPO_BRANCH:-claude/wordpress-honeypot-ubuntu-bs6ao2}"
: "${HP_DOMAIN:?HP_DOMAIN is required}"
: "${HP_ADMIN_EMAIL:?HP_ADMIN_EMAIL is required}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y git

# Linode images ship with a hostname of the form "localhost"; set something
# coherent so mail/log tooling doesn't complain.
hostnamectl set-hostname "${HP_DOMAIN%%.*}"

git clone --branch "${HP_REPO_BRANCH}" --depth 1 "${HP_REPO_URL}" /opt/wp-honeypot-src
cd /opt/wp-honeypot-src/wordpress-honeypot

cat >.env <<EOF
DOMAIN=${HP_DOMAIN}
SITE_TITLE=${HP_SITE_TITLE}
WP_ADMIN_EMAIL=${HP_ADMIN_EMAIL}
HONEYPOT_LOG_DIR=/var/log/wp-honeypot
ALERT_WEBHOOK_URL=${HP_ALERT_WEBHOOK_URL}
ALLOWED_SSH_CIDR=${HP_ALLOWED_SSH_CIDR}
EOF
chmod 600 .env

./install.sh

echo "==> WordPress honeypot StackScript finished $(date -Is)"
echo "==> Credentials are in /root/wp-honeypot-secrets.txt"
