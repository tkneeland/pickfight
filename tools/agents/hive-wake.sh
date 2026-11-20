#!/bin/bash
# Usage: hive-wake.sh [--ack]
# The triage wake line for a headless AT session, in plain bash (the Windows keepalive's claude -p session cannot run
# windows/hive-status.ps1: a nested PowerShell process is always refused, and nobody can approve it).
# Prints one line per supervisor (triage, automerge, beacon, msg: their *-status.json), then the wake line:
#   WAKE <line>      the watcher woke and the line is not handled yet (exit 10)
#   handled <line>   already acknowledged (exit 0)
#   no wake          the watcher has not woken yet (exit 0)
# --ack marks the current wake line handled (the same triage-wake.acked file hive-status.ps1 -Ack writes) and exits 0.
. "$(dirname "$0")/hive-env.sh" || exit 1
wake=$HIVE_STATE/triage-wake.txt; acked=$HIVE_STATE/triage-wake.acked
for k in triage automerge beacon msg; do
  f=$HIVE_STATE/$k-status.json
  [ -f "$f" ] && printf '%-10s %s\n' "$k" "$(jq -r '"\(.state) \(.line // "") at \(.at)"' "$f" 2>/dev/null)" || printf '%-10s %s\n' "$k" "no status"
done
if [ ! -s "$wake" ]; then echo "no wake"; exit 0; fi
w=$(tr -d '\r' < "$wake" | sed 's/[[:space:]]*$//')
if [ "${1:-}" = "--ack" ]; then printf '%s\n' "$w" > "$acked"; echo "acked $w"; exit 0; fi
a=$( [ -f "$acked" ] && tr -d '\r' < "$acked" | sed 's/[[:space:]]*$//')
if [ "$w" = "$a" ]; then echo "handled $w"; exit 0; fi
echo "WAKE $w"
exit 10
