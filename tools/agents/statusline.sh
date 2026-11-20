#!/bin/bash
# Claude Code statusLine command. Put HIVE_ACCOUNT=<handle> in the command (see docs/agents/hive-debrief.md).
# Line 1: <model> · 5h N% (r <time>) / T% pace (hive-pace.sh target; omitted without a window) · 7d N% (r <day time>) · AT·on pace|AT·ahead|MT
# Lines 2+: cached by hive-status-refresh.sh (agents/ready/PRs/last merge/triagemaster, then one line per running agent).
# Also saves the statusline JSON ($HIVE_STATE/usage-snapshot.json) and keeps this account's USAGE beacon (private channel)
# current. Line 1 ends with "msg:quota til HH:MM" while the channel is blocked by ntfy's daily quota. Windows: run it from Git Bash (tools/agents/windows/README.md).
in=$(cat)
. "$(dirname "$0")/hive-env.sh" || exit 1
printf '%s' "$in" > "$HIVE_STATE/usage-snapshot.json"
fmt() { [ -n "$1" ] && [ "$1" != null ] && hive_fmt "$1" "$2" | sed 's/AM$/a/;s/PM$/p/;s/:00\([ap]\)/\1/'; }
r5=$(echo "$in" | jq -r '.rate_limits.five_hour.resets_at // empty'); r7=$(echo "$in" | jq -r '.rate_limits.seven_day.resets_at // empty')
pc=$(bash "$HIVE_DIR/hive-pace.sh" target 2>/dev/null); [ -n "$pc" ] && pc=" / ${pc}% pace"
l1=$(echo "$in" | jq -r --arg pc "$pc" --arg r5 "$(fmt "$r5" +%-I:%M%p)" --arg r7 "$(fmt "$r7" '+%a %-I:%M%p')" '[.model.display_name, (.rate_limits.five_hour | if . then "5h \(.used_percentage|floor)% (r \($r5))\($pc)" else empty end), (.rate_limits.seven_day | if . then "7d \(.used_percentage|floor)% (r \($r7))" else empty end)] | join(" · ")' 2>/dev/null)
# msg:quota til HH:MM (local): the channel is blocked by ntfy's daily quota (HTTP 429) until then (hive-msg.sh send)
qm=""; q=$(hive_msg_quota_until) && qm=" · msg:quota til $(hive_fmt "$q" +%H:%M)"
echo "$l1 · $(bash "$HIVE_DIR/hive-at-mode.sh")$qm"
cat "$HIVE_STATE/status-cache.txt" 2>/dev/null
# refresh lines 2+ in the background, at most every 60 s
c=$HIVE_STATE/status-cache.txt
if [ -z "${HIVE_DRY_RUN:-}" ] && { [ ! -f "$c" ] || [ $(( $(date +%s) - $(hive_mtime "$c" || echo 0) )) -ge 60 ]; }; then touch "$c"; (bash "$HIVE_DIR/hive-status-refresh.sh" >/dev/null 2>&1 &); fi
# Usage beacon: run hive-beacon.sh at most every 5 min, in the background; it sends USAGE only on a change or hourly.
# Channel only; nothing goes to GitHub. Skipped in SINGLE_ACCOUNT (and PRIVATE) mode.
# HIVE_DRY_RUN=1 (testing): no beacon or gh writes at all, and the refresh job is skipped.
[ "$SINGLE_ACCOUNT" != 1 ] && [ -z "${HIVE_DRY_RUN:-}" ] || exit 0
stamp=$HIVE_STATE/.beacon-stamp
if [ ! -f "$stamp" ] || [ $(( $(date +%s) - $(hive_mtime "$stamp" || echo 0) )) -ge 300 ]; then
  touch "$stamp"
  (bash "$HIVE_DIR/hive-beacon.sh" >/dev/null 2>&1 &)
fi
