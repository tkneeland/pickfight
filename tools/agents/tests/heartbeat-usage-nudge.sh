#!/bin/bash
# Offline tests for the heartbeat's usage nudge (#1261): `pf-msg.sh heartbeat` asks a peer to fix its status line only
# when its newest USAGE (by message time) has no real 7-day numbers (a 1970 7-day reset or a ?% field), never for
# r5=1970 alone (5h window idle). Scratch PF_STATE_DIR, stub curl first on PATH logging every send. No network.
# macOS, Linux and Git Bash.   bash tools/agents/tests/heartbeat-usage-nudge.sh
AG=$(cd "$(dirname "$0")/.." && pwd)
# pf-env.sh sources the account conf after our exports, so the fixture needs a conf that sets neither of these
grep -qE '^(WATCH_PEERS|REPO_PATH)=' "$AG/accounts/schans2.conf" \
  && { echo "heartbeat-usage-nudge: accounts/schans2.conf sets WATCH_PEERS or REPO_PATH; this test needs them unset" >&2; exit 1; }
T=$(mktemp -d "${TMPDIR:-/tmp}/pf-nudge-test.XXXXXX"); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/state"
cat > "$T/bin/curl" <<'STUB'
#!/bin/bash
cat > /dev/null; data=""
while [ $# -gt 0 ]; do [ "$1" = -d ] && data=$2; shift; done
echo "SEND $data" >> "$PF_TEST_LOG"
exit 0
STUB
chmod +x "$T/bin/curl"
export PATH="$T/bin:$PATH" PF_STATE_DIR=$T/state PF_TEST_LOG=$T/calls.log WATCH_PEERS=agage-JG
unset PF_MSG_NOSEND
[ "$(command -v curl)" = "$T/bin/curl" ] || { echo "heartbeat-usage-nudge: stub curl not first on PATH" >&2; exit 1; }
PF_ACCOUNT=schans2 . "$AG/pf-env.sh" || exit 1
echo "PF_MSG_TOPIC=pf-testtopic" > "$T/state/pf-msg.conf"
INBOX=$T/state/msg-inbox.log; NUDGE=$T/state/.msg-usage-nudge-agage-JG
now=$(date -u +%s); far=2099-01-01T00:00:00Z; epoch0=1970-01-01T00:00:00Z   # epoch0: an unset reset time
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
stamped() { [ -f "$NUDGE" ] && echo yes || echo no; }
asks() { grep -c "schans2 ASK agage-JG: your USAGE reports no real numbers" "$PF_TEST_LOG"; }
# heartbeat: one pass as schans2 with a fresh send log (HELLO counts as just sent, so only ASKs reach the log)
heartbeat() { : > "$PF_TEST_LOG"; touch "$T/state/.msg-hello-last"; PF_ACCOUNT=schans2 bash "$AG/pf-msg.sh" heartbeat >/dev/null; }
# beat <USAGE text>: no nudge stamp, an older healthy line then <text> as the peer's newest USAGE, one heartbeat pass;
# prints how many ASKs went out
beat() {
  rm -f "$NUDGE"
  { echo "$((now - 600))|agage-JG|USAGE|10% 20% $far r5=$far agents=0"; echo "$((now - 60))|agage-JG|USAGE|$1"; } > "$INBOX"
  heartbeat; asks
}
check "healthy: no ASK" "$(beat "12% 20% $far r5=$far agents=1 at=$far")" 0
# the case from #1261: 5h block absent (0%, r5=1970), real 7-day numbers
check "idle 5h window: no ASK" "$(beat "0% 20% $far r5=$epoch0 agents=0 at=$far claude_at=$far")" 0
check "idle 5h window: no stamp" "$(stamped)" no
# no real 7-day numbers (empty snapshot, both resets 1970): ASK
check "all 1970: ASK" "$(beat "0% 0% $epoch0 r5=$epoch0 agents=0 at=$far")" 1
check "all 1970: stamp" "$(stamped)" yes
check "ASK quotes the line" "$(grep -c "no real numbers (0% 0% $epoch0 r5=$epoch0 agents=0 at=$far)" "$PF_TEST_LOG")" 1
# the next pass does not ask again (6h throttle); 6h later the still-broken peer is asked again
heartbeat; check "throttled: no second ASK" "$(asks)" 0
touch -t "$(pf_epoch_fmt "$((now - 21660))" +%Y%m%d%H%M.%S)" "$NUDGE"
heartbeat; check "after 6h: ASK again" "$(asks)" 1
# unknown percentages (older beacon format)
check "?% field: ASK" "$(beat "?% ?% $far r5=$far agents=0")" 1
# newest by message time, not file order: a newer healthy line written before an older broken one wins
rm -f "$NUDGE"
{ echo "$((now - 60))|agage-JG|USAGE|12% 20% $far r5=$far agents=1"
  echo "$((now - 3000))|agage-JG|USAGE|0% 0% $epoch0 r5=$epoch0 agents=0"; } > "$INBOX"
heartbeat; check "newest by time wins: no ASK" "$(asks)" 0
# no USAGE from the peer at all: nothing to judge, no ASK
rm -f "$NUDGE"; echo "$((now - 60))|agage-JG|HELLO|agage-JG" > "$INBOX"
heartbeat; check "no USAGE: no ASK" "$(asks)" 0
# PF_MSG_NOSEND sends nothing at all
rm -f "$NUDGE" "$T/state/.msg-hello-last"; : > "$PF_TEST_LOG"
echo "$((now - 60))|agage-JG|USAGE|0% 0% $epoch0 r5=$epoch0 agents=0" > "$INBOX"
PF_MSG_NOSEND=1 PF_ACCOUNT=schans2 bash "$AG/pf-msg.sh" heartbeat >/dev/null
check "NOSEND: nothing sent" "$(wc -l < "$PF_TEST_LOG" | tr -d ' ')" 0
echo "heartbeat-usage-nudge: $pass passed, $fail failed"; [ "$fail" = 0 ]
