# Source me: sets PF_RATE/PF_WEEK from the 5h window's % used and elapsed time in that window.
S=~/.claude/usage-snapshot.json; p=$(jq -r .rate_limits.five_hour.used_percentage $S); r=$(jq -r .rate_limits.five_hour.resets_at $S)
el=$(echo "scale=2;5-($r-$(date +%s))/3600"|bc); pr=$(echo "scale=0;$p*5/$el"|bc 2>/dev/null)
export PF_RATE="${p}% of the 5-hour window used in ${el} h, so a pace of ~${pr}% per 5 h (this covers all agents; exact token counts aren't exposed)"
export PF_WEEK="~$(echo "scale=0;$pr*40/100"|bc) full 5-hour windows/week at this pace (weekly window $(jq -r .rate_limits.seven_day.used_percentage $S)% used)"
