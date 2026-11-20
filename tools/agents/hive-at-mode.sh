#!/bin/bash
# Prints the AT state: "AT·on pace", "AT·ahead" (weekly use ahead of pace, so one worker; hive_pace in hive-env.sh) or "MT".
# Mode file: $HIVE_STATE/at-mode (AT|MT, default AT). Appends "·TM off" while the ticket-maker switch (hive-ticketmaker.sh) is off.
#   hive-at-mode.sh              print the state
#   hive-at-mode.sh AT|MT        switch mode
. "$(dirname "$0")/hive-env.sh" || exit 1
case "${1:-}" in
  AT|MT) echo "$1" > "$HIVE_STATE/at-mode"; echo "$1"; exit;;
esac
rm -f "$HIVE_STATE/day-until"   # left by the removed day override
m=$(cat "$HIVE_STATE/at-mode" 2>/dev/null || echo AT); [ "$m" = MT ] && { echo MT; exit; }
echo "AT·$(hive_pace)$([ "$(bash "$HIVE_DIR/hive-ticketmaker.sh")" = off ] && echo "·TM off")"
