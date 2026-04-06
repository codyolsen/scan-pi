#!/usr/bin/env bash
# Triggered by scanbd on button press — scan and upload TIFFs to Paperless
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="${CONF:-/etc/scansnap/scansnap.conf}"

if [[ -f "$CONF" ]]; then
    # shellcheck source=/dev/null
    source "$CONF"
fi

RESOLUTION="${RESOLUTION:-300}"
COLOR_MODE="${COLOR_MODE:-Gray}"
SOURCE="${SOURCE:-ADF Duplex}"
RETRY_MAX="${RETRY_MAX:-3}"
RETRY_DELAY="${RETRY_DELAY:-30}"
CLEANUP_ON_SUCCESS="${CLEANUP_ON_SUCCESS:-true}"
SCAN_DIR="${SCAN_DIR:-/var/lib/scansnap/scans}"
QUEUE_DIR="${QUEUE_DIR:-/var/lib/scansnap/upload-queue}"
DEAD_LETTER_DIR="${DEAD_LETTER_DIR:-/var/lib/scansnap/dead-letter}"

for d in "$SCAN_DIR" "$QUEUE_DIR" "$DEAD_LETTER_DIR"; do
    mkdir -p "$d"
done

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
WORKDIR="${SCAN_DIR}/${TIMESTAMP}"
mkdir -p "$WORKDIR"

# Discover scanner
DEVICE="${SCANNER_DEVICE:-}"
if [[ -z "$DEVICE" ]]; then
    DEVICE=$(scanimage -L 2>/dev/null | head -1 | sed "s/.*\`\(.*\)'.*/\1/")
fi

if [[ -z "$DEVICE" ]]; then
    log "ERROR: No scanner found"
    rm -rf "$WORKDIR"
    exit 1
fi

log "Scanning on $DEVICE..."

scanimage \
    --device-name="$DEVICE" \
    --resolution "$RESOLUTION" \
    --mode "$COLOR_MODE" \
    --source "$SOURCE" \
    --format=tiff \
    --batch="${WORKDIR}/page_%04d.tiff" \
    2>&1 || true

PAGES=$(find "$WORKDIR" -name 'page_*.tiff' | sort)
PAGE_COUNT=$(echo "$PAGES" | grep -c . || true)

if [[ "$PAGE_COUNT" -eq 0 ]]; then
    log "No pages scanned (feeder empty?)"
    rm -rf "$WORKDIR"
    exit 0
fi

log "Scanned $PAGE_COUNT page(s), uploading to Paperless..."

FAILED=0
while IFS= read -r tiff; do
    PAGE_NAME=$(basename "$tiff" .tiff)
    ATTEMPT=0
    UPLOADED=false

    while (( ATTEMPT < RETRY_MAX )); do
        if "$SCRIPT_DIR/upload-to-paperless.sh" "$tiff" "scan-${TIMESTAMP}-${PAGE_NAME}"; then
            UPLOADED=true
            break
        fi
        (( ATTEMPT++ ))
        log "Upload attempt $ATTEMPT/$RETRY_MAX failed for $PAGE_NAME, retrying in ${RETRY_DELAY}s..."
        sleep "$RETRY_DELAY"
    done

    if [[ "$UPLOADED" != "true" ]]; then
        log "Upload failed for $PAGE_NAME, queuing for retry"
        mv "$tiff" "$QUEUE_DIR/"
        (( FAILED++ ))
    fi
done <<< "$PAGES"

if [[ "$FAILED" -eq 0 ]]; then
    log "All $PAGE_COUNT page(s) uploaded successfully"
    if [[ "$CLEANUP_ON_SUCCESS" == "true" ]]; then
        rm -rf "$WORKDIR"
    fi
else
    log "$FAILED page(s) failed, moved to retry queue"
    rm -rf "$WORKDIR"
fi
