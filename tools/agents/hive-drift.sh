#!/bin/bash
# Usage: hive-drift.sh [repo-root]
# The hive's files in a game are installed copies of claude-hive (install.sh) and are never edited in the game: a hive
# change goes into claude-hive and is installed into every game. install.sh writes tools/agents/MANIFEST (the
# claude-hive version and a sha256 per hive-owned file); this checks the repo against it.
# Exit 0 = matches; 1 = drift (lists each changed, missing or extra file); 2 = no MANIFEST (installed before manifests).
# Account confs (tools/agents/accounts/) belong to the game and are never checked.
ROOT=${1:-$(cd "$(dirname "$0")/../.." && pwd)}
M=$ROOT/tools/agents/MANIFEST
[ -f "$M" ] || { echo "hive-drift: no tools/agents/MANIFEST in $ROOT (re-run claude-hive's install.sh)"; exit 2; }
# sha256 of a file with CRs dropped, so a Windows checkout of the same text matches (install.sh uses the same sum)
sum() { tr -d '\r' < "$1" | if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | cut -d' ' -f1; }
drift=0; listed=$(mktemp "${TMPDIR:-/tmp}/hive-drift.XXXXXX"); trap 'rm -f "$listed"' EXIT
while read -r want path; do
  case $want in ''|'#'*) continue;; esac
  echo "$path" >> "$listed"
  if [ ! -f "$ROOT/$path" ]; then echo "  missing  $path"; drift=1
  elif [ "$(sum "$ROOT/$path")" != "$want" ]; then
    echo "  changed  $path"; drift=1
  fi
done < "$M"
( cd "$ROOT" && find tools/agents -type f ! -path 'tools/agents/accounts/*' ! -name MANIFEST ! -name .DS_Store ) | sort | while read -r f; do
  grep -qxF "$f" "$listed" || echo "  extra    $f"
done | tee "$listed.extra"
[ -s "$listed.extra" ] && drift=1; rm -f "$listed.extra"
if [ $drift = 1 ]; then
  echo "hive-drift: $ROOT differs from claude-hive $(sed -n 's/^# claude-hive //p' "$M" | head -1). Hive files are never edited in a game: make the change in claude-hive's template and re-run install.sh."
  exit 1
fi
echo "hive-drift: matches claude-hive $(sed -n 's/^# claude-hive //p' "$M" | head -1)"
