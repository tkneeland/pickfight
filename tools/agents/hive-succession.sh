#!/bin/bash
# Works out who holds the triagemaster role and writes it to $HIVE_STATE/triagemaster. Prints the holder.
# With the hub's studio file (STUDIO_REPO, hive/accounts-active.conf cached by hive_studio_sync): the first account in its
# order that is in and viable (hive_viable); see the studio block below. Without one, SUCCESSION_RANK as follows.
# The rank-1 holder keeps the role until its weekly used >= HANDOFF_WEEKLY_USED with more than RESET_GRACE_HOURS until its
# reset, or >= HANDOFF_HARD_WEEKLY_USED at any time; then the next SUCCESSION_RANK with a beacon under BEACON_FRESH_HOURS old
# and under HANDOFF_WEEKLY_USED holds it. The role returns on its own once the original holder's weekly resets.
# Beacons are the newest USAGE message per account in $HIVE_STATE/msg-inbox.log (hive_beacon), this account's own usage
# snapshot for itself; a missing or stale inbox is backfilled from the channel first. No GitHub calls.
# With --post, the stand-in itself sends "TM <handle> until <reset ISO>" on the private channel when it takes over.
# SINGLE_ACCOUNT (and PRIVATE) mode: this account always holds the role.
. "$(dirname "$0")/hive-env.sh" || exit 1
[ "$SINGLE_ACCOUNT" != 1 ] || { hive_triagemaster; exit 0; }
now=$(date +%s); fresh=$(( BEACON_FRESH_HOURS * 3600 ))
hive_usage_backfill
# A #hive failover (hive-failover.sh takeover) holds the role until it expires: the newest TM "<h> until failover <expiry>"
# in the inbox or this account's own takeover file ("<h> <expiry> <taken at>"), ordered by the takeover's own time.
# The newest wins; an expired or superseded local marker is removed, so a stale file never outvotes a later takeover.
fo=$( { awk -F'|' '$3=="TM" && $4 ~ /^[^ ]+ until failover [0-9]+/ {split($4, w, " "); print $1, w[1], w[4], "inbox"}' "$HIVE_INBOX" 2>/dev/null
        [ -f "$HIVE_STATE/takeover" ] && awk '{print ($3 ? $3 : 0), $1, $2, "local"}' "$HIVE_STATE/takeover"; } | sort -n | tail -n 1)
if [ -n "$fo" ]; then read -r fo_at fo_who fo_exp fo_src <<EOT
$fo
EOT
  if [ "$fo_src" = inbox ] || [ "$fo_exp" -le "$now" ]; then rm -f "$HIVE_STATE/takeover"; fi   # superseded by a newer TM, or expired
  # an account switched out in the hub never holds the role, takeover or not
  if [ "$fo_exp" -gt "$now" ] && ! hive_is_out "$fo_who"; then echo "$fo_who" > "$HIVE_STATE/triagemaster"; echo "$fo_who"; exit 0; fi
fi
# no fresh beacon from any other account (no channel, listener down and backfill failed): make no decision, except that a
# holder switched out in the hub hands the role to the top of the studio queue
if ! hive_channel_fresh; then
  cur=$(hive_triagemaster)
  if hive_is_out "$cur"; then t=$(hive_queue_top); [ -n "$t" ] && { cur=$t; echo "$cur" > "$HIVE_STATE/triagemaster"; }; fi
  echo "$cur"; exit 0
fi
post() { [ "$HIVE_ARG" = --post ] && [ -z "${HIVE_DRY_RUN:-}" ]; }; HIVE_ARG=${1:-}
# post_dev <text>: the dev channel (Discord, DISCORD=1 with a token and DISCORD_DEV_CHANNEL), else the owner's outbox
post_dev() {
  if [ "${DISCORD:-0}" = 1 ] && [ "$PRIVATE" != 1 ]; then
    . "$HIVE_DIR/hive-discord-env.sh"
    if [ -n "$HIVE_DISCORD_TOKEN" ] && [ -n "$HIVE_DISCORD_DEV" ]; then
      bash "${HIVE_DISCORD_SH:-$HIVE_DIR/hive-discord.sh}" post "$HIVE_DISCORD_DEV" "$1" >/dev/null 2>&1; return
    fi
  fi
  hive_outbox FIRE "$1"
}
# The studio queue (the hub's hive/accounts-active.conf, issue #58): the first account in the file's order that is in and
# viable (hive_viable: fresh beacon, not at its 5h stop or weekly handoff). The role passes down the list while the holder
# is not viable and returns to a higher account as soon as it is. Nobody in is viable: the in account whose stop lifts
# soonest (v_free) holds it, else the top of the queue, and the holder says so once in the dev channel.
if hive_studio_on && queue=$(hive_queue) && [ -n "$queue" ]; then
  holder=""; first=""; best=""; bestf=0
  for h in $queue; do
    [ -n "$first" ] || first=$h
    if hive_viable "$h"; then holder=$h; break; fi
    if [ "$v_free" -gt 0 ] && { [ -z "$best" ] || [ "$v_free" -lt "$bestf" ]; }; then best=$h; bestf=$v_free; fi
  done
  fallback=0; [ -n "$holder" ] || { fallback=1; holder=${best:-$first}; }
  prev=$(cat "$HIVE_STATE/triagemaster" 2>/dev/null)
  echo "$holder" > "$HIVE_STATE/triagemaster"
  # TM is a notice for the hub and peers (each machine works the role out itself): short-lived, since a higher account
  # may come back on any cycle
  if [ "$holder" != "$prev" ] && [ "$holder" != "$first" ] && [ "$holder" = "$HIVE_ACCOUNT" ] && post; then
    bash "$HIVE_DIR/hive-msg.sh" send TM "$holder until $(TZ=UTC hive_fmt $((now + 3600)) +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1
  fi
  if [ "$fallback" = 1 ]; then
    if [ "$holder" = "$HIVE_ACCOUNT" ] && [ "$(cat "$HIVE_STATE/.tm-fallback" 2>/dev/null)" != "$holder" ] && post; then
      when=""; [ "$bestf" -gt 0 ] && [ "$holder" = "$best" ] && when=" Its usage frees up first, at $(hive_tzfmt "$bestf" '+%a %H:%M') $HIVE_TZ_LABEL."
      post_dev "No account that is in can hold the triagemaster role right now (each is offline or at its 5h or weekly stop), so $(hive_display_name "$holder") holds it until one can.$when" &&
        echo "$holder" > "$HIVE_STATE/.tm-fallback"
    fi
  else rm -f "$HIVE_STATE/.tm-fallback"; fi
  echo "$holder"; exit 0
fi
# Without a studio file: SUCCESSION_RANK
order=$(for h in $(hive_handles); do r=$(hive_rank_of "$h"); echo "${r:-9} $h"; done | sort -n | awk '{print $2}')
first=$(echo "$order" | head -n 1)
hive_beacon "$first"; holder=$first; reset0=$b_reset
if [ "$b_age" -lt "$fresh" ] && [ -n "$b_used" ] && { [ "$b_used" -ge "$HANDOFF_HARD_WEEKLY_USED" ] || { [ "$b_used" -ge "$HANDOFF_WEEKLY_USED" ] && [ $(( $(hive_iso2epoch "$b_reset") - now )) -gt $(( RESET_GRACE_HOURS * 3600 )) ]; }; }; then
  for h in $(echo "$order" | tail -n +2); do
    hive_beacon "$h"
    if [ "$b_age" -lt "$fresh" ] && [ -n "$b_used" ] && [ "$b_used" -lt "$HANDOFF_WEEKLY_USED" ]; then holder=$h; break; fi
  done
fi
prev=$(cat "$HIVE_STATE/triagemaster" 2>/dev/null)
echo "$holder" > "$HIVE_STATE/triagemaster"
if [ "$holder" != "$prev" ] && [ "$holder" != "$first" ] && [ "$holder" = "$HIVE_ACCOUNT" ] && [ "${1:-}" = "--post" ] && [ -z "${HIVE_DRY_RUN:-}" ]; then
  bash "$HIVE_DIR/hive-msg.sh" send TM "$holder until $reset0" >/dev/null 2>&1
fi
echo "$holder"
