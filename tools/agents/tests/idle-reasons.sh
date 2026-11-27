#!/bin/bash
# Offline test for issue #34: every message carries this account's daily send count (appended by hive-msg.sh send, stripped and
# recorded by the receiver), hive.sh status says why an account runs no workers or has a stale beacon (including this machine,
# with its pace), and hive-tm-check.sh does not flag a peer that line explains. Scratch HIVE_STATE_DIR, stub curl and gh.
# No network. macOS, Linux and Git Bash.   bash tools/agents/tests/idle-reasons.sh
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/hive-idle-test.XXXXXX") && [ -d "$T" ] || { echo "idle: cannot make a scratch dir" >&2; exit 1; }
T=$(cd "$T" && pwd) && case $T in */hive-idle-test.*) ;; *) echo "idle: odd scratch dir '$T'" >&2; exit 1;; esac
trap 'rm -rf "$T"' EXIT
hive_fixture "$T" "DISCORD=0" || exit 1
printf 'MIN_WEEKLY_REMAINING_FOR_TICKETS=10\n' >> "$AG/accounts/dave.conf"
mkdir -p "$T/bin" "$T/state"
# curl: records the posted body (-d) and answers a poll/stream from $HIVE_TEST_EVENTS (ntfy JSON lines)
cat > "$T/bin/curl" <<'STUB'
#!/bin/bash
cfg=$(cat | tr '\n' ' '); body=""; hdr=""; w=""
while [ $# -gt 0 ]; do case $1 in -d) body=$2; shift;; -D) hdr=$2; shift;; -w) w=$2; shift;; esac; shift; done
case $cfg in *"/json?"*) cat "$HIVE_TEST_EVENTS"; exit 0;; esac
echo "$body" >> "$HIVE_TEST_LOG"
[ -n "$hdr" ] && printf 'HTTP/1.1 200 X\r\n\r\n' > "$hdr"
[ -n "$w" ] && printf '200'
exit 0
STUB
cat > "$T/bin/gh" <<'STUB'
#!/bin/bash
case "$*" in
  "api user"*) echo carol;;
  "issue list"*"--assignee"*) echo "${HIVE_TEST_READY:-2}";;
  "issue list"*) echo 901;;
  "api --paginate repos/"*"/issues?state=open"*) echo '[]';;
  *) exit 1;;
esac
STUB
chmod +x "$T/bin/curl" "$T/bin/gh"; hive_stub_jq "$T/bin"
git init -q "$T/repo"; git -C "$T/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
export PATH="$T/bin:$PATH" HIVE_STATE_DIR=$T/state REPO_PATH=$T/repo HIVE_TEST_LOG=$T/sent.log HIVE_TEST_EVENTS=$T/events.json HIVE_ACCOUNT=carol
hive_require_stub "$T/bin" curl gh
S=$T/state; INBOX=$S/msg-inbox.log; : > "$HIVE_TEST_LOG"
echo "HIVE_MSG_TOPIC=hive-testtopic" > "$S/msg.conf"; echo alice > "$S/triagemaster"; echo '{}' > "$S/msg-status.json"
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
has() { case $2 in *"$3"*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL $1: no '$3' in:"; echo "$2" | sed 's/^/    /';; esac; }
lacks() { case $2 in *"$3"*) fail=$((fail+1)); echo "FAIL $1: unexpected '$3' in:"; echo "$2" | sed 's/^/    /';; *) pass=$((pass+1));; esac; }
now=$(date -u +%s); iso() { TZ=UTC hive_fmt "$1" +%Y-%m-%dT%H:%M:%SZ; }
. "$AG/hive-env.sh" || exit 1
iso() { TZ=UTC hive_fmt "$1" +%Y-%m-%dT%H:%M:%SZ; }

# 1 the send count goes out on every message and counts this one
bash "$AG/hive-msg.sh" send CLAIM 77; bash "$AG/hive-msg.sh" send ASK "@bob why?"
check "send 1 carries s1/100" "$(sed -n 1p "$HIVE_TEST_LOG")" "carol CLAIM 77 [s1/100]"
check "send 2 carries s2/100" "$(sed -n 2p "$HIVE_TEST_LOG")" "carol ASK @bob why? [s2/100]"
HIVE_MSG_DAILY_MAX=250 bash "$AG/hive-msg.sh" send INFO hi; has "max in the suffix" "$(sed -n 3p "$HIVE_TEST_LOG")" "[s3/250]"
check "self count read back" "$(hive_send_count carol)" "3 100"   # the file keeps today's count; max is the env's, default 100

# 2 the receiver strips it (backfill and listen) and records the newest count per account
ev() { printf '{"id":"%s","time":%s,"event":"message","message":"%s"}\n' "$1" "$2" "$3"; }
{ ev a1 $((now - 600)) "bob CLAIM 12 [s5/100]"; ev a2 $((now - 300)) "bob ASK @carol are you there? [s71/100]"; ev a3 $((now - 200)) "alice INFO plain old message"; } > "$T/events.json"
bash "$AG/hive-msg.sh" backfill
check "backfill strips the suffix" "$(grep -c '\[s' "$INBOX")" 0
has "backfill keeps the text" "$(cat "$INBOX")" "|bob|ASK|@carol are you there?"
check "old-format message untouched" "$(grep -c '|alice|INFO|plain old message$' "$INBOX")" 1
check "newest count recorded" "$(cut -d' ' -f2- "$S/.msg-sends-bob")" "71 100"
check "claimed still parses (exact number match)" "$(bash "$AG/hive-msg.sh" claimed 12; echo $?)" 0
rm -f "$INBOX" "$S/.msg-sends-bob" "$S/.msg-last-id"
( bash "$AG/hive-msg.sh" listen >/dev/null 2>&1 & lp=$!; sleep 4; kill "$lp" 2>/dev/null; wait "$lp" 2>/dev/null )
has "listen strips the suffix" "$(cat "$INBOX" 2>/dev/null)" "|bob|ASK|@carol are you there?"
check "listen leaves no suffix" "$(grep -c '\[s' "$INBOX" 2>/dev/null)" 0
check "listen recorded the count" "$(cut -d' ' -f2- "$S/.msg-sends-bob" 2>/dev/null)" "71 100"
pkill -f "hive-msg.sh listen" 2>/dev/null

# 3 reasons, one scenario each (hive_idle_reason, the function hive.sh status and tm-check call)
H=$(( $(date +%s) )); wk=$((H + 3 * 86400))
usage() {  # usage <handle> <age s> <5h%> <5h reset epoch> <7d%> <pace> <agents>
  echo "$((H - $2))|$1|USAGE|$3% $5% $(iso $wk) r5=$(iso $4) agents=$7 at=$(iso $((H - $2))) pace=$6"; }
: > "$INBOX"
{ usage bob 7200 40 $((H + 3600)) 20 ON_PACE 0; echo "$((H - 100))|bob|HELLO|bob"; } >> "$INBOX"; echo "$H 71 100" > "$S/.msg-sends-bob"
check "send cap" "$(hive_idle_reason bob 0 5)" "beacon held: send cap 71/100 (alive; check its CLAIMs/messages)"
echo "$H 40 100" > "$S/.msg-sends-bob"
check "stale, alive, under the cap: no reason (ASK it)" "$(hive_idle_reason bob 0 5)" ""
: > "$INBOX"; usage bob 7200 40 $((H + 3600)) 20 ON_PACE 0 >> "$INBOX"; echo "$((H - 7200))|bob|HELLO|bob" >> "$INBOX"
has "session down" "$(hive_idle_reason bob 0 5)" "session down? (no message in 120 min)"
: > "$INBOX"; usage bob 60 80 $((H + 14400)) 20 AHEAD 0 >> "$INBOX"
check "AHEAD with the numbers" "$(hive_idle_reason bob 0 5)" "held: AHEAD (5h 80%, target 20%)"
: > "$INBOX"; usage bob 60 10 $((H + 14400)) 20 AHEAD 0 >> "$INBOX"
check "weekly guard" "$(hive_idle_reason bob 0 5)" "held: weekly guard"
: > "$INBOX"; usage dave 60 10 $((H + 14400)) 95 AHEAD 0 >> "$INBOX"
check "weekly floor" "$(hive_idle_reason dave 0 5)" "held: weekly floor (95% of 90%)"
: > "$INBOX"; usage bob 60 95 $((H + 7200)) 20 AHEAD 0 >> "$INBOX"
check "5h stop" "$(hive_idle_reason bob 0 5)" "held: 5h stop (95% of 90%)"
: > "$INBOX"; usage bob 60 40 $((H + 9000)) 20 ON_PACE 0 >> "$INBOX"
check "no ready tickets" "$(hive_idle_reason bob 0 0)" "no ready tickets"
check "ready tickets, nothing else: unexplained" "$(hive_idle_reason bob 0 3)" ""
check "working account needs no reason" "$(hive_idle_reason bob 2 0)" ""

# 4 hive.sh status prints them, and this machine's line shows its pace
: > "$INBOX"
{ usage bob 7200 40 $((H + 3600)) 20 ON_PACE 0; echo "$((H - 100))|bob|HELLO|bob"; usage alice 60 40 $((H + 9000)) 20 ON_PACE 0; usage dave 60 10 $((H + 14400)) 95 AHEAD 0; } >> "$INBOX"
echo "$H 71 100" > "$S/.msg-sends-bob"
echo "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":80,\"resets_at\":$((H + 14400))},\"seven_day\":{\"used_percentage\":20,\"resets_at\":$wk}}}" > "$S/usage-snapshot.json"
out=$(bash "$AG/hive.sh" status)
l() { printf '%s\n' "$out" | grep "^$1 " | head -n 1; }
has "status: send cap" "$(l bob)" "beacon held: send cap 71/100"
has "status: no ready tickets" "$(l alice)" "no ready tickets"
has "status: weekly floor" "$(l dave)" "held: weekly floor (95% of 90%)"
has "status: self shows pace" "$(l carol)" "5h 80% AHEAD"
has "status: self reason" "$(l carol)" "held: AHEAD (5h 80%, target 20%)"
has "status --short carries it" "$(bash "$AG/hive.sh" status --short | grep '^bob:')" "beacon held: send cap 71/100"

# 5 tm-check: an explained peer is not flagged, an unexplained one is
rm -f "$S/.msg-sends-bob"; echo "$H 71 100" > "$S/.msg-sends-bob"
: > "$INBOX"; { usage bob 7200 40 $((H + 3600)) 20 ON_PACE 0; echo "$((H - 100))|bob|HELLO|bob"; usage alice 60 40 $((H + 9000)) 20 ON_PACE 0; } >> "$INBOX"
out=$(HIVE_TM_CHECK_SKIP_PROCS=1 HIVE_TEST_READY=2 bash "$AG/hive-tm-check.sh" 2>&1)
lacks "tm-check: explained peer not flagged" "$out" "WARN peer bob"
has "tm-check: explained peer is an INFO" "$out" "INFO peer bob: beacon held: send cap 71/100"
has "tm-check: unexplained peer is flagged" "$out" "WARN peer alice: agents 0"
out=$(HIVE_TM_CHECK_SKIP_PROCS=1 HIVE_TEST_READY=0 bash "$AG/hive-tm-check.sh" 2>&1)
has "tm-check: no ready tickets explains agents 0" "$out" "INFO peer alice: no ready tickets"

echo "idle-reasons: $pass passed, $fail failed"; [ "$fail" = 0 ]
