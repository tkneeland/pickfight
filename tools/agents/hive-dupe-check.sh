#!/bin/bash
# Usage: hive-dupe-check.sh "<keywords...>"
# Run before filing (or requesting) a ticket. Case-insensitive search of DUPE_PATHS (default: the whole repo, minus
# tools/agents and docs/agents), FEATURE_DOC, plus open AND closed issues. Spelling variants match ("hitstop" finds
# "hit-stop", "hit_stop", "HitStop"). Prints at most ~20 compact lines. Exit 1 when anything plausible matches, 0 when clean.
[ $# -gt 0 ] || { echo "usage: hive-dupe-check.sh \"<keywords...>\"" >&2; exit 2; }
. "$(dirname "$0")/hive-env.sh" || exit 2
words=$(echo "$*" | tr -cs '[:alnum:]' ' ')
rx=""
for w in $words; do
  [ ${#w} -ge 3 ] || continue
  v=$(echo "$w" | sed 's/./&[-_ ]?/g; s/\[-_ \]?$//')
  rx="${rx:+$rx|}$v"
done
[ -n "$rx" ] || { echo "no usable keywords" >&2; exit 2; }
hit=0; out=""
if [ -n "${DUPE_PATHS:-}" ]; then specs=($DUPE_PATHS); else specs=(.); fi
files=$(for rp in $REPO_PATHS; do (cd "$rp" 2>/dev/null && git grep -ilE "$rx" -- "${specs[@]}" ':!tools/agents' ':!docs/agents' ':!hive.conf' 2>/dev/null | sed "s#^#$(basename "$rp")/#"); done | head -6)
cd "$ROOT" 2>/dev/null || exit 2
if [ -n "$files" ]; then hit=1; out+="CODE: $(echo $files | tr ' ' ',')"$'\n'; fi
if [ -n "${FEATURE_DOC:-}" ] && [ -f "$FEATURE_DOC" ]; then
  feat=$(grep -iE "$rx" "$FEATURE_DOC" 2>/dev/null | cut -c1-110 | head -4)
  if [ -n "$feat" ]; then hit=1; out+="FEATURES:"$'\n'"$(echo "$feat" | sed 's/^/  /')"$'\n'; fi
fi
if [ "$TRACKER" = local ]; then
  iss=$(grep -rilE "$rx" "$TRACKER_DIR"/*/issues/ 2>/dev/null | head -8 | while read -r f; do echo "  ${f#$TRACKER_DIR/} [$(sed -n 's/^Status: *//p' "$f" | head -1)] $(sed -n '1s/^# *//p' "$f" | cut -c1-70)"; done)
else iss=$(gh issue list -R "$REPO" -s all --search "$*" -L 8 --json number,state,title -q '.[]|"  #\(.number) \(.state) \(.title[0:80])"' 2>/dev/null); fi
if [ -n "$iss" ]; then hit=1; out+="ISSUES:"$'\n'"$iss"$'\n'; fi
if [ $hit -eq 1 ]; then printf '%s' "$out" | head -20; echo "DUPLICATE? review the hits above before filing"; exit 1; fi
echo "clean: no matches for \"$*\""; exit 0
