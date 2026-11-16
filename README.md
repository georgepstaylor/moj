# moj

A macOS menu bar app for Slack-style emoji autocomplete in any app. Type `:` and part of a name (`:fire`), pick with ↑/↓ and press Return or Tab. Complete codes like `:tada:` are replaced as you type the closing colon.

moj needs Accessibility access (System Settings → Privacy & Security → Accessibility) to see what you type and to replace the shortcode.

## Build

```bash
./build.sh
open moj.app
```

Builds with SwiftPM and wraps the result in `moj.app` with Sparkle embedded. Local builds are signed with your Apple Development certificate, so the Accessibility permission survives rebuilds (an ad hoc signature would reset it every time).

## Release

```bash
scripts/release.sh 0.1.0
```

Builds a universal Release, signs it and Sparkle's helpers with Developer ID (hardened runtime, secure timestamps), notarizes and staples, signs the zip with moj's Sparkle key, publishes `moj.zip` as a release in the public [georgepstaylor/moj-releases](https://github.com/georgepstaylor/moj-releases) repo, and updates the feed (`appcast.xml`) and `install.sh` on that repo's main branch. One-time setup is in the comments at the top of the script.

The Sparkle private key lives in the login keychain under the account `moj`, and is backed up in 1Password (vault `moj-app`, item `Sparkle signing key`). Installed copies only accept updates signed with it. To set it up on another Mac:

```bash
op read "op://moj-app/Sparkle signing key/private key" > key.txt
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account moj -f key.txt
rm key.txt
```

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/georgepstaylor/moj-releases/main/install.sh | bash
```

After that, moj updates itself with Sparkle (menu bar → Check for Updates…, or automatically once a day).
