# scan-pi — Agent Setup Guide

You are helping a user set up scan-pi: a Raspberry Pi bridge that connects a USB document scanner to Paperless-ngx over WiFi. When the user presses the scan button, the Pi captures the document and uploads it to Paperless automatically.

## Architecture

```
[Scanner] --USB--> [Raspberry Pi] --WiFi--> [Paperless-ngx on NAS]
```

- **scanbd** monitors the scanner's hardware button
- On press: **SANE/scanimage** captures pages as TIFFs
- **curl** uploads each TIFF to Paperless-ngx via REST API
- Paperless handles OCR, deskew, blank page removal, and PDF/A archival

## Before you begin — ask these questions

**You MUST gather this information from the user before running anything.** Do not assume defaults or skip questions.

### 1. Scanner model

Ask: **What scanner do you have?**

This determines:
- Whether firmware is needed (epjitsu-backend models: S1300i, S1300, S1100, S300 require it; fujitsu-backend models: iX1600, iX1400, iX1300, fi-series do not)
- The correct udev rule (USB vendor/product ID)
- The correct scanbd device config (backend filter: `^epjitsu` vs `^fujitsu`)

If the scanner is not a Fujitsu ScanSnap, it may still work if SANE supports it — check `scanimage -L` after install.

### 2. Raspberry Pi access

Ask: **What is your Pi's IP address or hostname, and what username do you SSH in with?**

You need this to SSH in and run the installer.

### 3. Paperless-ngx connection

Ask: **What is your Paperless-ngx URL and port?** (e.g. `http://192.168.1.100:8000`)

Ask: **Do you have a Paperless API token?** If not, walk them through generating one: Paperless web UI → Settings → Admin → Tokens.

### 4. Scan preferences

Ask: **Do you want duplex (double-sided) or single-sided scanning?**
- Duplex: `SOURCE="ADF Duplex"`
- Single: `SOURCE="ADF Front"`

The defaults (300 DPI, Grayscale, Duplex) are optimal for OCR. Only change if the user has a specific need.

## Installation steps

### Step 1: Run the installer

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

The bootstrap script installs packages, configures scanbd, sets up SANE proxy mode, and installs the scan scripts to `~/scansnap/`.

### Step 2: Install firmware (if needed)

**Only for epjitsu-backend models** (S1300i, S1300, S1100, S300). Skip for fujitsu-backend models.

```bash
cd scan-pi  # or wherever the repo was cloned
sudo ./scripts/install-firmware.sh s1300i
```

Run `sudo ./scripts/install-firmware.sh` with no args to see supported models.

### Step 3: Configure Paperless connection

Edit `/etc/scansnap/scansnap.conf` with the values gathered in the questions above:

```bash
sudo nano /etc/scansnap/scansnap.conf
```

Set:
- `PAPERLESS_URL` — the URL from question 3
- `PAPERLESS_TOKEN` — the token from question 3
- `SOURCE` — the scan mode from question 4

### Step 4: Connect scanner and test

1. Plug the scanner into a USB port on the Pi
2. Log out and back in (for scanner group membership to take effect)
3. Run the health check: `~/scansnap/health-check.sh`
4. Load a document and press the scan button
5. Check logs: `tail -f /var/log/scansnap.log`

## Troubleshooting

If the user has issues, run the health check first:

```bash
~/scansnap/health-check.sh
```

This checks USB detection, SANE configuration, scanbd status, firmware, Paperless connectivity, and directory permissions. Fix any `[FAIL]` items it reports.

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

## Firmware

The ScanSnap S1300i requires a proprietary firmware file (`1300i_0D12.nal`) to operate with SANE. The `install-firmware.sh` script downloads it from GitHub releases and verifies via SHA256:

- **URL**: `https://github.com/codyolsen/scan-pi/releases/download/v1.0.0/1300i_0D12.nal`
- **SHA256**: `cbea48c6cee675c2ea970944b49b805d665ee659f753a50b83c176973f507591`
- **Installed to**: `/usr/share/sane/epjitsu/1300i_0D12.nal`

Other epjitsu-backend models (S1300, S1100, S300) need their own `.nal` firmware file. These can be extracted from the Windows/Mac ScanSnap drivers.

## Non-Fujitsu scanners

For other SANE-compatible scanners:
- The udev rule in `config/99-scansnap.rules` needs the correct USB vendor/product ID (find with `lsusb`)
- The scanbd device config filter needs to match the SANE backend name (find with `scanimage -L`)
- Check [SANE supported devices](http://www.sane-project.org/sane-supported-devices.html) for compatibility
