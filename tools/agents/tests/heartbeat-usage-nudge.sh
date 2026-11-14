#!/bin/bash
# Offline tests for the heartbeat's usage nudge (#1261). pf-beacon.sh marks each USAGE sl=ok (snapshot has rate_limits),
# sl=nolimits (status line JSON without them) or sl=none (nothing ever wrote the snapshot), the two #1189 setups.
# `pf-msg.sh heartbeat` asks a peer to fix its setup only for nolimits/none (beacons from before sl=: a 1970 7-day reset
# or a ?% field), in a beacon sent in the last 6h. Idle windows (r5=1970 at night, a 1970 7-day reset after a week
# without use) are healthy.
# Scratch PF_STATE_DIR and git repo, stub curl and gh first on PATH. No network. macOS, Linux and Git Bash.
#   bash tools/agents/tests/heartbeat-usage-nudge.sh
AG=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/pf-nudge-test.XXXXXX"); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/state"
cat > "$T/bin/curl" <<'STUB'
#!/bin/bash
cat > /dev/null; data=""
while [ $# -gt 0 ]; do [ "$1" = -d ] && data=$2; shift; done
echo "SEND $data" >> "$PF_TEST_LOG"
exit 0
STUB
printf '#!/bin/bash\nexit 0\n' > "$T/bin/gh"   # pf_live_agents asks gh for open issues: none
chmod +x "$T/bin/curl" "$T/bin/gh"
git init -q "$T/repo"; git -C "$T/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
# runs as schans2, whose conf sets neither WATCH_PEERS nor REPO_PATH, so these exports are what the scripts use
export PATH="$T/bin:$PATH" PF_STATE_DIR=$T/state PF_TEST_LOG=$T/calls.log WATCH_PEERS=agage-JG REPO_PATH=$T/repo
unset PF_MSG_NOSEND
[ "$(command -v curl)" = "$T/bin/curl" ] || { echo "heartbeat-usage-nudge: stub curl not first on PATH" >&2; exit 1; }
PF_ACCOUNT=schans2 . "$AG/pf-env.sh" || exit 1
echo "PF_MSG_TOPIC=pf-testtopic" > "$T/state/pf-msg.conf"
INBOX=$T/state/msg-inbox.log; NUDGE=$T/state/.msg-usage-nudge-agage-JG; SNAP=$T/state/usage-snapshot.json
now=$(date -u +%s); far=2099-01-01T00:00:00Z; epoch0=1970-01-01T00:00:00Z   # epoch0: an unset reset time
at="at=$(TZ=UTC pf_epoch_fmt "$((now - 120))" +%Y-%m-%dT%H:%M:%SZ)"
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
  { echo "$((now - 99999))|agage-JG|USAGE|10% 20% $far r5=$far agents=0 $at sl=ok"; echo "$((now - ${2:-60}))|agage-JG|USAGE|$1"; } > "$INBOX"
  heartbeat; asks
}
# beacon_sl <snapshot json>: the sl= token pf-beacon.sh sends for that snapshot
beacon_sl() { echo "$1" > "$SNAP"; : > "$PF_TEST_LOG"; PF_ACCOUNT=schans2 bash "$AG/pf-beacon.sh"; sed -n 's/.* sl=\([a-z]*\).*/\1/p' "$PF_TEST_LOG"; }

# --- pf-beacon.sh: the sl= marker
check "beacon: empty snapshot (#1189 on schans2) is sl=none" "$(beacon_sl '{}')" none
check "beacon: status line JSON without rate_limits (API key, old Claude Code) is sl=nolimits" "$(beacon_sl '{"model":{"id":"m"},"session_id":"s"}')" nolimits
check "beacon: status line, 5h block idle, is sl=ok" "$(beacon_sl "{\"model\":{\"id\":\"m\"},\"rate_limits\":{\"seven_day\":{\"used_percentage\":20,\"resets_at\":$((now + 86400))}}}")" ok
check "beacon: status line, both blocks idle, is sl=ok" "$(beacon_sl '{"model":{"id":"m"},"rate_limits":{}}')" ok
check "beacon: pf-usage.sh rate_limits only is sl=ok" "$(beacon_sl '{"rate_limits":{"five_hour":null,"seven_day":null}}')" ok
check "beacon: sl= before claude_at" "$(grep -c " sl=ok\( claude_at=[0-9TZ:-]*\)\?\$" "$PF_TEST_LOG")" 1

# --- heartbeat
check "healthy: no ASK" "$(beat "12% 20% $far r5=$far agents=1 $at sl=ok")" 0
# the case from #1261: 5h block absent (0%, r5=1970), real 7-day numbers
check "idle 5h window: no ASK" "$(beat "0% 20% $far r5=$epoch0 agents=0 $at sl=ok claude_at=$far")" 0
check "idle 5h window: no stamp" "$(stamped)" no
# a week without use, or just past the weekly reset: both blocks absent on a wired setup
check "idle week: no ASK" "$(beat "0% 0% $epoch0 r5=$epoch0 agents=0 $at sl=ok")" 0
# not wired (#1189): nothing ever wrote the snapshot, even if the beacon itself is fresh
check "not wired (sl=none): ASK" "$(beat "0% 0% $epoch0 r5=$epoch0 agents=0 $at sl=none")" 1
check "not wired: stamp" "$(stamped)" yes
# status line running without rate limits (API-key login or outdated Claude Code, the #1189 instructions' case)
check "no rate limits (sl=nolimits): ASK" "$(beat "0% 0% $epoch0 r5=$epoch0 agents=0 $at sl=nolimits")" 1
# the next pass does not ask again (6h throttle); 6h later the still-broken peer is asked again
heartbeat; check "throttled: no second ASK" "$(asks)" 0
touch -t "$(pf_epoch_fmt "$((now - 21660))" +%Y%m%d%H%M.%S)" "$NUDGE"
heartbeat; check "after 6h: ASK again" "$(asks)" 1
# beacons from before sl= keep the ticket's rule: 1970 7-day reset or ?% asks, r5=1970 alone does not
check "old format, all 1970: ASK" "$(beat "0% 0% $epoch0 r5=$epoch0 agents=0 $at")" 1
check "old format, idle 5h only: no ASK" "$(beat "0% 20% $far r5=$epoch0 agents=0 $at")" 0
check "old format, ?%: ASK" "$(beat "?% ?% $far r5=$far agents=0")" 1
# a peer that is off: its newest beacon (not wired) went out 3 days ago; peer-silent covers it, no ASK every 6h
check "peer off for days: no ASK" "$(beat "0% 0% $epoch0 r5=$epoch0 agents=0 $at sl=none" $((3 * 86400)))" 0
# newest by message time, not file order: a newer healthy line written before an older broken one wins
rm -f "$NUDGE"
{ echo "$((now - 60))|agage-JG|USAGE|12% 20% $far r5=$far agents=1 $at sl=ok"
  echo "$((now - 3000))|agage-JG|USAGE|0% 0% $epoch0 r5=$epoch0 agents=0 $at sl=none"; } > "$INBOX"
heartbeat; check "newest by time wins: no ASK" "$(asks)" 0
# PF_MSG_NOSEND sends nothing at all
rm -f "$NUDGE" "$T/state/.msg-hello-last"; : > "$PF_TEST_LOG"
echo "$((now - 60))|agage-JG|USAGE|0% 0% $epoch0 r5=$epoch0 agents=0 $at sl=none" > "$INBOX"
PF_MSG_NOSEND=1 PF_ACCOUNT=schans2 bash "$AG/pf-msg.sh" heartbeat >/dev/null
check "NOSEND: nothing sent" "$(wc -l < "$PF_TEST_LOG" | tr -d ' ')" 0
echo "heartbeat-usage-nudge: $pass passed, $fail failed"; [ "$fail" = 0 ]
