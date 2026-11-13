#!/bin/bash
# Zero-token triage watcher. Polls GitHub every 10 min and exits with one line only when something needs
# Claude's judgement; Claude acts, then restarts it. Merging green PRs is pf-automerge.sh.
#   UNTRIAGED <n...>   (triagemaster only) open issue missing a p1/p2/p3 label or an assignee
#   MYTICKET <n>       ready-for-agent ticket assigned to this account and no worktree in progress
#   FEATURES? PR <n>   (triagemaster only) open PR changes scripts/ or controller/ without docs/FEATURES.md (once per PR)
#   PEER_BEACON        a WATCH_PEERS account's USAGE beacon (private channel, msg-inbox.log) became fresh (once)
#   DEV_IDLE <account> <minutes>  (triagemaster only) a peer with live heartbeats has ready work (ready-for-agent ticket without a PR, or a
#                      review-blocked PR with no fix since) and its USAGE claude_at is 45+ min old; day, at night only p1; never for an
#                      account at its 5h/weekly stop; once per 2 h, plus one wake at 120 min (autotriage.md rule 21)
#   IDLE_SLOTS <n>/<target>  hourly: fewer active work packages than pf_worker_target (ticket-maker off: only if a ready ticket is startable) (day DAY_AGENTS, night
#                      NIGHT_AGENTS, 1 past FIVE_H_SLOW_USED, 0 past FIVE_H_STOP_USED or the weekly stop)
#   AUSTIN_QUEUE_LOW <n>  (triagemaster only, ticket-maker on) hourly: a peer has fewer than 5 ready dev tickets; Claude files and assigns more
#   MSG <TYPE> ...     a new CLAIM/ASK/FIRE line (or a late pf-ask.sh ANSWER) from pf-msg.sh listen (msg-wake.txt); checked every PF_TICK (10) s while idle
#   DISCORD_BUG <n> new in #change-requests  (triagemaster only, pf-discord.conf set up) people posted in the public
#                      channel; checked once a minute while idle; Claude reads them with pf-discord-bugs.sh read
#   DISCORD_DEV <n> new in #hive  the same for the private dev channel (pf-discord-bugs.sh --dev read): pre-approved
#   HIVE_TAKEOVER <msg id>  (not the triagemaster) a dev message in #hive has had no answer for 10 min and this account is the next
#                      live one in succession order (rule 21): run pf-hive-failover.sh takeover <id>, then answer. An account
#                      without pf-discord.conf asks the owner on the private channel instead (once per 6h).
#   DISCORD_APPROVED <issue> <user>  every 5 min: a dev reacted ✅ to the Discord source of a needs-triage issue
#   TM_CHECK_FAIL <line>  (triagemaster only) every 6h pf-tm-check.sh found a duty not covered; the line says how to fix it
#   DIGEST_DUE <YYYY-MM-DD>  (triagemaster only) it is DIGEST_HOUR (9) or later in the account's TZ and today's digest
#                      (autotriage.md rule 8) is not marked sent; repeats until `pf-triage-watch.sh --digest-sent` (#1257)
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
META_TICKETS=${META_TICKETS:-"702 720 619"}   # meta tickets that never count as a peer's dev queue
# pf_dev_throttled: the beacon in pf_beacon's b_* vars shows an account that must sit idle (rules 2, 3): 5h at the stop with the
# window still open, or weekly at the handoff level with the reset more than RESET_GRACE_HOURS away. Unknown numbers do not exempt.
pf_dev_throttled() {
  local r
  if [ -n "$b_p5" ] && [ "$b_p5" -ge "${FIVE_H_STOP_USED:-90}" ] && [ -n "$b_r5" ]; then
    r=$(pf_iso_to_epoch "$b_r5") && [ "$r" -gt "$(date +%s)" ] && return 0
  fi
  if [ -n "$b_used" ] && [ "$b_used" -ge "${HANDOFF_WEEKLY_USED:-85}" ] && [ -n "$b_reset" ]; then
    r=$(pf_iso_to_epoch "$b_reset") && [ $(( r - $(date +%s) )) -gt $(( ${RESET_GRACE_HOURS:-24} * 3600 )) ] && return 0
  fi
  return 1
}
# pf_dev_waiting <handle> <issues> <pr_tickets> <cr_busy>: 0 when work waits on the handle (autotriage.md rule 21): a
# ready-for-agent ticket with no open PR, or a review-blocked PR of theirs with no commit pushed since the block. At night only p1.
pf_dev_waiting() {
  local h=$1 night=0 n cr p
  [ "$(pf_daynight)" = night ] && night=1
  for n in $(echo "$2" | jq -r --arg h "$h" --argjson ni "$night" '.[] | select(.pull_request==null) | select(any(.assignees[]; .login==$h)) | select(any(.labels[]; .name=="ready-for-agent")) | select($ni==0 or any(.labels[]; .name=="p1")) | "\(.number)|\(any(.labels[]; .name=="conflict-risk"))"'); do
    cr=${n#*|}; n=${n%%|*}
    case " $META_TICKETS " in *" $n "*) continue;; esac
    case " $3 " in *" $n "*) continue;; esac
    [ "$cr" = true ] && [ "$4" = 1 ] && continue
    return 0
  done
  for p in $(gh pr list --repo "$REPO" --state open -L 100 --author "$h" --label review-blocked --json number,labels 2>/dev/null | jq -r --argjson ni "$night" '.[] | select($ni==0 or any(.labels[]; .name=="p1")) | .number'); do
    gh api --paginate "repos/$REPO/issues/$p/timeline?per_page=100" 2>/dev/null | jq -s -e 'add // [] | (map(select(.event=="labeled" and .label.name=="review-blocked")) | last | .created_at) as $b | $b != null and ([.[] | select((.event=="committed" or .event=="head_ref_force_pushed") and ((.created_at // .committer.date // .author.date // "") > $b))] | length == 0)' >/dev/null 2>&1 && return 0
  done
  return 1
}
# pf_dev_idle_check <issues> <pr_tickets> <cr_busy>: prints one "DEV_IDLE <account> <minutes>" line (exit 0) for the first peer whose
# Claude session is idle with work waiting, else nothing (exit 1). Stamp $PF_STATE/.dev-idle-<h>: "<epoch of wake> <stage 1|2>".
pf_dev_idle_check() {
  local h now ca idle st t stage ok
  now=$(date +%s)
  for h in $(pf_handles); do
    [ "$h" = "$PF_ACCOUNT" ] && continue
    # live heartbeat: a HELLO or USAGE line under 1 h old
    awk -F'|' -v h="$h" -v now="$now" '$2==h && ($3=="USAGE" || $3=="HELLO") && now-$1<3600 {f=1} END {exit !f}' "$PF_STATE/msg-inbox.log" 2>/dev/null || continue
    ca=$(pf_peer_claude_at "$h"); [ -n "$ca" ] || continue
    idle=$((now - ca)); [ "$idle" -ge 2700 ] || continue
    st=$(cat "$PF_STATE/.dev-idle-$h" 2>/dev/null || echo "0 0"); t=${st%% *}; stage=${st##* }
    ok=1
    if [ "$t" -ge "$ca" ]; then   # already woken in this idle stretch: next at 2 h, or the one stage-2 wake when idle reaches 2 h
      ok=0
      [ $((now - t)) -ge 7200 ] && ok=1
      [ "$stage" = 1 ] && [ "$idle" -ge 7200 ] && ok=1
    fi
    [ "$ok" = 1 ] || continue
    pf_beacon "$h"; pf_dev_throttled && continue
    pf_dev_waiting "$h" "$1" "$2" "$3" || continue
    stage=1; [ "$idle" -ge 7200 ] && stage=2
    echo "$now $stage" > "$PF_STATE/.dev-idle-$h"
    echo "DEV_IDLE $h $((idle / 60))"; return 0
  done
  return 1
}
# pf_digest_due [epoch]: prints today's date in the account's TZ (YYYY-MM-DD) when it is DIGEST_HOUR (default 9)
# o'clock or later there and $PF_STATE/digest-sent does not hold that date; nothing (exit 1) otherwise (#1257).
pf_digest_due() {
  local now=${1:-$(date +%s)} day hour
  day=$(pf_epoch_fmt "$now" +%Y-%m-%d) || return 1
  hour=$(pf_epoch_fmt "$now" +%H) || return 1
  [ "$((10#$hour))" -ge "${DIGEST_HOUR:-9}" ] || return 1
  [ -f "$PF_STATE/digest-sent" ] && [ "$(tr -d '\r\n ' < "$PF_STATE/digest-sent")" = "$day" ] && return 1
  echo "$day"
}
# pf_digest_mark_sent [epoch]: records today's digest as sent, so DIGEST_DUE stops until the next day.
pf_digest_mark_sent() {
  pf_epoch_fmt "${1:-$(date +%s)}" +%Y-%m-%d > "$PF_STATE/digest-sent"
}
[ "${1:-}" = --functions ] && { return 0 2>/dev/null || exit 0; }   # tests/triage-watch-in-progress.sh sources the helpers only
. "$(dirname "$0")/pf-env.sh" || exit 1
# `pf-triage-watch.sh --digest-sent`: the triagemaster has sent today's 9 AM digest (rule 8); zero tokens, no polling.
[ "${1:-}" = --digest-sent ] && { pf_digest_mark_sent && echo "digest marked sent for $(cat "$PF_STATE/digest-sent")"; exit 0; }
SEEN=$PF_STATE/.pf-triage-seen; touch "$SEEN"
# first run: a wake file older than this watcher counts as handled
[ -f "$PF_STATE/.msg-wake-handled" ] || pf_mtime "$PF_STATE/msg-wake.txt" > "$PF_STATE/.msg-wake-handled" 2>/dev/null
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
    # the 9 AM digest (rule 8, #1257): wakes until marked sent, so a session that starts late still sends it
    d=$(pf_digest_due) && { echo "DIGEST_DUE $d"; exit 0; }
  fi
  issues=$(gh api --paginate "repos/$REPO/issues?state=open&per_page=100" 2>/dev/null | jq -s 'add // []' 2>/dev/null)   # every page, one array
  [ "$issues" = "[]" ] && issues=""
  # open PRs once per poll, not per ticket (empty on failure: then only branches count)
  pr_tickets=$(pf_pr_tickets "$(gh pr list --repo "$REPO" --state open -L 200 --json number,body,title,headRefName 2>/dev/null)")
  cr_busy=0
  if [ -n "$issues" ]; then
    if pf_is_triagemaster; then
      u=$(echo "$issues" | jq -r '.[] | select(.pull_request==null) | select(((.labels|map(.name)|map(test("^p[123]$"))|any)|not) or ((.assignees|length)==0)) | .number' | tr '\n' ' ')
      [ -n "${u// /}" ] && { echo "UNTRIAGED $u"; exit 0; }
    fi
    # rule 6: one conflict-risk ticket in flight across all devs; while one is in progress, the others wait (no MYTICKET)
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
  if pf_is_triagemaster && [ -n "$issues" ]; then
    d=$(pf_dev_idle_check "$issues" "$pr_tickets" "$cr_busy") && { echo "$d"; exit 0; }
  fi
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
      for n in $(echo "$issues" | jq -r --arg me "$PF_ACCOUNT" '.[] | select(.pull_request==null) | select(any(.labels[]; .name=="ready-for-agent")) | select((.assignees|length)==0 or any(.assignees[]; .login==$me)) | "\(.number)|\(any(.labels[]; .name=="conflict-risk"))"'); do
        cr=${n#*|}; n=${n%%|*}
        [ "$cr" = true ] && [ "$cr_busy" = 1 ] && continue   # held by rule 6, not startable
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
    # #hive failover (rule 21): every minute, on every machine that is not the triagemaster
    if [ $((tick % 6)) = 3 ] && ! pf_is_triagemaster; then
      hv=$(bash "$(dirname "$0")/pf-hive-failover.sh" check 2>/dev/null) && { echo "$hv"; exit 0; }
    fi
    # Discord #bug-reports (autotriage.md rule 18): once a minute, triagemaster only, once the bot token is set up
    : > "$PF_STATE/.triage-watch-alive"
    if [ $((tick % 6)) = 0 ] && [ -f "$PF_STATE/pf-discord.conf" ] && pf_is_triagemaster; then
      n=$(bash "$(dirname "$0")/pf-discord-bugs.sh" check 2>"$PF_STATE/discord-check.err"); rc=$?
      [ "$rc" = 0 ] && { echo "DISCORD_BUG $n new in #change-requests"; exit 0; }
      n=$(bash "$(dirname "$0")/pf-discord-bugs.sh" --dev check 2>/dev/null) && { echo "DISCORD_DEV $n new in #hive"; exit 0; }
      if [ $((tick % 30)) = 0 ]; then
        a=$(bash "$(dirname "$0")/pf-discord-bugs.sh" approvals 2>/dev/null | head -n 1)
        [ -n "$a" ] && { echo "DISCORD_APPROVED $a"; exit 0; }
      fi
      if [ "$rc" = 2 ]; then   # Discord unreadable: wake after 10 failed checks in a row, then at most hourly
        f=$(( $(cat "$PF_STATE/.discord-fails" 2>/dev/null || echo 0) + 1 )); echo "$f" > "$PF_STATE/.discord-fails"
        dl=$(cat "$PF_STATE/.discord-fail-woke" 2>/dev/null || echo 0)
        if [ "$f" -ge 10 ] && [ $(( $(date +%s) - dl )) -ge 3600 ]; then
          date +%s > "$PF_STATE/.discord-fail-woke"
          echo "TM_CHECK_FAIL Discord #change-requests unreadable for 10 min: $(head -c 160 "$PF_STATE/discord-check.err" | tr '\n' ' ') (run pf-tm-check.sh)"; exit 0
        fi
      else echo 0 > "$PF_STATE/.discord-fails"; fi
    fi
  done
done
