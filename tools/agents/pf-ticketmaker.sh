#!/bin/bash
# Ticket-maker switch. Mode file: $PF_STATE/pf-ticketmaker (on|off, default on).
#   pf-ticketmaker.sh          print on|off
#   pf-ticketmaker.sh on|off   set it
# Off: the ticket-maker does not run. Tickets come only from owner/playtest bug reports, [REVIEW-BUG]s
# and CI/main-red evidence; triage, workers, review and merging carry on as normal (autotriage.md rule 11).
. "$(dirname "$0")/pf-env.sh" || exit 1
f="$PF_STATE/pf-ticketmaker"
case "$1" in
  on|off) echo "$1" > "$f"; echo "$1" ;;
  "") m=$(cat "$f" 2>/dev/null); echo "${m:-on}" ;;
  *) echo "usage: pf-ticketmaker.sh [on|off]" >&2; exit 2 ;;
esac
