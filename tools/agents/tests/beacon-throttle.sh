#!/bin/bash
# Offline tests for the USAGE beacon throttle (#1263): `pf-beacon.sh --throttle` (what `windows/pf-supervise.sh beacon`
# runs every 5 min) sends at most once per 15 min on the stamp the status line shares, and a send refused by ntfy's
# daily quota (HTTP 429) logs "rate limited (retry in <n>s)" instead of a bare failure.
# Scratch PF_STATE_DIR, stub curl and gh first on PATH (curl logs every send), a scratch git repo. No network.
# macOS, Linux and Git Bash.   bash tools/agents/tests/beacon-throttle.sh
AG=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/pf-throttle-test.XXXXXX"); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/state"
# PF_TEST_429=1: answer like ntfy.sh over its quota (headers on stdout for -D -, exit 22 as curl -f does)
cat > "$T/bin/curl" <<'STUB'
#!/bin/bash
cat > /dev/null; echo "curl $*" >> "$PF_TEST_LOG"
if [ -n "${PF_TEST_429:-}" ]; then printf 'HTTP/1.1 429 Too Many Requests\r\nRetry-After: 3600\r\n\r\n'; exit 22; fi
printf 'HTTP/1.1 200 OK\r\n\r\n'; exit 0
STUB
printf '#!/bin/bash\nexit 0\n' > "$T/bin/gh"   # pf_live_agents asks gh for open issues: none
chmod +x "$T/bin/curl" "$T/bin/gh"
git init -q "$T/repo"; git -C "$T/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
export PATH="$T/bin:$PATH" PF_STATE_DIR=$T/state REPO_PATH=$T/repo PF_TEST_LOG=$T/calls.log
[ "$(command -v curl)" = "$T/bin/curl" ] || { echo "beacon-throttle: stub curl not first on PATH" >&2; exit 1; }
PF_ACCOUNT=schans2 . "$AG/pf-env.sh" || exit 1
echo "PF_MSG_TOPIC=pf-testtopic" > "$T/state/pf-msg.conf"
now=$(date +%s)
echo "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":5,\"resets_at\":$((now + 3600))},\"seven_day\":{\"used_percentage\":20,\"resets_at\":$((now + 4 * 86400))}}}" > "$T/state/usage-snapshot.json"
STAMP=$T/state/.beacon-stamp
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
sends() { grep -c "schans2 USAGE" "$PF_TEST_LOG"; }
beacon() { PF_ACCOUNT=schans2 bash "$AG/pf-beacon.sh" "$@"; echo $?; }
age_stamp() { touch -t "$(pf_epoch_fmt "$((now - $1))" +%Y%m%d%H%M.%S)" "$STAMP"; }   # age_stamp <seconds old>

# 1 no stamp yet: the first pass sends and starts the 15-min clock
: > "$PF_TEST_LOG"; rm -f "$STAMP"
check "first pass sends" "$(beacon --throttle)" 0
check "first pass: one USAGE" "$(sends)" 1
check "first pass: stamp written" "$([ -f "$STAMP" ] && echo yes || echo no)" yes
# 2 the next supervisor pass (5 min later, stamp fresh): no send, exit 3
age_stamp 300
check "second pass throttled" "$(beacon --throttle)" 3
check "two passes: still one USAGE" "$(sends)" 1
# 3 once the stamp is 15 min old the next pass sends again
age_stamp 960
check "after 15 min sends" "$(beacon --throttle)" 0
check "after 15 min: two USAGE" "$(sends)" 2
# 4 three hours of 5-min supervisor passes (36) send 12 USAGE, one per 15 min, so a day sends 96 instead of 288.
# Simulated clock: before each pass the stamp is aged to the time since the last send.
: > "$PF_TEST_LOG"; rm -f "$STAMP"; t=0; last=-1
while [ $t -lt 10800 ]; do
  [ $last -ge 0 ] && age_stamp $((t - last))
  PF_ACCOUNT=schans2 bash "$AG/pf-beacon.sh" --throttle && last=$t
  t=$((t + 300))
done
check "3h of 5-min passes: 12 USAGE" "$(sends)" 12
# 5 an unthrottled send (status line, pf-usage.sh first send) also resets the clock for the supervisor
: > "$PF_TEST_LOG"; age_stamp 3600
check "plain send" "$(beacon)" 0
check "supervisor after a plain send: throttled" "$(beacon --throttle)" 3
check "plain then throttled: one USAGE" "$(sends)" 1
# 6 ntfy over quota (429): exit 1, beacon.log says why; the slot was claimed before the send, so the next pass waits
# for the next 15-min slot instead of retrying every 5 min
: > "$PF_TEST_LOG"; : > "$T/state/beacon.log"; age_stamp 960
check "429 exits 1" "$(PF_TEST_429=1 beacon --throttle)" 1
check "429 logged" "$(sed 's/^[^ ]* //' "$T/state/beacon.log")" "USAGE send failed: rate limited (retry in 3600s)"
check "429: next pass throttled" "$(PF_TEST_429=1 beacon --throttle)" 3
# 6b the slot is claimed before the slow steps: a sender that starts while another is mid-send is throttled
age_stamp 960; : > "$PF_TEST_LOG"
mkdir -p "$T/slow"; printf '#!/bin/bash\nsleep 3; exec %q "$@"\n' "$T/bin/curl" > "$T/slow/curl"; chmod +x "$T/slow/curl"
PATH="$T/slow:$PATH" PF_ACCOUNT=schans2 bash "$AG/pf-beacon.sh" --throttle & slow=$!
sleep 1; check "concurrent sender throttled" "$(beacon --throttle)" 3
wait $slow; check "concurrent: one USAGE" "$(sends)" 1
# 7 pf-msg.sh send itself reports the 429 on stderr and exits 1
out=$(PF_TEST_429=1 PF_ACCOUNT=schans2 bash "$AG/pf-msg.sh" send INFO test 2>&1); rc=$?
check "send 429 message" "$out" "pf-msg: rate limited (retry in 3600s)"
check "send 429 exit" "$rc" 1
echo "beacon-throttle: $pass passed, $fail failed"; [ "$fail" = 0 ]
