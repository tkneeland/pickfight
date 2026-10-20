#!/bin/bash
# Claude Code status line that also keeps your usage beacon on issue #432 current (docs/agents/collaboration.md).
# Install: copy to ~/.claude/statusline-usage.sh, then in ~/.claude/settings.json set
#   "statusLine": {"type": "command", "command": "bash ~/.claude/statusline-usage.sh"}
# Set PF_LOGIN to your GitHub login, and (to edit your existing comment instead of posting a new one)
# put that comment's id in ~/.claude/.beacon-comment-id. Needs jq and an authenticated gh.
PF_LOGIN=${PF_LOGIN:-$(gh api user -q .login 2>/dev/null)}
in=$(cat); printf '%s' "$in" > ~/.claude/usage-snapshot.json
echo "$in" | jq -r '[.model.display_name, (.rate_limits.five_hour | if . then "5h \(.used_percentage|floor)%" else empty end), (.rate_limits.seven_day | if . then "7d \(.used_percentage|floor)%" else empty end)] | join(" · ")' 2>/dev/null
stamp=~/.claude/.beacon-stamp
mtime=$(stat -f %m "$stamp" 2>/dev/null || stat -c %Y "$stamp" 2>/dev/null || echo 0)
if [ ! -f "$stamp" ] || [ $(( $(date +%s) - mtime )) -ge 900 ]; then
  touch "$stamp"
  ( body=$(jq -r --arg who "$PF_LOGIN" '"\($who) usage @ \(now|todate)\n5h: \(.rate_limits.five_hour.used_percentage // "?")% (resets \(.rate_limits.five_hour.resets_at // 0|todate))\n7d: \(.rate_limits.seven_day.used_percentage // "?")% (resets \(.rate_limits.seven_day.resets_at // 0|todate))"' ~/.claude/usage-snapshot.json)
    id=$(cat ~/.claude/.beacon-comment-id 2>/dev/null)
    if [ -n "$id" ]; then gh api -X PATCH repos/tkneeland/pickfight/issues/comments/$id -f body="$body" >/dev/null 2>&1
    else gh api repos/tkneeland/pickfight/issues/432/comments -f body="$body" -q .id > ~/.claude/.beacon-comment-id 2>/dev/null; fi ) >/dev/null 2>&1 &
fi
