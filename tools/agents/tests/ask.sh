#!/bin/bash
# Offline tests for hive-ask.sh: the ASK goes out tagged [q<id>]; the answer is matched by id from the asked
# account only (never crossed with another question's answer); the timeout message; a late answer wakes the
# listener once as MSG ANSWER. Scratch HIVE_STATE_DIR and a stub curl first on PATH (logs sends, serves the listen
# stream from a file). No network. macOS, Linux and Git Bash.   bash tools/agents/tests/ask.sh
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/hive-ask-test.XXXXXX") && [ -d "$T" ] || { echo "ask: cannot make a scratch dir" >&2; exit 1; }
# a POSIX path: a Windows "C:/..." TMPDIR would split PATH at its colon. Cleanup only ever removes the mktemp dir.
T=$(cd "$T" && pwd) && case $T in */hive-ask-test.*) ;; *) echo "ask: odd scratch dir '$T'" >&2; exit 1;; esac
trap 'kill $LP 2>/dev/null; rm -rf "$T"' EXIT
hive_fixture "$T" || exit 1
mkdir -p "$T/bin" "$T/state"
cat > "$T/bin/curl" <<'STUB'
#!/bin/bash
cfg=$(cat); data=""; w=""
while [ $# -gt 0 ]; do case $1 in -d) data=$2;; -w) w=$2;; esac; shift; done
[ -n "$data" ] && echo "SEND $data" >> "$HIVE_TEST_LOG"
[ -n "$w" ] && printf 200   # send reads the HTTP code (-w)
case $cfg in *poll=1*) ;; */json*) cat "$HIVE_TEST_STREAM" 2>/dev/null;; esac
exit 0
STUB
chmod +x "$T/bin/curl"
export PATH="$T/bin:$PATH" HIVE_STATE_DIR=$T/state HIVE_TEST_LOG=$T/calls.log HIVE_TEST_STREAM=$T/stream.json \
  HIVE_ASK_POLL=1 HIVE_ASK_BACKFILL_SEC=0
[ "$(command -v curl)" = "$T/bin/curl" ] || { echo "ask: stub curl not first on PATH; refusing to touch the network" >&2; exit 1; }
HIVE_ACCOUNT=carol . "$AG/hive-env.sh" || exit 1
echo "HIVE_MSG_TOPIC=hive-testtopic" > "$T/state/msg.conf"
INBOX=$T/state/msg-inbox.log; WAKE=$T/state/msg-wake.txt; OPEN=$T/state/ask-open.txt
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
ask() { HIVE_ACCOUNT=carol bash "$AG/hive-ask.sh" "$@"; }
# listen_until <id>: run the listener until it has taken message <id> from the stream (a slow machine needs more than a
# fixed sleep), give it a moment to write any wake, then stop it
listen_until() {
  HIVE_ACCOUNT=carol bash "$AG/hive-msg.sh" listen & LP=$!
  for _ in $(seq 1 150); do [ "$(cat "$T/state/.msg-last-id" 2>/dev/null)" = "$1" ] && break; sleep 0.1; done
  sleep 1; kill $LP 2>/dev/null; wait $LP 2>/dev/null
}
# the id of the newest ASK sent
sent_id() { sed -n 's/^SEND carol ASK @[^ ]* \[\(q[0-9]*\)\].*/\1/p' "$HIVE_TEST_LOG" | tail -n 1; }
# answer_when_asked <from> <text>: once an ASK is sent, append <from>'s ANSWER "[q<id>] <text>" to the inbox
answer_when_asked() {
  ( for _ in $(seq 1 300); do id=$(sent_id); [ -n "$id" ] && break; sleep 0.1; done
    echo "$(date -u +%s)|$1|ANSWER|[$id] $2" >> "$INBOX" ) &
}
now=$(date -u +%s)

# 1 the ASK is tagged and addressed; the answer is matched by id and printed without the tag
: > "$HIVE_TEST_LOG"; : > "$INBOX"
answer_when_asked bob "yes, the listener is up"
out=$(ask bob "is your listener up?" 60); rc=$?; wait
check "answered: exit" "$rc" 0
check "answered: text" "$out" "yes, the listener is up"
check "ask format" "$(grep -c '^SEND carol ASK @bob \[q[0-9]\{11,\}\] is your listener up? \[s[0-9]*/[0-9]*\]$' "$HIVE_TEST_LOG")" 1
check "answered: nothing left open" "$(cat "$OPEN" 2>/dev/null | wc -l | tr -d ' ')" 0

# 2 not crossed: another question's answer, the same id from the wrong account, and an untagged ANSWER are ignored
: > "$HIVE_TEST_LOG"
{ echo "$now|bob|ANSWER|[q1111111111999] an answer to someone else's question"
  echo "$now|bob|ANSWER|no tag at all"; } > "$INBOX"
( for _ in $(seq 1 300); do id=$(sent_id); [ -n "$id" ] && break; sleep 0.1; done
  echo "$(date -u +%s)|alice|ANSWER|[$id] wrong account" >> "$INBOX"; sleep 1.5
  echo "$(date -u +%s)|bob|ANSWER|[$id] the right one" >> "$INBOX" ) &
out=$(ask bob "which one?" 60); rc=$?; wait
check "not crossed: exit" "$rc" 0
check "not crossed: text" "$out" "the right one"

# 3 two questions in flight at once each get their own answer (90 s windows, longer than both 30 s send waits: on slow Windows the second ask can
#   take longer than 10 s to send, and each ask exits as soon as its answer lands)
: > "$HIVE_TEST_LOG"; : > "$INBOX"
ask bob "first?" 90 > "$T/a1" & A1=$!
for _ in $(seq 1 300); do id1=$(sent_id); [ -n "$id1" ] && break; sleep 0.1; done
[ -n "$id1" ] || { echo "FAIL in flight: first ask never sent"; fail=$((fail+1)); }
sleep 1.1   # a different epoch second, so the ids differ even if the random part collides
ask bob "second?" 90 > "$T/a2" & A2=$!
for _ in $(seq 1 300); do id2=$(sent_id); [ -n "$id2" ] && [ "$id2" != "$id1" ] && break; sleep 0.1; done
[ -n "$id2" ] && [ "$id2" != "$id1" ] || { echo "FAIL in flight: second ask never sent"; fail=$((fail+1)); }
{ echo "$(date -u +%s)|bob|ANSWER|[$id2] two"; echo "$(date -u +%s)|bob|ANSWER|[$id1] one"; } >> "$INBOX"
wait $A1; wait $A2
check "in flight: first" "$(cat "$T/a1")" "one"
check "in flight: second" "$(cat "$T/a2")" "two"

# 4 timeout: exit 1, the heartbeat message in ET, and the question stays open
: > "$HIVE_TEST_LOG"; hb=$(( $(date -u +%s) - 750 ))   # 12.5 min: half a minute clear of a boundary
echo "$hb|bob|HELLO|bob" > "$INBOX"
out=$(ask bob "anyone there?" 1); rc=$?
check "timeout: exit" "$rc" 1
check "timeout: message" "$out" "bob hasn't answered (last heartbeat $(( ($(date -u +%s) - hb) / 60 )) min ago, $(TZ=$HIVE_TZ hive_epoch_fmt "$hb" +%H:%M) ET)"
lid=$(sent_id)
check "timeout: left open" "$(grep -c "^$lid|bob|" "$OPEN")" 1
: > "$INBOX"
check "timeout, no heartbeat" "$(ask bob "still nobody?" 1)" "bob hasn't answered (no heartbeat on record)"

# 5 late answer: the listener wakes once with MSG ANSWER; another account's ANSWER with the id, and a repeat, do not
rm -f "$WAKE" "$T/state/.msg-last-id"
t=$(date -u +%s)
{ echo "{\"id\":\"m1\",\"time\":$t,\"event\":\"message\",\"message\":\"alice ANSWER [$lid] not yours\"}"
  echo "{\"id\":\"m2\",\"time\":$t,\"event\":\"message\",\"message\":\"bob ANSWER [q1111111111999] some other question\"}"; } > "$HIVE_TEST_STREAM"
listen_until m2
check "late: no wake for others" "$(cat "$WAKE" 2>/dev/null)" ""
rm -f "$T/state/.msg-last-id"
echo "{\"id\":\"m3\",\"time\":$t,\"event\":\"message\",\"message\":\"bob ANSWER [$lid] here now\"}" > "$HIVE_TEST_STREAM"
listen_until m3
check "late: wake" "$(cat "$WAKE" 2>/dev/null)" "MSG ANSWER bob [$lid] here now"
check "late: closed" "$(grep -c "^$lid|" "$OPEN")" 0
rm -f "$WAKE" "$T/state/.msg-last-id"
listen_until m3
check "late: wakes once" "$(cat "$WAKE" 2>/dev/null)" ""
# an open question older than 24h is dropped and never wakes
echo "q2222222222000|bob|$((now - 90000))" >> "$OPEN"; rm -f "$T/state/.msg-last-id"
echo "{\"id\":\"m4\",\"time\":$t,\"event\":\"message\",\"message\":\"bob ANSWER [q2222222222000] a day late\"}" > "$HIVE_TEST_STREAM"
listen_until m4
check "late: 24h expiry" "$(cat "$WAKE" 2>/dev/null)" ""

# 6 usage errors send nothing
: > "$HIVE_TEST_LOG"
ask carol "me?" >/dev/null 2>&1; check "self: exit" "$?" 2
ask nobody "who?" >/dev/null 2>&1; check "unknown account: exit" "$?" 2
ask bob "x" soon >/dev/null 2>&1; check "bad timeout: exit" "$?" 2
check "errors sent nothing" "$(grep -c SEND "$HIVE_TEST_LOG")" 0

# 7 an ASK wakes only its addressee: `@other` does not, `@me` does, a broadcast does
wake_for() { # <id> <message>: run the listener over one fresh ASK, print the wake it wrote
  rm -f "$WAKE" "$T/state/.msg-last-id"
  echo "{\"id\":\"$1\",\"time\":$(date -u +%s),\"event\":\"message\",\"message\":\"$2\"}" > "$HIVE_TEST_STREAM"
  listen_until "$1"; cat "$WAKE" 2>/dev/null
}
check "ask to other: no wake" "$(wake_for w1 'bob ASK @alice [q1] hello?')" ""
check "ask to me: wake" "$(wake_for w2 'bob ASK @carol [q2] hello?')" "MSG ASK bob @carol [q2] hello?"
check "ask to me, bare: wake" "$(wake_for w3 'bob ASK @carol')" "MSG ASK bob @carol"
check "ask to me with colon: wake" "$(wake_for w7 'bob ASK @carol: hello')" "MSG ASK bob @carol: hello"
check "ask to carolyn: no wake" "$(wake_for w4 'bob ASK @carolyn hi')" ""
check "broadcast ask: wake" "$(wake_for w5 'bob ASK anyone up?')" "MSG ASK bob anyone up?"
check "fire: wake" "$(wake_for w6 'bob FIRE peer-silent alice')" "MSG FIRE bob peer-silent alice"

echo "ask: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
