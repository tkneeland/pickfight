#!/bin/bash
# Export the macOS build of pickfight from origin/main and install it to
# /Applications/Pickfight.app. Builds from a throwaway clone, so it never
# touches the working checkout. Headless only: never opens a window.
set -e
REPO=/Users/tkneeland/Desktop/godotProjects/pickfight
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git -C "$REPO" fetch -q origin
git clone -q --branch main "$REPO/.git" "$TMP/src" 2>/dev/null || git clone -q "$REPO" "$TMP/src"
git -C "$TMP/src" fetch -q "$REPO" refs/remotes/origin/main && git -C "$TMP/src" checkout -q FETCH_HEAD
SHA=$(git -C "$TMP/src" rev-parse --short HEAD)
godot --headless --path "$TMP/src" --import >/dev/null 2>&1 || true
godot --headless --path "$TMP/src" --export-release "macOS" "$TMP/Pickfight.zip" >/dev/null 2>&1
[ -s "$TMP/Pickfight.zip" ] || { echo "EXPORT FAILED"; exit 1; }
(cd "$TMP" && unzip -q Pickfight.zip)
rm -rf /Applications/Pickfight.app
mv "$TMP/Pickfight.app" /Applications/Pickfight.app
echo "$SHA" > "$HOME/.claude/pickfight-installed-sha"
echo "INSTALLED /Applications/Pickfight.app at main $SHA"
