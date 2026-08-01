#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${HERE}/.env"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo ./install.sh)." >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing .env — copy .env.example to .env and fill in values first." >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

: "${DOMAIN:?Set DOMAIN in .env}"
: "${WP_ADMIN_EMAIL:?Set WP_ADMIN_EMAIL in .env}"
: "${SITE_TITLE:?Set SITE_TITLE in .env}"

export HONEYPOT_LOG_DIR="${HONEYPOT_LOG_DIR:-/var/log/wp-honeypot}"
export WP_ROOT="/var/www/${DOMAIN}"
export HONEYPOT_SRC="$HERE"

for step in 01-provision-os 02-install-lemp 03-install-wordpress 04-populate-content 05-harden-and-monitor 06-deploy-honeytokens; do
  echo "==> Running ${step}"
  bash "${HERE}/scripts/${step}.sh"
done

cat <<EOF

==> Done.
    Site:   http://${DOMAIN}/
    Logs:   ${HONEYPOT_LOG_DIR}/events.log, ${HONEYPOT_LOG_DIR}/honeytoken.log
    Creds:  /root/wp-honeypot-secrets.txt (root-only — copy out and delete when done)
EOF
