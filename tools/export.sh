#!/usr/bin/env bash
# Build release exports for macOS (.app) and Windows (.exe) into build/.
# Usage: tools/export.sh [macos|windows|all]   (default: all)
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

export_one() {
	local preset="$1" out="$2"
	mkdir -p "$(dirname "$out")"
	"$GODOT" --headless --path . --export-release "$preset" "$out"
	echo "Built $out"
}

case "$TARGET" in
	macos)   export_one "macOS" "build/macos/Pickfight.app" ;;
	windows) export_one "Windows" "build/windows/Pickfight.exe" ;;
	all)
		export_one "macOS" "build/macos/Pickfight.app"
		export_one "Windows" "build/windows/Pickfight.exe"
		;;
	*) echo "usage: $0 [macos|windows|all]" >&2; exit 2 ;;
esac
