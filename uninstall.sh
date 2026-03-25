#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# TrueConf Zabbix Sender — uninstaller
#
# Usage:
#   sudo ./uninstall.sh
#
# Removes everything that install.sh created:
#   1. Stops and disables the systemd service (if it was installed)
#   2. Removes the systemd unit file
#   3. Removes the Zabbix alertscript symlink
#   4. Removes the install directory /opt/trueconf-zabbix-sender (including
#      the venv, queue, config, and all scripts)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

INSTALL_DIR="/opt/trueconf-zabbix-sender"
ZABBIX_SCRIPTS_DIR="/usr/lib/zabbix/alertscripts"
SERVICE_NAME="trueconf-zabbix-sender"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# ── Root check ────────────────────────────────────────────────────────────────
if [[ ${EUID} -ne 0 ]]; then
    echo "Error: this uninstaller must be run as root (use: sudo $0)" >&2
    exit 1
fi

echo "=== TrueConf Zabbix Sender — Uninstall ==="
echo ""

# ── Stop and disable the systemd service ─────────────────────────────────────
if systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null \
   && systemctl list-unit-files "${SERVICE_NAME}.service" | grep -q "${SERVICE_NAME}"; then
    echo "Stopping and disabling service: ${SERVICE_NAME}"
    systemctl stop    "${SERVICE_NAME}" 2>/dev/null || true
    systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
    echo "[OK] Service stopped and disabled"
else
    echo "[SKIP] Service ${SERVICE_NAME} not found in systemd"
fi

# ── Remove the systemd unit file ─────────────────────────────────────────────
if [[ -f "${SERVICE_FILE}" ]]; then
    rm -f "${SERVICE_FILE}"
    systemctl daemon-reload
    echo "[OK] Removed: ${SERVICE_FILE}"
else
    echo "[SKIP] Service unit file not found: ${SERVICE_FILE}"
fi

# ── Remove the Zabbix alertscript symlink ─────────────────────────────────────
SYMLINK="${ZABBIX_SCRIPTS_DIR}/send-trueconf-message.sh"
if [[ -L "${SYMLINK}" ]]; then
    rm -f "${SYMLINK}"
    echo "[OK] Removed symlink: ${SYMLINK}"
elif [[ -f "${SYMLINK}" ]]; then
    echo "[WARN] ${SYMLINK} exists but is not a symlink — not removing (check manually)"
else
    echo "[SKIP] Symlink not found: ${SYMLINK}"
fi

# ── Remove the install directory ─────────────────────────────────────────────
if [[ -d "${INSTALL_DIR}" ]]; then
    # Warn if the queue has unprocessed or error files
    PENDING=$(find "${INSTALL_DIR}/queue" -maxdepth 1 -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "${PENDING}" -gt 0 ]]; then
        echo "[WARN] ${PENDING} unprocessed/error file(s) in ${INSTALL_DIR}/queue — removing with the directory"
    fi

    rm -rf "${INSTALL_DIR}"
    echo "[OK] Removed: ${INSTALL_DIR}"
else
    echo "[SKIP] Install directory not found: ${INSTALL_DIR}"
fi

echo ""
echo "=== Uninstall complete ==="
