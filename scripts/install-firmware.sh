#!/usr/bin/env bash
# Install scanner firmware for epjitsu-backend ScanSnap models
# Usage: sudo ./install-firmware.sh <model>
#
# Supported models:
#   s1300i  — ScanSnap S1300i
#
# Models that do NOT need firmware (fujitsu backend):
#   iX1600, iX1400, iX1300, fi-series
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run with sudo: sudo ./install-firmware.sh <model>" >&2
    exit 1
fi

MODEL="${1:-}"

case "$MODEL" in
    s1300i)
        FIRMWARE_FILE="1300i_0D12.nal"
        FIRMWARE_SHA256="cbea48c6cee675c2ea970944b49b805d665ee659f753a50b83c176973f507591"
        ;;
    "")
        echo "Usage: sudo ./install-firmware.sh <model>"
        echo ""
        echo "Supported models:"
        echo "  s1300i    ScanSnap S1300i"
        echo ""
        echo "Not needed for: iX1600, iX1400, iX1300, fi-series (fujitsu backend)"
        exit 0
        ;;
    *)
        echo "Unknown model: $MODEL" >&2
        echo "Supported: s1300i" >&2
        echo "If your model isn't listed, you may need to extract the .nal file from the Windows/Mac ScanSnap drivers." >&2
        exit 1
        ;;
esac

FIRMWARE_DIR="/usr/share/sane/epjitsu"
FIRMWARE_PATH="${FIRMWARE_DIR}/${FIRMWARE_FILE}"
FIRMWARE_URL="https://github.com/codyolsen/scan-pi/releases/download/v1.0.0/${FIRMWARE_FILE}"

mkdir -p "$FIRMWARE_DIR"

if [[ -f "$FIRMWARE_PATH" ]]; then
    echo "Firmware already installed at ${FIRMWARE_PATH}"
    exit 0
fi

echo "Downloading ${FIRMWARE_FILE}..."
curl -sL -o "$FIRMWARE_PATH" "$FIRMWARE_URL"

ACTUAL_SHA=$(sha256sum "$FIRMWARE_PATH" | cut -d' ' -f1)
if [[ "$ACTUAL_SHA" != "$FIRMWARE_SHA256" ]]; then
    rm -f "$FIRMWARE_PATH"
    echo "ERROR: Checksum mismatch — download may be corrupt" >&2
    echo "  Expected: ${FIRMWARE_SHA256}" >&2
    echo "  Got:      ${ACTUAL_SHA}" >&2
    exit 1
fi

echo "Installed and verified: ${FIRMWARE_PATH}"
