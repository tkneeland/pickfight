#!/bin/bash
# Zero-token usage refresh for sessions with no status line (headless `claude -p`, launchd jobs): reads the 5h and 7d
# utilization from Anthropic's OAuth usage endpoint with this machine's own Claude Code login, writes the rate_limits
# part of $PF_STATE/usage-snapshot.json in the status line's format, then refreshes the #432 beacon (pf-beacon.sh).
# The token is read from the macOS keychain or ~/.claude/.credentials.json and is never printed or logged.
. "$(dirname "$0")/pf-env.sh" || exit 1
log() { echo "$(date -u +%FT%TZ) $*" >> "$PF_STATE/beacon.log"; }
creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || cat "$HOME/.claude/.credentials.json" 2>/dev/null)
tok=$(echo "$creds" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
[ -n "$tok" ] || { log "pf-usage: no Claude Code login found"; exit 1; }
u=$(curl -sf --max-time 20 https://api.anthropic.com/api/oauth/usage \
  -H "Authorization: Bearer $tok" -H "anthropic-beta: oauth-2025-04-20") || { log "pf-usage: usage endpoint failed (expired login?)"; exit 1; }
rl=$(echo "$u" | jq -c 'def w: {used_percentage: (if .utilization then (.utilization | floor) else null end),
    resets_at: (if .resets_at then (.resets_at | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) else null end)};
  {five_hour: (.five_hour | w), seven_day: (.seven_day | w)}') || { log "pf-usage: unexpected response"; exit 1; }
snap=$PF_STATE/usage-snapshot.json
old=$(cat "$snap" 2>/dev/null); [ -n "$old" ] || old='{}'
echo "$old" | jq --argjson rl "$rl" '.rate_limits = $rl' > "$snap.tmp" && mv "$snap.tmp" "$snap"
[ "${1:-}" = --no-beacon ] || bash "$PF_DIR/pf-beacon.sh"
