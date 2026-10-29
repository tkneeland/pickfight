# Source me (bash): sets PF_RATE/PF_WEEK from the 5h window's % used and elapsed time in that window.
# Falls back to the "unavailable" strings, silently, when the snapshot is missing, empty ({}), unreadable or out of range.
. "$(dirname "${BASH_SOURCE[0]:-$0}")/pf-env.sh" || return 1
S=$PF_STATE/usage-snapshot.json; n=$(date +%s)
p=$(jq -r '.rate_limits.five_hour.used_percentage | numbers' "$S" 2>/dev/null)
r=$(jq -r '.rate_limits.five_hour.resets_at | if type == "string" then . else numbers end' "$S" 2>/dev/null)
case $r in *[!0-9.]*) r=$(pf_iso_to_epoch "$r");; esac   # an ISO string instead of epoch seconds
# awk, not bc: Git Bash on Windows has no bc
[ -n "$p" ] && [ -n "$r" ] && el=$(awk -v r="$r" -v n="$n" 'BEGIN{printf "%.2f", 5-(r-n)/3600}') || el=
if [ -n "$el" ] && awk -v e="$el" 'BEGIN{exit !(e > 0 && e <= 5)}'; then
  pr=$(awk -v p="$p" -v e="$el" 'BEGIN{printf "%d", p*5/e}' 2>/dev/null)
  export PF_RATE="${p}% of the 5-hour window used in ${el} h, so a pace of ~${pr}% per 5 h (this covers all agents; exact token counts aren't exposed)"
  export PF_WEEK="~$(awk -v pr="$pr" 'BEGIN{printf "%d", pr*40/100}') full 5-hour windows/week at this pace (weekly window $(jq -r .rate_limits.seven_day.used_percentage $S)% used)"
else
  export PF_RATE="usage snapshot unavailable (no statusline data yet)" PF_WEEK="unavailable"
fi
