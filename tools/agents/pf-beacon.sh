#!/bin/bash
# Writes this account's #432 usage beacon once, in the foreground, from $PF_STATE/usage-snapshot.json
# (saved by statusline-usage.sh). Edits the account's existing beacon comment; finds it on #432 when
# .beacon-comment-id is missing, and posts a new one only if none exists. Errors go to $PF_STATE/beacon.log.
# Run by statusline-usage.sh every 15 min, and by `windows/pf-supervise.sh beacon`, which outlives the status line.
. "$(dirname "$0")/pf-env.sh" || exit 1
log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >> "$PF_STATE/beacon.log"; }
snap=$PF_STATE/usage-snapshot.json
[ -s "$snap" ] || { log "no usage snapshot yet (status line not run?)"; exit 1; }
body=$(jq -r --arg a "$PF_ACCOUNT" '
  "\($a) usage @ \(now|todate)\n5h: \(.rate_limits.five_hour.used_percentage // "?")% (resets \(.rate_limits.five_hour.resets_at // 0|todate))\n7d: \(.rate_limits.seven_day.used_percentage // "?")% (resets \(.rate_limits.seven_day.resets_at // 0|todate))\n<!-- usage \({account:$a, at:(now|floor), five_hour:.rate_limits.five_hour, seven_day:.rate_limits.seven_day}|tojson) -->"' "$snap") \
  || { log "bad snapshot"; exit 1; }
idf=$PF_STATE/.beacon-comment-id; id=$(cat "$idf" 2>/dev/null)
if [ -z "$id" ]; then
  id=$(gh api "repos/$REPO/issues/432/comments?per_page=100" --paginate \
    --jq ".[]|select(.user.login==\"$PF_ACCOUNT\" and (.body|startswith(\"$PF_ACCOUNT usage @\")))|.id" 2>>"$PF_STATE/beacon.log" | tail -n 1)
  [ -n "$id" ] && echo "$id" > "$idf"
fi
if [ -n "$id" ]; then
  gh api -X PATCH "repos/$REPO/issues/comments/$id" -f body="$body" >/dev/null 2>>"$PF_STATE/beacon.log" || { log "PATCH $id failed"; exit 1; }
else
  id=$(gh api "repos/$REPO/issues/432/comments" -f body="$body" -q .id 2>>"$PF_STATE/beacon.log") || { log "POST failed"; exit 1; }
  echo "$id" > "$idf"
fi
# best effort: also tell the private channel (doorbell for the other machine); never fails the beacon
bash "$PF_DIR/pf-msg.sh" send USAGE "$(jq -r '"\(.rate_limits.five_hour.used_percentage // 0|floor)% \(.rate_limits.seven_day.used_percentage // 0|floor)% \(.rate_limits.seven_day.resets_at // 0|floor|todate)"' "$snap")" >/dev/null 2>&1 || true
