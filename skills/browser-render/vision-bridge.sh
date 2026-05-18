#!/bin/bash
# Usage: bash vision-bridge.sh <url>
# Screenshots a URL, saves it to the openclaw outbox, and outputs a markdown image
# reference that the openclaw chat UI renders inline automatically.
set -euo pipefail

URL="${1:?Usage: bash vision-bridge.sh <url>}"
CHROMIUM=/home/node/.cache/ms-playwright/chromium-1217/chrome-linux64/chrome
OUTDIR=/exchange/outbox/openclaw/screenshots
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
IMGFILE="$OUTDIR/screenshot-$TIMESTAMP.png"

mkdir -p "$OUTDIR"

"$CHROMIUM" --headless --no-sandbox --disable-gpu \
  --screenshot="$IMGFILE" --window-size=1280,900 "$URL" 2>/dev/null

echo "![Screenshot]($IMGFILE)"
