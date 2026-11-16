#!/bin/zsh
# Builds moj.app next to this script.
#
#   ./build.sh                            a local build, signed with your Apple Development certificate
#   RELEASE=1 VERSION=1.2.0 ./build.sh    what scripts/release.sh runs: universal, Developer ID,
#                                         hardened runtime and secure timestamps (needed to notarize)
#
# SIGN_ID overrides the signing identity. A stable identity (not ad hoc, "-") keeps the
# Accessibility permission working across rebuilds.
set -euo pipefail
cd "$(dirname "$0")"

RELEASE="${RELEASE:-0}"
VERSION="${VERSION:-0.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 0)}"

identity() { security find-identity -v -p codesigning | grep -o "\"$1: [^\"]*\"" | head -1 | tr -d '"' || true; }
if [[ -z "${SIGN_ID:-}" ]]; then
  if [[ "$RELEASE" == 1 ]]; then SIGN_ID="$(identity 'Developer ID Application')"; else SIGN_ID="$(identity 'Apple Development')"; fi
  SIGN_ID="${SIGN_ID:--}"
fi

ARCHS=()
[[ "$RELEASE" == 1 ]] && ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

APP=moj.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$BIN/moj" "$APP/Contents/MacOS/moj"
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# The icon (drawn by scripts/make-icon.swift): Assets.car for macOS 26+, AppIcon.icns for older.
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx \
  --minimum-deployment-target 14.0 --app-icon AppIcon \
  --output-partial-info-plist "$(mktemp -t moj-icon).plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

# Sign inside out: Sparkle's helpers, the framework, then the app (Sparkle's documented order).
SIGN_FLAGS=(--force --sign "$SIGN_ID")
[[ "$RELEASE" == 1 ]] && SIGN_FLAGS+=(--options runtime --timestamp)
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
for item in "$SPARKLE/Versions/B/XPCServices/Installer.xpc" "$SPARKLE/Versions/B/XPCServices/Downloader.xpc" \
            "$SPARKLE/Versions/B/Autoupdate" "$SPARKLE/Versions/B/Updater.app" "$SPARKLE"; do
  [[ -e "$item" ]] && codesign "${SIGN_FLAGS[@]}" --preserve-metadata=entitlements "$item"
done
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"

echo "Built $(pwd)/$APP $VERSION ($BUILD_NUMBER), signed with $SIGN_ID"
