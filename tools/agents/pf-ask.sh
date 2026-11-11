#!/bin/bash
# Ask another machine's agent a question on the private channel and wait for its answer (#1207, rule 17).
#   pf-ask.sh <account> "<question>" [timeout s, default 180]
# Sends `ASK @<account> [q<id>] <question>` (id: epoch plus random), then waits for an ANSWER from <account> whose text
# starts with `[q<id>]` in msg-inbox.log (filled by `pf-msg.sh listen`; a `pf-msg.sh backfill` pass every 30 s covers
# a listener that is down). Prints the answer without its id and exits 0.
# On timeout prints "<account> hasn't answered (last heartbeat <N> min ago, <HH:MM> ET)" and exits 1. The question
# stays open in $PF_STATE/ask-open.txt, so a late answer still wakes this machine as a normal `MSG ANSWER`.
# Only for what the other machine can answer from its own files and state; questions for a human go to #hive.
# Exit 2: bad usage or nothing could be sent. Env: PF_ASK_POLL (s between inbox reads, default 2),
# PF_ASK_BACKFILL_SEC (s between backfill passes, default 30, 0 = never).
AG=$(cd "$(dirname "$0")" && pwd)
. "$AG/pf-env.sh" || exit 2
INBOX=$PF_STATE/msg-inbox.log
OPEN=$PF_STATE/ask-open.txt
to=${1:-}; q=${2:-}; timeout=${3:-180}
usage() { echo "usage: pf-ask.sh <account> \"<question>\" [timeout s, default 180]" >&2; exit 2; }
[ -n "$to" ] && [ -n "$q" ] || usage
case $timeout in ''|*[!0-9]*) usage;; esac
[ "$to" != "$PF_ACCOUNT" ] || { echo "pf-ask: $to is this account; ask another machine" >&2; exit 2; }
pf_handles | grep -qxF -- "$to" || { echo "pf-ask: unknown account '$to' (known: $(pf_handles | tr '\n' ' '))" >&2; exit 2; }
grep -qs '^PF_MSG_TOPIC=..*' "$PF_STATE/pf-msg.conf" || { echo "pf-ask: no channel configured (pf-msg.sh init); not sent" >&2; exit 2; }

id="q$(date -u +%s)$(od -An -N2 -tu2 /dev/urandom | tr -d ' \n')"
bash "$AG/pf-msg.sh" send ASK "@$to [$id] $q" || { echo "pf-ask: send failed" >&2; exit 2; }

# The answer from $to tagged [$id], without the tag; empty if none yet.
answer() {
  [ -f "$INBOX" ] || return 0
  awk -F'|' -v from="$to" -v tag="[$id]" '
    $2 == from && $3 == "ANSWER" {
      rest = substr($0, length($1) + length($2) + length($3) + 4)
      if (index(rest, tag) == 1) { a = substr(rest, length(tag) + 1); sub(/^ +/, "", a); found = 1; print a; exit }
    }' "$INBOX"
}
found() { a=$(answer); [ -n "$a" ] && { printf '%s\n' "$a"; return 0; }; return 1; }

poll=${PF_ASK_POLL:-2}; bf=${PF_ASK_BACKFILL_SEC:-30}
start=$(date -u +%s); last_bf=$start
while :; do
  found && exit 0
  t=$(date -u +%s)
  [ $((t - start)) -ge "$timeout" ] && break
  if [ "$bf" -gt 0 ] && [ $((t - last_bf)) -ge "$bf" ]; then
    bash "$AG/pf-msg.sh" backfill >/dev/null 2>&1; last_bf=$t
  fi
  sleep "$poll"
done

# Timed out: leave the question open for the listener's late-answer wake, then look once more so an answer that
# landed meanwhile is not lost between the last read and the record.
echo "$id|$to|$start" >> "$OPEN"
if found; then
  grep -vF -- "$id|" "$OPEN" > "$OPEN.tmp"; mv "$OPEN.tmp" "$OPEN"
  exit 0
fi
hb=$(awk -F'|' -v p="$to" '$2 == p && ($3 == "HELLO" || $3 == "USAGE") && $1 + 0 > m { m = $1 + 0 } END { print int(m) }' "$INBOX" 2>/dev/null)
if [ "${hb:-0}" -gt 0 ]; then
  echo "$to hasn't answered (last heartbeat $(( ($(date -u +%s) - hb) / 60 )) min ago, $(TZ=$PF_ET_TZ pf_epoch_fmt "$hb" +%H:%M) ET)"
else
  echo "$to hasn't answered (no heartbeat on record)"
fi
exit 1
