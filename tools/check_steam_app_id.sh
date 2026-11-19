#!/bin/bash
# Usage: bash tools/check_steam_app_id.sh <project.godot> [app id]
# A shipped build's Steam app ID (#1289, docs/steam-readiness.md 1.5). The release workflow runs it before export
# with the STEAM_APP_ID repo variable, and tools/export.sh with $STEAM_APP_ID (full game) or $STEAM_DEMO_APP_ID (the
# Next Fest demo, which Steam gives its own app ID) on a copy of project.godot it restores afterwards:
#   no app ID: prints "unset" and changes nothing, so the build keeps the dev default 480 (Spacewar). Under GitHub
#     Actions it also prints a ::warning:: so a tag that ships 480 to itch is visible (the steam job skips anyway).
#   a whole number from 1 to 4294967295 (Steam app IDs are 32-bit), not 480, no leading zero: writes it as
#     `steam_app_id=` under [pickfight] and prints it.
#   anything else (480, 0, leading zeros, too big, not a number, no single steam_app_id line): exits 1 and writes
#     nothing, so a build never ships Spacewar or an ID Steam would read differently from the upload's.
# With a real ID, scripts/SteamPlatform.gd's steamInitEx only succeeds for players who own the game on Steam (no
# relaunch through Steam): itch players without it get no Steam features (invites, Steam name), where 480 gave
# them to anyone with Steam open.
f=$1; id=${2-}
[ -f "$f" ] || { echo "check_steam_app_id: no such file: $f" >&2; exit 2; }
if [ -z "$id" ]; then
	[ -n "${GITHUB_ACTIONS:-}" ] && echo "::warning::STEAM_APP_ID is not set: this build keeps Spacewar's app ID 480 (fine before the Steam app exists; docs/steam-readiness.md 1.5)" >&2
	echo unset; exit 0
fi
fail() { echo "::error::Steam app ID $1" >&2; exit 1; }
case $id in *[!0-9]*) fail "'$id' is not a whole number";; 0*) fail "'$id' is 0 or has a leading zero";; esac
[ ${#id} -le 10 ] && [ "$id" -le 4294967295 ] || fail "'$id' is above 4294967295 (Steam app IDs are 32-bit)"
[ "$id" -ne 480 ] || fail "is 480 (Spacewar, Valve's test app): never ship it (docs/steam-readiness.md 1.5)"
[ "$(grep -c '^steam_app_id=' "$f")" = 1 ] || fail "has no single steam_app_id= line to set in $f"
sed -i.bak "s/^steam_app_id=.*/steam_app_id=$id/" "$f" && rm -f "$f.bak"
grep -qx "steam_app_id=$id" "$f" || fail "could not be written to $f"
echo "$id"
