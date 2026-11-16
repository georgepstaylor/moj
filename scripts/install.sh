#!/usr/bin/env bash
# Installs moj from the latest release into /Applications and opens it. After that, moj
# updates itself.
#
#   curl -fsSL https://raw.githubusercontent.com/georgepstaylor/moj-releases/main/install.sh | bash
set -euo pipefail

URL="https://github.com/georgepstaylor/moj-releases/releases/latest/download/moj.zip"
DEST="/Applications/moj.app"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading moj…"
curl -fsSL "$URL" -o "$tmp/moj.zip"
ditto -x -k "$tmp/moj.zip" "$tmp"

if pgrep -xq moj; then
  echo "Quitting the running copy…"
  osascript -e 'quit app "moj"' >/dev/null 2>&1 || true
  for _ in {1..20}; do pgrep -xq moj || break; sleep 0.25; done
fi

rm -rf "$DEST"
ditto "$tmp/moj.app" "$DEST"

# Releases are notarized; this check fails if the download was tampered with.
spctl --assess --type execute "$DEST"

echo "Installed moj $(defaults read "$DEST/Contents/Info" CFBundleShortVersionString)"
echo "moj needs Accessibility access: System Settings → Privacy & Security → Accessibility."
open "$DEST"
