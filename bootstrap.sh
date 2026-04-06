#!/usr/bin/env bash
# One-shot setup for a fresh Raspberry Pi OS install
# Run on the Pi: sudo ./bootstrap.sh
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run with sudo: sudo ./bootstrap.sh" >&2
    exit 1
fi

INSTALL_USER="${SUDO_USER:?Must run with sudo, not as root directly}"
INSTALL_HOME=$(eval echo "~${INSTALL_USER}")
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Installing for user: ${INSTALL_USER}"

# --- Packages ---
echo "==> Updating packages..."
apt update

echo "==> Installing dependencies..."
apt install -y sane-utils libsane1 libsane-common scanbd curl jq

# --- User permissions ---
echo "==> Adding ${INSTALL_USER} to scanner group..."
usermod -aG scanner "$INSTALL_USER"

# --- Working directories ---
echo "==> Creating working directories..."
install -d -o "$INSTALL_USER" -g scanner -m 0775 \
    /var/lib/scansnap/scans \
    /var/lib/scansnap/upload-queue \
    /var/lib/scansnap/dead-letter

# --- Config ---
echo "==> Installing config..."
install -d -m 0755 /etc/scansnap
if [[ ! -f /etc/scansnap/scansnap.conf ]]; then
    install -m 0600 -o "$INSTALL_USER" "${SCRIPT_DIR}/config/scansnap.conf.example" /etc/scansnap/scansnap.conf
    echo "    Created /etc/scansnap/scansnap.conf — edit with your Paperless URL and token"
else
    echo "    Config already exists, skipping"
fi

# --- udev ---
echo "==> Installing udev rule..."
install -m 0644 "${SCRIPT_DIR}/config/99-scansnap.rules" /etc/udev/rules.d/99-scansnap.rules
udevadm control --reload-rules
udevadm trigger

# --- Scripts (user home dir) ---
echo "==> Installing scripts to ${INSTALL_HOME}/scansnap/..."
install -d -o "$INSTALL_USER" -g "$INSTALL_USER" "${INSTALL_HOME}/scansnap"
install -m 0755 -o "$INSTALL_USER" "${SCRIPT_DIR}/scripts/scan-and-upload.sh" "${INSTALL_HOME}/scansnap/"
install -m 0755 -o "$INSTALL_USER" "${SCRIPT_DIR}/scripts/upload-to-paperless.sh" "${INSTALL_HOME}/scansnap/"
install -m 0755 -o "$INSTALL_USER" "${SCRIPT_DIR}/scripts/health-check.sh" "${INSTALL_HOME}/scansnap/"

# --- scanbd ---
echo "==> Configuring scanbd..."
mkdir -p /etc/scanbd/scripts
install -m 0755 "${SCRIPT_DIR}/config/scanbd-scan.script" /etc/scanbd/scripts/scan.script
install -m 0644 "${SCRIPT_DIR}/config/scanner.d/epjitsu.conf" /etc/scanbd/scanner.d/epjitsu.conf

# Set scanbd to run as the installing user
sed -i "s/^[[:space:]]*user[[:space:]]*=.*/        user    = ${INSTALL_USER}/" /etc/scanbd/scanbd.conf

# Add epjitsu device config if not already included
if ! grep -q 'scanner.d/epjitsu.conf' /etc/scanbd/scanbd.conf; then
    sed -i '/include(scanner.d\/fujitsu.conf)/a include(scanner.d/epjitsu.conf)' /etc/scanbd/scanbd.conf
fi

# --- SANE proxy mode for scanbd ---
echo "==> Configuring SANE for scanbd proxy mode..."
# Back up original dll.conf if not already backed up
if [[ ! -f /etc/sane.d/dll.conf.pre-scansnap ]]; then
    cp /etc/sane.d/dll.conf /etc/sane.d/dll.conf.pre-scansnap
fi
# System SANE clients go through scanbd's net proxy
echo "net" > /etc/sane.d/dll.conf

# Configure net backend to connect to scanbd
if ! grep -q '^localhost' /etc/sane.d/net.conf; then
    echo "connect_timeout = 3" >> /etc/sane.d/net.conf
    echo "localhost" >> /etc/sane.d/net.conf
fi

# --- Log file ---
touch /var/log/scansnap.log
chown "$INSTALL_USER":scanner /var/log/scansnap.log

# --- Start ---
echo "==> Starting scanbd..."
systemctl restart scanbd
systemctl enable scanbd

echo ""
echo "================================================"
echo "  Setup complete!"
echo "================================================"
echo ""
echo "  Next steps:"
echo "    1. Edit /etc/scansnap/scansnap.conf"
echo "       - Set PAPERLESS_URL and PAPERLESS_TOKEN"
echo "    2. Plug in your ScanSnap via USB"
echo "    3. Log out and back in (for scanner group)"
echo "    4. Press the scan button — it should just work"
echo ""
echo "  Logs:    tail -f /var/log/scansnap.log"
echo "  Status:  sudo systemctl status scanbd"
echo ""
