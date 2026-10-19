#!/bin/bash
# Resolve append-only conflicts in tools/scenario_runner.gd (keep both sides).
# For the last conflict (file-end appends), restore the HEAD function's tail that git folded into the shared suffix.
f=tools/scenario_runner.gd; T=/private/tmp/claude-502/sr-tail.txt
last=$(grep -n '^=======$' $f | tail -1 | cut -d: -f1)
awk -v L=$last 'NR>L && /^>>>>>>> /{found=1;next} found{print}' $f | grep -v '^$' | head -3 > $T
awk -v L=$last -v TF=$T '
/^<<<<<<< /{next}
/^=======$/{ if(NR==L && prev!="\treturn failures"){ while((getline line < TF)>0) print line; print "" } ; next }
/^>>>>>>> /{next}
{print; if($0!="") prev=$0}' $f > /private/tmp/claude-502/sr.gd && mv /private/tmp/claude-502/sr.gd $f
grep -c '^<<<<<<<\|^>>>>>>>' $f
# A dispatcher conflict ending at the match's tail duplicates the default arm
# plus the next doc-comment line mid-dispatcher; drop the first copy.
f=tools/scenario_runner.gd
if [ "$(grep -c "^		_:$" $f)" -gt 1 ]; then
  n=$(grep -n "^		_:$" $f | head -1 | cut -d: -f1)
  sed -i '' "${n},$((n+3))d" $f
fi
# A name-list conflict can drop the comma after HEAD's last name.
awk '{ if (prev != "") { if (prev ~ /^\t"[a-z0-9_]+"$/ && $0 ~ /^\t"[a-z0-9_]+",?$/) prev = prev ","; print prev } prev = $0 } END { print prev }' tools/scenario_runner.gd > /private/tmp/claude-502/sr-comma.gd && mv /private/tmp/claude-502/sr-comma.gd tools/scenario_runner.gd
