#!/bin/bash
# Prints the AT state: "AT·on pace", "AT·ahead" (the pace governor says AHEAD: start no new workers), "AT·behind" (BEHIND:
# start another, up to the max; hive-pace.sh via hive_pace_now in hive-env.sh) or "MT".
# Appends "·TM off" while the ticket-maker switch (hive-ticketmaker.sh) is off.
# MT comes from the hub: an account switched out in the studio's hive/accounts-active.conf (hive_mt, issue #58). The local
# at-mode file is retired there. A game without a studio file keeps it ($HIVE_STATE/at-mode, AT|MT, default AT):
#   hive-at-mode.sh              print the state
#   hive-at-mode.sh AT|MT        switch mode (no studio file only; with one, switch the account in or out in the hub)
. "$(dirname "$0")/hive-env.sh" || exit 1
case "${1:-}" in
  AT|MT)
    if hive_studio_on; then echo "hive-at-mode: AT/MT is the hub's in/out switch for this studio (members tab); not changed here" >&2; exit 2; fi
    echo "$1" > "$HIVE_STATE/at-mode"; echo "$1"; exit;;
esac
rm -f "$HIVE_STATE/day-until"   # left by the removed day override
hive_mt && { echo MT; exit; }
hive_pace_now; case $p_state in AHEAD) p=ahead;; BEHIND) p=behind;; *) p="on pace";; esac
echo "AT·$p$([ "$(bash "$HIVE_DIR/hive-ticketmaker.sh")" = off ] && echo "·TM off")"
