#!/bin/zsh
# Builds moj.app (release) next to this script.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=moj.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/moj" "$APP/Contents/MacOS/moj"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Ad-hoc signature. Set SIGN_ID to a Developer ID to keep Accessibility permission across rebuilds.
codesign --force --deep --sign "${SIGN_ID:--}" "$APP"
echo "Built $(pwd)/$APP"
