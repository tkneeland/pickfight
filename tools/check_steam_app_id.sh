#!/bin/bash
# Usage: bash tools/check_steam_app_id.sh <project.godot> [app id]
# The release build's Steam app ID (#1289, docs/steam-readiness.md 1.5). The release workflow runs it before export
# with the STEAM_APP_ID repo variable (docs/steam-upload.md):
#   no app ID (the variable is unset): prints "unset" and changes nothing. Builds keep the dev default, 480, and the
#     release's steam job skips the upload, as it already does without the variable.
#   a positive whole number other than 480: writes it as `steam_app_id=` under [pickfight] and prints it.
#   anything else (480, 0, not a number, no steam_app_id line): exits 1 and writes nothing, so a tag never ships
#     Spacewar (Valve's test app, 480) or a broken ID to Steam or itch.
# scripts/SteamPlatform.gd reads the setting and calls steamInitEx with it (no relaunch through Steam), so itch
# players without the game on Steam just get no Steam features, as today.
f=$1; id=${2-}
[ -f "$f" ] || { echo "check_steam_app_id: no such file: $f" >&2; exit 2; }
[ -n "$id" ] || { echo unset; exit 0; }
fail() { echo "::error::STEAM_APP_ID $1" >&2; exit 1; }
case $id in *[!0-9]*) fail "'$id' is not a whole number";; esac
[ ${#id} -le 10 ] || fail "'$id' is too long for a Steam app ID"
id=$((10#$id))
[ "$id" -gt 0 ] || fail "is 0"
[ "$id" -ne 480 ] || fail "is 480 (Spacewar, Valve's test app): never ship it (docs/steam-readiness.md 1.5)"
[ "$(grep -c '^steam_app_id=' "$f")" = 1 ] || fail "has no single steam_app_id= line to set in $f"
sed -i.bak "s/^steam_app_id=.*/steam_app_id=$id/" "$f" && rm -f "$f.bak"
grep -qx "steam_app_id=$id" "$f" || fail "could not be written to $f"
echo "$id"
