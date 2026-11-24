#!/bin/bash
# The hub's control frames land here (docs/hub/voice-protocol.md, "Controls"). Zero Claude tokens: hive-voice.mjs runs it for a
# `control` frame from the hub, in the checkout of the project the frame was sent for, with HIVE_ACCOUNT set.
#   hive-control.sh state                 print the current state
# Only this verb runs; anything else exits 2 and changes nothing. The ticket-maker mode is no longer a control: the hub writes
# it to the studio's hive/ticket-maker.conf (hive_tm_mode). AT/MT is not one either: it is the studio's in/out switch.
# It prints one JSON line {"ticketmaker":"full|suggestions|off"}.
. "$(dirname "$0")/hive-env.sh" || exit 1
case "${1:-} ${2:-}" in
  "state ") ;;
  *) echo "usage: hive-control.sh state" >&2; exit 2 ;;
esac
hive_tm_mode
jq -cn --arg t "$tm_mode" '{ticketmaker:$t}'
