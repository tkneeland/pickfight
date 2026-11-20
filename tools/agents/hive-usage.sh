#!/bin/bash
# Zero-token usage refresh for sessions with no status line (headless `claude -p`, launchd jobs): reads the 5h and 7d
# utilization from Anthropic's OAuth usage endpoint with this machine's own Claude Code login, writes the rate_limits
# part of $HIVE_STATE/usage-snapshot.json in the status line's format, then runs the USAGE beacon (hive-beacon.sh), which
# sends only when the numbers changed or an hour passed. The token is read from the macOS keychain or $CLAUDE_CONFIG_DIR/.credentials.json (default ~/.claude) and is
# never printed, logged or put on a command line (the curl headers go in on stdin). An expired login is skipped, not refreshed (refresh tokens rotate and
# would log Claude Code out): an idle account's usage doesn't change, and any running Claude session refreshes the login.
. "$(dirname "$0")/hive-env.sh" || exit 1
# Usage: hive-usage.sh [--no-beacon]   (--no-beacon: refresh the snapshot only)
log() { echo "$(date -u +%FT%TZ) $*" >> "$HIVE_STATE/beacon.log"; }
creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || cat "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json" 2>/dev/null)
tok=$(echo "$creds" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
[ -n "$tok" ] || { log "hive-usage: no Claude Code login found"; exit 1; }
exp=$(echo "$creds" | jq -r '(.claudeAiOauth.expiresAt // 0) / 1000 | floor' 2>/dev/null)
[ "${exp:-0}" -gt 0 ] && [ "$exp" -le "$(date +%s)" ] && { log "hive-usage: login expired, skipped until a Claude session refreshes it"; exit 0; }
u=$(printf 'Authorization: Bearer %s\nanthropic-beta: oauth-2025-04-20\n' "$tok" |
  curl -sf --max-time 20 -H @- https://api.anthropic.com/api/oauth/usage) || { log "hive-usage: usage endpoint failed"; exit 1; }
unset tok creds
rl=$(echo "$u" | jq -c 'def w: {used_percentage: (if .utilization then (.utilization | floor) else null end),
    resets_at: (try (.resets_at | sub("\\.[0-9]+"; "") | sub("[+-]00:00$"; "Z") | fromdateiso8601) catch null)};
  {five_hour: (.five_hour | w), seven_day: (.seven_day | w)}') || { log "hive-usage: unexpected response"; exit 1; }
snap=$HIVE_STATE/usage-snapshot.json
old=$(jq -c . "$snap" 2>/dev/null); [ -n "$old" ] || old='{}'
echo "$old" | jq --argjson rl "$rl" '.rate_limits = $rl' > "$snap.tmp.$$" && mv "$snap.tmp.$$" "$snap" ||
  { rm -f "$snap.tmp.$$"; log "hive-usage: snapshot write failed"; exit 1; }
{ [ "${1:-}" = --no-beacon ] || [ "$SINGLE_ACCOUNT" = 1 ]; } && exit 0
# hive-beacon.sh sends only when the numbers changed or an hour passed (its change-only gate)
bash "$HIVE_DIR/hive-beacon.sh"
