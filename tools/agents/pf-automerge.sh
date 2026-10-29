#!/bin/bash
# Zero-token auto-integrator: merges any open PR that is MERGEABLE with every CI check passed, then
# runs INSTALL_SCRIPT (if set). Conflicting PRs get one comment asking to rebase.
# PRs labelled conflict-risk are merged only when this account is the current triagemaster.
. "$(dirname "$0")/pf-env.sh" || exit 1
PF_TMP=${TMPDIR:-/tmp}
LOCK=$PF_TMP/pickfight-automerge-$PF_ACCOUNT.lock
if [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK")" 2>/dev/null; then echo "ALREADY RUNNING"; exit 0; fi
echo $$ > "$LOCK"; trap 'rm -f "$LOCK"' EXIT
# "PR conflicts" markers are per account and hold the PR head they were raised for: a new push re-arms the
# notice, and the marker goes once the PR stops conflicting or is no longer open.
STUCK_DIR=$PF_STATE/pf-stuck; mkdir -p "$STUCK_DIR"
cd "$ROOT" || exit 1
while true; do
  merged=0
  open=$(gh pr list --repo $REPO --state open --json number,isDraft --jq '.[]|select(.isDraft|not)|.number' 2>/dev/null) && listed=1 || listed=0
  if [ "$listed" = 1 ]; then
    for mark in "$STUCK_DIR"/*; do
      [ -e "$mark" ] || continue
      echo "$open" | grep -qx "${mark##*/}" || rm -f "$mark"
    done
  fi
  for P in $open; do
    info=$(gh pr view $P --repo $REPO --json mergeable,headRefOid --jq '.mergeable + " " + .headRefOid' 2>/dev/null)
    m=${info%% *}; sha=${info#* }
    if [ "$m" = "CONFLICTING" ]; then
      [ "$(cat "$STUCK_DIR/$P" 2>/dev/null)" = "$sha" ] || { echo "$sha" > "$STUCK_DIR/$P"; echo "$(date '+%F %T') STUCK $P conflicts with main"; pf_notify "PR #$P conflicts with main"; }
      gh pr view $P --repo $REPO --json comments --jq '.comments[].body' | grep -q "\[INTEGRATOR\]" || \
        gh pr comment $P --repo $REPO --body "[INTEGRATOR] Conflicts with main. Author: please rebase onto origin/main and push; it merges automatically once CI is green." >/dev/null
      continue
    fi
    [ "$m" = "MERGEABLE" ] && rm -f "$STUCK_DIR/$P"   # no longer conflicting
    [ "$m" = "MERGEABLE" ] || continue
    labels=$(gh pr view $P --repo $REPO --json labels --jq '.labels[].name')
    echo "$labels" | grep -qx review-blocked && continue   # rule 12: confirmed reviewer finding
    echo "$labels" | grep -qx review-passed || continue    # rule 12: no merge before a reviewer pass
    if gh pr view $P --repo $REPO --json labels --jq '.labels[].name' | grep -qx conflict-risk && ! pf_is_triagemaster; then continue; fi
    states=$(gh pr checks $P --repo $REPO --json state --jq '.[].state' 2>/dev/null)
    [ -n "$states" ] || continue
    echo "$states" | grep -qv "SUCCESS\|SKIPPED\|NEUTRAL" && continue
    gh pr merge $P --repo $REPO --merge --delete-branch >/dev/null 2>&1 && { echo "$(date '+%F %T') MERGED $P"; merged=1; rm -f "$STUCK_DIR/$P"; }
  done
  if [ $merged -eq 1 ]; then
    # Never move a human's checkout: fast-forward only when it is already on main, and install only from main.
    on_main=0
    if [ "$(git branch --show-current 2>/dev/null)" = main ]; then
      on_main=1
      { git fetch -q && git merge -q --ff-only origin/main; } 2>/dev/null || echo "$(date '+%F %T') WARN: main checkout not fast-forwarded"
    else
      echo "$(date '+%F %T') main checkout is not on main: not updated, no install"
    fi
    if [ "$on_main" = 1 ] && [ -n "${INSTALL_SCRIPT:-}" ] && [ -f "$INSTALL_SCRIPT" ]; then
      command -v pgrep >/dev/null 2>&1 && while pgrep -f "$(basename "$INSTALL_SCRIPT")" >/dev/null; do sleep 10; done
      bash "$INSTALL_SCRIPT"
    fi
  fi
  sleep 180
done
