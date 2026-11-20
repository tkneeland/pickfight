#!/bin/bash
# Resolves the usual merge conflict in append-only files (tools/scenario_runner.gd, docs/FEATURES.md) during
# `git merge origin/main` on a ticket branch: takes main's copy, then re-inserts each block this branch added
# after the same anchor line (or at the end of the file). A plain union merge drops the tail of one side's
# last function when both sides end with the same lines, so it is not used for scenario_runner.gd.
#   pf-scenario-merge.sh [file...]   run inside the worktree with the merge in progress; default: both files
# Exits 1, leaving that file with its conflict markers and unstaged, if an anchor line is missing or ambiguous,
# or if no working Python 3 is found (python3, python or py -3; the Windows Store python3 stub does not count).
set -euo pipefail
git rev-parse -q --verify MERGE_HEAD >/dev/null || { echo "no merge in progress"; exit 1; }
# Find a Python that really runs before touching any file: a missing one used to leave main's copy staged.
PY=()
for cand in python3 python "py -3"; do
  read -ra try <<<"$cand"
  if "${try[@]}" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then PY=("${try[@]}"); break; fi
done
[ ${#PY[@]} -gt 0 ] || { echo "no working Python 3 (python3, python, py -3): conflicts left for a hand merge"; exit 1; }
base=$(git merge-base HEAD MERGE_HEAD)
files=("$@"); [ ${#files[@]} -eq 0 ] && files=(tools/scenario_runner.gd docs/FEATURES.md)
rc=0
for f in "${files[@]}"; do
  git ls-files -u -- "$f" | grep -q . || continue
  saved=$(mktemp)
  cp "$f" "$saved"   # the conflicted copy, restored if the resolve fails
  git show "MERGE_HEAD:$f" > "$f"
  if ! git diff -U1 "$base" HEAD -- "$f" | "${PY[@]}" -I -c '
import sys, re
path = sys.argv[1]
main = open(path).read().split("\n")
hunks, cur = [], None
for line in sys.stdin.read().split("\n"):
    if line.startswith("@@"):
        cur = {"anchor": None, "add": [], "bad": False}; hunks.append(cur)
    elif cur is None or line.startswith(("---", "+++")):
        continue
    elif line.startswith("+"):
        cur["add"].append(line[1:])
    elif line.startswith("-"):
        cur["bad"] = True
    elif line.startswith(" ") and not cur["add"]:
        cur["anchor"] = line[1:]
bad = 0
for h in hunks:
    if h["bad"]:
        print("REMOVED LINES (not append-only), resolve by hand:", path); bad = 1; continue
    if not h["add"]:
        continue
    hits = [i for i, l in enumerate(main) if l == h["anchor"]] if h["anchor"] is not None else []
    if len(hits) == 1:
        main[hits[0] + 1:hits[0] + 1] = h["add"]
    elif h is hunks[-1]:
        # end-of-file block (its anchor is a common tail like "\treturn failures"): append
        while main and main[-1] == "": main.pop()
        main += [l for l in h["add"]] + [""]
    else:
        print("ANCHOR %s in %s: %r, resolve by hand" % ("missing" if not hits else "ambiguous", path, h["anchor"])); bad = 1
open(path, "w").write("\n".join(main))
sys.exit(bad)
' "$f"; then
    cp "$saved" "$f"; rm -f "$saved"
    echo "NOT resolved $f: conflict markers left, resolve by hand"; rc=1; continue
  fi
  rm -f "$saved"
  git add "$f"
  echo "resolved $f"
done
exit $rc
