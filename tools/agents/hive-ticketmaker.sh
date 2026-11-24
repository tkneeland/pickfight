#!/bin/bash
# Ticket-maker mode for this game: full|suggestions|off (docs/agents/hive.md rule 11; hive_tm_mode in hive-env.sh).
#   hive-ticketmaker.sh                              print full|suggestions|off
#   hive-ticketmaker.sh full|suggestions|on|off      set the local fallback (no studio only; on = full, off = suggestions)
# With a studio (STUDIO_REPO) the studio owner sets it per game in the hive hub (Ticket-maker panel, the studio's
# hive/ticket-maker.conf); setting it here is refused (exit 3) and changes nothing.
# full: the triagemaster's own idea and bug hunting runs. suggestions: none of that; reports, owner and dev requests and CI
# failures are filed, [REVIEW-BUG]s wait for a member's approval on the decisions issue. off: no tickets at all.
. "$(dirname "$0")/hive-env.sh" || exit 1
case "${1:-}" in
  "") ;;
  full|suggestions|on|off)
    if [ -n "$STUDIO_REPO" ]; then
      echo "hive-ticketmaker: the ticket-maker mode is set in the hive hub (Ticket-maker panel) for this studio; not changed here" >&2; exit 3
    fi
    echo "$1" > "$HIVE_STATE/ticketmaker" || exit 1 ;;
  *) echo "usage: hive-ticketmaker.sh [full|suggestions|on|off]" >&2; exit 2 ;;
esac
hive_tm_mode; echo "$tm_mode"
