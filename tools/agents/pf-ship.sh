#!/bin/bash
# Usage: pf-ship.sh <issue> "<title>" "<summary body>"
# Merges main into the issue's worktree branch, opens the PR with a Resource Usage section, waits for CI, merges, installs.
# Opens but does not merge a conflict-risk PR unless this account is the current triagemaster.
. "$(dirname "$0")/pf-env.sh" || exit 1
i=$1; t=$2; b=$3; R=$ROOT; W=$R/.claude/worktrees/$i/pickfight
FIXER=${FIX_RUNNER:-$HOME/.claude/pf-fix-runner.sh}   # optional helper that repairs tools/scenario_runner.gd conflicts
cd "$W" || exit 1
git fetch -q
if ! git merge -q origin/main >/dev/null 2>&1; then
  u=$(git diff --name-only --diff-filter=U)
  for cf in $u; do case $cf in tools/scenario_runner.gd) [ -x "$FIXER" ] || { echo "CONFLICT $i: $cf needs a human merge (no FIX_RUNNER)"; exit 2; }; "$FIXER" >/dev/null;; scripts/PickupWeapons.gd|scripts/Sfx.gd|docs/FEATURES.md|CREDITS.md) sed -i '' -e '/^<<<<<<< /d' -e '/^=======$/d' -e '/^>>>>>>> /d' $cf;; translations/strings.en.translation) git checkout -q --theirs $cf; godot --headless --path . --import >/dev/null 2>&1;; *) echo "CONFLICT $i: $cf needs a human merge"; exit 2;; esac; done
  if godot --headless --path . --check-only -s tools/scenario_runner.gd 2>&1 | grep -qE "SCRIPT ERROR|Parse Error"; then echo "CONFLICT $i: parse error after auto-resolve"; exit 2; fi
  if [ "$(grep -c "^		_:$" tools/scenario_runner.gd)" != "1" ]; then echo "CONFLICT $i: runner default arm misplaced"; exit 2; fi
  git add -A && git commit -qm "merge: main into #$i" || exit 2
fi
git push -qu origin HEAD 2>&1 | grep -v remote
S=$(jq -r '.rate_limits' "$PF_STATE/usage-snapshot.json")
p5=$(echo "$S" | jq -r .five_hour.used_percentage); p7=$(echo "$S" | jq -r .seven_day.used_percentage)
r5=$(date -r "$(echo "$S" | jq -r .five_hour.resets_at)" "+%a %b %-d, %-I:%M %p $TZ_LABEL")
r7=$(date -r "$(echo "$S" | jq -r .seven_day.resets_at)" "+%a %b %-d, %-I:%M %p $TZ_LABEL")
rate=${PF_RATE:-unknown}; week=${PF_WEEK:-unknown}
pr=$(gh pr create --title "$t" --body "Closes #$i.

$b

## Resource Usage
- *5-hour rate:* $rate
- *Weekly projection:* $week
- *5-hour window resets:* $r5 (${p5}% used)
- *Weekly window resets:* $r7 (${p7}% used)

🤖 Generated with [Claude Code](https://claude.com/claude-code)" | tail -1); n=${pr##*/}; echo "PR $pr"
if gh pr view $n --json labels -q '.labels[].name' | grep -qx conflict-risk && ! pf_is_triagemaster; then echo "CONFLICT-RISK PR $n opened; only the triagemaster ($(pf_triagemaster)) merges it. Not merging."; exit 0; fi
sleep 20; i=0; until s=$(gh pr checks $n 2>&1); ! echo "$s" | grep -qE "pending|no checks"; do i=$((i+1)); [ $i -gt 60 ] && { echo "CI TIMEOUT $n (conflict?)"; exit 1; }; sleep 30; done
if gh pr checks $n 2>&1 | grep -qE "[[:space:]]fail[[:space:]]"; then echo "CI FAILED $n"; gh pr checks $n | grep -E "[[:space:]]fail[[:space:]]"; exit 1; fi
echo "$s" | grep -v pass
if gh pr view $n --json labels -q '.labels[].name' | grep -qx review-blocked; then echo "REVIEW-BLOCKED $n: a confirmed reviewer finding must be fixed first. Not merging."; exit 1; fi
gh pr merge $n --merge --delete-branch 2>&1 | tail -1; st=$(gh pr view $n --json state -q .state); echo "$n $st"; [ "$st" = MERGED ] || { echo "MERGE FAILED $n"; exit 1; }
cd $R && git pull -q; [ -n "${INSTALL_SCRIPT:-}" ] && [ -f "$INSTALL_SCRIPT" ] && bash "$INSTALL_SCRIPT" 2>&1 | tail -1; exit 0
