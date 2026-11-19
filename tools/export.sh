#!/usr/bin/env bash
# Build release exports for macOS (.app), Windows (.exe) and Linux into build/,
# or the Next Fest demo (the Demo presets) into build/demo/.
# Usage: tools/export.sh [macos|windows|linux|all|demo]   (default: all)
# Needs Godot 4.6.2 on PATH (or GODOT=/path/to/godot) and the 4.6.2 export
# templates installed (Editor > Manage Export Templates, or the .tpz from
# https://github.com/godotengine/godot/releases/tag/4.6.2-stable).
set -euo pipefail

cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
TARGET="${1:-all}"

# A fresh clone has no .godot/ import cache; an import pass builds it so the
# export includes the imported assets (sounds, textures).
if [ ! -d .godot/imported ]; then
	"$GODOT" --headless --path . --import
fi

# The shipped Steam app ID (#1289, docs/steam-readiness.md 1.5): $STEAM_APP_ID for the full game, $STEAM_DEMO_APP_ID
# for the demo (Steam gives a demo its own app ID). Set, it goes into project.godot for this export only and the
# file is put back afterwards; 480, 0 or a malformed ID stops the export. Unset, the build keeps the dev 480.
if [ "$TARGET" = demo ]; then APP_ID="${STEAM_DEMO_APP_ID:-}"; else APP_ID="${STEAM_APP_ID:-}"; fi
if [ -n "$APP_ID" ]; then
	cp project.godot project.godot.export-backup
	trap 'mv -f project.godot.export-backup project.godot' EXIT
	bash tools/check_steam_app_id.sh project.godot "$APP_ID" >/dev/null
	echo "Steam app ID $APP_ID for this export"
else
	echo "No $([ "$TARGET" = demo ] && echo STEAM_DEMO_APP_ID || echo STEAM_APP_ID) set: this build keeps the dev Steam app ID 480 (do not ship it)" >&2
fi

export_one() {
	local preset="$1" out="$2"
	mkdir -p "$(dirname "$out")"
	"$GODOT" --headless --path . --export-release "$preset" "$out"
	echo "Built $out"
}

case "$TARGET" in
	macos)   export_one "macOS" "build/macos/Pickfight.app" ;;
	windows) export_one "Windows" "build/windows/Pickfight.exe" ;;
	linux)   export_one "Linux" "build/linux/pickfight.x86_64" ;;
	all)
		export_one "macOS" "build/macos/Pickfight.app"
		export_one "Windows" "build/windows/Pickfight.exe"
		export_one "Linux" "build/linux/pickfight.x86_64"
		;;
	demo)
		export_one "Demo macOS" "build/demo/macos/Pickfight Demo.app"
		export_one "Demo Windows" "build/demo/windows/Pickfight Demo.exe"
		export_one "Demo Linux" "build/demo/linux/pickfight-demo.x86_64"
		;;
	*) echo "usage: $0 [macos|windows|linux|all|demo]" >&2; exit 2 ;;
esac
