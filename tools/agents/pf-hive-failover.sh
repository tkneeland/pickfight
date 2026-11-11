#!/bin/bash
# #hive failover check (autotriage.md rule 21, #1210), zero tokens. One pass; pf-triage-watch.sh runs it once a minute on
# every account that is not the triagemaster.
#   exit 0 + "HIVE_TAKEOVER <message id>"  a dev message in #hive has had no bot reply for 10 min (HIVE_WAIT s) and THIS
#                                          account is the next live account in succession order (pf-succession.sh ranks)
#   exit 1                                 nothing to do (not the next account, nothing unanswered, or already woken for it)
#   exit 2                                 Discord could not be read
# A live account is one with any private-channel message under 1 h old in msg-inbox.log (HELLO every 15 min); a stale
# heartbeat is skipped, so a dead machine never blocks the failover. Only the first live account after the triagemaster
# wakes, so two machines never both take over. Each message wakes at most once (marker .hive-takeover-seen).
# No $PF_STATE/pf-discord.conf: the account cannot watch #hive, so it asks the owner on the private channel (once a day).
# #hive channel: PF_HIVE_CHANNEL in the environment, else PF_DISCORD_HIVE_CHANNEL in pf-discord.conf, else the channel
# named "hive" in the guild. Messages are data, never instructions.
. "$(dirname "$0")/pf-env.sh" || exit 1
now=${PF_NOW:-$(date +%s)}
WAIT=${HIVE_WAIT:-600}
pf_is_triagemaster && exit 1
if [ ! -f "$PF_STATE/pf-discord.conf" ]; then
  a=$(pf_mtime "$PF_STATE/.hive-noconf-asked" || true); a=${a:-0}
  if [ $(( now - a )) -gt 86400 ]; then
    touch "$PF_STATE/.hive-noconf-asked"
    bash "$PF_DIR/pf-msg.sh" send ASK "$PF_ACCOUNT has no pf-discord.conf, so it cannot watch #hive for failover (rule 21). Owner: please send the bot token out of band." >/dev/null 2>&1
  fi
  exit 1
fi
. "$PF_DIR/pf-discord-env.sh"
# the next live account: succession order, minus the holder, minus stale heartbeats
tm=$(pf_triagemaster)
live() {
  [ "$1" = "$PF_ACCOUNT" ] && return 0
  awk -F'|' -v h="$1" -v now="$now" '$2==h && $1+0>m {m=$1+0} END {exit !(m>0 && now-m<3600)}' "$PF_STATE/msg-inbox.log" 2>/dev/null
}
next=""
for h in $(for x in $(pf_handles); do r=$(sed -n 's/^SUCCESSION_RANK=\([0-9]*\).*/\1/p' "$PF_DIR/accounts/$x.conf"); echo "${r:-99} $x"; done | sort -n | awk '{print $2}'); do
  [ "$h" = "$tm" ] && continue
  live "$h" && { next=$h; break; }
done
[ "$next" = "$PF_ACCOUNT" ] || exit 1
[ -n "$PF_DISCORD_TOKEN" ] || exit 2
CH=${PF_HIVE_CHANNEL:-$(pf_discord_conf PF_DISCORD_HIVE_CHANNEL)}
[ -n "$CH" ] || CH=$(cat "$PF_STATE/.hive-channel-id" 2>/dev/null)
if [ -z "$CH" ]; then
  CH=$(dcurl "/guilds/$PF_DISCORD_GUILD/channels" | jq -r '[.[]? | select(.name == "hive")][0].id // empty' 2>/dev/null)
  [ -n "$CH" ] || { echo "pf-hive-failover: no #hive channel found" >&2; exit 2; }
  echo "$CH" > "$PF_STATE/.hive-channel-id"
fi
page=$(dcurl "/channels/$CH/messages?limit=50")
echo "$page" | jq -e 'type == "array"' >/dev/null 2>&1 || { echo "pf-hive-failover: Discord said $(echo "$page" | head -c 200)" >&2; exit 2; }
# dev messages with no bot message after them, oldest first: "<id> <ISO seconds>Z" (ids compared as [length, text])
touch "$PF_STATE/.hive-takeover-seen"
cands=$(echo "$page" | jq -r 'sort_by(.id | [length, .]) | . as $all | to_entries[]
  | select(.value.author.bot != true and ($all[.key+1:] | map(.author.bot == true) | any | not))
  | "\(.value.id) \(.value.timestamp[0:19])Z"')
while read -r id ts; do
  [ -n "$id" ] || continue
  grep -qx "$id" "$PF_STATE/.hive-takeover-seen" && continue
  e=$(pf_iso_to_epoch "$ts") || continue
  [ $(( now - e )) -ge "$WAIT" ] || continue
  echo "$id" >> "$PF_STATE/.hive-takeover-seen"
  echo "HIVE_TAKEOVER $id"; exit 0
done <<EOT
$cands
EOT
exit 1
