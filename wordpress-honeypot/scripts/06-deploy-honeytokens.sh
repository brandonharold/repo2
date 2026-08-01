#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${DOMAIN:?}"
WP_ROOT="${WP_ROOT:-/var/www/${DOMAIN}}"

# All values below are inert, randomly generated placeholders — they do not
# correspond to any real credential, key, or account. Their only purpose is
# to look plausible enough that a human or scanner requests the file; the
# resulting HTTP request is what gets logged and alerted on
# (see config/nginx-wordpress-honeypot.conf.tmpl + honeytoken.log).

cat >"${WP_ROOT}/wp-config.php.bak" <<EOF
<?php
// ** Database settings ** //
define( 'DB_NAME', 'wp_prod' );
define( 'DB_USER', 'wp_admin' );
define( 'DB_PASSWORD', '$(openssl rand -hex 16)' );
define( 'DB_HOST', 'localhost' );
define( 'DB_CHARSET', 'utf8mb4' );
define( 'AUTH_KEY', '$(openssl rand -base64 48 | tr -d '\n')' );
define( 'SECURE_AUTH_KEY', '$(openssl rand -base64 48 | tr -d '\n')' );
\$table_prefix = 'wp_';
EOF

cat >"${WP_ROOT}/.env" <<EOF
APP_ENV=production
DB_HOST=localhost
DB_DATABASE=wp_prod
DB_USERNAME=wp_admin
DB_PASSWORD=$(openssl rand -hex 16)
MAIL_PASSWORD=$(openssl rand -hex 12)
EOF

mkdir -p "${WP_ROOT}/.git"
cat >"${WP_ROOT}/.git/config" <<EOF
[core]
	repositoryformatversion = 0
	filemode = true
	bare = false
[remote "origin"]
	url = https://deploy:$(openssl rand -hex 10)@git.internal.example.com/summit/website.git
	fetch = +refs/heads/*:refs/remotes/origin/*
EOF

WORKDIR="$(mktemp -d)"
cat >"${WORKDIR}/README.txt" <<'EOF'
This file was served by a research honeypot. No production data was
present on this host. The request that retrieved this file has been
logged for security research purposes.
EOF
( cd "$WORKDIR" && zip -q backup.zip README.txt )
mv "${WORKDIR}/backup.zip" "${WP_ROOT}/backup.zip"
rm -rf "$WORKDIR"

chown www-data:www-data \
  "${WP_ROOT}/wp-config.php.bak" \
  "${WP_ROOT}/.env" \
  "${WP_ROOT}/.git/config" \
  "${WP_ROOT}/backup.zip"
chmod 640 \
  "${WP_ROOT}/wp-config.php.bak" \
  "${WP_ROOT}/.env" \
  "${WP_ROOT}/.git/config" \
  "${WP_ROOT}/backup.zip"
