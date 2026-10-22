# Source me (bash): sets PF_RATE/PF_WEEK from the 5h window's % used and elapsed time in that window.
. "$(dirname "${BASH_SOURCE[0]:-$0}")/pf-env.sh" || return 1
S=$PF_STATE/usage-snapshot.json; p=$(jq -r .rate_limits.five_hour.used_percentage $S); r=$(jq -r .rate_limits.five_hour.resets_at $S)
# awk, not bc: Git Bash on Windows has no bc
el=$(awk -v r="$r" -v n="$(date +%s)" 'BEGIN{printf "%.2f", 5-(r-n)/3600}'); pr=$(awk -v p="$p" -v e="$el" 'BEGIN{printf "%d", p*5/e}' 2>/dev/null)
export PF_RATE="${p}% of the 5-hour window used in ${el} h, so a pace of ~${pr}% per 5 h (this covers all agents; exact token counts aren't exposed)"
export PF_WEEK="~$(awk -v pr="$pr" 'BEGIN{printf "%d", pr*40/100}') full 5-hour windows/week at this pace (weekly window $(jq -r .rate_limits.seven_day.used_percentage $S)% used)"
