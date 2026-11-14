#!/bin/bash
# Offline tests for the heartbeat's usage nudge (#1261): `pf-msg.sh heartbeat` asks a peer to fix its status line only
# when its newest USAGE has no real 7-day numbers AND comes from a stale snapshot (at= over 1h old) in a beacon sent in
# the last 6h. Idle windows (r5=1970 at night, a 1970 7-day reset after a week without use) with a fresh snapshot are
# healthy. Scratch PF_STATE_DIR, stub curl first on PATH logging every send. No network. macOS, Linux and Git Bash.
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
# runs as schans2, whose conf sets no WATCH_PEERS, so this export is the peer list the heartbeat uses
export PATH="$T/bin:$PATH" PF_STATE_DIR=$T/state PF_TEST_LOG=$T/calls.log WATCH_PEERS=agage-JG
unset PF_MSG_NOSEND
PF_ACCOUNT=schans2 . "$AG/pf-env.sh" || exit 1
echo "PF_MSG_TOPIC=pf-testtopic" > "$T/state/pf-msg.conf"
INBOX=$T/state/msg-inbox.log; NUDGE=$T/state/.msg-usage-nudge-agage-JG
now=$(date -u +%s); far=2099-01-01T00:00:00Z; epoch0=1970-01-01T00:00:00Z   # epoch0: an unset reset time
iso() { TZ=UTC pf_epoch_fmt "$1" +%Y-%m-%dT%H:%M:%SZ; }
fresh=$(iso $((now - 120))); stale=$(iso $((now - 2 * 86400)))   # snapshot times (at=): 2 min / 2 days old
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
stamped() { [ -f "$NUDGE" ] && echo yes || echo no; }
asks() { grep -c "schans2 ASK agage-JG: your USAGE reports no real numbers" "$PF_TEST_LOG"; }
# heartbeat: one pass as schans2 with a fresh send log (HELLO counts as just sent, so only ASKs reach the log)
heartbeat() { : > "$PF_TEST_LOG"; touch "$T/state/.msg-hello-last"; PF_ACCOUNT=schans2 bash "$AG/pf-msg.sh" heartbeat >/dev/null; }
# beat <USAGE text> [sent seconds ago]: no nudge stamp, an older healthy line then <text> as the peer's newest USAGE
# (sent 60 s ago unless given), one heartbeat pass; prints how many ASKs went out
beat() {
  rm -f "$NUDGE"
  { echo "$((now - 99999))|agage-JG|USAGE|10% 20% $far r5=$far agents=0 at=$(iso $((now - 99999)))"
    echo "$((now - ${2:-60}))|agage-JG|USAGE|$1"; } > "$INBOX"
  heartbeat; asks
}
check "healthy: no ASK" "$(beat "12% 20% $far r5=$far agents=1 at=$fresh")" 0
# the case from #1261: 5h block absent (0%, r5=1970), real 7-day numbers, fresh snapshot
check "idle 5h window: no ASK" "$(beat "0% 20% $far r5=$epoch0 agents=0 at=$fresh claude_at=$fresh")" 0
check "idle 5h window: no stamp" "$(stamped)" no
# a week without use (or just past the weekly reset): both blocks absent, snapshot still being rewritten
check "idle week, fresh snapshot: no ASK" "$(beat "0% 0% $epoch0 r5=$epoch0 agents=0 at=$fresh")" 0
# broken setup (#1189): empty snapshot nobody rewrites, beacon still going out
check "broken (stale empty snapshot): ASK" "$(beat "0% 0% $epoch0 r5=$epoch0 agents=0 at=$stale")" 1
check "broken: stamp" "$(stamped)" yes
# the next pass does not ask again (6h throttle); 6h later the still-broken line is asked about again
heartbeat; check "throttled: no second ASK" "$(asks)" 0
touch -t "$(pf_epoch_fmt "$((now - 21660))" +%Y%m%d%H%M.%S)" "$NUDGE"
heartbeat; check "after 6h: ASK again" "$(asks)" 1
# unknown percentages (older beacon format) from a stale snapshot
check "?% field, stale snapshot: ASK" "$(beat "?% ?% $far r5=$far agents=0 at=$stale")" 1
# a peer that is off: its newest beacon (broken) went out 3 days ago; peer-silent covers it, no ASK every 6h
check "peer off for days: no ASK" "$(beat "0% 0% $epoch0 r5=$epoch0 agents=0 at=$stale" $((3 * 86400)))" 0
# order by message time, not file order: a newer healthy line written before an older broken one wins
rm -f "$NUDGE"
{ echo "$((now - 60))|agage-JG|USAGE|12% 20% $far r5=$far agents=1 at=$fresh"
  echo "$((now - 3000))|agage-JG|USAGE|0% 0% $epoch0 r5=$epoch0 agents=0 at=$stale"; } > "$INBOX"
heartbeat; check "newest by time wins: no ASK" "$(asks)" 0
# PF_MSG_NOSEND sends nothing at all
rm -f "$NUDGE" "$T/state/.msg-hello-last"; : > "$PF_TEST_LOG"
echo "$((now - 60))|agage-JG|USAGE|0% 0% $epoch0 r5=$epoch0 agents=0 at=$stale" > "$INBOX"
PF_MSG_NOSEND=1 PF_ACCOUNT=schans2 bash "$AG/pf-msg.sh" heartbeat >/dev/null
check "NOSEND: nothing sent" "$(wc -l < "$PF_TEST_LOG" | tr -d ' ')" 0
echo "heartbeat-usage-nudge: $pass passed, $fail failed"; [ "$fail" = 0 ]
