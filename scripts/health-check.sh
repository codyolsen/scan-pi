#!/usr/bin/env bash
# scan-pi health check — verify scanner, scanbd, and Paperless connectivity
set +e

CONF="${CONF:-/etc/scansnap/scansnap.conf}"
if [[ -f "$CONF" ]]; then
    # shellcheck source=/dev/null
    source "$CONF"
fi

PASS=0
FAIL=0
WARN=0

pass() { echo "  [OK]   $1"; (( PASS++ )); }
fail() { echo "  [FAIL] $1"; (( FAIL++ )); }
warn() { echo "  [WARN] $1"; (( WARN++ )); }

echo "scan-pi health check"
echo "===================="
echo ""

# --- Scanner USB ---
echo "Scanner:"
DEVICE_LINE=$(lsusb 2>/dev/null | grep -i -E 'fujitsu|04c5' | head -1)
if [[ -n "$DEVICE_LINE" ]]; then
    pass "USB device found: ${DEVICE_LINE}"
else
    fail "No scanner on USB (is it plugged in and powered on?)"
fi

if command -v sane-find-scanner &>/dev/null; then
    SANE_FOUND=$(sane-find-scanner -q 2>&1 | grep -i -E 'fujitsu|04c5' | head -1)
    if [[ -n "$SANE_FOUND" ]]; then
        pass "SANE finds the scanner"
    else
        fail "SANE cannot find the scanner (check USB cable/port)"
    fi
else
    fail "sane-find-scanner not installed (apt install sane-utils)"
fi

echo ""

# --- scanbd ---
echo "scanbd:"
if systemctl is-active --quiet scanbd 2>/dev/null; then
    pass "scanbd is running"
else
    fail "scanbd is not running (sudo systemctl start scanbd)"
fi

if [[ -f /etc/scanbd/scanner.d/epjitsu.conf ]]; then
    pass "epjitsu device config present"
else
    fail "Missing /etc/scanbd/scanner.d/epjitsu.conf"
fi

if [[ -f /etc/scanbd/scripts/scan.script ]]; then
    pass "Scan trigger script present"
else
    fail "Missing /etc/scanbd/scripts/scan.script"
fi

echo ""

# --- SANE config ---
echo "SANE config:"
if [[ -f /etc/sane.d/dll.conf ]]; then
    DLL_CONTENT=$(grep -v '^#' /etc/sane.d/dll.conf | grep -v '^$')
    if [[ "$DLL_CONTENT" == "net" ]]; then
        pass "dll.conf set to net-only (scanbd proxy mode)"
    else
        warn "dll.conf has more than just 'net' — scanbd may not work"
    fi
else
    fail "Missing /etc/sane.d/dll.conf"
fi

if grep -q '^localhost' /etc/sane.d/net.conf 2>/dev/null; then
    pass "net.conf points to localhost"
else
    fail "net.conf missing localhost entry"
fi

echo ""

# --- Firmware ---
echo "Firmware:"
if [[ -f /usr/share/sane/epjitsu/1300i_0D12.nal ]]; then
    SIZE=$(stat -c%s /usr/share/sane/epjitsu/1300i_0D12.nal 2>/dev/null || stat -f%z /usr/share/sane/epjitsu/1300i_0D12.nal 2>/dev/null)
    if [[ "$SIZE" -gt 60000 && "$SIZE" -lt 70000 ]]; then
        pass "S1300i firmware present (${SIZE} bytes)"
    else
        fail "Firmware file wrong size (${SIZE} bytes, expected ~65K) — may be corrupt"
    fi
else
    warn "S1300i firmware not found (only needed for S1300i/S1300/S1100)"
fi

echo ""

# --- Scripts ---
echo "Scripts:"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
for script in scan-and-upload.sh upload-to-paperless.sh; do
    if [[ -x "${SCRIPT_DIR}/${script}" ]]; then
        pass "${script} present and executable"
    elif [[ -f "${SCRIPT_DIR}/${script}" ]]; then
        warn "${script} present but not executable"
    else
        fail "${script} not found in ${SCRIPT_DIR}"
    fi
done

echo ""

# --- Config ---
echo "Config:"
if [[ -f "$CONF" ]]; then
    pass "Config file exists at ${CONF}"
else
    fail "No config file at ${CONF}"
fi

if [[ -n "${PAPERLESS_URL:-}" ]]; then
    pass "PAPERLESS_URL is set: ${PAPERLESS_URL}"
else
    fail "PAPERLESS_URL is not set in config"
fi

if [[ -n "${PAPERLESS_TOKEN:-}" ]]; then
    pass "PAPERLESS_TOKEN is set"
else
    fail "PAPERLESS_TOKEN is not set in config"
fi

echo ""

# --- Paperless connectivity ---
echo "Paperless:"
if [[ -n "${PAPERLESS_URL:-}" && -n "${PAPERLESS_TOKEN:-}" ]]; then
    HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
        -H "Authorization: Token ${PAPERLESS_TOKEN}" \
        "${PAPERLESS_URL}/api/" 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" == "200" ]]; then
        pass "Paperless API reachable and authenticated"
    elif [[ "$HTTP_CODE" == "401" || "$HTTP_CODE" == "403" ]]; then
        fail "Paperless reachable but token is invalid (HTTP ${HTTP_CODE})"
    elif [[ "$HTTP_CODE" == "000" ]]; then
        fail "Cannot reach Paperless at ${PAPERLESS_URL} (connection refused or DNS failure)"
    else
        warn "Paperless returned HTTP ${HTTP_CODE}"
    fi
else
    warn "Skipping Paperless check (URL or token not configured)"
fi

echo ""

# --- Directories ---
echo "Directories:"
for d in "${SCAN_DIR:-/var/lib/scansnap/scans}" "${QUEUE_DIR:-/var/lib/scansnap/upload-queue}" "${DEAD_LETTER_DIR:-/var/lib/scansnap/dead-letter}"; do
    if [[ -d "$d" && -w "$d" ]]; then
        pass "${d} exists and writable"
    elif [[ -d "$d" ]]; then
        fail "${d} exists but not writable"
    else
        fail "${d} does not exist"
    fi
done

QUEUED=$(find "${QUEUE_DIR:-/var/lib/scansnap/upload-queue}" -name '*.tiff' 2>/dev/null | wc -l | tr -d '[:space:]')
if [[ "$QUEUED" -gt 0 ]]; then
    warn "${QUEUED} file(s) stuck in retry queue"
fi

# --- Summary ---
echo ""
echo "===================="
echo "  ${PASS} passed, ${FAIL} failed, ${WARN} warnings"
if [[ "$FAIL" -eq 0 ]]; then
    echo "  Ready to scan!"
else
    echo "  Fix the failures above and re-run."
fi

exit "$FAIL"
