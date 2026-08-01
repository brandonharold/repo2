#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${DOMAIN:?}"
WP_ADMIN_EMAIL="${WP_ADMIN_EMAIL:?}"
SITE_TITLE="${SITE_TITLE:?}"
WP_ROOT="${WP_ROOT:-/var/www/${DOMAIN}}"

# --- WP-CLI ---
if ! command -v wp >/dev/null; then
  curl -fsSL -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
  chmod +x /usr/local/bin/wp
fi

# --- Database ---
DB_NAME="wp_honeypot"
DB_USER="wp_honeypot_$(openssl rand -hex 4)"
DB_PASS="$(openssl rand -base64 24)"

mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

# --- WordPress core ---
mkdir -p "${WP_ROOT}"
chown www-data:www-data "${WP_ROOT}"

sudo -u www-data wp core download --path="${WP_ROOT}" --locale=en_US

sudo -u www-data wp config create \
  --path="${WP_ROOT}" \
  --dbname="${DB_NAME}" \
  --dbuser="${DB_USER}" \
  --dbpass="${DB_PASS}" \
  --dbhost="localhost" \
  --skip-check \
  --extra-php <<'PHP'
define( 'DISALLOW_FILE_EDIT', true );
define( 'DISALLOW_FILE_MODS', true );
define( 'WP_AUTO_UPDATE_CORE', 'minor' );
define( 'WP_DEBUG', false );
define( 'WP_DEBUG_LOG', false );
PHP

WP_ADMIN_USER="siteadmin_$(openssl rand -hex 3)"
WP_ADMIN_PASS="$(openssl rand -base64 24)"

sudo -u www-data wp core install \
  --path="${WP_ROOT}" \
  --url="http://${DOMAIN}" \
  --title="${SITE_TITLE}" \
  --admin_user="${WP_ADMIN_USER}" \
  --admin_password="${WP_ADMIN_PASS}" \
  --admin_email="${WP_ADMIN_EMAIL}" \
  --skip-email

# Nobody should be logging into wp-admin over the web on this box — it's
# administered via WP-CLI. Any web login succeeding is itself a signal.
sudo -u www-data wp option update default_role subscriber --path="${WP_ROOT}"

find "${WP_ROOT}" -type d -exec chmod 750 {} \;
find "${WP_ROOT}" -type f -exec chmod 640 {} \;
chown -R www-data:www-data "${WP_ROOT}"

umask 077
install -m 600 /dev/null /root/wp-honeypot-secrets.txt
cat >/root/wp-honeypot-secrets.txt <<EOF
WordPress honeypot credentials — generated $(date -Is)
Copy these out and delete this file if root access to this box is shared.

Site URL:        http://${DOMAIN}/
WP admin user:    ${WP_ADMIN_USER}
WP admin pass:    ${WP_ADMIN_PASS}
WP admin email:   ${WP_ADMIN_EMAIL}

DB name:          ${DB_NAME}
DB user:          ${DB_USER}
DB pass:          ${DB_PASS}

MariaDB root pass: see /root/.my.cnf
EOF
