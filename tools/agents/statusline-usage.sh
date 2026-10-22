#!/bin/bash
# Claude Code statusLine command. Set PF_ACCOUNT=<handle> in the command (see docs/agents/autotriage-debrief.md).
# Line 1: <model> · 5h N% (r <time>) · 7d N% (r <day time>) · AT·day|AT·night|MT
# Lines 2+: cached by pf-status-refresh.sh (agents/ready/PRs/last merge/triagemaster, then one line per running agent).
# Also saves the statusline JSON ($PF_STATE/usage-snapshot.json) and keeps this account's #432 usage beacon current.
in=$(cat)
. "$(dirname "$0")/pf-env.sh" || exit 1
printf '%s' "$in" > "$PF_STATE/usage-snapshot.json"
fmt() { [ -n "$1" ] && [ "$1" != null ] && pf_epoch_fmt "$1" "$2" | sed 's/AM$/a/;s/PM$/p/;s/:00\([ap]\)/\1/'; }
r5=$(echo "$in" | jq -r '.rate_limits.five_hour.resets_at // empty'); r7=$(echo "$in" | jq -r '.rate_limits.seven_day.resets_at // empty')
l1=$(echo "$in" | jq -r --arg r5 "$(fmt "$r5" +%-I:%M%p)" --arg r7 "$(fmt "$r7" '+%a %-I:%M%p')" '[.model.display_name, (.rate_limits.five_hour | if . then "5h \(.used_percentage|floor)% (r \($r5))" else empty end), (.rate_limits.seven_day | if . then "7d \(.used_percentage|floor)% (r \($r7))" else empty end)] | join(" · ")' 2>/dev/null)
echo "$l1 · $(bash "$PF_DIR/pf-at-mode.sh")"
cat "$PF_STATE/pf-status-cache.txt" 2>/dev/null
# refresh lines 2+ in the background, at most every 60 s
c=$PF_STATE/pf-status-cache.txt
if [ -z "${PF_DRY_RUN:-}" ] && { [ ! -f $c ] || [ $(( $(date +%s) - $(pf_mtime $c) )) -ge 60 ]; }; then touch $c; (bash "$PF_DIR/pf-status-refresh.sh" >/dev/null 2>&1 &); fi
# Usage beacon (#432): keep this account's comment current, at most every 15 min, in the background.
# PF_DRY_RUN=1 (testing): no gh writes at all, and the refresh job is skipped.
stamp=$PF_STATE/.beacon-stamp
if [ -z "${PF_DRY_RUN:-}" ] && { [ ! -f "$stamp" ] || [ $(( $(date +%s) - $(pf_mtime "$stamp") )) -ge 900 ]; }; then
  touch "$stamp"
  ( body=$(jq -r --arg a "$PF_ACCOUNT" '"\($a) usage @ \(now|todate)\n5h: \(.rate_limits.five_hour.used_percentage // "?")% (resets \(.rate_limits.five_hour.resets_at // 0|todate))\n7d: \(.rate_limits.seven_day.used_percentage // "?")% (resets \(.rate_limits.seven_day.resets_at // 0|todate))"' "$PF_STATE/usage-snapshot.json")
    id=$(cat "$PF_STATE/.beacon-comment-id" 2>/dev/null)
    if [ -n "$id" ]; then gh api -X PATCH repos/$REPO/issues/comments/$id -f body="$body" >/dev/null 2>&1
    else gh api repos/$REPO/issues/432/comments -f body="$body" -q .id > "$PF_STATE/.beacon-comment-id" 2>/dev/null; fi ) >/dev/null 2>&1 &
fi
