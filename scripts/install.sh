#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

NGINX_CONF="/etc/nginx/nginx.conf"
CONF_D="/etc/nginx/conf.d"
RTMP_D="/etc/nginx/rtmp.d"
WEB_ROOT="/var/www/html"
HLS_DIR="${WEB_ROOT}/hls"
PANEL_CONF="${CONF_D}/rtmp-panel.conf"
RTMP_CONF="${RTMP_D}/live.conf"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this script with sudo:"
    echo "sudo ./setup.sh"
    exit 1
fi

timestamp="$(date +%Y%m%d-%H%M%S)"

backup_file() {
    local path="$1"
    if [[ -f "${path}" ]]; then
        cp "${path}" "${path}.backup-${timestamp}"
    fi
}

require_file() {
    local path="$1"
    if [[ ! -f "${path}" ]]; then
        echo "Missing required repo file: ${path}" >&2
        exit 1
    fi
}

ensure_top_level_line() {
    local line="$1"
    if ! grep -Fqx "${line}" "${NGINX_CONF}"; then
        backup_file "${NGINX_CONF}"
        printf '\n%s\n' "${line}" >> "${NGINX_CONF}"
    fi
}

require_file "${REPO_DIR}/configs/rtmp-live.conf"
require_file "${REPO_DIR}/configs/rtmp-panel.conf"
require_file "${REPO_DIR}/web/panel.html"
require_file "${REPO_DIR}/web/stat.xsl"

echo "==> Installing or updating Nginx and RTMP module"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y nginx libnginx-mod-rtmp

echo "==> Preparing directories"
install -d -m 0755 "${CONF_D}" "${RTMP_D}" "${WEB_ROOT}" "${HLS_DIR}"
chown -R www-data:www-data "${HLS_DIR}"

echo "==> Installing your dashboard website"
backup_file "${WEB_ROOT}/panel.html"
backup_file "${WEB_ROOT}/stat.xsl"
install -m 0644 "${REPO_DIR}/web/panel.html" "${WEB_ROOT}/panel.html"
install -m 0644 "${REPO_DIR}/web/stat.xsl" "${WEB_ROOT}/stat.xsl"

echo "==> Installing dashboard HTTP config"
backup_file "${PANEL_CONF}"
install -m 0644 "${REPO_DIR}/configs/rtmp-panel.conf" "${PANEL_CONF}"

echo "==> Checking Nginx main config"
if [[ ! -f "${NGINX_CONF}" ]]; then
    echo "Nginx config was not created by package install: ${NGINX_CONF}" >&2
    exit 1
fi

existing_rtmp="no"
if nginx -T 2>/dev/null | grep -Eq '^[[:space:]]*rtmp[[:space:]]*\{'; then
    existing_rtmp="yes"
elif grep -Eq '^[[:space:]]*rtmp[[:space:]]*\{' "${NGINX_CONF}"; then
    existing_rtmp="yes"
fi

if ! grep -Eq '^[[:space:]]*include[[:space:]]+/etc/nginx/modules-enabled/\*\.conf;' "${NGINX_CONF}"; then
    echo "==> Adding module include to nginx.conf"
    backup_file "${NGINX_CONF}"
    sed -i '1i include /etc/nginx/modules-enabled/*.conf;' "${NGINX_CONF}"
fi

if [[ "${existing_rtmp}" == "yes" ]]; then
    echo "==> Existing RTMP block found; leaving it in place"
    echo "    If that block does not define application live, add the contents of configs/rtmp-live.conf manually."
else
    echo "==> Installing managed RTMP live config"
    backup_file "${RTMP_CONF}"
    install -m 0644 "${REPO_DIR}/configs/rtmp-live.conf" "${RTMP_CONF}"
    ensure_top_level_line "include /etc/nginx/rtmp.d/*.conf;"
fi

if ! grep -Eq 'include[[:space:]]+/etc/nginx/conf\.d/\*\.conf;' "${NGINX_CONF}"; then
    echo "WARNING: nginx.conf does not appear to include /etc/nginx/conf.d/*.conf."
    echo "The RTMP dashboard config was installed at ${PANEL_CONF}, but your Nginx config may not load it."
fi

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    echo "==> Opening firewall ports with UFW"
    ufw allow 1935/tcp
    ufw allow 8080/tcp
fi

echo "==> Testing Nginx config"
nginx -t

echo "==> Enabling and reloading Nginx"
systemctl enable nginx >/dev/null
systemctl reload nginx || systemctl restart nginx

server_ip="$(hostname -I | awk '{print $1}')"

echo
echo "RTMP setup complete."
echo "Publish URL:   rtmp://${server_ip:-YOUR_SERVER_IP}/live/mystream"
echo "HLS URL:       http://${server_ip:-YOUR_SERVER_IP}:8080/hls/mystream.m3u8"
echo "Dashboard:     http://${server_ip:-YOUR_SERVER_IP}:8080/panel.html"
echo "Stats XML:     http://${server_ip:-YOUR_SERVER_IP}:8080/stat"
