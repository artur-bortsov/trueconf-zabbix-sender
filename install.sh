#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# TrueConf Zabbix Sender — installer for Ubuntu 22.04 / 24.04
#
# Usage:
#   sudo ./install.sh [--install-service]
#
# What this script does:
#   1. Verifies Python 3.10+ is available
#   2. Installs system packages (python3-venv, python3-pip)
#   3. Copies files to /opt/trueconf-zabbix-sender
#   4. Creates a Python virtual environment and installs python-trueconf-bot
#      (also installs the 'tomli' backport automatically on Python 3.10)
#   5. Creates a symlink in the Zabbix alertscripts directory
#   6. Sets secure file permissions (owner: zabbix)
#
# With --install-service:
#   7. Installs the systemd unit file (does NOT start or enable it)
#      To enable: sudo systemctl enable --now trueconf-zabbix-sender
#
# After installation, edit /opt/trueconf-zabbix-sender/config.toml with your
# credentials if they differ from the bundled defaults.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
INSTALL_DIR="/opt/trueconf-zabbix-sender"
ZABBIX_SCRIPTS_DIR="/usr/lib/zabbix/alertscripts"
VENV_DIR="${INSTALL_DIR}/venv"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SERVICE=false

# ── Argument parsing ──────────────────────────────────────────────────────────
for arg in "$@"; do
    case "${arg}" in
        --install-service)
            INSTALL_SERVICE=true
            ;;
        --help|-h)
            sed -n '2,/^#$/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "Unknown argument: ${arg}" >&2
            echo "Usage: $0 [--install-service]" >&2
            exit 1
            ;;
    esac
done

# ── Root check ────────────────────────────────────────────────────────────────
if [[ ${EUID} -ne 0 ]]; then
    echo "Error: this installer must be run as root (use: sudo $0 $*)" >&2
    exit 1
fi

echo "=== TrueConf Zabbix Sender — Installation ==="
echo "Install directory : ${INSTALL_DIR}"
echo "Zabbix scripts dir: ${ZABBIX_SCRIPTS_DIR}"
echo ""

# ── Python version check ──────────────────────────────────────────────────────
if ! command -v python3 &>/dev/null; then
    echo "Error: python3 not found. Install it first: apt install python3" >&2
    exit 1
fi

PYTHON_VERSION="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
PYTHON_MAJOR="${PYTHON_VERSION%%.*}"
PYTHON_MINOR="${PYTHON_VERSION##*.}"

if [[ "${PYTHON_MAJOR}" -lt 3 ]] || { [[ "${PYTHON_MAJOR}" -eq 3 ]] && [[ "${PYTHON_MINOR}" -lt 10 ]]; }; then
    echo "Error: Python 3.10 or higher is required (found Python ${PYTHON_VERSION})" >&2
    exit 1
fi
echo "[OK] Python ${PYTHON_VERSION}"

# ── System packages ───────────────────────────────────────────────────────────
echo "Installing system dependencies..."
apt-get update -qq
apt-get install -y python3-venv python3-pip --quiet
echo "[OK] System packages"

# ── Install directory ─────────────────────────────────────────────────────────
echo "Creating install directory: ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"

# ── Copy application files ────────────────────────────────────────────────────
echo "Copying application files..."
cp "${SCRIPT_DIR}/trueconf_sender.py"   "${INSTALL_DIR}/"
cp "${SCRIPT_DIR}/send-trueconf-message.sh" "${INSTALL_DIR}/"
chmod +x "${INSTALL_DIR}/send-trueconf-message.sh"

# Copy config only when it doesn't already exist to preserve user settings
if [[ ! -f "${INSTALL_DIR}/config.toml" ]]; then
    cp "${SCRIPT_DIR}/config.toml" "${INSTALL_DIR}/"
    echo "[NOTE] New config created at ${INSTALL_DIR}/config.toml — edit it with your credentials."
else
    echo "[SKIP] Config already exists at ${INSTALL_DIR}/config.toml — not overwriting."
fi

# ── Python virtual environment ────────────────────────────────────────────────
echo "Creating Python virtual environment in ${VENV_DIR}..."
python3 -m venv "${VENV_DIR}"

echo "Installing python-trueconf-bot..."
"${VENV_DIR}/bin/pip" install --upgrade pip --quiet
"${VENV_DIR}/bin/pip" install python-trueconf-bot --quiet

# Python 3.10 does not ship tomllib in the standard library (added in 3.11).
# Install the 'tomli' backport so config.toml parsing works on Python 3.10.
if [[ "${PYTHON_MINOR}" -lt 11 ]]; then
    echo "Installing tomli backport for Python ${PYTHON_VERSION}..."
    "${VENV_DIR}/bin/pip" install tomli --quiet
    echo "[OK] tomli installed"
fi

echo "[OK] Python dependencies installed"

# ── Zabbix alertscript symlink ──────────────────────────────────────────────────────
if [[ -d "${ZABBIX_SCRIPTS_DIR}" ]]; then
    echo "Creating Zabbix alertscript symlink..."
    ln -sf "${INSTALL_DIR}/send-trueconf-message.sh" \
           "${ZABBIX_SCRIPTS_DIR}/send-trueconf-message.sh"
    echo "[OK] Symlink: ${ZABBIX_SCRIPTS_DIR}/send-trueconf-message.sh"
else
    echo "[WARN] Zabbix alertscripts directory not found: ${ZABBIX_SCRIPTS_DIR}"
    echo "       Manually symlink send-trueconf-message.sh after Zabbix is installed."
fi

# ── File permissions ──────────────────────────────────────────────────────────
echo "Setting file permissions..."
if id zabbix &>/dev/null; then
    chown -R zabbix:zabbix "${INSTALL_DIR}"
    chmod 750 "${INSTALL_DIR}"
    chmod 640 "${INSTALL_DIR}/config.toml"
    chmod 750 "${INSTALL_DIR}/send-trueconf-message.sh"
    echo "[OK] Ownership: zabbix:zabbix"
else
    echo "[WARN] User 'zabbix' not found. Set ownership manually:"
    echo "       chown -R zabbix:zabbix ${INSTALL_DIR}"
    echo "       chmod 640 ${INSTALL_DIR}/config.toml"
fi

# ── Systemd service (optional) ────────────────────────────────────────────────
if ${INSTALL_SERVICE}; then
    # Create the queue directory only when the service is being installed.
    # Its presence is the signal to send-trueconf-message.sh to use queue mode
    # instead of direct mode. Without the service running there is no daemon to
    # process the queue, so the directory must not exist without the service.
    echo "Creating queue directory: ${INSTALL_DIR}/queue"
    mkdir -p "${INSTALL_DIR}/queue"
    if id zabbix &>/dev/null; then
        chown zabbix:zabbix "${INSTALL_DIR}/queue"
        chmod 770 "${INSTALL_DIR}/queue"
    fi
    echo "[OK] Queue directory created"

    SERVICE_FILE="${SCRIPT_DIR}/trueconf-zabbix-sender.service"
    if [[ -f "${SERVICE_FILE}" ]]; then
        echo "Installing systemd service..."
        cp "${SERVICE_FILE}" /etc/systemd/system/
        systemctl daemon-reload
        echo "[OK] Service unit installed"
        echo ""
        echo "To enable and start the persistent service:"
        echo "  sudo systemctl enable --now trueconf-zabbix-sender"
        echo "To view service logs:"
        echo "  journalctl -u trueconf-zabbix-sender -f"
    else
        echo "[WARN] Service unit file not found: ${SERVICE_FILE}"
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=== Installation complete! ==="
echo ""
echo "Next steps:"
echo "  1. Review configuration:  ${INSTALL_DIR}/config.toml"
echo "  2. Test connectivity:"
echo "       ${INSTALL_DIR}/send-trueconf-message.sh \\"
echo "         'user@consultant.ru' 'TrueConf bot test message'"
echo "  3. Configure Zabbix media type:"
echo "       Script name : send-trueconf-message.sh"
echo "       Parameter 1 : {ALERT.SENDTO}   (recipient email addresses)"
echo "       Parameter 2 : {ALERT.MESSAGE}  (alert message body)"
if ${INSTALL_SERVICE}; then
    echo ""
    echo "  (Optional) Enable persistent service:"
    echo "       sudo systemctl enable --now trueconf-zabbix-sender"
fi
echo ""
