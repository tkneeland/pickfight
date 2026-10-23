#!/usr/bin/env bash
# Records every gameplay clip (or the ones named) with Godot's Movie Maker, one
# window at a time, each capped by a 180 s alarm. See docs/launch/clips.md.
#   [CLIP_SECONDS=3] [FRAME_PNG=2] tools/capture_clips.sh <out-dir> [clip ...]
set -u
OUT="${1:?usage: tools/capture_clips.sh <out-dir> [clip ...]}"; shift
CLIPS=("$@"); [ ${#CLIPS[@]} -eq 0 ] && CLIPS=(brawl lava soccer ctf weapons podium)
cd "$(dirname "$0")/.." || exit 1
mkdir -p "$OUT"
# Movie Maker records at the project's viewport size, not --resolution, so the
# run needs a temporary override.cfg (gitignored) that raises it to 1920x1080.
[ -e override.cfg ] && { echo "override.cfg already exists; remove it first" >&2; exit 1; }
printf '[display]\nwindow/size/viewport_width=1920\nwindow/size/viewport_height=1080\n' > override.cfg
trap 'rm -f override.cfg' EXIT
EXTRA=(); [ -n "${CLIP_SECONDS:-}" ] && EXTRA+=(--seconds="$CLIP_SECONDS") # quick test clips
[ -n "${FRAME_PNG:-}" ] && EXTRA+=(--frame-png="$FRAME_PNG") # also save viewport PNGs at these seconds
for clip in "${CLIPS[@]}"; do
	perl -e 'alarm 180; exec @ARGV' godot --path . --write-movie "$OUT/$clip.avi" \
		--fixed-fps 60 --resolution 1920x1080 -s tools/capture_clips.gd -- --only="$clip" --out="$OUT" ${EXTRA[@]+"${EXTRA[@]}"}
	rc=$?
	pgrep -fl "godot.*capture_clips" && { echo "a capture window is still open" >&2; exit 1; }
	[ $rc -eq 0 ] || echo "clip $clip failed (exit $rc)" >&2
	ls -la "$OUT/$clip.avi"
done
