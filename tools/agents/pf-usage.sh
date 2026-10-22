#!/bin/bash
# Zero-token usage refresh for sessions with no status line (headless `claude -p`, launchd jobs): reads the 5h and 7d
# utilization from Anthropic's OAuth usage endpoint with this machine's own Claude Code login, writes the rate_limits
# part of $PF_STATE/usage-snapshot.json in the status line's format, then refreshes the #432 beacon (pf-beacon.sh) when
# the numbers changed or an hour passed. The token is read from the macOS keychain or ~/.claude/.credentials.json and is
# never printed, logged or put on a command line. An expired login is skipped, not refreshed (refresh tokens rotate and
# would log Claude Code out): an idle account's usage doesn't change, and any running Claude session refreshes the login.
. "$(dirname "$0")/pf-env.sh" || exit 1
log() { echo "$(date -u +%FT%TZ) $*" >> "$PF_STATE/beacon.log"; }
creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || cat "$HOME/.claude/.credentials.json" 2>/dev/null)
tok=$(echo "$creds" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
[ -n "$tok" ] || { log "pf-usage: no Claude Code login found"; exit 1; }
exp=$(echo "$creds" | jq -r '(.claudeAiOauth.expiresAt // 0) / 1000 | floor' 2>/dev/null)
[ "${exp:-0}" -gt 0 ] && [ "$exp" -le "$(date +%s)" ] && { log "pf-usage: login expired, skipped until a Claude session refreshes it"; exit 0; }
u=$(printf 'Authorization: Bearer %s\nanthropic-beta: oauth-2025-04-20\n' "$tok" |
  curl -sf --max-time 20 -H @- https://api.anthropic.com/api/oauth/usage) || { log "pf-usage: usage endpoint failed"; exit 1; }
unset tok creds
rl=$(echo "$u" | jq -c 'def w: {used_percentage: (if .utilization then (.utilization | floor) else null end),
    resets_at: (try (.resets_at | sub("\\.[0-9]+"; "") | sub("[+-]00:00$"; "Z") | fromdateiso8601) catch null)};
  {five_hour: (.five_hour | w), seven_day: (.seven_day | w)}') || { log "pf-usage: unexpected response"; exit 1; }
snap=$PF_STATE/usage-snapshot.json
old=$(jq -c . "$snap" 2>/dev/null) || old='{}'
prev=$(echo "$old" | jq -c '.rate_limits // {}')
echo "$old" | jq --argjson rl "$rl" '.rate_limits = $rl' > "$snap.tmp" && mv "$snap.tmp" "$snap" ||
  { rm -f "$snap.tmp"; log "pf-usage: snapshot write failed"; exit 1; }
[ "${1:-}" = --no-beacon ] && exit 0
stamp=$PF_STATE/.pf-usage-beacon; last=$(cat "$stamp" 2>/dev/null || echo 0)
[ "$prev" = "$rl" ] && [ $(( $(date +%s) - last )) -lt 3600 ] && exit 0
bash "$PF_DIR/pf-beacon.sh" && date +%s > "$stamp"
