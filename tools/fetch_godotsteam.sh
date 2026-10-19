#!/bin/bash
# Installs the GodotSteam GDExtension (#428) into addons/godotsteam/, which is git-ignored so
# its ~31 MB of binaries never enter history. Pinned release + sha256; keeps only macOS universal,
# Windows x86_64 and Linux x86_64. Without it the game runs fine: SteamPlatform.gd stays dormant.
#   bash tools/fetch_godotsteam.sh      (from the repo root; the release workflow runs it before export)
set -euo pipefail
VER=4.23.1
URL="https://codeberg.org/godotsteam/godotsteam/releases/download/v$VER/godotsteam-$VER-gdextension-plugin-4.4.zip.tar.xz"
SHA=37d53ede5eda11d2247d70c1af91f95a4777ad2a419fc8a24de1cc816d21cc0a
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/gs.tar.xz" "$URL"
echo "$SHA  $tmp/gs.tar.xz" | shasum -a 256 -c - >/dev/null
tar -xJf "$tmp/gs.tar.xz" -C "$tmp" addons/godotsteam/osx addons/godotsteam/win64 addons/godotsteam/linux64
rm -rf addons/godotsteam; mkdir -p addons/godotsteam
for d in osx win64 linux64; do mkdir -p addons/godotsteam/$d; done
cp "$tmp"/addons/godotsteam/osx/libgodotsteam.macos.template_*.universal.dylib "$tmp"/addons/godotsteam/osx/libsteam_api.dylib addons/godotsteam/osx/
cp "$tmp"/addons/godotsteam/win64/libgodotsteam.windows.template_*.x86_64.dll "$tmp"/addons/godotsteam/win64/steam_api64.dll addons/godotsteam/win64/
cp "$tmp"/addons/godotsteam/linux64/libgodotsteam.linux.template_*.x86_64.so "$tmp"/addons/godotsteam/linux64/libsteam_api.so addons/godotsteam/linux64/
cp tools/godotsteam/godotsteam.gdextension tools/godotsteam/license.md addons/godotsteam/
echo "GodotSteam $VER installed in addons/godotsteam"
