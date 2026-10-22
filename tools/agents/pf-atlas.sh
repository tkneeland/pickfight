#!/bin/bash
# Deterministic Atlas bookkeeping for pickfight, so the model doesn't hand-roll it.
#   pf-atlas.sh accept <wp> <Dnnn> <sha> [verdict]   mark a deliverable accepted in .claude/atlas-state/<wp>.json
#   pf-atlas.sh closeout <wp> <pr> <fixsha> "<suite line>" <issue>...
#                                                    [AI CODE REVIEW]+[CLOSEOUT] comment, ready-for-agent -> ready-for-human, log it
#   pf-atlas.sh tests <regex> [dir]                  comma list of scenario names matching regex (for --scenarios=)
#   pf-atlas.sh run <regex> [dir]                    run those scenarios, print PASS/FAIL summary only
set -euo pipefail
. "$(dirname "$0")/pf-env.sh"
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
      gh issue comment "$i" -R "$REPO" --body "[AI CODE REVIEW] Aggregate two-axis review (correctness, contract) of work package $wp; all findings fixed in $fix. [CLOSEOUT] Delivered in PR #$pr. $suite. Evidence: test-results/$wp/verification.md." >/dev/null
      gh issue edit "$i" -R "$REPO" --remove-label ready-for-agent --add-label ready-for-human >/dev/null
      echo -n "$i "
    done; echo
    f=$(state "$wp"); [ -f "$f" ] && jqi "$f" --argjson pr "$pr" --arg is "$*" \
      '.checkpoint="pr-opened" | .repository_deliveries[0].pr=$pr | .tracker_action_log += [{"action":"review+closeout, ready-for-human","issues":$is}]' ;;
  tests)
    d=${3:-.}; bash "$d/tools/list_scenarios.sh" | grep -E "$2" | paste -sd, - ;;
  run)
    d=${3:-.}; l=$(bash "$d/tools/list_scenarios.sh" | grep -E "$2" | paste -sd, -)
    [ -z "$l" ] && { echo "no scenarios match $2"; exit 1; }
    perl -e 'alarm 1800; exec @ARGV' godot --headless --path "$d" --fixed-fps 60 -s tools/scenario_runner.gd -- --scenarios="$l" 2>&1 | grep -E "^FAIL|passed, " ;;
  *) sed -n '2,7p' "$0"; exit 1;;
esac
