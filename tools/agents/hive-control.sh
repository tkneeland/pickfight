#!/bin/bash
# The hub's buttons land here (docs/hub/voice-protocol.md, "Controls"). Zero Claude tokens: hive-voice.mjs runs it for a
# `control` frame from the hub, in the checkout of the project the button was pressed for, with HIVE_ACCOUNT set.
#   hive-control.sh state                 print the current state
#   hive-control.sh ticketmaker on|off    hive-ticketmaker.sh on|off
# Only these verbs and values run; anything else exits 2 and changes nothing. The scripts stay the single source of truth.
# (AT/MT is not a hub button: whether an account works on its own is the studio's in/out switch.)
# On success it prints one JSON line {"ticketmaker":"on|off"} and, after a change, sends a fresh USAGE beacon
# in the background so every hub tab and peer sees the new state within seconds.
. "$(dirname "$0")/hive-env.sh" || exit 1
case "${1:-} ${2:-}" in
  "state ") ;;
  "ticketmaker on"|"ticketmaker off") bash "$HIVE_DIR/hive-ticketmaker.sh" "$2" >/dev/null || exit 1 ;;
  *) echo "usage: hive-control.sh state | ticketmaker on|off" >&2; exit 2 ;;
esac
jq -cn --arg t "$(bash "$HIVE_DIR/hive-ticketmaker.sh")" '{ticketmaker:$t}'
[ "${1:-}" != state ] && [ "${HIVE_CONTROL_NOBEACON:-}" != 1 ] && { nohup bash "$HIVE_DIR/hive-beacon.sh" >/dev/null 2>&1 & }
exit 0
