#!/bin/bash
# Offline tests for the USAGE beacon throttle (#1263): `pf-beacon.sh --throttle` (what `windows/pf-supervise.sh beacon`
# runs every 5 min, and pf-usage.sh) sends at most once per 15 min on the stamp the status line shares, claims that slot
# before its slow steps, and a send refused by ntfy's daily quota (HTTP 429) is logged with its retry time, after which
# pf-msg.sh fails fast until then.
# Scratch PF_STATE_DIR and HOME, stub curl/gh/security first on PATH (curl logs every send), a scratch git repo.
# No network. macOS, Linux and Git Bash.   bash tools/agents/tests/beacon-throttle.sh
AG=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/pf-throttle-test.XXXXXX"); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/state" "$T/home/.claude"
# curl stub. PF_TEST_429=<Retry-After value>: answer like ntfy.sh over its quota (headers on stdout for -D -, exit 22 as
# curl -f does). Each send logs whether .beacon-stamp was already newer than the $PF_TEST_MARK file at call time (bash -nt,
# portable), to prove the slot was claimed first. The OAuth usage endpoint (pf-usage.sh) answers with $PF_TEST_USAGE.
cat > "$T/bin/curl" <<'STUB'
#!/bin/bash
cat > /dev/null
case "$*" in *api/oauth/usage*) cat "$PF_TEST_USAGE"; exit 0;; esac
claimed=no; [ "$PF_STATE_DIR/.beacon-stamp" -nt "$PF_TEST_MARK" ] && claimed=yes
echo "curl claimed=$claimed $*" >> "$PF_TEST_LOG"
if [ -n "${PF_TEST_429:-}" ]; then printf 'HTTP/1.1 429 Too Many Requests\r\nRetry-After: %s\r\n\r\n' "$PF_TEST_429"; exit 22; fi
printf 'HTTP/1.1 200 OK\r\n\r\n'; exit 0
STUB
printf '#!/bin/bash\nexit 0\n' > "$T/bin/gh"         # pf_live_agents asks gh for open issues: none
printf '#!/bin/bash\nexit 1\n' > "$T/bin/security"   # pf-usage.sh: never the real macOS keychain
chmod +x "$T/bin/curl" "$T/bin/gh" "$T/bin/security"
git init -q "$T/repo"; git -C "$T/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
export PATH="$T/bin:$PATH" PF_STATE_DIR=$T/state REPO_PATH=$T/repo PF_TEST_LOG=$T/calls.log HOME=$T/home PF_TEST_USAGE=$T/usage.json \
  PF_TEST_MARK=$T/mark
unset PF_TEST_429
[ "$(command -v curl)" = "$T/bin/curl" ] || { echo "beacon-throttle: stub curl not first on PATH" >&2; exit 1; }
PF_ACCOUNT=schans2 . "$AG/pf-env.sh" || exit 1
echo "PF_MSG_TOPIC=pf-testtopic" > "$T/state/pf-msg.conf"
now=$(date +%s)
SNAP=$T/state/usage-snapshot.json
good_snap() { echo "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":5,\"resets_at\":$((now + 3600))},\"seven_day\":{\"used_percentage\":20,\"resets_at\":$((now + 4 * 86400))}}}" > "$SNAP"; }
good_snap
STAMP=$T/state/.beacon-stamp; FAILED=$T/state/.beacon-failed; BLOCK=$T/state/.msg-blocked-until
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
sends() { grep -c "schans2 USAGE" "$PF_TEST_LOG"; }
exists() { [ -f "$1" ] && echo yes || echo no; }
beacon() { PF_ACCOUNT=schans2 bash "$AG/pf-beacon.sh" "$@"; echo $?; }
age_stamp() { touch -t "$(pf_epoch_fmt "$((now - $1))" +%Y%m%d%H%M.%S)" "$STAMP"; }   # age_stamp <seconds old>

# 1 no stamp yet: the first pass sends and starts the 15-min clock, claiming the slot before the send (the mark is a
# minute old, so only a stamp touched before curl ran is newer than it)
: > "$PF_TEST_LOG"; rm -f "$STAMP"; touch -t "$(pf_epoch_fmt "$((now - 60))" +%Y%m%d%H%M.%S)" "$PF_TEST_MARK"
check "first pass sends" "$(beacon --throttle)" 0
check "first pass: one USAGE" "$(sends)" 1
check "slot claimed before the send" "$(grep -c '^curl claimed=yes .*schans2 USAGE' "$PF_TEST_LOG")" 1
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
# 6 a corrupt snapshot does not claim the slot
age_stamp 960; echo '{"rate_limits": {' > "$SNAP"
check "bad snapshot exits 1" "$(beacon --throttle)" 1
check "bad snapshot: slot not claimed" "$(( $(date +%s) - $(pf_mtime "$STAMP") >= 900 ))" 1
good_snap
# 7 ntfy over quota (429): exit 1, beacon.log says why, .beacon-failed holds it; the slot stays claimed, so the next
# pass waits for the next 15-min slot, and the supervisor can tell that exit 3 from a healthy one
: > "$PF_TEST_LOG"; : > "$T/state/beacon.log"; age_stamp 960
check "429 exits 1" "$(PF_TEST_429=3600 beacon --throttle)" 1
check "429 logged" "$(sed 's/^[^ ]* //' "$T/state/beacon.log")" "USAGE send failed: rate limited (retry in 3600s)"
check "429: failure recorded" "$(cat "$FAILED" 2>/dev/null)" "USAGE send failed: rate limited (retry in 3600s)"
check "429: next pass throttled" "$(beacon --throttle)" 3
# 8 after a 429 pf-msg.sh fails fast until Retry-After, without calling ntfy again
: > "$PF_TEST_LOG"
out=$(PF_ACCOUNT=schans2 bash "$AG/pf-msg.sh" send INFO test 2>&1); rc=$?
check "blocked send exit" "$rc" 1
check "blocked send says why" "$(echo "$out" | sed 's/[0-9][0-9]*s)/Ns)/')" "pf-msg: rate limited (retry in Ns)"
check "blocked send: no request" "$(wc -l < "$PF_TEST_LOG" | tr -d ' ')" 0
# 9 once the block has passed, a successful send clears it and the failure flag
echo $((now - 1)) > "$BLOCK"; age_stamp 960; : > "$PF_TEST_LOG"
check "send after the block" "$(beacon --throttle)" 0
check "block cleared" "$(exists "$BLOCK")" no
check "failure flag cleared" "$(exists "$FAILED")" no
# 10 a Retry-After in seconds is capped at 24h; an HTTP-date is reported as is and sets no block
: > "$PF_TEST_LOG"; rm -f "$BLOCK"
out=$(PF_TEST_429=999999 PF_ACCOUNT=schans2 bash "$AG/pf-msg.sh" send INFO test 2>&1)
check "429 capped at 24h" "$out" "pf-msg: rate limited (retry in 86400s)"
check "24h block set" "$(( $(cat "$BLOCK") - $(date -u +%s) <= 86400 ))" 1
rm -f "$BLOCK"
out=$(PF_TEST_429="Sat, 14 Nov 2026 20:00:00 GMT" PF_ACCOUNT=schans2 bash "$AG/pf-msg.sh" send INFO test 2>&1); rc=$?
check "429 HTTP-date" "$out" "pf-msg: rate limited (retry after Sat, 14 Nov 2026 20:00:00 GMT)"
check "429 HTTP-date exit" "$rc" 1
check "429 HTTP-date: no block" "$(exists "$BLOCK")" no
# 11 pf-usage.sh: a hold-back by the 15-min clock is not a failure (exit 0) and keeps the new numbers pending, so the
# next run sends them even though the snapshot already holds them
usage_json() { echo "{\"five_hour\":{\"utilization\":$1,\"resets_at\":\"2099-01-01T00:00:00Z\"},\"seven_day\":{\"utilization\":20,\"resets_at\":\"2099-01-02T00:00:00Z\"}}" > "$PF_TEST_USAGE"; }
usage() { PF_ACCOUNT=schans2 bash "$AG/pf-usage.sh"; echo $?; }
echo "{\"claudeAiOauth\":{\"accessToken\":\"test-token\",\"expiresAt\":$(( (now + 86400) * 1000 ))}}" > "$T/home/.claude/.credentials.json"
rm -f "$STAMP" "$T/state/.pf-usage-beacon" "$T/state/.pf-usage-pending"; good_snap; : > "$PF_TEST_LOG"
usage_json 20; check "usage: first run sends" "$(usage)" 0
check "usage: one USAGE" "$(sends)" 1
usage_json 35; check "usage: changed within 15 min: exit 0" "$(usage)" 0
check "usage: held back" "$(sends)" 1
check "usage: pending kept" "$(exists "$T/state/.pf-usage-pending")" yes
age_stamp 960; check "usage: same numbers next run" "$(usage)" 0
check "usage: pending sent" "$(sends)" 2
check "usage: pending cleared" "$(exists "$T/state/.pf-usage-pending")" no
echo "beacon-throttle: $pass passed, $fail failed"; [ "$fail" = 0 ]
