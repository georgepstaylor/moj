#!/usr/bin/env bash
# Builds, signs, notarizes and publishes a moj release.
#
#   scripts/release.sh 0.2.1
#
# The notarized moj.zip goes to a release in the public georgepstaylor/moj-releases repo. Sparkle's
# update feed is appcast.xml on that repo's main branch (SUFeedURL in Resources/Info.plist), and
# scripts/install.sh is published beside it. This repo gets the version tag.
#
# Needs, once per Mac:
#   - A "Developer ID Application" certificate in the login keychain.
#   - A notarytool profile (default "cadence-notary", the same Apple ID and team as Cadence;
#     override with NOTARY_PROFILE):
#       xcrun notarytool store-credentials cadence-notary --apple-id <you@example.com> --team-id 4Y2TS85X2J
#   - moj's Sparkle EdDSA private key in the login keychain, under the account "moj" (its public
#     half is SUPublicEDKey in Resources/Info.plist). Without the same key, installed copies refuse
#     updates. It's backed up in 1Password (vault moj-app, item "Sparkle signing key"); import it with:
#       op read "op://moj-app/Sparkle signing key/private key" > key.txt
#       .build/artifacts/sparkle/Sparkle/bin/generate_keys --account moj -f key.txt && rm key.txt
# And once: the public georgepstaylor/moj-releases repo, with a main branch.
set -euo pipefail

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: scripts/release.sh <major.minor.patch>" >&2
  exit 64
fi
TAG="v$VERSION"
PUBLIC_REPO="georgepstaylor/moj-releases"
FEED_URL="https://raw.githubusercontent.com/$PUBLIC_REPO/main/appcast.xml"
SPARKLE_ACCOUNT="moj"
cd "$(dirname "$0")/.."

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

step "Checking the repo"
[[ "$(git branch --show-current)" == "main" ]] || fail "release from main"
[[ -z "$(git status --porcelain)" ]] || fail "commit or stash your changes first"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && fail "tag $TAG already exists"
gh auth status >/dev/null 2>&1 || fail "gh isn't logged in (gh auth login)"
gh repo view "$PUBLIC_REPO" >/dev/null 2>&1 || fail "$PUBLIC_REPO doesn't exist (see the comment at the top)"
BUILD_NUMBER="$(git rev-list --count HEAD)"
PREVIOUS_TAG="$(git describe --tags --abbrev=0 HEAD 2>/dev/null || true)"

# Releases reach people automatically through Sparkle, so they must be notarized.
NOTARY_PROFILE="${NOTARY_PROFILE:-cadence-notary}"
DEVELOPER_ID="$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)"
[[ -n "$DEVELOPER_ID" ]] || fail "no Developer ID Application certificate in the keychain"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || fail "notarytool profile '$NOTARY_PROFILE' not found (see the comment at the top)"
echo "Signing with $DEVELOPER_ID and notarizing (profile $NOTARY_PROFILE)"

step "Building moj $VERSION ($BUILD_NUMBER)"
rm -rf dist
mkdir -p dist
RELEASE=1 VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" SIGN_ID="$DEVELOPER_ID" ./build.sh
APP="moj.app"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
[[ "$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString)" == "$VERSION" ]] || fail "version mismatch in Info.plist"
if codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q get-task-allow; then
  fail "the app has the get-task-allow entitlement; Apple won't notarize it"
fi

ZIP="dist/moj.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

step "Notarizing (usually a few minutes)"
result="$(xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)"
submission="$(plutil -extract id raw - <<<"$result")"
status="$(plutil -extract status raw - <<<"$result")"
if [[ "$status" != "Accepted" ]]; then
  xcrun notarytool log "$submission" --keychain-profile "$NOTARY_PROFILE" >&2 || true
  fail "notarization $status (submission $submission)"
fi
xcrun stapler staple "$APP"
spctl --assess --type execute "$APP"
rm "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP"

step "Writing the update feed"
# What changed since the previous version, from this repo's commit subjects. Shown in Sparkle's
# update window (as HTML) and on the release page (as Markdown).
CHANGES="$(git log --no-merges --format='%s' ${PREVIOUS_TAG:+"$PREVIOUS_TAG"..}HEAD)"
CHANGES_HTML="$(sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's|^|<li>|' -e 's|$|</li>|' <<<"$CHANGES")"
# sign_update prints: sparkle:edSignature="…" length="…"
SIGNATURE_ATTRS="$("$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" "$ZIP")"
[[ "$SIGNATURE_ATTRS" == *edSignature* ]] || fail "sign_update didn't return a signature (is the Sparkle key in this keychain?)"

# Sparkle only needs the newest release in the feed.
cat > dist/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>moj</title>
    <item>
      <title>moj $VERSION</title>
      <pubDate>$(LC_ALL=C date -R)</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<h3>What's new in moj $VERSION</h3><ul>$CHANGES_HTML</ul>]]></description>
      <enclosure url="https://github.com/$PUBLIC_REPO/releases/download/$TAG/moj.zip" type="application/octet-stream" $SIGNATURE_ATTRS/>
    </item>
  </channel>
</rss>
XML
xmllint --noout dist/appcast.xml

step "Publishing $TAG"
git tag -a "$TAG" -m "moj $VERSION"
if git remote get-url origin >/dev/null 2>&1; then
  git push origin main
  git push origin "$TAG"
else
  echo "No origin remote: tagged $TAG locally only"
fi

NOTES="dist/notes.md"
{
  echo "Download **moj.zip**, unzip it and move moj to Applications, or run:"
  echo
  echo '```'
  echo "curl -fsSL https://raw.githubusercontent.com/$PUBLIC_REPO/main/install.sh | bash"
  echo '```'
  echo
  echo "Installed copies update themselves."
  echo
  echo "### Changes"
  sed 's/^/- /' <<<"$CHANGES"
} > "$NOTES"
gh release create "$TAG" "$ZIP" dist/appcast.xml --repo "$PUBLIC_REPO" \
  --title "moj $VERSION" --notes-file "$NOTES"

# Puts a file on the public repo's main branch, creating or replacing it.
publish_file() {
  local local_path="$1" remote_path="$2" sha
  sha="$(gh api "repos/$PUBLIC_REPO/contents/$remote_path" --jq .sha 2>/dev/null || true)"
  gh api -X PUT "repos/$PUBLIC_REPO/contents/$remote_path" --silent \
    -f message="moj $VERSION: $remote_path" -f content="$(base64 < "$local_path" | tr -d '\n')" \
    ${sha:+-f sha="$sha"}
}
publish_file scripts/install.sh install.sh
# Last, so the feed only ever points at a download that exists.
publish_file dist/appcast.xml appcast.xml
curl -fsS "$FEED_URL" >/dev/null || echo "warning: $FEED_URL isn't reachable yet" >&2

step "Done"
gh release view "$TAG" --repo "$PUBLIC_REPO" --json url --jq .url
