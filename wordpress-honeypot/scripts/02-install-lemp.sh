#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get install -y \
  nginx \
  mariadb-server \
  php-fpm php-mysql php-curl php-gd php-mbstring php-xml php-zip php-intl php-imagick

PHP_VERSION="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
echo "export PHP_VERSION=${PHP_VERSION}" >/etc/wp-honeypot-php-version
export PHP_VERSION

systemctl enable --now mariadb
systemctl enable --now "php${PHP_VERSION}-fpm"
systemctl enable --now nginx

# --- Baseline MariaDB hardening (equivalent of mysql_secure_installation,
# run non-interactively). ---
DB_ROOT_PASS="$(openssl rand -base64 24)"
mysql <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQL

install -m 600 /dev/null /root/.my.cnf
cat >/root/.my.cnf <<EOF
[client]
user=root
password=${DB_ROOT_PASS}
EOF
