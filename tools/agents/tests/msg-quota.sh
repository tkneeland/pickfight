#!/bin/bash
# Offline tests for the channel send budget (issue #111): the daily budget in hive-msg.sh send, the 429 backoff, the
# access token, change-only USAGE (hive-beacon.sh), HELLO only after an hour of silence, peer-silent on any message,
# the quota marker (msg-status.json, status line) and the steady-state daily volume.
# Scratch HIVE_STATE_DIR, a curl shim (answers HIVE_TEST_CODE, default 200, with an optional Retry-After) and a gh stub
# first on PATH; HIVE_NOW pins the clock. No network. macOS, Linux and Git Bash.   bash tools/agents/tests/msg-quota.sh
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/hive-quota-test.XXXXXX") || exit 1; hive_test_guard
hive_fixture "$T" || exit 1
mkdir -p "$T/bin" "$T/state"
cat > "$T/bin/curl" <<'STUB'
#!/bin/bash
case " $* " in *" -K "*) cfg=$(cat | tr '\n' ' ');; *) cfg=;; esac; echo "curl $* | $cfg" >> "$HIVE_TEST_LOG"
code=${HIVE_TEST_CODE:-200}; hdr=""; w=""
while [ $# -gt 0 ]; do case $1 in -D) hdr=$2; shift;; -w) w=$2; shift;; esac; shift; done
if [ -n "$hdr" ]; then
  { printf 'HTTP/1.1 %s X\r\n' "$code"; [ -n "${HIVE_TEST_RA:-}" ] && printf 'retry-after: %s\r\n' "$HIVE_TEST_RA"; printf '\r\n'; } > "$hdr"
fi
[ -n "$w" ] && printf '%s' "$code"
exit 0
STUB
chmod +x "$T/bin/curl"; hive_noop_stub "$T/bin" gh; hive_stub_jq "$T/bin"
git init -q "$T/repo"
export PATH="$T/bin:$PATH" HIVE_STATE_DIR=$T/state REPO_PATH=$T/repo HIVE_ACCOUNT=alice HIVE_TEST_LOG=$T/calls.log WATCH_PEERS=bob
hive_require_stub "$T/bin" curl gh
S=$T/state; LOG=$S/beacon.log; INBOX=$S/msg-inbox.log
echo "HIVE_MSG_TOPIC=hive-testtopic" > "$S/msg.conf"
# 2026-11-14T13:30:00Z, a Saturday: 08:30 ET (EST)
base=1794663000
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
reset() { rm -f "$S"/.msg-* "$S"/.usage-* "$LOG" "$INBOX" "$S/msg-wake.txt" "$S/msg-status.json"; : > "$HIVE_TEST_LOG"; }
send() { bash "$AG/hive-msg.sh" send "$@" 2>/dev/null; }
sends() { grep -c "^curl " "$HIVE_TEST_LOG"; }
sent_type() { grep -c "alice $1 " "$HIVE_TEST_LOG"; }
export HIVE_NOW=$base
# The file runs one part so each stays under the watchdog on Git Bash, where a process spawn costs ~10x (issue #338):
#   msg-quota.sh [core]  sections 1-4 (budget, 429, quota marker, access token)
#   msg-quota.sh beacon  sections 5-8 (USAGE gate, HELLO, peer-silent, locks); the msg-beacon.sh wrapper runs it under all.sh
#   msg-quota.sh volume1|volume2|volume3  section 9 (24 h of steady-state sends in three 8 h slices); the msg-volume<N>.sh wrappers run them under all.sh
part=${1:-core}
case $part in core|beacon|volume[123]) ;; *) echo "usage: msg-quota.sh [core|beacon|volume1|volume2|volume3]" >&2; exit 2;; esac
snap() {  # snap <5h> <7d> <5h reset epoch>
  echo "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":$1,\"resets_at\":$3},\"seven_day\":{\"used_percentage\":$2,\"resets_at\":$((base + 4 * 86400))}}}" > "$S/usage-snapshot.json"; }
beacon() { HIVE_NOW=$((base + $1 * 60)) bash "$AG/hive-beacon.sh"; }   # beacon <minutes after base>
r5=$((base + 3 * 3600))

if [ "$part" = core ]; then
# 1 budget: with HIVE_MSG_DAILY_MAX=10, USAGE/HELLO/INFO stop at 7 sent today; priority types still go out
reset; export HIVE_MSG_DAILY_MAX=10
for i in 1 2 3 4 5 6 7; do send INFO "note $i"; done
check "budget: 7 INFO sent" "$(sent_type INFO)" 7
send INFO "note 8"; check "budget: 8th INFO dropped (rc)" "$?" 4
send HELLO alice; send USAGE "1% 2%"
check "budget: INFO dropped" "$(sent_type INFO)" 7
check "budget: HELLO dropped" "$(sent_type HELLO)" 0
check "budget: USAGE dropped" "$(sent_type USAGE)" 0
check "budget: each drop logged" "$(grep -c 'dropped' "$LOG")" 3
check "budget: drop names the type" "$(grep -c 'dropped HELLO' "$LOG")" 1
for t in CLAIM RELEASE ASK ANSWER FIRE TM; do send $t "x"; done
for i in 1 2 3 4; do send CLAIM "$i"; done
check "budget: priority types all sent past the budget" "$(sends)" 17
HIVE_NOW=$((base + 86400)) send INFO "next day"
check "budget: a new UTC day starts a fresh count" "$(sent_type INFO)" 8
unset HIVE_MSG_DAILY_MAX
reset; for i in 1 2 3 4 5 6 7 8 9 10; do send INFO "n$i"; done
check "budget: default 100 lets 10 INFO through" "$(sent_type INFO)" 10

# 2 HTTP 429: back off until now + retry-after, logged once; nothing is sent until then; header dump cleaned up
reset
HIVE_TEST_CODE=429 HIVE_TEST_RA=40000 send CLAIM 5; check "429: send fails" "$?" 3
check "429: backoff until now + retry-after" "$(cat "$S/.msg-backoff-until")" $((base + 40000))
HIVE_TEST_CODE=429 HIVE_TEST_RA=40000 send FIRE "x"; HIVE_NOW=$((base + 39000)) send CLAIM 6
check "429: no curl call during backoff" "$(sends)" 1
check "429: logged once" "$(grep -c '429' "$LOG")" 1
check "429: log names the until time" "$(grep -c 'until 2026-11-15T00:36:40Z' "$LOG")" 1
check "429: header dump removed" "$(ls -A "$S" | grep -c hdr)" 0
HIVE_NOW=$((base + 40001)) send CLAIM 7; check "429: sends resume after the until time" "$?" 0
check "429: one more curl call" "$(sends)" 2
reset; HIVE_TEST_CODE=429 send CLAIM 5
check "429 without retry-after: back off 1 h" "$(cat "$S/.msg-backoff-until")" $((base + 3600))
# other failures are logged with their HTTP code, and do not back off
reset; HIVE_TEST_CODE=500 send CLAIM 5; check "500: send fails" "$?" 1
check "500: logged with the code" "$(grep -c 'CLAIM failed: HTTP 500' "$LOG")" 1
check "500: no backoff" "$([ -f "$S/.msg-backoff-until" ] && echo yes || echo no)" no

# 3 quota marker: hive-msg.sh status writes msg-status.json with quota; the status line shows msg:quota til HH:MM (local)
reset; HIVE_TEST_CODE=429 HIVE_TEST_RA=7200 send CLAIM 5
bash "$AG/hive-msg.sh" status "listener pid 42"
check "status: quota until" "$(jq -r .quota "$S/msg-status.json")" "2026-11-14T15:30:00Z"
check "status: still running" "$(jq -r .state "$S/msg-status.json")" running
check "status: line kept" "$(jq -r .line "$S/msg-status.json")" "listener pid 42"
sl=$(echo '{"model":{"display_name":"M"}}' | HIVE_DRY_RUN=1 bash "$AG/statusline.sh" | head -n 1)
check "status line: quota marker in local time" "$(echo "$sl" | grep -o 'msg:quota til [0-9:]*')" "msg:quota til 10:30"
HIVE_NOW=$((base + 7201)) bash "$AG/hive-msg.sh" status "listener pid 42"
check "status: quota null after the until time" "$(jq -r .quota "$S/msg-status.json")" null
sl=$(echo '{"model":{"display_name":"M"}}' | HIVE_NOW=$((base + 7201)) HIVE_DRY_RUN=1 bash "$AG/statusline.sh" | head -n 1)
check "status line: no marker after" "$(echo "$sl" | grep -c 'msg:quota')" 0

# 4 access token: sent as a Bearer header through the curl config on stdin, never in argv; text holding it is refused
reset; printf 'HIVE_MSG_TOPIC=hive-testtopic\nHIVE_MSG_TOKEN="tk_secret123"\r\n' > "$S/msg.conf"
send CLAIM 9
check "token: Authorization header in the config" "$(grep -c '| .*header = "Authorization: Bearer tk_secret123"' "$HIVE_TEST_LOG")" 1
check "token: not in argv" "$(sed 's/ | .*//' "$HIVE_TEST_LOG" | grep -c tk_secret123)" 0
send INFO "oops tk_secret123"; check "token: text containing it refused" "$?" 1
check "token: refused text not sent" "$(sends)" 1
echo "HIVE_MSG_TOPIC=hive-testtopic" > "$S/msg.conf"; : > "$HIVE_TEST_LOG"; send CLAIM 9
check "no token: no Authorization header" "$(grep -c Authorization "$HIVE_TEST_LOG")" 0
# the leak check covers the token too
printf 'HIVE_MSG_TOPIC=hive-testtopic\nHIVE_MSG_TOKEN=tk_secret123\n' > "$S/msg.conf"
echo "tk_secret123" > "$T/repo/leak.txt"; git -C "$T/repo" add leak.txt
check "leakcheck: token found" "$(bash "$AG/hive-msg-leakcheck.sh" "$T/repo" >/dev/null; echo $?)" 1
git -C "$T/repo" rm -q --cached leak.txt; rm -f "$T/repo/leak.txt"
echo "HIVE_MSG_TOPIC=hive-testtopic" > "$S/msg.conf"

fi
if [ "$part" = beacon ]; then
# 5 USAGE only on change (hive-beacon.sh): 5 points on 5h or 7d, a new 5h reset, else hourly; never within 10 min
reset; snap 10 20 $r5
beacon 0; check "usage: first beacon sent" "$(sent_type USAGE)" 1
beacon 5; check "usage: unchanged at +5 min exits 0" "$?" 0
check "usage: unchanged at +5 min not sent" "$(sent_type USAGE)" 1
snap 14 24 $r5; beacon 15; check "usage: 4 points is no change" "$(sent_type USAGE)" 1
snap 15 24 $r5; beacon 20; check "usage: 5h moved 5 points: sent" "$(sent_type USAGE)" 2
snap 40 24 $r5; beacon 25; check "usage: change within 10 min held back" "$(sent_type USAGE)" 2
beacon 31; check "usage: held change sent after 10 min" "$(sent_type USAGE)" 3
snap 40 29 $r5; beacon 45; check "usage: 7d moved 5 points: sent" "$(sent_type USAGE)" 4
snap 40 29 $((r5 + 5 * 3600)); beacon 60; check "usage: new 5h reset: sent" "$(sent_type USAGE)" 5
beacon 100; check "usage: unchanged 40 min later: not sent" "$(sent_type USAGE)" 5
beacon 121; check "usage: hourly keepalive" "$(sent_type USAGE)" 6
check "usage: gate skips are not logged" "$(grep -c USAGE "$LOG" 2>/dev/null || true)" 0

# 6 HELLO only when this account sent nothing for 60 min
reset; echo $((base - 1800)) > "$S/.msg-last-sent"
bash "$AG/hive-msg.sh" heartbeat >/dev/null; check "hello: sent 30 min ago: no HELLO" "$(sent_type HELLO)" 0
HIVE_NOW=$((base + 1801)) bash "$AG/hive-msg.sh" heartbeat >/dev/null; check "hello: silent 60 min: HELLO" "$(sent_type HELLO)" 1
HIVE_NOW=$((base + 1900)) bash "$AG/hive-msg.sh" heartbeat >/dev/null; check "hello: the HELLO counts as a send" "$(sent_type HELLO)" 1
reset; bash "$AG/hive-msg.sh" heartbeat >/dev/null; check "hello: never sent: HELLO" "$(sent_type HELLO)" 1

# 7 peer-silent: any message from the peer counts; the threshold is 2 h
silent() { rm -f "$S"/.msg-silent-* "$S/msg-wake.txt"; echo "$base" > "$S/.msg-last-sent"; HIVE_MSG_NOSEND=1 bash "$AG/hive-msg.sh" heartbeat >/dev/null; cat "$S/msg-wake.txt" 2>/dev/null; }
reset; { echo "$((base - 4 * 3600))|bob|HELLO|bob"; echo "$((base - 1800))|bob|CLAIM|12"; } > "$INBOX"
check "silent: a CLAIM 30 min ago keeps bob alive" "$(silent)" ""
{ echo "$((base - 4 * 3600))|bob|HELLO|bob"; echo "$((base - 5400))|bob|USAGE|1% 2%"; } > "$INBOX"
check "silent: 90 min is under the 2 h threshold" "$(silent)" ""
{ echo "$((base - 4 * 3600))|bob|HELLO|bob"; echo "$((base - 7500))|bob|INFO|hi"; } > "$INBOX"
check "silent: 2h05m wakes" "$(silent)" "MSG FIRE peer-silent bob (last message 2026-11-14T11:25:00Z)"
check "silent: no HELLO under NOSEND" "$(sends)" 0

# 8 one listener and one supervisor per HIVE_STATE: a live pid in msg-listen.pid / msg-run.pid makes a second one exit at
# once; a stale pid (dead process) is taken over; the lock is released on exit
quick() {  # quick <cmd...>: "rc=<n>" when it exits within 5 s, else "hung" (then killed)
  "$@" > "$T/q.out" 2>&1 </dev/null & local p=$! i=0
  while kill -0 $p 2>/dev/null && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
  if kill -0 $p 2>/dev/null; then hive_kill_tree $p; wait $p 2>/dev/null; echo hung; else wait $p; echo "rc=$?"; fi; }
reset; sleep 30 & holder=$!; HIVE_TEST_PIDS="$HIVE_TEST_PIDS $holder"; echo $holder > "$S/msg-listen.pid"
check "lock: second listener exits at once" "$(quick bash "$AG/hive-msg.sh" listen)" "rc=0"
check "lock: says it is already running" "$(grep -c 'already running' "$T/q.out")" 1
check "lock: holder's pid kept" "$(cat "$S/msg-listen.pid")" "$holder"
echo $holder > "$S/msg-run.pid"
check "lock: second supervisor exits at once" "$(quick bash "$AG/hive-msg.sh" run)" "rc=0"
check "lock: windows supervisor shares the run lock" "$(quick bash "$AG/windows/hive-supervise.sh" msg)" "rc=0"
kill $holder; wait $holder 2>/dev/null
bash "$AG/hive-msg.sh" listen 2>/dev/null </dev/null & lp=$!; HIVE_TEST_PIDS="$HIVE_TEST_PIDS $lp"
i=0; while [ "$(cat "$S/msg-listen.pid" 2>/dev/null)" != "$lp" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
check "lock: stale pid taken over" "$(cat "$S/msg-listen.pid" 2>/dev/null)" "$lp"
hive_kill_tree $lp; wait $lp 2>/dev/null
check "lock: released on exit" "$([ -f "$S/msg-listen.pid" ] && echo held || echo gone)" gone
rm -f "$S/msg-run.pid"

fi
case $part in volume?)
# 9 steady-state volume: 24 h of unchanged usage, the beacon and the heartbeat every 10 min: <= 60 sends. Run as three 8 h slices
# (volume1..3, each its own file under all.sh and so its own watchdog), each <= 20 sends, so the three together stay <= 60.
reset; snap 10 20 $r5
# every iteration starts two bash scripts; a Windows process spawn is ~10x slower, so Git Bash samples every 30 min (still <= 20)
step=10; [ "$HIVE_TEST_WIN" = 1 ] && step=30
k=${part#volume}; m=$(( (k - 1) * 480 )); end=$(( k * 480 ))
while [ $m -lt $end ]; do
  HIVE_NOW=$((base + m * 60)) bash "$AG/hive-beacon.sh"
  HIVE_NOW=$((base + m * 60)) bash "$AG/hive-msg.sh" heartbeat >/dev/null
  m=$((m + step))
done
n=$(sends); check "volume: at most 20 sends in 8 h slice $k (got $n)" "$([ "$n" -le 20 ] && echo ok)" ok
;; esac
echo "msg-quota${1:+ $1}: $pass passed, $fail failed"; [ "$fail" = 0 ]
