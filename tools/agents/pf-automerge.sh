#!/bin/bash
# Zero-token auto-integrator: merges any open PR that is MERGEABLE with every CI check passed, then
# runs INSTALL_SCRIPT (if set). Conflicting PRs get one comment asking to rebase.
# PRs labelled conflict-risk are merged only when this account is the current triagemaster.
. "$(dirname "$0")/pf-env.sh" || exit 1
PF_TMP=${TMPDIR:-/tmp}
LOCK=$PF_TMP/pickfight-automerge-$PF_ACCOUNT.lock
if [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK")" 2>/dev/null; then echo "ALREADY RUNNING"; exit 0; fi
echo $$ > "$LOCK"; trap 'rm -f "$LOCK"' EXIT
cd "$ROOT" || exit 1
while true; do
  merged=0
  for P in $(gh pr list --repo $REPO --state open --json number,isDraft --jq '.[]|select(.isDraft|not)|.number' 2>/dev/null); do
    m=$(gh pr view $P --repo $REPO --json mergeable --jq .mergeable 2>/dev/null)
    if [ "$m" = "CONFLICTING" ]; then
      [ -f $PF_TMP/pf-stuck-$P ] || { touch $PF_TMP/pf-stuck-$P; echo "$(date '+%F %T') STUCK $P conflicts with main"; pf_notify "PR #$P conflicts with main"; }
      gh pr view $P --repo $REPO --json comments --jq '.comments[].body' | grep -q "\[INTEGRATOR\]" || \
        gh pr comment $P --repo $REPO --body "[INTEGRATOR] Conflicts with main. Author: please rebase onto origin/main and push; it merges automatically once CI is green." >/dev/null
      continue
    fi
    [ "$m" = "MERGEABLE" ] || continue
    gh pr view $P --repo $REPO --json labels --jq '.labels[].name' | grep -qx review-blocked && continue   # rule 12: confirmed reviewer finding
    if gh pr view $P --repo $REPO --json labels --jq '.labels[].name' | grep -qx conflict-risk && ! pf_is_triagemaster; then continue; fi
    states=$(gh pr checks $P --repo $REPO --json state --jq '.[].state' 2>/dev/null)
    [ -n "$states" ] || continue
    echo "$states" | grep -qv "SUCCESS\|SKIPPED\|NEUTRAL" && continue
    gh pr merge $P --repo $REPO --merge --delete-branch >/dev/null 2>&1 && { echo "$(date '+%F %T') MERGED $P"; merged=1; }
  done
  if [ $merged -eq 1 ]; then
    git checkout -q main 2>/dev/null; git pull -q 2>/dev/null
    if [ -n "${INSTALL_SCRIPT:-}" ] && [ -f "$INSTALL_SCRIPT" ]; then
      command -v pgrep >/dev/null 2>&1 && while pgrep -f "$(basename "$INSTALL_SCRIPT")" >/dev/null; do sleep 10; done
      bash "$INSTALL_SCRIPT"
    fi
  fi
  sleep 180
done
