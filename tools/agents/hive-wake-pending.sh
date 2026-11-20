#!/bin/bash
# Usage: hive-wake-pending.sh
# Zero-token wake check for headless sessions (claude -p), which nobody can type MSG/TRIAGE wakes into (issue #398).
# Prints what is new since the last call and exits 0; prints nothing and exits 1 when there is nothing. Advances its cursors.
#   triage-wake.txt  the watcher rewrites it on every wake: printed whenever its content differs from the last one seen
#   msg-inbox.log    `epoch|handle|TYPE|text`, read from a byte offset (reset to 0 when the file shrank: rotated or truncated);
#                    only ASK/ANSWER/INFO lines that mention @<this account>, or TM/triagemaster when this account is the triagemaster, and not
#                    sent by this account. With no cursor yet, only lines from the last 30 min (no replay of old history).
# Cursors: $HIVE_STATE/wake-pending.seen (wake text) and wake-pending.offset (inbox bytes).
. "$(dirname "$0")/hive-env.sh" || exit 1
wake=$HIVE_STATE/triage-wake.txt; inbox=$HIVE_STATE/msg-inbox.log
seen=$HIVE_STATE/wake-pending.seen; offf=$HIVE_STATE/wake-pending.offset
out=""

if [ -s "$wake" ]; then
  w=$(tr -d '\r' < "$wake" | sed 's/[[:space:]]*$//')
  s=""; [ -f "$seen" ] && s=$(cat "$seen")
  if [ "$w" != "$s" ]; then out="TRIAGE $w"; printf '%s\n' "$w" > "$seen"; fi
fi

if [ -f "$inbox" ]; then
  size=$(wc -c < "$inbox" | tr -d ' ')
  fresh=0; [ -f "$offf" ] || fresh=1
  off=$(cat "$offf" 2>/dev/null); case $off in ''|*[!0-9]*) off=0; fresh=1;; esac
  [ "$off" -le "$size" ] || off=0
  re="@$HIVE_ACCOUNT([^A-Za-z0-9_-]|\$)"
  hive_is_triagemaster && re="$re|(^|[^A-Za-z0-9])(TM|triagemaster)([^A-Za-z0-9]|\$)"
  now=$(date +%s)
  new=$(tail -c +"$((off + 1))" "$inbox" | tr -d '\r' | awk -F'|' -v me="$HIVE_ACCOUNT" -v re="$re" -v fresh="$fresh" -v now="$now" '
    $3 ~ /^(ASK|ANSWER|INFO)$/ && $2 != me {
      if (fresh && $1 + 0 < now - 1800) next
      t = $0; sub(/^[^|]*\|[^|]*\|[^|]*\|/, "", t)
      if (tolower(t) ~ tolower(re)) print }')
  echo "$size" > "$offf"
  if [ -n "$new" ]; then out=${out:+$out$'\n'}"MSG $new"; fi
fi

[ -n "$out" ] || exit 1
printf '%s\n' "$out"
