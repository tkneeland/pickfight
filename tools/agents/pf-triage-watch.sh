#!/bin/bash
# Zero-token triage watcher. Polls GitHub every 10 min and exits with one line only when something needs
# Claude's judgement; Claude acts, then restarts it. Merging green PRs is pf-automerge.sh.
#   UNTRIAGED <n...>   (triagemaster only) open issue missing a p1/p2/p3 label or an assignee
#   MYTICKET <n>       ready-for-agent ticket assigned to this account and no worktree in progress
#   FEATURES? PR <n>   (triagemaster only) open PR changes scripts/ or controller/ without docs/FEATURES.md (once per PR)
#   PEER_BEACON        a WATCH_PEERS account's #432 usage beacon became fresh (once)
#   IDLE_SLOTS <n>/<target>  hourly: fewer active work packages than pf_worker_target (day DAY_AGENTS, night
#                      NIGHT_AGENTS, 1 past FIVE_H_SLOW_USED, 0 past FIVE_H_STOP_USED or the weekly stop)
#   AUSTIN_QUEUE_LOW <n>  (triagemaster only, ticket-maker on) hourly: a peer has fewer than 5 ready dev tickets; Claude files and assigns more
#   MSG <TYPE> ...     a new CLAIM/ASK/FIRE line from pf-msg.sh listen (msg-wake.txt); checked every PF_TICK (10) s while idle
. "$(dirname "$0")/pf-env.sh" || exit 1
SEEN=$PF_STATE/.pf-triage-seen; touch "$SEEN"
# first run: a wake file older than this watcher counts as handled
[ -f "$PF_STATE/.msg-wake-handled" ] || pf_mtime "$PF_STATE/msg-wake.txt" > "$PF_STATE/.msg-wake-handled" 2>/dev/null
META_TICKETS=${META_TICKETS:-"702 720 619"}   # meta tickets that never count as a peer's dev queue
while true; do
  issues=$(gh api --paginate "repos/$REPO/issues?state=open&per_page=100" 2>/dev/null | jq -s 'add // []' 2>/dev/null)   # every page, one array
  [ "$issues" = "[]" ] && issues=""
  if [ -n "$issues" ]; then
    if pf_is_triagemaster; then
      u=$(echo "$issues" | jq -r '.[] | select(.pull_request==null and .number!=432) | select(((.labels|map(.name)|map(test("^p[123]$"))|any)|not) or ((.assignees|length)==0)) | .number' | tr '\n' ' ')
      [ -n "${u// /}" ] && { echo "UNTRIAGED $u"; exit 0; }
    fi
    for n in $(echo "$issues" | jq -r --arg me "$PF_ACCOUNT" '.[] | select(.pull_request==null) | select(any(.assignees[]; .login==$me)) | select(any(.labels[]; .name=="ready-for-agent")) | .number'); do
      # skip tickets already in progress: a local or remote branch for the issue exists
      # (feat/issue-N-slug from workers, or fix/N-slug from the owner's main terminal)
      git -C "$ROOT" branch -a --list "*issue-$n-*" "*/$n-*" | grep -q . && continue
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
    # every page, oldest first: the last match is the peer's newest beacon
    t=$(gh api --paginate "repos/$REPO/issues/432/comments?per_page=100" --jq ".[] | select(.user.login==\"$peer\") | .body" 2>/dev/null | sed -n 's/.*usage @ \([0-9TZ:-]*\).*/\1/p' | tail -1)
    if [ -n "$t" ] && [ $(( $(date +%s) - $(pf_iso_to_epoch "$t" || echo 0) )) -lt 21600 ]; then
      echo "beacon-$peer" >> "$SEEN"; echo "PEER_BEACON $peer fresh at $t"; exit 0
    fi
  done
  # hourly productivity check: fewer active work packages than this mode's minimum -> wake Claude to start more
  last=$(cat "$PF_STATE/.pf-slots-last" 2>/dev/null || echo 0)
  if [ $(( $(date +%s) - last )) -ge 3600 ]; then
    date +%s > "$PF_STATE/.pf-slots-last"
    min=$(pf_worker_target)
    active=$(ls "$ROOT"/.claude/atlas-state/*.json 2>/dev/null | wc -l | tr -d ' ')
    # plus tickets of mine in flight outside Atlas: open, assigned to me, a branch exists
    for n in $(echo "$issues" | jq -r --arg me "$PF_ACCOUNT" '.[] | select(.pull_request==null) | select(any(.assignees[]; .login==$me)) | .number'); do
      git -C "$ROOT" branch -a --list "*issue-$n-*" | grep -q . && active=$((active+1))
    done
    if [ "$active" -lt "$min" ]; then echo "IDLE_SLOTS $active/$min active work packages"; exit 0; fi
    if pf_is_triagemaster && pf_budget_ok && [ "$(bash "$(dirname "$0")/pf-ticketmaker.sh")" = on ]; then
      # no refill while the ticket-maker is off (playtest phase, autotriage.md rule 11)
      # peers' queues: dev tickets assigned to a peer (meta tickets excluded)
      for peer in ${WATCH_PEERS:-agage-JG}; do
        aq=$(echo "$issues" | jq --arg p "$peer" --arg m "$META_TICKETS" '[.[] | select(.pull_request==null and (.number|IN($m|split(" ")|map(tonumber)[])|not)) | select(any(.assignees[]; .login==$p)) | select(any(.labels[]; .name=="ready-for-agent"))] | length' 2>/dev/null || echo 9)
        [ "$aq" -lt 5 ] && { echo "AUSTIN_QUEUE_LOW $aq ready tickets queued for $peer"; exit 0; }
      done
    fi
  fi
  # idle 10 min in short ticks so a channel message (pf-msg.sh listen -> msg-wake.txt) wakes us within PF_TICK seconds
  tick=0
  while [ "$tick" -lt 60 ]; do
    sleep "${PF_TICK:-10}"; tick=$((tick+1))
    # new = wake file modified since the last one handled (so an identical repeat message still wakes)
    wm=$(pf_mtime "$PF_STATE/msg-wake.txt")
    if [ -n "$wm" ] && [ -s "$PF_STATE/msg-wake.txt" ] && [ "$wm" != "$(cat "$PF_STATE/.msg-wake-handled" 2>/dev/null)" ]; then
      echo "$wm" > "$PF_STATE/.msg-wake-handled"; head -n 1 "$PF_STATE/msg-wake.txt"; exit 0
    fi
  done
done
