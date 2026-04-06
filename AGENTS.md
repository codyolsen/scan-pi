# scan-pi — LLM/Agent Setup Guide

You are helping a user set up scan-pi: a Raspberry Pi bridge that connects a USB document scanner to Paperless-ngx over WiFi. When the user presses the scan button, the Pi captures the document and uploads it to Paperless automatically.

## What this project does

```
[Scanner] --USB--> [Raspberry Pi] --WiFi--> [Paperless-ngx on NAS]
```

- **scanbd** monitors the scanner's hardware button
- On press: **SANE/scanimage** captures pages as TIFFs
- **curl** uploads each TIFF to Paperless-ngx via REST API
- Paperless handles OCR, deskew, blank page removal, and PDF/A archival

## Prerequisites the user needs

1. A Raspberry Pi (3B+ or newer) with SSH access and WiFi configured
2. A SANE-compatible USB document scanner (tested: Fujitsu ScanSnap S1300i)
3. A running Paperless-ngx instance on the network with an API token

## Installation steps

### Step 1: Install on the Pi

SSH into the Pi and run:

```bash
curl -sL https://raw.githubusercontent.com/codyolsen/scan-pi/main/install-remote.sh | sudo bash
```

Or clone and run manually:

```bash
git clone https://github.com/codyolsen/scan-pi.git
cd scan-pi
sudo ./bootstrap.sh
```

The bootstrap script will:
- Install sane-utils, scanbd, curl, jq
- Download scanner firmware (ScanSnap S1300i)
- Configure scanbd for button detection
- Configure SANE in scanbd proxy mode
- Install scan scripts to ~/scansnap/
- Create working directories at /var/lib/scansnap/

### Step 2: Configure Paperless connection

Edit `/etc/scansnap/scansnap.conf` and set:
- `PAPERLESS_URL` — e.g. `http://192.168.1.100:8000`
- `PAPERLESS_TOKEN` — generate at Paperless Settings → Admin → Tokens

### Step 3: Connect scanner and test

1. Plug the scanner into a USB port on the Pi
2. Log out and back in (for scanner group membership)
3. Run the health check: `~/scansnap/health-check.sh`
4. Load a document and press the scan button
5. Check logs: `tail -f /var/log/scansnap.log`

## Troubleshooting

If the user has issues, run the health check first:

```bash
~/scansnap/health-check.sh
```

This checks USB detection, SANE configuration, scanbd status, firmware, Paperless connectivity, and directory permissions. Fix any [FAIL] items it reports.

Common issues:
- **Scanner not on USB**: Try a different cable or port. USB 2.0 ports (black) are more reliable than USB 3.0 (blue) for older scanners.
- **scanbd not running**: `sudo systemctl restart scanbd`
- **SANE can't find scanner**: Check that `/etc/sane.d/dll.conf` contains only `net` and `/etc/sane.d/net.conf` has `localhost`.
- **Paperless upload fails**: Verify URL and token with `curl -s -H "Authorization: Token <token>" http://<url>/api/`

## Key files on the Pi after install

- `~/scansnap/scan-and-upload.sh` — main scan script (triggered by scanbd)
- `~/scansnap/upload-to-paperless.sh` — Paperless API upload helper
- `~/scansnap/health-check.sh` — diagnostic tool
- `/etc/scansnap/scansnap.conf` — all configuration (scan settings, Paperless connection)
- `/var/log/scansnap.log` — scan activity log

## Non-S1300i scanners

For other SANE-compatible scanners:
- The udev rule in `config/99-scansnap.rules` needs the correct USB vendor/product ID
- The scanbd device config in `config/scanner.d/epjitsu.conf` needs the correct backend filter
- Fujitsu-backend scanners (iX1600, iX1400, fi-series) don't need firmware — change filter from `^epjitsu` to `^fujitsu`
- Other brands: check `scanimage -L` for the backend name and adjust accordingly
