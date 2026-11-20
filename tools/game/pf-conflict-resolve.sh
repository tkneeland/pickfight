#!/bin/bash
# Pickfight's merge-conflict fixers, run by the hive's hive-ship.sh (hive.conf CONFLICT_RESOLVER_CMD) inside the ticket
# worktree when merging main in conflicts. Resolves the files it knows and stages them; anything else stays unmerged and
# hive-ship.sh stops for a human or agent merge. Carried over from the old pf-ship.sh.
#   tools/scenario_runner.gd, docs/FEATURES.md   tools/game/pf-scenario-merge.sh (re-inserts this branch's blocks into
#                                   main's copy); the runner then gets a parse check
#   scripts/PickupWeapons.gd, scripts/Sfx.gd, CREDITS.md   append-only lists: keep both sides
#   translations/strings.en.translation   generated: take main's, then re-import
here=$(cd "$(dirname "$0")" && pwd)
for f in $(git diff --name-only --diff-filter=U); do
  case $f in
    docs/FEATURES.md) bash "$here/pf-scenario-merge.sh" "$f" >/dev/null 2>&1;;
    tools/scenario_runner.gd)
      stages=$(git ls-files -u -- "$f")   # the conflict's index entries, to put back if the result does not parse
      bash "$here/pf-scenario-merge.sh" "$f" >/dev/null 2>&1 || continue
      if godot --headless --path . --check-only -s "$f" 2>&1 | grep -qE "SCRIPT ERROR|Parse Error" \
        || [ "$(grep -c "^		_:$" "$f")" != 1 ]; then
        # back to the conflicted file: a human or agent merges it
        git rm -q --cached -- "$f" && printf '%s\n' "$stages" | git update-index --index-info && git checkout -q -m -- "$f"
      fi;;
    scripts/PickupWeapons.gd|scripts/Sfx.gd|CREDITS.md)
      sed -i.bak -e '/^<<<<<<< /d' -e '/^=======$/d' -e '/^>>>>>>> /d' "$f" && rm -f "$f.bak" && git add -- "$f";;
    translations/strings.en.translation)
      git checkout -q --theirs -- "$f" && git add -- "$f" && godot --headless --path . --import >/dev/null 2>&1;;
  esac
done
exit 0
