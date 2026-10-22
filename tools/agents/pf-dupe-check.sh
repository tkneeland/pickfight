#!/bin/bash
# Usage: pf-dupe-check.sh "<keywords...>"
# Run before filing a ticket. Case-insensitive search of scripts/, controller/, scenes/ and docs/FEATURES.md,
# plus open AND closed issues. Spelling variants match ("hitstop" finds "hit-stop", "hit_stop", "HitStop").
# Prints at most ~20 compact lines. Exit 1 when anything plausible matches, 0 when clean.
[ $# -gt 0 ] || { echo "usage: pf-dupe-check.sh \"<keywords...>\"" >&2; exit 2; }
. "$(dirname "$0")/pf-env.sh" 2>/dev/null; : "${REPO:=tkneeland/pickfight}"
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
words=$(echo "$*" | tr -cs '[:alnum:]' ' ')
rx=""
for w in $words; do
  [ ${#w} -ge 3 ] || continue
  v=$(echo "$w" | sed 's/./&[-_ ]?/g; s/\[-_ \]?$//')
  rx="${rx:+$rx|}$v"
done
[ -n "$rx" ] || { echo "no usable keywords" >&2; exit 2; }
hit=0; out=""
files=$(cd "$ROOT" && grep -rilE "$rx" scripts controller scenes docs/FEATURES.md 2>/dev/null | head -6)
if [ -n "$files" ]; then hit=1; out+="CODE: $(echo $files | tr ' ' ',')"$'\n'; fi
feat=$(grep -iE "$rx" "$ROOT/docs/FEATURES.md" 2>/dev/null | cut -c1-110 | head -4)
if [ -n "$feat" ]; then hit=1; out+="FEATURES:"$'\n'"$(echo "$feat" | sed 's/^/  /')"$'\n'; fi
iss=$(gh issue list -R "$REPO" -s all --search "$*" -L 8 --json number,state,title -q '.[]|"  #\(.number) \(.state) \(.title[0:80])"' 2>/dev/null)
if [ -n "$iss" ]; then hit=1; out+="ISSUES:"$'\n'"$iss"$'\n'; fi
if [ $hit -eq 1 ]; then printf '%s' "$out" | head -20; echo "DUPLICATE? review the hits above before filing"; exit 1; fi
echo "clean: no matches for \"$*\""; exit 0
