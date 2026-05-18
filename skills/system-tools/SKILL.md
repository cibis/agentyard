---
name: system-tools
description: Shell utilities pre-installed in the openclaw container — browser automation (Chromium), HTTP clients, JSON processing, Python, archive tools, network diagnostics, and process management.
---

# System Tools Skill

The following tools are pre-installed in the openclaw container and available in every shell command.

---

## Browser Automation — Chromium

Chromium is installed via Playwright at:
`/home/node/.cache/ms-playwright/chromium-1217/chrome-linux64/chrome`

Use the shell alias below, or let openclaw's built-in `browser` tool handle navigation (preferred — it manages tabs, SSRF policy, and CDP automatically).

```bash
# Convenient alias (add to scripts that need direct chromium access)
CHROMIUM=/home/node/.cache/ms-playwright/chromium-1217/chrome-linux64/chrome

# Screenshot a page (saves to /tmp/screenshot.png)
$CHROMIUM --headless --no-sandbox --disable-gpu \
  --screenshot=/tmp/screenshot.png \
  --window-size=1280,900 \
  https://example.com

# Dump page HTML to stdout
$CHROMIUM --headless --no-sandbox --disable-gpu \
  --dump-dom \
  https://example.com

# Print page to PDF
$CHROMIUM --headless --no-sandbox --disable-gpu \
  --print-to-pdf=/tmp/page.pdf \
  https://example.com
```

> Always include `--no-sandbox --disable-gpu` in Docker.
> For web browsing tasks, prefer openclaw's `browser` tool — it is already configured with `noSandbox` and permissive SSRF policy.

---

## HTTP Clients — curl / wget

```bash
# GET request
curl -s https://api.example.com/data

# POST JSON
curl -s -X POST https://api.example.com/endpoint \
  -H "Content-Type: application/json" \
  -d '{"key":"value"}'

# Download file silently
wget -q -O /tmp/file.zip https://example.com/file.zip

# Follow redirects, save with original filename
wget -q https://example.com/archive.tar.gz
```

---

## JSON Processing — jq

```bash
# Pretty-print
curl -s https://api.example.com/data | jq .

# Extract field
curl -s https://api.example.com/data | jq '.results[0].name'

# Filter array
echo '[{"name":"a","val":1},{"name":"b","val":2}]' | jq '.[] | select(.val > 1)'

# Transform to CSV
echo '[{"a":1,"b":2},{"a":3,"b":4}]' | jq -r '.[] | [.a,.b] | @csv'
```

---

## Python 3

```bash
# Run a script
python3 /path/to/script.py

# One-liner
python3 -c "import json, sys; data=json.load(sys.stdin); print(data['key'])"

# Install a package (scoped to current session)
pip3 install requests --quiet

# Quick HTTP server on port 9080
python3 -m http.server 9080 --directory /tmp/www
```

---

## Archive Tools — zip / unzip

```bash
# Extract zip
unzip -q archive.zip -d /tmp/output/

# Create zip
zip -qr output.zip /path/to/directory/

# List contents without extracting
unzip -l archive.zip
```

---

## Network Diagnostics

```bash
# Ping host
ping -c 4 8.8.8.8

# DNS lookup
dig example.com
nslookup example.com

# Show network interfaces
ifconfig

# Show open ports / connections
netstat -tlnp
```

---

## Process Management — procps / htop

```bash
# List all processes
ps aux

# Find by name
pgrep -a chromium

# Kill by name
pkill chromium

# Interactive process viewer (terminal required)
htop
```

---

## Build Tools — gcc / g++ / make

```bash
# Compile C
gcc -o /tmp/mybin /tmp/myprogram.c

# Compile C++
g++ -o /tmp/mybin /tmp/myprogram.cpp

# Run make
make -C /tmp/project/
```

---

## Text Editing — vim / nano

```bash
# Edit file (non-interactive one-liner with vim)
vim -c '%s/foo/bar/g' -c 'wq' /path/to/file

# Append a line
echo "new line" >> /path/to/file

# nano is available for interactive sessions via SSH
nano /path/to/file
```

---

## Virtual Display — Xvfb

Provides a headless X display for GUI apps that require one (beyond Chromium's `--headless` flag).

```bash
# Start virtual display on :99
Xvfb :99 -screen 0 1280x900x24 &
export DISPLAY=:99

# Run a GUI app against it
DISPLAY=:99 some-gui-app
```

---

## Notes

- All tools are available without `sudo` (container runs as root).
- Chromium binary name is `chromium` (not `chromium-browser`) on this image.
- `pip3 install` installs into the session only; for persistent packages add them to the docker-compose startup script in `docker-compose.yml`.
- Python packages needed repeatedly should be added to the `apt-get install` block in `docker-compose.yml` or installed via pip in the startup script.
