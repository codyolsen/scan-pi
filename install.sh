#!/usr/bin/env bash
# Deploy project files from dev machine to a Raspberry Pi
set -euo pipefail

PI_HOST="${1:?Usage: ./install.sh user@hostname}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PI_USER=$(echo "$PI_HOST" | cut -d@ -f1)
PI_DIR="/home/${PI_USER}/scan-pi"

echo "==> Syncing to ${PI_HOST}:${PI_DIR}..."
rsync -avz --exclude '.git' --exclude '*.conf' --exclude '.claude' "${SCRIPT_DIR}/" "${PI_HOST}:${PI_DIR}/"

echo "==> Running bootstrap on Pi..."
ssh "$PI_HOST" "cd ${PI_DIR} && sudo ./bootstrap.sh"

echo "==> Done. SSH in to configure: ssh ${PI_HOST}"
