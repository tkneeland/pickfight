#!/bin/bash
# Offline tests for pf-ask.sh (#1207): the ASK goes out tagged [q<id>]; the answer is matched by id from the asked
# account only (never crossed with another question's answer); the timeout message; a late answer wakes the
# listener once as MSG ANSWER. Scratch PF_STATE_DIR and a stub curl first on PATH (logs sends, serves the listen
# stream from a file). No network. macOS, Linux and Git Bash.   bash tools/agents/tests/ask.sh
AG=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/pf-ask-test.XXXXXX") && [ -d "$T" ] || { echo "ask: cannot make a scratch dir" >&2; exit 1; }
# a POSIX path: a Windows "C:/..." TMPDIR would split PATH at its colon. Cleanup only ever removes the mktemp dir.
T=$(cd "$T" && pwd) && case $T in */pf-ask-test.*) ;; *) echo "ask: odd scratch dir '$T'" >&2; exit 1;; esac
trap 'kill $LP 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/state"
cat > "$T/bin/curl" <<'STUB'
#!/bin/bash
cfg=$(cat); data=""
while [ $# -gt 0 ]; do [ "$1" = -d ] && data=$2; shift; done
[ -n "$data" ] && echo "SEND $data" >> "$PF_TEST_LOG"
case $cfg in *poll=1*) ;; */json*) cat "$PF_TEST_STREAM" 2>/dev/null;; esac
exit 0
STUB
chmod +x "$T/bin/curl"
export PATH="$T/bin:$PATH" PF_STATE_DIR=$T/state PF_TEST_LOG=$T/calls.log PF_TEST_STREAM=$T/stream.json \
  PF_ASK_POLL=1 PF_ASK_BACKFILL_SEC=0
[ "$(command -v curl)" = "$T/bin/curl" ] || { echo "ask: stub curl not first on PATH; refusing to touch the network" >&2; exit 1; }
PF_ACCOUNT=schans2 . "$AG/pf-env.sh" || exit 1
echo "PF_MSG_TOPIC=pf-testtopic" > "$T/state/pf-msg.conf"
INBOX=$T/state/msg-inbox.log; WAKE=$T/state/msg-wake.txt; OPEN=$T/state/ask-open.txt
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
ask() { PF_ACCOUNT=schans2 bash "$AG/pf-ask.sh" "$@"; }
# listen_until <id>: run the listener until it has taken message <id> from the stream (a slow machine needs more than a
# fixed sleep), give it a moment to write any wake, then stop it
listen_until() {
  PF_ACCOUNT=schans2 bash "$AG/pf-msg.sh" listen & LP=$!
  for _ in $(seq 1 150); do [ "$(cat "$T/state/.msg-last-id" 2>/dev/null)" = "$1" ] && break; sleep 0.1; done
  sleep 1; kill $LP 2>/dev/null; wait $LP 2>/dev/null
}
# the id of the newest ASK sent
sent_id() { sed -n 's/^SEND schans2 ASK @[^ ]* \[\(q[0-9]*\)\].*/\1/p' "$PF_TEST_LOG" | tail -n 1; }
# answer_when_asked <from> <text>: once an ASK is sent, append <from>'s ANSWER "[q<id>] <text>" to the inbox
answer_when_asked() {
  ( for _ in $(seq 1 50); do id=$(sent_id); [ -n "$id" ] && break; sleep 0.1; done
    echo "$(date -u +%s)|$1|ANSWER|[$id] $2" >> "$INBOX" ) &
}
now=$(date -u +%s)

# 1 the ASK is tagged and addressed; the answer is matched by id and printed without the tag
: > "$PF_TEST_LOG"; : > "$INBOX"
answer_when_asked agage-JG "yes, the listener is up"
out=$(ask agage-JG "is your listener up?" 10); rc=$?; wait
check "answered: exit" "$rc" 0
check "answered: text" "$out" "yes, the listener is up"
check "ask format" "$(grep -c '^SEND schans2 ASK @agage-JG \[q[0-9]\{11,\}\] is your listener up?$' "$PF_TEST_LOG")" 1
check "answered: nothing left open" "$(cat "$OPEN" 2>/dev/null | wc -l | tr -d ' ')" 0

# 2 not crossed: another question's answer, the same id from the wrong account, and an untagged ANSWER are ignored
: > "$PF_TEST_LOG"
{ echo "$now|agage-JG|ANSWER|[q1111111111999] an answer to someone else's question"
  echo "$now|agage-JG|ANSWER|no tag at all"; } > "$INBOX"
( for _ in $(seq 1 50); do id=$(sent_id); [ -n "$id" ] && break; sleep 0.1; done
  echo "$(date -u +%s)|tkneeland|ANSWER|[$id] wrong account" >> "$INBOX"; sleep 1.5
  echo "$(date -u +%s)|agage-JG|ANSWER|[$id] the right one" >> "$INBOX" ) &
out=$(ask agage-JG "which one?" 10); rc=$?; wait
check "not crossed: exit" "$rc" 0
check "not crossed: text" "$out" "the right one"

# 3 two questions in flight at once each get their own answer
: > "$PF_TEST_LOG"; : > "$INBOX"
ask agage-JG "first?" 10 > "$T/a1" & A1=$!
for _ in $(seq 1 50); do id1=$(sent_id); [ -n "$id1" ] && break; sleep 0.1; done
sleep 1.1   # a different epoch second, so the ids differ even if the random part collides
ask agage-JG "second?" 10 > "$T/a2" & A2=$!
for _ in $(seq 1 50); do id2=$(sent_id); [ "$id2" != "$id1" ] && break; sleep 0.1; done
{ echo "$(date -u +%s)|agage-JG|ANSWER|[$id2] two"; echo "$(date -u +%s)|agage-JG|ANSWER|[$id1] one"; } >> "$INBOX"
wait $A1; wait $A2
check "in flight: first" "$(cat "$T/a1")" "one"
check "in flight: second" "$(cat "$T/a2")" "two"

# 4 timeout: exit 1, the heartbeat message in ET, and the question stays open
: > "$PF_TEST_LOG"; hb=$(( $(date -u +%s) - 750 ))   # 12.5 min: half a minute clear of a boundary
echo "$hb|agage-JG|HELLO|agage-JG" > "$INBOX"
out=$(ask agage-JG "anyone there?" 1); rc=$?
check "timeout: exit" "$rc" 1
check "timeout: message" "$out" "agage-JG hasn't answered (last heartbeat $(( ($(date -u +%s) - hb) / 60 )) min ago, $(TZ=$PF_ET_TZ pf_epoch_fmt "$hb" +%H:%M) ET)"
lid=$(sent_id)
check "timeout: left open" "$(grep -c "^$lid|agage-JG|" "$OPEN")" 1
: > "$INBOX"
check "timeout, no heartbeat" "$(ask agage-JG "still nobody?" 1)" "agage-JG hasn't answered (no heartbeat on record)"

# 5 late answer: the listener wakes once with MSG ANSWER; another account's ANSWER with the id, and a repeat, do not
rm -f "$WAKE" "$T/state/.msg-last-id"
t=$(date -u +%s)
{ echo "{\"id\":\"m1\",\"time\":$t,\"event\":\"message\",\"message\":\"tkneeland ANSWER [$lid] not yours\"}"
  echo "{\"id\":\"m2\",\"time\":$t,\"event\":\"message\",\"message\":\"agage-JG ANSWER [q1111111111999] some other question\"}"; } > "$PF_TEST_STREAM"
listen_until m2
check "late: no wake for others" "$(cat "$WAKE" 2>/dev/null)" ""
rm -f "$T/state/.msg-last-id"
echo "{\"id\":\"m3\",\"time\":$t,\"event\":\"message\",\"message\":\"agage-JG ANSWER [$lid] here now\"}" > "$PF_TEST_STREAM"
listen_until m3
check "late: wake" "$(cat "$WAKE" 2>/dev/null)" "MSG ANSWER agage-JG [$lid] here now"
check "late: closed" "$(grep -c "^$lid|" "$OPEN")" 0
rm -f "$WAKE" "$T/state/.msg-last-id"
listen_until m3
check "late: wakes once" "$(cat "$WAKE" 2>/dev/null)" ""
# an open question older than 24h is dropped and never wakes
echo "q2222222222000|agage-JG|$((now - 90000))" >> "$OPEN"; rm -f "$T/state/.msg-last-id"
echo "{\"id\":\"m4\",\"time\":$t,\"event\":\"message\",\"message\":\"agage-JG ANSWER [q2222222222000] a day late\"}" > "$PF_TEST_STREAM"
listen_until m4
check "late: 24h expiry" "$(cat "$WAKE" 2>/dev/null)" ""

# 6 usage errors send nothing
: > "$PF_TEST_LOG"
ask schans2 "me?" >/dev/null 2>&1; check "self: exit" "$?" 2
ask nobody "who?" >/dev/null 2>&1; check "unknown account: exit" "$?" 2
ask agage-JG "x" soon >/dev/null 2>&1; check "bad timeout: exit" "$?" 2
check "errors sent nothing" "$(grep -c SEND "$PF_TEST_LOG")" 0

echo "ask: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
