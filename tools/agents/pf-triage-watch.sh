#!/bin/bash
# Zero-token triage watcher. Polls GitHub every 10 min and exits with one line only when something needs
# Claude's judgement; Claude acts, then restarts it. Merging green PRs is pf-automerge.sh.
#   UNTRIAGED <n...>   (triagemaster only) open issue missing a p1/p2/p3 label or an assignee
#   MYTICKET <n>       ready-for-agent ticket assigned to this account and no worktree in progress
#   FEATURES? PR <n>   (triagemaster only) open PR changes scripts/ or controller/ without docs/FEATURES.md (once per PR)
#   PEER_BEACON        a WATCH_PEERS account's #432 usage beacon became fresh (once)
#   IDLE_SLOTS <n>/<min>  hourly: fewer active work packages than the mode's minimum (day DAY_MIN_AGENTS,
#                      night the low end of NIGHT_PREFERRED_AGENTS); skipped when the weekly budget says stop
#   AUSTIN_QUEUE_LOW <n>  (triagemaster only) hourly: a peer has fewer than 5 ready dev tickets; Claude files and assigns more
. "$(dirname "$0")/pf-env.sh" || exit 1
SEEN=$PF_STATE/.pf-triage-seen; touch "$SEEN"
META_TICKETS=${META_TICKETS:-"702 720 619"}   # meta tickets that never count as a peer's dev queue
while true; do
  issues=$(gh api "repos/$REPO/issues?state=open&per_page=100" 2>/dev/null)
  if [ -n "$issues" ]; then
    if pf_is_triagemaster; then
      u=$(echo "$issues" | jq -r '.[] | select(.pull_request==null and .number!=432) | select(((.labels|map(.name)|map(test("^p[123]$"))|any)|not) or ((.assignees|length)==0)) | .number' | tr '\n' ' ')
      [ -n "${u// /}" ] && { echo "UNTRIAGED $u"; exit 0; }
    fi
    for n in $(echo "$issues" | jq -r --arg me "$PF_ACCOUNT" '.[] | select(.pull_request==null) | select(any(.assignees[]; .login==$me)) | select(any(.labels[]; .name=="ready-for-agent")) | .number'); do
      # skip tickets already in progress: a local or remote branch for the issue exists
      git -C "$ROOT" branch -a --list "*issue-$n-*" | grep -q . && continue
      # only when I am idle: no Atlas state file (removed at closeout)
      [ -z "$(ls "$ROOT"/.claude/atlas-state/*.json 2>/dev/null)" ] && { echo "MYTICKET $n"; exit 0; }
    done
    if pf_is_triagemaster; then
      for p in $(echo "$issues" | jq -r '.[] | select(.pull_request!=null) | .number'); do
        grep -qx "pr$p" "$SEEN" && continue
        files=$(gh api "repos/$REPO/pulls/$p/files?per_page=100" --jq '.[].filename' 2>/dev/null) || continue
        [ -z "$files" ] && continue
        echo "$files" | grep -qE '^(scripts|controller)/' && ! echo "$files" | grep -qx docs/FEATURES.md && { echo "pr$p" >> "$SEEN"; echo "FEATURES? PR $p"; exit 0; }
        echo "pr$p" >> "$SEEN"
      done
    fi
  fi
  for peer in ${WATCH_PEERS:-agage-JG}; do
    grep -qx "beacon-$peer" "$SEEN" && continue
    t=$(gh api "repos/$REPO/issues/432/comments" --jq ".[] | select(.user.login==\"$peer\") | .body" 2>/dev/null | sed -n 's/.*usage @ \([0-9TZ:-]*\).*/\1/p' | head -1)
    if [ -n "$t" ] && [ $(( $(date +%s) - $(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$t" +%s 2>/dev/null || echo 0) )) -lt 21600 ]; then
      echo "beacon-$peer" >> "$SEEN"; echo "PEER_BEACON $peer fresh at $t"; exit 0
    fi
  done
  # hourly productivity check: fewer active work packages than this mode's minimum -> wake Claude to start more
  last=$(cat "$PF_STATE/.pf-slots-last" 2>/dev/null || echo 0)
  if [ $(( $(date +%s) - last )) -ge 3600 ]; then
    date +%s > "$PF_STATE/.pf-slots-last"
    if [ "$(pf_daynight)" = day ]; then min=$DAY_MIN_AGENTS; else min=${NIGHT_PREFERRED_AGENTS%%-*}; fi
    active=$(ls "$ROOT"/.claude/atlas-state/*.json 2>/dev/null | wc -l | tr -d ' ')
    if pf_budget_ok && [ "$active" -lt "$min" ]; then echo "IDLE_SLOTS $active/$min active work packages"; exit 0; fi
    if pf_is_triagemaster && pf_budget_ok; then
      # peers' queues: dev tickets assigned to a peer (meta tickets excluded)
      for peer in ${WATCH_PEERS:-agage-JG}; do
        aq=$(echo "$issues" | jq --arg p "$peer" --arg m "$META_TICKETS" '[.[] | select(.pull_request==null and (.number|IN($m|split(" ")|map(tonumber)[])|not)) | select(any(.assignees[]; .login==$p)) | select(any(.labels[]; .name=="ready-for-agent"))] | length' 2>/dev/null || echo 9)
        [ "$aq" -lt 5 ] && { echo "AUSTIN_QUEUE_LOW $aq ready tickets queued for $peer"; exit 0; }
      done
    fi
  fi
  sleep 600
done
