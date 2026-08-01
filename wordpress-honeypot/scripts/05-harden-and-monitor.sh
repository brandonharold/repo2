#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${DOMAIN:?}"
WP_ROOT="${WP_ROOT:-/var/www/${DOMAIN}}"
HONEYPOT_LOG_DIR="${HONEYPOT_LOG_DIR:-/var/log/wp-honeypot}"
HONEYPOT_SRC="${HONEYPOT_SRC:?}"
ALERT_WEBHOOK_URL="${ALERT_WEBHOOK_URL:-}"
# shellcheck disable=SC1091
PHP_VERSION="$(source /etc/wp-honeypot-php-version && echo "$PHP_VERSION")"

WP="sudo -u www-data wp --path=${WP_ROOT}"

# --- Logging directory ---
mkdir -p "${HONEYPOT_LOG_DIR}"
: >"${HONEYPOT_LOG_DIR}/events.log"
: >"${HONEYPOT_LOG_DIR}/honeytoken.log"
: >"${HONEYPOT_LOG_DIR}/wp-login.log"
: >"${HONEYPOT_LOG_DIR}/xmlrpc.log"
chown -R www-data:adm "${HONEYPOT_LOG_DIR}"
chmod 750 "${HONEYPOT_LOG_DIR}"
chmod 640 "${HONEYPOT_LOG_DIR}"/*.log

# --- mu-plugin logger ---
mkdir -p "${WP_ROOT}/wp-content/mu-plugins"
install -m 640 -o www-data -g www-data \
  "${HONEYPOT_SRC}/mu-plugins/honeypot-logger.php" \
  "${WP_ROOT}/wp-content/mu-plugins/honeypot-logger.php"

$WP config set HONEYPOT_LOG_DIR "${HONEYPOT_LOG_DIR}" --raw=false

# --- Nginx ---
sed \
  -e "s#__DOMAIN__#${DOMAIN}#g" \
  -e "s#__WP_ROOT__#${WP_ROOT}#g" \
  -e "s#__PHP_VERSION__#${PHP_VERSION}#g" \
  -e "s#__HONEYPOT_LOG_DIR__#${HONEYPOT_LOG_DIR}#g" \
  "${HONEYPOT_SRC}/config/nginx-wordpress-honeypot.conf.tmpl" \
  >/etc/nginx/sites-available/wp-honeypot.conf

install -m 644 "${HONEYPOT_SRC}/config/nginx-limits.conf" /etc/nginx/conf.d/wp-honeypot-limits.conf

ln -sf /etc/nginx/sites-available/wp-honeypot.conf /etc/nginx/sites-enabled/wp-honeypot.conf
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl reload nginx

# --- fail2ban ---
install -m 644 "${HONEYPOT_SRC}/config/fail2ban-filter-wp-honeypot-login.conf" \
  /etc/fail2ban/filter.d/wp-honeypot-login.conf
install -m 644 "${HONEYPOT_SRC}/config/fail2ban-filter-wp-honeypot-honeytoken.conf" \
  /etc/fail2ban/filter.d/wp-honeypot-honeytoken.conf
install -m 644 "${HONEYPOT_SRC}/config/fail2ban-jail-wp-honeypot.local" \
  /etc/fail2ban/jail.d/wp-honeypot.local

systemctl enable --now fail2ban
systemctl restart fail2ban

# --- logrotate ---
install -m 644 "${HONEYPOT_SRC}/config/logrotate-wp-honeypot" /etc/logrotate.d/wp-honeypot

# --- Alert service ---
mkdir -p /opt/wp-honeypot/monitoring /etc/wp-honeypot
install -m 750 "${HONEYPOT_SRC}/monitoring/alert-watch.sh" /opt/wp-honeypot/monitoring/alert-watch.sh

if [[ ! -f /etc/wp-honeypot/alert.env ]]; then
  install -m 600 "${HONEYPOT_SRC}/monitoring/alert.env.example" /etc/wp-honeypot/alert.env
fi
sed -i \
  -e "s#^HONEYPOT_LOG_DIR=.*#HONEYPOT_LOG_DIR=${HONEYPOT_LOG_DIR}#" \
  -e "s#^ALERT_WEBHOOK_URL=.*#ALERT_WEBHOOK_URL=${ALERT_WEBHOOK_URL}#" \
  /etc/wp-honeypot/alert.env
chmod 600 /etc/wp-honeypot/alert.env

install -m 644 "${HONEYPOT_SRC}/config/wp-honeypot-alert.service" /etc/systemd/system/wp-honeypot-alert.service
systemctl daemon-reload
systemctl enable --now wp-honeypot-alert
