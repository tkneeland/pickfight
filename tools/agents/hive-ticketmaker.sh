#!/bin/bash
# Ticket-maker switch. Mode file: $HIVE_STATE/ticketmaker (on|off, default on).
#   hive-ticketmaker.sh          print on|off
#   hive-ticketmaker.sh on|off   set it
# Off: the ticket-maker (the triagemaster's own idea and bug hunting, docs/agents/hive.md rule 11) does not run. Tickets come
# only from owner and user bug reports, [REVIEW-BUG]s and CI/main-red evidence; triage, workers, review and merging carry on.
# The triagemaster mirrors a change to the other accounts with a TM line on the channel (hive-succession.sh --post).
. "$(dirname "$0")/hive-env.sh" || exit 1
f="$HIVE_STATE/ticketmaker"
case "${1:-}" in
  on|off) echo "$1" > "$f"; echo "$1" ;;
  "") m=$(cat "$f" 2>/dev/null); echo "${m:-on}" ;;
  *) echo "usage: hive-ticketmaker.sh [on|off]" >&2; exit 2 ;;
esac
