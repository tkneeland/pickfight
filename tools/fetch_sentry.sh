#!/bin/bash
# Installs the Sentry Godot SDK (#681) into addons/sentry/, which is git-ignored so its binaries
# never enter history. Pinned release + sha256; keeps only macOS (universal), Windows x86_64 and
# Linux x86_64. Without it the game runs fine: scripts/CrashReporting.gd stays inactive.
#   bash tools/fetch_sentry.sh      (from the repo root; the release workflow runs it before export)
set -euo pipefail
VER=2.3.0
URL="https://github.com/getsentry/sentry-godot/releases/download/$VER/sentry-godot-$VER%2B8ec9083.zip"
SHA=f8de89d3860b00b19bf52eb3b9d66cd3ac3e5522a375e72f16f60672450c7417
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/sentry.zip" "$URL"
echo "$SHA  $tmp/sentry.zip" | shasum -a 256 -c - >/dev/null
unzip -q "$tmp/sentry.zip" -d "$tmp/x" 'addons/sentry/bin/macos/*' 'addons/sentry/bin/windows/x86_64/*' 'addons/sentry/bin/linux/x86_64/*'
rm -rf addons/sentry; mkdir -p addons/sentry
cp -R "$tmp/x/addons/sentry/bin" addons/sentry/bin
cp tools/sentry/sentry.gdextension.template addons/sentry/sentry.gdextension
cp tools/sentry/LICENSE.md addons/sentry/
echo "Sentry Godot SDK $VER installed in addons/sentry"
