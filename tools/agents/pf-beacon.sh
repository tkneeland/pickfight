#!/bin/bash
# Sends this account's usage beacon once, in the foreground: a USAGE message on the private channel (pf-msg.sh), the only
# usage beacon (#1153; the old issue comments are retired). Built from $PF_STATE/usage-snapshot.json (saved by
# statusline-usage.sh or pf-usage.sh). Format: "<5h>% <7d>% <7d reset ISO> r5=<5h reset ISO> agents=<n> at=<snapshot ISO> [claude_at=<ISO>]".
# claude_at (#1233) = newest Claude transcript write on this account (pf_claude_at), omitted when unknown; the triagemaster
# wakes DEV_IDLE when it is old while work waits.
# Errors go to $PF_STATE/beacon.log; exit 1 when nothing was sent.
# --throttle: exit 3 without sending when $PF_STATE/.beacon-stamp is under 15 min old, so every sender shares one 15-minute
# clock and the channel stays under ntfy's 250 messages/day (#1263). A send claims that stamp before its slow steps (as the
# status line does), so two senders cannot both pass the check; a failed send waits for the next 15-min slot.
# Run by statusline-usage.sh every 15 min, pf-usage.sh, and `windows/pf-supervise.sh beacon --throttle`, which outlives the status line.
. "$(dirname "$0")/pf-env.sh" || exit 1
log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >> "$PF_STATE/beacon.log"; }
stamp=$PF_STATE/.beacon-stamp
if [ "${1:-}" = --throttle ] && [ -f "$stamp" ] && [ $(( $(date +%s) - $(pf_mtime "$stamp" || echo 0) )) -lt 900 ]; then exit 3; fi
snap=$PF_STATE/usage-snapshot.json
[ -s "$snap" ] || { log "no usage snapshot yet (status line not run?)"; exit 1; }
[ -f "$PF_STATE/pf-msg.conf" ] || { log "no channel configured (pf-msg.sh init); USAGE not sent"; exit 1; }
touch "$stamp"   # claim this 15-min slot before the slow steps (pf_live_agents, the send)
# Stamp the beacon with when the snapshot was taken, not now: if the status line stops running, the
# beacon must look stale instead of republishing old numbers as fresh.
sat=$(pf_mtime "$snap")
# running worker agents = live worktrees on an issue branch (pf_live_agents; the status line counts them the same way)
agents=$(pf_live_agents | wc -l | tr -d " ")
msg=$(jq -r --arg ag "${agents:-0}" --argjson sat "${sat:-0}" '"\(.rate_limits.five_hour.used_percentage // 0|floor)% \(.rate_limits.seven_day.used_percentage // 0|floor)% \(.rate_limits.seven_day.resets_at // 0|floor|todate) r5=\(.rate_limits.five_hour.resets_at // 0|floor|todate) agents=\($ag) at=\($sat|todate)"' "$snap") \
  || { log "bad snapshot"; exit 1; }
ca=$(pf_claude_at)
[ -n "$ca" ] && msg="$msg claude_at=$(TZ=UTC pf_epoch_fmt "$ca" +%Y-%m-%dT%H:%M:%SZ)"
err=$(bash "$PF_DIR/pf-msg.sh" send USAGE "$msg" 2>&1 >/dev/null) || { log "USAGE send failed${err:+: ${err#pf-msg: }}"; exit 1; }
