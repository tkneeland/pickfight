#!/bin/bash
# Zero-token triage watcher. Polls the tracker every WATCH_INTERVAL (600) s and exits with one line only when something needs
# Claude's judgement; Claude acts, then restarts it. Merging green PRs is hive-automerge.sh.
#   UNTRIAGED <n...>   (triagemaster only) open issue missing a p1/p2/p3 label or an assignee
#   MYTICKET <n>       ready-for-agent ticket assigned to this account, no open PR or branch on it, and no work package in progress
#   FEATURES? PR <n>   (triagemaster only, needs FEATURE_DOC + FEATURE_PATHS) PR touches those paths without FEATURE_DOC (once per PR)
#   PEER_BEACON <h>    a peer account's USAGE beacon (private channel, msg-inbox.log) became fresh (once)
#   DEV_IDLE <account> <minutes>  (triagemaster only) a peer with live heartbeats has ready work (ready-for-agent ticket without a
#                      PR, or a review-blocked PR with no fix since) and its USAGE claude_at is 45+ min old; in its quiet hours only p1;
#                      never for an account at its 5h/weekly stop; once per 2 h, plus one wake at 120 min (docs/agents/hive.md rule 21)
#   IDLE_SLOTS <n>/<target>  hourly: fewer active work packages than hive_worker_target (WORKER_TARGET on pace, 1 ahead of pace or past
#                      FIVE_H_SLOW_USED, 0 past FIVE_H_STOP_USED or the weekly stop). Ticket-maker off: only if a ready ticket is startable
#   PEER_QUEUE_LOW <n> <peer>  (triagemaster only, ticket-maker on) hourly: a peer has fewer than PEER_QUEUE_MIN ready dev tickets
#   <hook line>        the first non-empty stdout line of any WATCH_HOOKS command (run every poll, zero tokens)
#   MSG <TYPE> ...     a new CLAIM/ASK/FIRE line (or a late hive-ask.sh ANSWER) from hive-msg.sh listen (msg-wake.txt); checked every
#                      HIVE_TICK (10) s while idle
#   DISCORD_BUG <n> new in #<DISCORD_BUGS_NAME>  (triagemaster only, DISCORD=1 with a bot token) people posted in the public channel;
#                      checked once a minute while idle; Claude reads them with hive-discord-bugs.sh read
#   DISCORD_DEV <n> new in #<DISCORD_DEV_NAME>  the same for the private dev channel (hive-discord-bugs.sh --dev read): pre-approved
#   HIVE_TAKEOVER <msg id>  (not the triagemaster, DISCORD=1) a dev message in the dev channel has had no answer for 10 min and this
#                      account is the next live one in succession order (rule 21): run hive-failover.sh takeover <id>, then answer
#   DISCORD_APPROVED <issue> <user>  every 5 min: a dev reacted ✅ to the Discord source of a needs-triage issue
#   TM_CHECK_FAIL <line>  (triagemaster only) every 6h hive-tm-check.sh found a duty not covered; the line says how to fix it
#   MODE_MT            hive-at-mode.sh says MT: stop watching
# TRACKER=local: UNTRIAGED <ids> = in-scope needs-triage tickets, MYTICKET <id> = in-scope ready-for-agent ticket while no
# work package is active. GitHub is not polled at all (no FEATURES?/DEV_IDLE/PEER_QUEUE_LOW lines).

# Tickets the open PRs are working on, space-separated: Closes|Fixes|Resolves|Refs #N in a title or body (one PR may close
# several tickets), or a head branch named for the ticket. $1 = gh pr list --json number,body,title,headRefName
hive_pr_tickets() {
  echo "$1" | jq -r '[.[] | ((((.title // "") + "\n" + (.body // "")) | scan("(?i)(?<![a-z])(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?|refs?)[:\\s]+#([0-9]+)") | .[0]),
    ((.headRefName // "") | scan("issue-([0-9]+)-|(?:^|/)([0-9]+)-") | map(select(. != null))[0]))] | unique | join(" ")' 2>/dev/null
}
# hive_ticket_in_progress <n> <hive_pr_tickets output>: an open PR is on it, or a local or remote branch for it exists
# (feat/issue-N-slug from workers, <type>/N-slug from the owner's main terminal). The MYTICKET filter and IDLE_SLOTS count use it.
hive_ticket_in_progress() {
  case " $2 " in *" $1 "*) return 0;; esac
  git -C "$ROOT" branch -a --list "*issue-$1-*" "*/$1-*" | grep -q .
}
# hive_dev_throttled <handle>: the beacon in hive_beacon's b_* vars shows an account that must sit idle (rules 2, 3, 5): 5h at
# its own stop (hive_limits) with the window still open, weekly at the handoff level or at its own weekly ticket limit with the
# reset more than RESET_GRACE_HOURS away. Unknown numbers do not exempt.
hive_dev_throttled() {
  local r; hive_limits "$1"
  if [ -n "$b_used" ] && [ -n "$b_reset" ] && r=$(hive_iso_to_epoch "$b_reset") && hive_weekly_capped "$b_used" "$r" "$l_wmin"; then return 0; fi
  if [ -n "$b_p5" ] && [ "$b_p5" -ge "$l_5h" ] && [ -n "$b_r5" ]; then
    r=$(hive_iso_to_epoch "$b_r5") && [ "$r" -gt "$(date +%s)" ] && return 0
  fi
  if [ -n "$b_used" ] && [ "$b_used" -ge "${HANDOFF_WEEKLY_USED:-85}" ] && [ -n "$b_reset" ]; then
    r=$(hive_iso_to_epoch "$b_reset") && [ $(( r - $(date +%s) )) -gt $(( ${RESET_GRACE_HOURS:-24} * 3600 )) ] && return 0
  fi
  return 1
}
# hive_dev_waiting <handle> <issues> <pr_tickets> <cr_busy>: 0 when work waits on the handle (hive.md rule 21): a ready-for-agent
# ticket with no open PR, or a review-blocked PR of theirs with no commit pushed since the block. In the handle's quiet hours only p1.
hive_dev_waiting() {
  local h=$1 quiet=0 n cr p
  hive_quiet "$h" && quiet=1
  for n in $(echo "$2" | jq -r --arg h "$h" --argjson ni "$quiet" '.[] | select(.pull_request==null) | select(any(.assignees[]; .login==$h)) | select(any(.labels[]; .name=="ready-for-agent")) | select($ni==0 or any(.labels[]; .name=="p1")) | "\(.number)|\(any(.labels[]; .name=="conflict-risk"))"'); do
    cr=${n#*|}; n=${n%%|*}
    case " ${META_TICKETS:-} " in *" $n "*) continue;; esac
    case " $3 " in *" $n "*) continue;; esac
    [ "$cr" = true ] && [ "$4" = 1 ] && continue
    return 0
  done
  for p in $(gh pr list --repo "$REPO" --state open -L 100 --author "$h" --label review-blocked --json number,labels 2>/dev/null | jq -r --argjson ni "$quiet" '.[] | select($ni==0 or any(.labels[]; .name=="p1")) | .number'); do
    gh api --paginate "repos/$REPO/issues/$p/timeline?per_page=100" 2>/dev/null | jq -s -e 'add // [] | (map(select(.event=="labeled" and .label.name=="review-blocked")) | last | .created_at) as $b | $b != null and ([.[] | select((.event=="committed" or .event=="head_ref_force_pushed") and ((.created_at // .committer.date // .author.date // "") > $b))] | length == 0)' >/dev/null 2>&1 && return 0
  done
  return 1
}
# hive_dev_idle_check <issues> <pr_tickets> <cr_busy>: prints one "DEV_IDLE <account> <minutes>" line (exit 0) for the first peer
# whose Claude session is idle with work waiting, else nothing (exit 1). Stamp $HIVE_STATE/.dev-idle-<h>: "<epoch of wake> <stage 1|2>".
hive_dev_idle_check() {
  local h now ca idle st t stage ok
  now=${HIVE_NOW:-$(date +%s)}   # HIVE_NOW pins the clock (tests)
  for h in $(hive_handles); do
    [ "$h" = "$HIVE_ACCOUNT" ] && continue
    # live: any channel message from it under HIVE_PEER_LIVE_SECS old (HELLO and USAGE only go out hourly when idle)
    [ $(( now - $(hive_peer_heard "$h") )) -lt "$HIVE_PEER_LIVE_SECS" ] || continue
    ca=$(hive_peer_claude_at "$h"); [ -n "$ca" ] || continue
    idle=$((now - ca)); [ "$idle" -ge 2700 ] || continue
    st=$(cat "$HIVE_STATE/.dev-idle-$h" 2>/dev/null || echo "0 0"); t=${st%% *}; stage=${st##* }
    # rule 21: one wake per 2 h whatever claude_at does (it can move hourly with the dev away), plus one stage-2 wake when idle reaches 2 h
    ok=0
    [ $((now - t)) -ge 7200 ] && ok=1
    [ "$stage" = 1 ] && [ "$t" -ge "$ca" ] && [ "$idle" -ge 7200 ] && ok=1
    [ "$ok" = 1 ] || continue
    hive_beacon "$h"; hive_dev_throttled "$h" && continue
    hive_dev_waiting "$h" "$1" "$2" "$3" || continue
    stage=1; [ "$idle" -ge 7200 ] && stage=2
    echo "$now $stage" > "$HIVE_STATE/.dev-idle-$h"
    echo "DEV_IDLE $h $((idle / 60))"; return 0
  done
  return 1
}
[ "${1:-}" = --functions ] && { return 0 2>/dev/null || exit 0; }   # tests/triage-watch-in-progress.sh sources the helpers only
. "$(dirname "$0")/hive-env.sh" || exit 1
SEEN=$HIVE_STATE/.triage-seen; touch "$SEEN"
# first run: a channel wake file older than this watcher counts as handled
[ -f "$HIVE_STATE/.msg-wake-handled" ] || hive_mtime "$HIVE_STATE/msg-wake.txt" > "$HIVE_STATE/.msg-wake-handled" 2>/dev/null
SKIP_NUMS="${BEACON_ISSUE:-} $DECISIONS_ISSUE ${META_TICKETS:-}"   # never untriaged work, never a dev queue
# Discord wakes run only where the bot is on (DISCORD=1, not private, a token in discord.conf)
discord_on() { [ "${DISCORD:-0}" = 1 ] && [ "$PRIVATE" != 1 ] && [ "$SINGLE_ACCOUNT" != 1 ] && grep -q '^HIVE_DISCORD_TOKEN=.' "$HIVE_STATE/discord.conf" 2>/dev/null; }
run_hooks() {  # WATCH_HOOKS: ';'-separated commands, run from the install root
  local h out IFS=';'; for h in $WATCH_HOOKS; do
    [ -n "${h// /}" ] || continue
    out=$(cd "$HIVE_ROOT" && bash -c "$h" 2>/dev/null | sed '/^[[:space:]]*$/d' | head -1)
    [ -n "$out" ] && { echo "$out"; return 0; }
  done; return 1; }
ticketmaker() { bash "$HIVE_DIR/hive-ticketmaker.sh" 2>/dev/null || echo on; }
while true; do
  : > "$HIVE_STATE/.triage-watch-alive"   # heartbeat for hive-tm-check.sh (rule 19), every poll and tick
  [ "$(bash "$HIVE_DIR/hive-at-mode.sh")" = MT ] && { echo MODE_MT; exit 0; }
  # every 6h the triagemaster self-checks its duties (rule 19); first in the loop so other wakes never postpone it
  if hive_is_triagemaster && [ "$SINGLE_ACCOUNT" != 1 ]; then
    last=$(cat "$HIVE_STATE/.tmcheck-last" 2>/dev/null || echo 0)
    if [ $(( $(date +%s) - last )) -ge 21600 ]; then
      date +%s > "$HIVE_STATE/.tmcheck-last"
      f=$(bash "$HIVE_DIR/hive-tm-check.sh" --quiet 2>/dev/null | grep '^FAIL' | head -n 1)
      [ -n "$f" ] && { echo "TM_CHECK_FAIL ${f#FAIL }"; exit 0; }
    fi
  fi
  run_hooks && exit 0
  issues=""; pr_tickets=""; cr_busy=0
  if [ "$TRACKER" = local ]; then
    u=$(hive_tickets needs-triage | tr '\n' ' '); [ -n "${u// /}" ] && { echo "UNTRIAGED $u"; exit 0; }
    if [ "$(hive_active_packages)" = 0 ]; then
      r=$(hive_tickets ready-for-agent | head -1); [ -n "$r" ] && { echo "MYTICKET $r"; exit 0; }
    fi
  else
    issues=$(gh api --paginate "repos/$REPO/issues?state=open&per_page=100" 2>/dev/null | jq -s 'add // []' 2>/dev/null)   # every page, one array
    [ "$issues" = "[]" ] && issues=""
    # open PRs once per poll, not per ticket (empty on failure: then only branches count)
    pr_tickets=$(hive_pr_tickets "$(gh pr list --repo "$REPO" --state open -L 200 $(hive_pr_author_flag) --json number,body,title,headRefName 2>/dev/null)")
  fi
  if [ -n "$issues" ]; then
    if hive_is_triagemaster; then
      u=$(echo "$issues" | jq -r --arg skip "$SKIP_NUMS" '($skip|split(" ")|map(select(length>0)|tonumber)) as $s | .[] | select(.pull_request==null and (.number|IN($s[])|not)) | select(((.labels|map(.name)|map(test("^p[123]$"))|any)|not) or ((.assignees|length)==0)) | .number' | tr '\n' ' ')
      [ -n "${u// /}" ] && { echo "UNTRIAGED $u"; exit 0; }
    fi
    # rule 6: one conflict-risk ticket in flight across all devs; while one is in progress, the others wait (no MYTICKET)
    for c in $(echo "$issues" | jq -r '.[] | select(.pull_request==null) | select(any(.labels[]; .name=="conflict-risk")) | .number'); do
      hive_ticket_in_progress "$c" "$pr_tickets" && { cr_busy=1; break; }
    done
    for n in $(echo "$issues" | jq -r --arg me "$HIVE_ACCOUNT" '.[] | select(.pull_request==null) | select(any(.assignees[]; .login==$me)) | select(any(.labels[]; .name=="ready-for-agent")) | "\(.number)|\(any(.labels[]; .name=="conflict-risk"))"'); do
      cr=${n#*|}; n=${n%%|*}
      # skip tickets already in progress: a branch for the issue, or an open PR that closes or refs it
      hive_ticket_in_progress "$n" "$pr_tickets" && continue
      [ "$cr" = true ] && [ "$cr_busy" = 1 ] && continue
      # only when I am idle: no Atlas state file (removed at closeout)
      [ "$(hive_active_packages)" = 0 ] && { echo "MYTICKET $n"; exit 0; }
    done
    if hive_is_triagemaster && [ -n "${FEATURE_DOC:-}" ] && [ -n "${FEATURE_PATHS:-}" ]; then
      for p in $(echo "$issues" | jq -r '.[] | select(.pull_request!=null) | .number'); do
        grep -qx "pr$p" "$SEEN" && continue
        files=$(gh api "repos/$REPO/pulls/$p/files?per_page=100" --jq '.[].filename' 2>/dev/null) || continue
        [ -z "$files" ] && continue
        echo "$files" | grep -qE "$FEATURE_PATHS" && ! echo "$files" | grep -qx "$FEATURE_DOC" && { echo "pr$p" >> "$SEEN"; echo "FEATURES? PR $p"; exit 0; }
        echo "pr$p" >> "$SEEN"
      done
    fi
  fi
  if [ "$SINGLE_ACCOUNT" != 1 ]; then
    hive_usage_backfill
    for peer in $(hive_peers); do
      grep -qx "beacon-$peer" "$SEEN" && continue
      hive_beacon "$peer"   # newest USAGE message from the peer
      if [ "$b_age" -lt $(( BEACON_FRESH_HOURS * 3600 )) ]; then
        echo "beacon-$peer" >> "$SEEN"; echo "PEER_BEACON $peer fresh at $b_at"; exit 0
      fi
    done
    if hive_is_triagemaster && [ -n "$issues" ]; then
      d=$(hive_dev_idle_check "$issues" "$pr_tickets" "$cr_busy") && { echo "$d"; exit 0; }
    fi
  fi
  # hourly productivity check: fewer active work packages than this mode's minimum -> wake Claude to start more
  last=$(cat "$HIVE_STATE/.slots-last" 2>/dev/null || echo 0)
  if [ $(( $(date +%s) - last )) -ge 3600 ]; then
    date +%s > "$HIVE_STATE/.slots-last"
    min=$(hive_worker_target)
    active=$(hive_active_packages)
    # plus tickets of mine in flight outside Atlas: open, assigned to me, a branch or open PR on it
    if [ -n "$issues" ]; then
      for n in $(echo "$issues" | jq -r --arg me "$HIVE_ACCOUNT" '.[] | select(.pull_request==null) | select(any(.assignees[]; .login==$me)) | .number'); do
        hive_ticket_in_progress "$n" "$pr_tickets" && active=$((active+1))
      done
    fi
    # ticket-maker off (rule 11): fewer workers is expected, so wake only if a ready ticket I could start exists
    startable=1
    if [ "$active" -lt "$min" ] && [ -n "$issues" ] && [ "$(ticketmaker)" = off ]; then
      startable=0
      for n in $(echo "$issues" | jq -r --arg me "$HIVE_ACCOUNT" '.[] | select(.pull_request==null) | select(any(.labels[]; .name=="ready-for-agent")) | select((.assignees|length)==0 or any(.assignees[]; .login==$me)) | "\(.number)|\(any(.labels[]; .name=="conflict-risk"))"'); do
        cr=${n#*|}; n=${n%%|*}
        [ "$cr" = true ] && [ "$cr_busy" = 1 ] && continue   # held by rule 6, not startable
        hive_ticket_in_progress "$n" "$pr_tickets" || { startable=1; break; }
      done
    fi
    if [ "$active" -lt "$min" ] && [ "$startable" = 1 ]; then echo "IDLE_SLOTS $active/$min active work packages"; exit 0; fi
    # peers' queues (no refill while the ticket-maker is off, rule 11; meta and skip tickets excluded)
    if [ -n "$issues" ] && [ "$SINGLE_ACCOUNT" != 1 ] && hive_is_triagemaster && hive_budget_ok && [ "$(ticketmaker)" = on ]; then
      for peer in $(hive_peers); do
        aq=$(echo "$issues" | jq --arg p "$peer" --arg m "$SKIP_NUMS" '[.[] | select(.pull_request==null and (.number|IN($m|split(" ")|map(select(length>0)|tonumber)[])|not)) | select(any(.assignees[]; .login==$p)) | select(any(.labels[]; .name=="ready-for-agent"))] | length' 2>/dev/null || echo 99)
        [ "${aq:-99}" -lt "$PEER_QUEUE_MIN" ] && { echo "PEER_QUEUE_LOW $aq $peer"; exit 0; }
      done
    fi
  fi
  # idle in short ticks so a channel message (hive-msg.sh listen -> msg-wake.txt) wakes us within HIVE_TICK seconds
  step=${HIVE_TICK:-10}; ticks=$(( ${WATCH_INTERVAL:-600} / step )); [ "$ticks" -ge 1 ] || ticks=1
  tick=0
  while [ "$tick" -lt "$ticks" ]; do
    sleep "$step"; tick=$((tick+1))
    : > "$HIVE_STATE/.triage-watch-alive"
    # new = wake file modified since the last one handled (so an identical repeat message still wakes)
    wm=$(hive_mtime "$HIVE_STATE/msg-wake.txt")
    if [ -n "$wm" ] && [ -s "$HIVE_STATE/msg-wake.txt" ] && [ "$wm" != "$(cat "$HIVE_STATE/.msg-wake-handled" 2>/dev/null)" ]; then
      echo "$wm" > "$HIVE_STATE/.msg-wake-handled"; head -n 1 "$HIVE_STATE/msg-wake.txt"; exit 0
    fi
    [ "${DISCORD:-0}" = 1 ] && [ "$PRIVATE" != 1 ] && [ "$SINGLE_ACCOUNT" != 1 ] || continue
    # dev-channel failover (rule 21): every minute, on every machine that is not the triagemaster
    if [ $((tick % 6)) = 3 ] && ! hive_is_triagemaster; then
      hv=$(bash "$HIVE_DIR/hive-failover.sh" check 2>/dev/null) && { echo "$hv"; exit 0; }
    fi
    # Discord channels (rule 18): once a minute, triagemaster only, once the bot token is set up
    if [ $((tick % 6)) = 0 ] && discord_on && hive_is_triagemaster; then
      n=$(bash "$HIVE_DIR/hive-discord-bugs.sh" check 2>"$HIVE_STATE/discord-check.err"); rc=$?
      [ "$rc" = 0 ] && { echo "DISCORD_BUG $n new in #$DISCORD_BUGS_NAME"; exit 0; }
      [ -n "${DISCORD_DEV_CHANNEL:-}" ] && n=$(bash "$HIVE_DIR/hive-discord-bugs.sh" --dev check 2>/dev/null) && { echo "DISCORD_DEV $n new in #$DISCORD_DEV_NAME"; exit 0; }
      if [ $((tick % 30)) = 0 ]; then
        a=$(bash "$HIVE_DIR/hive-discord-bugs.sh" approvals 2>/dev/null | head -n 1)
        [ -n "$a" ] && { echo "DISCORD_APPROVED $a"; exit 0; }
      fi
      if [ "$rc" = 2 ]; then   # Discord unreadable: wake after 10 failed checks in a row, then at most hourly
        f=$(( $(cat "$HIVE_STATE/.discord-fails" 2>/dev/null || echo 0) + 1 )); echo "$f" > "$HIVE_STATE/.discord-fails"
        dl=$(cat "$HIVE_STATE/.discord-fail-woke" 2>/dev/null || echo 0)
        if [ "$f" -ge 10 ] && [ $(( $(date +%s) - dl )) -ge 3600 ]; then
          date +%s > "$HIVE_STATE/.discord-fail-woke"
          echo "TM_CHECK_FAIL Discord #$DISCORD_BUGS_NAME unreadable for 10 checks: $(head -c 160 "$HIVE_STATE/discord-check.err" | tr '\n' ' ') (run hive-tm-check.sh)"; exit 0
        fi
      else echo 0 > "$HIVE_STATE/.discord-fails"; fi
    fi
  done
done
