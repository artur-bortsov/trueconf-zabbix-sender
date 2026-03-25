#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# TrueConf Zabbix Message Sender — alertscript wrapper
#
# Usage:
#   send-trueconf-message.sh "<emails>" "<message>"
#
#   <emails>  — space-separated recipient email addresses
#               e.g. "alice@consultant.ru bob@consultant.ru"
#   <message> — message text to send (Zabbix problem description, etc.)
#
# Email addresses are automatically mapped to TrueConf IDs as configured in
# config.toml (e.g. user@consultant.ru → user@tconf.consultant.ru).
#
# Exit codes mirror Python trueconf_sender.py:
#   0 — all messages delivered
#   1 — usage error
#   2 — configuration error
#   3 — delivery failure
#
# This script is designed to be placed in Zabbix's AlertScripts directory
# (default: /usr/lib/zabbix/alertscripts) or symlinked there.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Argument check ────────────────────────────────────────────────────────────
if [[ $# -lt 2 ]]; then
    echo "Usage: $(basename "$0") \"<emails>\" \"<message>\"" >&2
    echo "  <emails>  — space-separated recipient email addresses" >&2
    echo "  <message> — message text" >&2
    exit 1
fi

# ── Locate the Python interpreter and sender script ───────────────────────────
# Resolve the directory containing this script, even if it is a symlink.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# Check common install locations for the virtual environment.
# Priority: venv inside SCRIPT_DIR > installed path > system python3
if [[ -x "${SCRIPT_DIR}/venv/bin/python3" ]]; then
    PYTHON="${SCRIPT_DIR}/venv/bin/python3"
elif [[ -x "/opt/trueconf-zabbix-sender/venv/bin/python3" ]]; then
    PYTHON="/opt/trueconf-zabbix-sender/venv/bin/python3"
    SCRIPT_DIR="/opt/trueconf-zabbix-sender"
else
    PYTHON="python3"
fi

SENDER="${SCRIPT_DIR}/trueconf_sender.py"

if [[ ! -f "${SENDER}" ]]; then
    echo "Error: sender script not found: ${SENDER}" >&2
    exit 2
fi

# ── Route to queue or direct mode ─────────────────────────────────────────────────
QUEUE_DIR="${SCRIPT_DIR}/queue"

if [[ -d "${QUEUE_DIR}" ]]; then
    # Queue mode: service is installed; write a task file and exit immediately.
    # The running service daemon picks it up within ~1 second and delivers it
    # without a new TrueConf connection. Recommended for production.
    exec "${PYTHON}" "${SENDER}" --queue "$1" "$2"
else
    # Direct mode: no queue directory found (service not installed).
    # Connect to TrueConf, send, disconnect. Suitable for infrequent alerts.
    exec "${PYTHON}" "${SENDER}" "$1" "$2"
fi
