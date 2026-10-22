#!/bin/bash
# Prints the AT state, e.g. "AT·night" or "MT". Mode file: $PF_STATE/pf-at-mode (AT|MT, default AT).
# Day override (owner asked for speed at night): $PF_STATE/pf-day-until holds an epoch; day mode until then.
# Night hours (NIGHT_START..NIGHT_END) and TZ come from tools/agents/accounts/<handle>.conf.
. "$(dirname "$0")/pf-env.sh" || exit 1
m=$(cat "$PF_STATE/pf-at-mode" 2>/dev/null || echo AT); [ "$m" = MT ] && { echo MT; exit; }
echo "AT·$(pf_daynight)"
