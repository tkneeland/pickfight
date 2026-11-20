#!/bin/bash
# Main terminal: blocks until the AT session appends to the outbox, prints the new lines, exits (zero tokens).
# Run it in the background from the control-panel session and act on what it prints; restart it after each wake.
. "$(dirname "$0")/hive-env.sh" || exit 1
f=$HIVE_OUTBOX; seen=$HIVE_STATE/outbox.seen; touch "$f"
n=$(cat "$seen" 2>/dev/null || wc -l < "$f"); n=${n// /}
while [ "$(wc -l < "$f" | tr -d ' ')" -le "$n" ]; do sleep 20; done
sleep 5; tail -n +$((n+1)) "$f"; wc -l < "$f" | tr -d ' ' > "$seen"
