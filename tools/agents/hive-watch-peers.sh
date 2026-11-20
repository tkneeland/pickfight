#!/bin/bash
# Zero-token watcher: exits (waking the Claude session that ran it in the background) when a peer needs attention.
# Meant for the triagemaster. Peers = WATCH_PEERS in the account conf (default: every other account conf).
#   PEER ACTIVITY  a peer did anything new in the repo.
#   STALE          a peer has been idle IDLE_HOURS+ while ready-for-agent tickets sit assigned to them: take them over.
#   UNOWNED        a ready-for-agent ticket has no assignee: claim it.
# UNOWNED/STALE tickets with a recent CLAIM from another account (channel or [CLAIM] comment) are skipped.
# One watcher per account per machine: a second window exits at once instead of racing.
. "$(dirname "$0")/hive-env.sh" || exit 1
LOCK=$HIVE_STATE/watch-peers.lock
IDLE_HOURS=${IDLE_HOURS:-8}
[ "$SINGLE_ACCOUNT" = 1 ] && { echo "single-account mode: no peers to watch"; exit 0; }
PEERS=$(hive_peers)
[ -n "$PEERS" ] || { echo "no peers to watch (add accounts/<handle>.conf files or set WATCH_PEERS)"; exit 0; }
if [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK")" 2>/dev/null; then
  echo "ALREADY WATCHED by pid $(cat "$LOCK") in another window; nothing to do."
  exit 0
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
latest() {  # newest event by any peer
  gh api "repos/$REPO/events?per_page=50" \
    --jq "[.[]|select(.actor.login|IN($(printf '"%s",' $PEERS | sed 's/,$//')))]|sort_by(.created_at)|last|\"\(.id) \(.created_at) \(.type) \(.actor.login) \(.payload.ref // .payload.pull_request.number // .payload.issue.number // \"\")\""
}
ready() {  # open ready-for-agent issues as "number:assignee" (assignee may be empty)
  gh issue list --repo "$REPO" --state open --label ready-for-agent --limit 100 \
    --json number,assignees --jq '.[]|"\(.number):\(.assignees|map(.login)|join(","))"'
}
# 0 when another account claimed issue $1 in the last 24h: a channel CLAIM (hive-msg.sh) or a "[CLAIM]" issue comment
claimed_elsewhere() {
  bash "$HIVE_DIR/hive-msg.sh" claimed "$1" 2>/dev/null && return 0
  cutoff=$(( $(date -u +%s) - 86400 ))
  for ts in $(gh api "repos/$REPO/issues/$1/comments" --jq ".[] | select((.body|startswith(\"[CLAIM]\")) and .user.login!=\"$HIVE_ACCOUNT\") | .created_at" 2>/dev/null); do
    [ "$(hive_iso2epoch "$ts")" -ge "$cutoff" ] && return 0
  done
  return 1
}
filter_claimed() { out=""; for n in $1; do claimed_elsewhere "$n" || out="$out$n "; done; echo "$out"; }
base=$(latest)
case "$base" in null*|"") base="null 1970-01-01T00:00:00Z";; esac   # no peer event in the last 50
first=1
while true; do
  [ $first -eq 1 ] || sleep 300
  first=0
  now_s=$(date +%s)
  now=$(latest) || continue
  case "$now" in null*|"") now=$base;; esac   # no peer event in the last 50: nothing new
  if [ -n "$now" ] && [ "$(echo "$now" | cut -d" " -f2)" \> "$(echo "$base" | cut -d" " -f2)" ]; then
    echo "PEER ACTIVITY: $now"; exit 0
  fi
  list=$(ready) || continue
  unowned=$(echo "$list" | grep -E ':$' | cut -d: -f1 | tr '\n' ' ')
  unowned=$(filter_claimed "$unowned")
  if [ -n "${unowned// }" ]; then echo "UNOWNED: #${unowned% }"; exit 0; fi
  last=$(echo "$now" | awk '{print $2}')
  last_s=$(hive_iso_to_epoch "$last" || echo "$now_s")
  theirs=$(echo "$list" | grep -E ":($(echo $PEERS | tr ' ' '|'))" | cut -d: -f1 | tr '\n' ' ')
  theirs=$(filter_claimed "$theirs")
  # Once per idle stretch: a STALE already reported for this last-activity time is not reported again.
  STALE_MARK="$HIVE_STATE/stale-reported"
  if [ -n "${theirs// }" ] && [ $(( now_s - last_s )) -ge $(( IDLE_HOURS * 3600 )) ] \
     && [ "$(cat "$STALE_MARK" 2>/dev/null)" != "$last" ]; then
    echo "$last" > "$STALE_MARK"
    echo "STALE: peer idle since $last UTC; their tickets: #${theirs% }"; exit 0
  fi
done
