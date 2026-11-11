#!/bin/bash
# Zero-token triage watcher. Polls GitHub every 10 min and exits with one line only when something needs
# Claude's judgement; Claude acts, then restarts it. Merging green PRs is pf-automerge.sh.
#   UNTRIAGED <n...>   (triagemaster only) open issue missing a p1/p2/p3 label or an assignee
#   MYTICKET <n>       ready-for-agent ticket assigned to this account and no worktree in progress
#   FEATURES? PR <n>   (triagemaster only) open PR changes scripts/ or controller/ without docs/FEATURES.md (once per PR)
#   PEER_BEACON        a WATCH_PEERS account's USAGE beacon (private channel, msg-inbox.log) became fresh (once)
#   IDLE_SLOTS <n>/<target>  hourly: fewer active work packages than pf_worker_target (ticket-maker off: only if a ready ticket is startable) (day DAY_AGENTS, night
#                      NIGHT_AGENTS, 1 past FIVE_H_SLOW_USED, 0 past FIVE_H_STOP_USED or the weekly stop)
#   AUSTIN_QUEUE_LOW <n>  (triagemaster only, ticket-maker on) hourly: a peer has fewer than 5 ready dev tickets; Claude files and assigns more
#   MSG <TYPE> ...     a new CLAIM/ASK/FIRE line from pf-msg.sh listen (msg-wake.txt); checked every PF_TICK (10) s while idle
#   DISCORD_BUG <n> new in #bug-reports  (triagemaster only, pf-discord.conf set up) people posted in the Discord server's
#                      #bug-reports channel; checked once a minute while idle; Claude reads them with pf-discord-bugs.sh read
#   TM_CHECK_FAIL <line>  (triagemaster only) every 6h pf-tm-check.sh found a duty not covered; the line says how to fix it
# Tickets the open PRs are working on, space-separated: Closes|Fixes|Resolves|Refs #N in a title or body (one PR may
# close several tickets, #1147), or a head branch named for the ticket. $1 = gh pr list --json number,body,title,headRefName
pf_pr_tickets() {
  echo "$1" | jq -r '[.[] | ((((.title // "") + "\n" + (.body // "")) | scan("(?i)(?<![a-z])(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?|refs?)[:\\s]+#([0-9]+)") | .[0]),
    ((.headRefName // "") | scan("issue-([0-9]+)-|(?:^|/)([0-9]+)-") | map(select(. != null))[0]))] | unique | join(" ")' 2>/dev/null
}
# pf_ticket_in_progress <n> <pf_pr_tickets output>: an open PR is on it, or a local or remote branch for it exists
# (feat/issue-N-slug from workers, fix/N-slug from the owner's main terminal). The MYTICKET filter and IDLE_SLOTS count use it.
pf_ticket_in_progress() {
  case " $2 " in *" $1 "*) return 0;; esac
  git -C "$ROOT" branch -a --list "*issue-$1-*" "*/$1-*" | grep -q .
}
[ "${1:-}" = --functions ] && { return 0 2>/dev/null || exit 0; }   # tests/triage-watch-in-progress.sh sources the helpers only
. "$(dirname "$0")/pf-env.sh" || exit 1
SEEN=$PF_STATE/.pf-triage-seen; touch "$SEEN"
# first run: a wake file older than this watcher counts as handled
[ -f "$PF_STATE/.msg-wake-handled" ] || pf_mtime "$PF_STATE/msg-wake.txt" > "$PF_STATE/.msg-wake-handled" 2>/dev/null
META_TICKETS=${META_TICKETS:-"702 720 619"}   # meta tickets that never count as a peer's dev queue
while true; do
  : > "$PF_STATE/.triage-watch-alive"   # heartbeat for pf-tm-check.sh (rule 19), every poll and tick
  # every 6h the triagemaster self-checks its duties (autotriage.md rule 19); first in the loop so other wakes
  # never postpone it. A FAIL wakes Claude to fix it.
  if pf_is_triagemaster; then
    last=$(cat "$PF_STATE/.pf-tmcheck-last" 2>/dev/null || echo 0)
    if [ $(( $(date +%s) - last )) -ge 21600 ]; then
      date +%s > "$PF_STATE/.pf-tmcheck-last"
      f=$(bash "$(dirname "$0")/pf-tm-check.sh" --quiet 2>/dev/null | grep '^FAIL' | head -n 1)
      [ -n "$f" ] && { echo "TM_CHECK_FAIL ${f#FAIL }"; exit 0; }
    fi
  fi
  issues=$(gh api --paginate "repos/$REPO/issues?state=open&per_page=100" 2>/dev/null | jq -s 'add // []' 2>/dev/null)   # every page, one array
  [ "$issues" = "[]" ] && issues=""
  # open PRs once per poll, not per ticket (empty on failure: then only branches count)
  pr_tickets=$(pf_pr_tickets "$(gh pr list --repo "$REPO" --state open -L 200 --json number,body,title,headRefName 2>/dev/null)")
  if [ -n "$issues" ]; then
    if pf_is_triagemaster; then
      u=$(echo "$issues" | jq -r '.[] | select(.pull_request==null) | select(((.labels|map(.name)|map(test("^p[123]$"))|any)|not) or ((.assignees|length)==0)) | .number' | tr '\n' ' ')
      [ -n "${u// /}" ] && { echo "UNTRIAGED $u"; exit 0; }
    fi
    # rule 6: one conflict-risk ticket in flight across all devs; while one is in progress, the others wait (no MYTICKET)
    cr_busy=0
    for c in $(echo "$issues" | jq -r '.[] | select(.pull_request==null) | select(any(.labels[]; .name=="conflict-risk")) | .number'); do
      pf_ticket_in_progress "$c" "$pr_tickets" && { cr_busy=1; break; }
    done
    for n in $(echo "$issues" | jq -r --arg me "$PF_ACCOUNT" '.[] | select(.pull_request==null) | select(any(.assignees[]; .login==$me)) | select(any(.labels[]; .name=="ready-for-agent")) | "\(.number)|\(any(.labels[]; .name=="conflict-risk"))"'); do
      cr=${n#*|}; n=${n%%|*}
      # skip tickets already in progress: a branch for the issue, or an open PR that closes or refs it
      pf_ticket_in_progress "$n" "$pr_tickets" && continue
      [ "$cr" = true ] && [ "$cr_busy" = 1 ] && continue
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
  pf_usage_backfill
  for peer in ${WATCH_PEERS:-agage-JG}; do
    grep -qx "beacon-$peer" "$SEEN" && continue
    pf_beacon "$peer"   # newest USAGE message from the peer
    if [ "$b_age" -lt 21600 ]; then
      echo "beacon-$peer" >> "$SEEN"; echo "PEER_BEACON $peer fresh at $b_at"; exit 0
    fi
  done
  # hourly productivity check: fewer active work packages than this mode's minimum -> wake Claude to start more
  last=$(cat "$PF_STATE/.pf-slots-last" 2>/dev/null || echo 0)
  if [ $(( $(date +%s) - last )) -ge 3600 ]; then
    date +%s > "$PF_STATE/.pf-slots-last"
    min=$(pf_worker_target)
    active=$(ls "$ROOT"/.claude/atlas-state/*.json 2>/dev/null | wc -l | tr -d ' ')
    # plus tickets of mine in flight outside Atlas: open, assigned to me, a branch or open PR on it
    for n in $(echo "$issues" | jq -r --arg me "$PF_ACCOUNT" '.[] | select(.pull_request==null) | select(any(.assignees[]; .login==$me)) | .number'); do
      pf_ticket_in_progress "$n" "$pr_tickets" && active=$((active+1))
    done
    # ticket-maker off (rule 11): fewer workers is expected, so wake only if a ready ticket I could start exists
    # (assigned to me or unassigned, not already in progress)
    startable=1
    if [ "$active" -lt "$min" ] && [ "$(bash "$(dirname "$0")/pf-ticketmaker.sh")" = off ]; then
      startable=0
      for n in $(echo "$issues" | jq -r --arg me "$PF_ACCOUNT" '.[] | select(.pull_request==null) | select(any(.labels[]; .name=="ready-for-agent")) | select((.assignees|length)==0 or any(.assignees[]; .login==$me)) | .number'); do
        pf_ticket_in_progress "$n" "$pr_tickets" || { startable=1; break; }
      done
    fi
    if [ "$active" -lt "$min" ] && [ "$startable" = 1 ]; then echo "IDLE_SLOTS $active/$min active work packages"; exit 0; fi
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
    # Discord #bug-reports (autotriage.md rule 18): once a minute, triagemaster only, once the bot token is set up
    : > "$PF_STATE/.triage-watch-alive"
    if [ $((tick % 6)) = 0 ] && [ -f "$PF_STATE/pf-discord.conf" ] && pf_is_triagemaster; then
      n=$(bash "$(dirname "$0")/pf-discord-bugs.sh" check 2>"$PF_STATE/discord-check.err"); rc=$?
      [ "$rc" = 0 ] && { echo "DISCORD_BUG $n new in #bug-reports"; exit 0; }
      if [ "$rc" = 2 ]; then   # Discord unreadable: wake after 10 failed checks in a row, then at most hourly
        f=$(( $(cat "$PF_STATE/.discord-fails" 2>/dev/null || echo 0) + 1 )); echo "$f" > "$PF_STATE/.discord-fails"
        dl=$(cat "$PF_STATE/.discord-fail-woke" 2>/dev/null || echo 0)
        if [ "$f" -ge 10 ] && [ $(( $(date +%s) - dl )) -ge 3600 ]; then
          date +%s > "$PF_STATE/.discord-fail-woke"
          echo "TM_CHECK_FAIL Discord #bug-reports unreadable for 10 min: $(head -c 160 "$PF_STATE/discord-check.err" | tr '\n' ' ') (run pf-tm-check.sh)"; exit 0
        fi
      else echo 0 > "$PF_STATE/.discord-fails"; fi
    fi
  done
done
