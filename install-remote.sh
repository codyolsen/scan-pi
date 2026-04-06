#!/usr/bin/env bash
# One-liner installer for ScanSnap Pi
# Usage: curl -sL https://raw.githubusercontent.com/codyolsen/scan-pi/main/install-remote.sh | sudo bash
set -euo pipefail

REPO="https://github.com/codyolsen/scan-pi"
BRANCH="main"
INSTALL_DIR="/tmp/scan-pi-install"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run with sudo: curl -sL <url> | sudo bash" >&2
    exit 1
fi

if [[ -z "${SUDO_USER:-}" ]]; then
    echo "Run with sudo, not as root directly" >&2
    exit 1
fi

echo "==> NOTICE ME SCAN-PI!"
echo "    https://github.com/codyolsen/scan-pi"
echo ""

# Check for git
if ! command -v git &>/dev/null; then
    echo "==> Installing git..."
    apt update -qq && apt install -y -qq git
fi

# Clone
echo "==> Downloading..."
rm -rf "$INSTALL_DIR"
git clone -q --depth 1 -b "$BRANCH" "$REPO" "$INSTALL_DIR"

# Run bootstrap (pass through INSTALL_FIRMWARE if set)
cd "$INSTALL_DIR"
./bootstrap.sh

# Cleanup
rm -rf "$INSTALL_DIR"

echo ""
echo "  Edit /etc/scansnap/scansnap.conf with your Paperless URL and token,"
echo "  then plug in your scanner and press the button."
