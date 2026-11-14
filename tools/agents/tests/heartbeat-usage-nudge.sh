#!/bin/bash
# Offline tests for the heartbeat's usage nudge (#1261): `pf-msg.sh heartbeat` asks a peer to fix its status line only
# when its newest USAGE has no real numbers (7-day reset 1970 or a ?% field), never for r5=1970 alone (5h window idle).
# Scratch PF_STATE_DIR, stub curl first on PATH logging every send. No network. macOS, Linux and Git Bash.
#   bash tools/agents/tests/heartbeat-usage-nudge.sh
AG=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/pf-nudge-test.XXXXXX"); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/state"
cat > "$T/bin/curl" <<'STUB'
#!/bin/bash
cat > /dev/null; echo "curl $*" >> "$PF_TEST_LOG"
exit 0
STUB
chmod +x "$T/bin/curl"
export PATH="$T/bin:$PATH" PF_STATE_DIR=$T/state PF_TEST_LOG=$T/calls.log WATCH_PEERS=agage-JG
unset PF_MSG_NOSEND
PF_ACCOUNT=tkneeland . "$AG/pf-env.sh" || exit 1
echo "PF_MSG_TOPIC=pf-testtopic" > "$T/state/pf-msg.conf"
INBOX=$T/state/msg-inbox.log; NUDGE=$T/state/.msg-usage-nudge-agage-JG
now=$(date -u +%s); far=2099-01-01T00:00:00Z; epoch0=1970-01-01T00:00:00Z   # epoch0: an unset reset time
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
stamped() { [ -f "$NUDGE" ] && echo yes || echo no; }
asks() { grep -c "tkneeland ASK agage-JG: your USAGE reports no real numbers" "$PF_TEST_LOG"; }
# heartbeat: one pass as tkneeland with a fresh send log (HELLO counts as just sent, so only ASKs reach the log)
heartbeat() { : > "$PF_TEST_LOG"; touch "$T/state/.msg-hello-last"; PF_ACCOUNT=tkneeland bash "$AG/pf-msg.sh" heartbeat >/dev/null; }
# beat <USAGE text>: no nudge stamp, the peer's newest USAGE is <text>, one heartbeat pass; prints how many ASKs went out
beat() {
  rm -f "$NUDGE"
  { echo "$((now - 600))|agage-JG|USAGE|10% 20% $far r5=$far agents=0"; echo "$((now - 60))|agage-JG|USAGE|$1"; } > "$INBOX"
  heartbeat; asks
}
check "healthy: no ASK" "$(beat "12% 20% $far r5=$far agents=1 at=$far")" 0
# the case from #1261: 5h block absent (0%, r5=1970), real 7-day numbers
check "idle 5h window: no ASK" "$(beat "0% 20% $far r5=$epoch0 agents=0 at=$far claude_at=$far")" 0
check "idle 5h window: no stamp" "$(stamped)" no
# broken status line: empty snapshot, both resets 1970
check "all 1970: ASK" "$(beat "0% 0% $epoch0 r5=$epoch0 agents=0 at=$far")" 1
check "all 1970: stamp" "$(stamped)" yes
# the next pass does not ask again (6h throttle); 6h later the still-broken line is asked about again
heartbeat; check "throttled: no second ASK" "$(asks)" 0
touch -t "$(pf_epoch_fmt "$((now - 21660))" +%Y%m%d%H%M.%S)" "$NUDGE"
heartbeat; check "after 6h: ASK again" "$(asks)" 1
# unknown percentages from the status line
check "?% field: ASK" "$(beat "?% 20% $far r5=$far agents=0")" 1
# PF_MSG_NOSEND sends nothing at all
rm -f "$NUDGE"; rm -f "$T/state/.msg-hello-last"; : > "$PF_TEST_LOG"
PF_MSG_NOSEND=1 PF_ACCOUNT=tkneeland bash "$AG/pf-msg.sh" heartbeat >/dev/null
check "NOSEND: nothing sent" "$(wc -l < "$PF_TEST_LOG" | tr -d ' ')" 0
echo "heartbeat-usage-nudge: $pass passed, $fail failed"; [ "$fail" = 0 ]
