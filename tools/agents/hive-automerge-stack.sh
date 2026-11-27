#!/bin/bash
# Usage: hive-automerge-stack.sh <owner/repo>
# Zero-token merger for a stacked repo with no hive install of its own (the hive's own repo, the studio's): hive-watchdog.sh
# starts one per such repo on the triagemaster's machine. The gate is hive-automerge.sh's, with gh alone: open, non-draft,
# MERGEABLE, every check passed, review-passed, not review-blocked; conflict-risk only while this account is the
# triagemaster. Merges with this install's MERGE_METHOD and deletes the branch. Loops every 2 min; HIVE_AUTOMERGE_ONCE=1: one pass.
repo=${1:-}; case $repo in */*) ;; *) echo "usage: hive-automerge-stack.sh <owner/repo>" >&2; exit 2;; esac
export PATH="$PATH:$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
. "$(dirname "$0")/hive-env.sh" || exit 1
L=${HIVE_AUTOMERGE_LOG:-$HIVE_STATE/automerge-stack.log}
while true; do
  tm=0; hive_is_triagemaster && tm=1
  gh pr list -R "$repo" -s open --json number,isDraft,mergeable,labels,statusCheckRollup -q '.[] |
    select((.isDraft|not) and .mergeable=="MERGEABLE"
      and ([.labels[].name]|index("review-passed")) and (([.labels[].name]|index("review-blocked"))|not)
      and ([.statusCheckRollup[]? | (.conclusion // .state)] | all(. == "SUCCESS" or . == "SKIPPED" or . == "NEUTRAL")))
    | "\(.number) \([.labels[].name]|index("conflict-risk") != null)"' 2>/dev/null </dev/null |
  while read -r n cr; do
    [ "$cr" = true ] && [ "$tm" != 1 ] && continue
    gh pr merge "$n" -R "$repo" --"${MERGE_METHOD:-merge}" --delete-branch >/dev/null 2>&1 </dev/null && echo "$(date '+%F %T') MERGED $repo#$n" >> "$L"
  done
  [ "${HIVE_AUTOMERGE_ONCE:-}" = 1 ] && exit 0
  sleep 120
done
