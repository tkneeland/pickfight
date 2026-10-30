#!/bin/bash
# Sends this account's usage beacon once, in the foreground: a USAGE message on the private channel (pf-msg.sh), the only
# usage beacon (#1153; the old issue comments are retired). Built from $PF_STATE/usage-snapshot.json (saved by
# statusline-usage.sh or pf-usage.sh). Format: "<5h>% <7d>% <7d reset ISO> r5=<5h reset ISO> agents=<n> at=<snapshot ISO>".
# Errors go to $PF_STATE/beacon.log; exit 1 when nothing was sent.
# Run by statusline-usage.sh every 15 min, pf-usage.sh, and `windows/pf-supervise.sh beacon`, which outlives the status line.
. "$(dirname "$0")/pf-env.sh" || exit 1
log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >> "$PF_STATE/beacon.log"; }
snap=$PF_STATE/usage-snapshot.json
[ -s "$snap" ] || { log "no usage snapshot yet (status line not run?)"; exit 1; }
# Stamp the beacon with when the snapshot was taken, not now: if the status line stops running, the
# beacon must look stale instead of republishing old numbers as fresh.
sat=$(pf_mtime "$snap")
# running worker agents = live worktrees on an issue branch (pf_live_agents; the status line counts them the same way)
agents=$(pf_live_agents | wc -l | tr -d " ")
msg=$(jq -r --arg ag "${agents:-0}" --argjson sat "${sat:-0}" '"\(.rate_limits.five_hour.used_percentage // 0|floor)% \(.rate_limits.seven_day.used_percentage // 0|floor)% \(.rate_limits.seven_day.resets_at // 0|floor|todate) r5=\(.rate_limits.five_hour.resets_at // 0|floor|todate) agents=\($ag) at=\($sat|todate)"' "$snap") \
  || { log "bad snapshot"; exit 1; }
[ -f "$PF_STATE/pf-msg.conf" ] || { log "no channel configured (pf-msg.sh init); USAGE not sent"; exit 1; }
bash "$PF_DIR/pf-msg.sh" send USAGE "$msg" >/dev/null 2>>"$PF_STATE/beacon.log" || { log "USAGE send failed"; exit 1; }
