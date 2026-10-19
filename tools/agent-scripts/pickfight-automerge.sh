#!/bin/bash
# Zero-token auto-integrator (budget mode until 2026-10-01): merges any open
# agage-JG PR that is MERGEABLE with every CI check passed, then rebuilds
# /Applications/Pickfight.app. Conflicting PRs get one comment asking to rebase.
LOCK=/tmp/pickfight-automerge.lock
if [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK")" 2>/dev/null; then echo "ALREADY RUNNING"; exit 0; fi
echo $$ > "$LOCK"; trap 'rm -f "$LOCK"' EXIT
REPO=tkneeland/pickfight
cd /Users/tkneeland/Desktop/godotProjects/pickfight || exit 1
while true; do
  merged=0
  for P in $(gh pr list --repo $REPO --state open --json number,isDraft --jq '.[]|select(.isDraft|not)|.number' 2>/dev/null); do
    m=$(gh pr view $P --repo $REPO --json mergeable --jq .mergeable 2>/dev/null)
    if [ "$m" = "CONFLICTING" ]; then
      [ -f /tmp/pf-stuck-$P ] || { touch /tmp/pf-stuck-$P; echo "$(date '+%F %T') STUCK $P conflicts with main"; osascript -e "display notification \"PR #$P conflicts with main\" with title \"Pickfight\"" 2>/dev/null; }
      gh pr view $P --repo $REPO --json comments --jq '.comments[].body' | grep -q "\[INTEGRATOR\]" || \
        gh pr comment $P --repo $REPO --body "[INTEGRATOR] Conflicts with main. Author: please rebase onto origin/main and push; it merges automatically once CI is green." >/dev/null
      continue
    fi
    [ "$m" = "MERGEABLE" ] || continue
    states=$(gh pr checks $P --repo $REPO --json state --jq '.[].state' 2>/dev/null)
    [ -n "$states" ] || continue
    echo "$states" | grep -qv "SUCCESS\|SKIPPED\|NEUTRAL" && continue
    gh pr merge $P --repo $REPO --merge --delete-branch >/dev/null 2>&1 && { echo "$(date '+%F %T') MERGED $P"; merged=1; }
  done
  if [ $merged -eq 1 ]; then
    git checkout -q main 2>/dev/null; git pull -q 2>/dev/null
    while pgrep -f pickfight-install-mac.sh >/dev/null; do sleep 10; done
    bash ~/.claude/pickfight-install-mac.sh
  fi
  sleep 180
done
