#!/bin/bash
# Deterministic Atlas bookkeeping, so the model does not hand-roll it.
#   hive-atlas.sh accept <wp> <Dnnn> <sha> [verdict]   mark a deliverable accepted in .claude/atlas-state/<wp>.json
#   hive-atlas.sh closeout <wp> <pr> <fixsha> "<test summary line>" <issue-or-local-id>...
#                                                    [AI CODE REVIEW]+[CLOSEOUT] comment, ready-for-agent -> ready-for-human, log it
set -euo pipefail
. "$(dirname "$0")/hive-env.sh"
state() { echo "$ROOT/.claude/atlas-state/$1.json"; }
jqi() { local f=$1; shift; jq "$@" "$f" > "$f.tmp" && mv "$f.tmp" "$f"; }
case "${1:-}" in
  accept)
    f=$(state "$2"); v=${5:-accepted}
    jqi "$f" --arg d "$3" --arg s "$4" --arg v "$v" \
      'if any(.deliverables[]?; .id==$d)
       then (.deliverables[] | select(.id==$d)) |= (.worker_status="completed" | .returned_commit=$s | .acceptance_verdict=$v)
       else .deliverables += [{"id":$d,"worker_status":"completed","returned_commit":$s,"acceptance_verdict":$v}] end'
    echo "$3 $v";;
  closeout)
    wp=$2 pr=$3 fix=$4 suite=$5; shift 5
    for i in "$@"; do
      if [ "$TRACKER" = local ]; then
        hive_set_status "$i" "$CLOSEOUT_STATUS" "[AI CODE REVIEW] Aggregate two-axis review (correctness, contract) of work package $wp; all findings fixed in $fix. [CLOSEOUT] Delivered in PR #$pr. $suite. Evidence: test-results/$wp/verification.md."
        echo -n "$i "; continue
      fi
      gh issue comment "$i" -R "$REPO" --body "[AI CODE REVIEW] Aggregate two-axis review (correctness, contract) of work package $wp; all findings fixed in $fix. [CLOSEOUT] Delivered in PR #$pr. $suite. Evidence: test-results/$wp/verification.md." >/dev/null
      gh issue edit "$i" -R "$REPO" --remove-label ready-for-agent --add-label ready-for-human >/dev/null
      echo -n "$i "
    done; echo
    f=$(state "$wp"); [ -f "$f" ] && jqi "$f" --argjson pr "$pr" --arg is "$*" \
      '.checkpoint="pr-opened" | .repository_deliveries[0].pr=$pr | .tracker_action_log += [{"action":"review+closeout, ready-for-human","issues":$is}]' ;;
  *) sed -n '2,6p' "$0"; exit 1;;
esac
