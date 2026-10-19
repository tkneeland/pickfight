#!/bin/bash
# Zero-token watcher: exits (waking the Claude session that ran it in the
# background) when there is something for tkneeland's Claude to do:
#   AUSTIN ACTIVITY  Austin (agage-JG) did anything new in tkneeland/pickfight.
#   STALE            Austin has been idle IDLE_HOURS+ while ready-for-agent
#                    tickets sit assigned to him: take them over.
#   UNOWNED          a ready-for-agent ticket has no assignee: claim it.
#   RESET            the weekly budget reset (2026-10-01) passed: triage #212.
# #212 (PC/online) is parked until the reset and ignored before it.
# One watcher per machine: a second window exits at once instead of racing.
LOCK=/tmp/pickfight-watch-austin.lock
IDLE_HOURS=8
PARKED=212
RESET_EPOCH=$(date -j -f "%Y-%m-%d %H:%M" "2026-10-01 00:00" +%s)
RESET_MARK="$HOME/.claude/pickfight-reset-announced"
if [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK")" 2>/dev/null; then
  echo "ALREADY WATCHED by pid $(cat "$LOCK") in another window; nothing to do."
  exit 0
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
latest() {
  gh api "repos/tkneeland/pickfight/events?per_page=50" \
    --jq '[.[]|select(.actor.login=="agage-JG")]|sort_by(.created_at)|last|"\(.id) \(.created_at) \(.type) \(.payload.ref // .payload.pull_request.number // .payload.issue.number // "")"'
}
ready() {  # open ready-for-agent issues as "number:assignee" (assignee may be empty)
  gh issue list --repo tkneeland/pickfight --state open --label ready-for-agent --limit 100 \
    --json number,assignees --jq '.[]|"\(.number):\(.assignees|map(.login)|join(","))"'
}
base=$(latest)
first=1
while true; do
  [ $first -eq 1 ] || sleep 300
  first=0
  now_s=$(date +%s)
  if [ "$now_s" -ge "$RESET_EPOCH" ] && [ ! -f "$RESET_MARK" ]; then
    touch "$RESET_MARK"; echo "RESET: budget week reset; triage parked #$PARKED"; exit 0
  fi
  now=$(latest) || continue
  if [ -n "$now" ] && [ "$(echo "$now" | cut -d" " -f2)" \> "$(echo "$base" | cut -d" " -f2)" ]; then
    echo "AUSTIN ACTIVITY: $now"; exit 0
  fi
  list=$(ready) || continue
  if [ "$now_s" -lt "$RESET_EPOCH" ]; then list=$(echo "$list" | grep -v "^$PARKED:"); fi
  unowned=$(echo "$list" | grep -E ':$' | cut -d: -f1 | tr '\n' ' ')
  if [ -n "${unowned// }" ]; then echo "UNOWNED: #${unowned% }"; exit 0; fi
  last=$(echo "$now" | awk '{print $2}')
  last_s=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$last" +%s 2>/dev/null || echo "$now_s")
  austins=$(echo "$list" | grep "agage-JG" | cut -d: -f1 | tr '\n' ' ')
  # Once per idle stretch: a STALE already reported for this last-activity
  # time is not reported again.
  STALE_MARK="$HOME/.claude/pickfight-stale-reported"
  if [ -n "${austins// }" ] && [ $(( now_s - last_s )) -ge $(( IDLE_HOURS * 3600 )) ] \
     && [ "$(cat "$STALE_MARK" 2>/dev/null)" != "$last" ]; then
    echo "$last" > "$STALE_MARK"
    echo "STALE: Austin idle since $last UTC; his tickets: #${austins% }"; exit 0
  fi
done
