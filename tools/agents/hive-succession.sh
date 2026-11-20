#!/bin/bash
# Works out who holds the triagemaster role and writes it to $HIVE_STATE/triagemaster. Prints the holder.
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
  if [ "$fo_exp" -gt "$now" ]; then echo "$fo_who" > "$HIVE_STATE/triagemaster"; echo "$fo_who"; exit 0; fi
fi
# no fresh beacon from any other account (no channel, listener down and backfill failed): make no decision
hive_channel_fresh || { hive_triagemaster; exit 0; }
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
