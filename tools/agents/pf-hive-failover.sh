#!/bin/bash
# #hive failover (autotriage.md rule 21), zero tokens. When a dev's message in #hive has had no answer for 10 minutes,
# the next live account in succession order takes the triagemaster role. Machines never talk to each other here:
# every decision comes from #hive itself plus this machine's inbox (pf-msg.sh), so all machines reach the same answer.
#   pf-hive-failover.sh check            one pass. Exit 0 and print "HIVE_TAKEOVER <msg id>" when THIS account must take
#                                        over; 1 nothing to do (or this account is the holder, or not the successor);
#                                        2 not set up or Discord unreadable (no pf-discord.conf: asks the owner once per 6h)
#   pf-hive-failover.sh takeover <id>    the woken agent runs it; re-checks the clock and that it is the successor first (exit 3 if not): posts "taking over from <holder> (now <me>)" as a reply
#                                        to <id>, keeps the claim only if that notice is the earliest of the notices posted
#                                        meanwhile (a rival's earlier one wins and ours is deleted: exit 3), then records
#                                        this account as triagemaster and sends TM on the private channel. The agent then
#                                        answers with pf-discord-bugs.sh --dev reply <id> "<text>".
# Rules: a message is ANSWERED by any bot reply that is not a takeover notice (an ack with no reply does not count: in
# #hive always reply). A notice restarts the 10 minute clock and names the new holder, so a taker that dies is failed
# over in turn. Holder = the newest notice's "(now X)", else this machine's pf-triagemaster file. Successor = the first
# live account after the holder by SUCCESSION_RANK, wrapping to the lowest. Live = a HELLO or USAGE from it in
# msg-inbox.log under PF_HIVE_LIVE_SECS (3600); this account always counts as live.
# Env (tests): PF_NOW epoch override, PF_HIVE_FAILOVER_SECS (600), PF_HIVE_LIVE_SECS (3600), PF_ACCOUNTS_DIR.
. "$(dirname "$0")/pf-env.sh" || exit 1
. "$(dirname "$0")/pf-discord-env.sh"
now() { echo "${PF_NOW:-$(date -u +%s)}"; }
SECS=${PF_HIVE_FAILOVER_SECS:-600}; LIVE=${PF_HIVE_LIVE_SECS:-3600}; ACC=${PF_ACCOUNTS_DIR:-$PF_DIR/accounts}
INBOX=$PF_STATE/msg-inbox.log; NOTICE='taking over from '
# epoch seconds a Discord snowflake id was created (64-bit shell arithmetic; no jq numbers, they lose precision)
snow() { echo $(( ( ($1 >> 22) + 1420070400000 ) / 1000 )); }
rank_of() { sed -n 's/^SUCCESSION_RANK=\([0-9]*\).*/\1/p' "$ACC/$1.conf" 2>/dev/null | head -n 1; }
live() {  # live <account>
  [ "$1" = "$PF_ACCOUNT" ] && return 0
  awk -F'|' -v a="$1" -v n="$(now)" -v w="$LIVE" '$2==a && ($3=="HELLO" || $3=="USAGE") && n-$1<w {f=1} END {exit !f}' "$INBOX" 2>/dev/null
}
successor() {  # successor <holder>: the next live account by rank after it (wraps), never the holder itself
  local hr h r order first=""
  hr=$(rank_of "$1"); hr=${hr:-0}
  order=$(for f in "$ACC"/*.conf; do h=$(basename "$f" .conf)
    [ "${h#_}" = "$h" ] || continue
    r=$(rank_of "$h"); [ -n "$r" ] && echo "$r $h"; done | sort -n | awk '{print $2}')
  for h in $order; do [ "$h" = "$1" ] && continue
    [ "$(rank_of "$h")" -gt "$hr" ] && live "$h" && { echo "$h"; return; }; done
  for h in $order; do [ "$h" = "$1" ] && continue
    [ "$(rank_of "$h")" -lt "$hr" ] && live "$h" && { echo "$h"; return; }; done
}
fetch() {  # the newest 50 messages of #hive as a JSON array; fails when Discord does
  local p; p=$(dcurl "/channels/$PF_DISCORD_DEV/messages?limit=50") || return 2
  echo "$p" | jq -e 'type == "array"' >/dev/null 2>&1 || { echo "pf-hive-failover: Discord said $(echo "$p" | head -c 160)" >&2; return 2; }
  echo "$p"
}
# unanswered <messages json>: "<id> <newest notice id or -> <its new holder or ->" per human message with no real answer, oldest first
unanswered() {
  echo "$1" | jq -r --arg n "$NOTICE" '
    sort_by(.id | [length, .]) as $all
    | $all[] | select(.author.bot != true and (.type // 0 | IN(0, 19)) and ((.content // "") != "")) | .id as $id
    | [$all[] | select(.author.bot == true and .message_reference.message_id == $id)] as $r
    | select(([$r[] | select(.content | startswith($n) | not)] | length) == 0)
    | ([$r[] | select(.content | startswith($n))] | last) as $t
    | "\($id) \($t.id // "-") \($t.content // "" | capture("\\(now (?<w>[^)]+)\\)").w // "-")"'
}
# due <id> <notice id or -> <new holder or ->: 0 when the 10 min clock has run out (from the newest notice, if any), the
# message is under 24h old, this account is not the holder and it is the designated successor. Sets H (the holder).
due() {
  local t0; t0=$(snow "$1"); [ "$2" != - ] && t0=$(snow "$2")
  [ $(( $(now) - t0 )) -ge "$SECS" ] || return 1
  [ $(( $(now) - $(snow "$1") )) -le 86400 ] || return 1
  H=$(holder_for "$3"); [ "$H" = "$PF_ACCOUNT" ] && return 1
  [ "$(successor "$H")" = "$PF_ACCOUNT" ]
}
holder_for() { [ "${1:--}" != - ] && echo "$1" || pf_triagemaster; }
case "${1:-}" in
  check)
    if [ -z "$PF_DISCORD_TOKEN" ]; then   # not set up: ask the owner once per 6h, never fail silently
      s=$(pf_mtime "$PF_STATE/.hive-noconf-asked" || true); s=${s:-0}
      if [ $(( $(date +%s) - s )) -ge 21600 ]; then
        bash "$PF_DIR/pf-msg.sh" send ASK "$PF_ACCOUNT has no pf-discord.conf, so it cannot watch #hive for failover (rule 21). Owner: share the bot token over the private channel; it goes in \$PF_STATE/pf-discord.conf, never in git." >/dev/null 2>&1
        touch "$PF_STATE/.hive-noconf-asked"
      fi
      exit 2
    fi
    msgs=$(fetch) || exit 2
    unanswered "$msgs" | while read -r id nid nowh; do
      due "$id" "$nid" "$nowh" || continue
      # debounce: a wake for this message and this notice is not repeated for 5 min (the agent may be mid-takeover)
      st=$PF_STATE/.hive-failover-$id-$nid; w=$(pf_mtime "$st" || true); w=${w:-0}
      [ $(( $(date +%s) - w )) -lt 300 ] && continue
      touch "$st"; echo "HIVE_TAKEOVER $id"; exit 10
    done
    [ $? = 10 ] && exit 0; exit 1 ;;
  takeover)
    id=${2:-}; case $id in ""|*[!0-9]*) echo "usage: pf-hive-failover.sh takeover <message id>" >&2; exit 2;; esac
    pf_discord_need_token pf-hive-failover
    msgs=$(fetch) || exit 2
    line=$(unanswered "$msgs" | awk -v i="$id" '$1==i') || true
    [ -n "$line" ] || { echo "message $id is already answered (or not in #hive)"; exit 3; }
    read -r _ nid nowh <<EOT
$line
EOT
    # re-check right before acting, on fresh data: a stale wake, an earlier takeover (its notice restarts the clock) or
    # a different successor all mean another machine owns this one
    if ! due "$id" "$nid" "$nowh"; then
      [ "$H" = "$PF_ACCOUNT" ] && { echo "already the holder"; exit 0; }
      echo "not due, or not the successor: another machine owns message $id"; exit 3
    fi
    h=$H
    before=$(echo "$msgs" | jq -r --arg i "$id" '[.[] | select(.message_reference.message_id == $i) | .id] | join(" ")')
    body=$(jq -n --arg t "${NOTICE}${h} (now ${PF_ACCOUNT})" --arg id "$id" '{content: $t, message_reference: {message_id: $id}, allowed_mentions: {parse: []}}')
    mine=$(dcurl "/channels/$PF_DISCORD_DEV/messages" -X POST -H "Content-Type: application/json" -d "$body" | jq -r '.id // empty')
    after=$(fetch) || exit 2
    # a post that timed out may still have landed: find our own new notice instead of posting a second one
    [ -n "$mine" ] || mine=$(echo "$after" | jq -r --arg i "$id" --arg t "(now ${PF_ACCOUNT})" --arg n "$NOTICE" --arg b " $before " '
      [.[] | .id as $mid | select(.message_reference.message_id == $i and (.content | startswith($n)) and (.content | endswith($t)) and ($b | contains(" " + $mid + " ") | not)) | .id]
      | sort_by([length, .]) | first // empty')
    [ -n "$mine" ] || { echo "pf-hive-failover: could not post the notice" >&2; exit 2; }
    # the earliest notice posted since we looked wins; a later one yields (deleting its own message is best effort)
    win=$(echo "$after" | jq -r --arg i "$id" --arg n "$NOTICE" --arg b " $before " '
      [.[] | .id as $mid | select(.message_reference.message_id == $i and (.content | startswith($n)) and ($b | contains(" " + $mid + " ") | not)) | .id]
      | sort_by([length, .]) | first // empty')
    if [ "$win" != "$mine" ]; then
      dcurl "/channels/$PF_DISCORD_DEV/messages/$mine" -X DELETE >/dev/null 2>&1
      echo "another machine took over first (notice $win)"; exit 3
    fi
    # take the role the way pf-succession.sh reads it: a TM "<me> until failover <expiry>" on the private channel (and a
    # local copy), honoured by pf-succession.sh on every machine until it expires
    exp=$(( $(now) + ${PF_HIVE_TAKEOVER_SECS:-21600} ))
    echo "$PF_ACCOUNT $exp $(now)" > "$PF_STATE/pf-takeover"; echo "$PF_ACCOUNT" > "$PF_STATE/pf-triagemaster"
    bash "$PF_DIR/pf-msg.sh" send TM "$PF_ACCOUNT until failover $exp (from $h, #hive $id)" >/dev/null 2>&1
    echo "TAKEOVER_OK from $h"; exit 0 ;;
  *) echo "usage: pf-hive-failover.sh check|takeover <message id>" >&2; exit 2 ;;
esac
