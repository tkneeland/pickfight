#!/bin/bash
# Offline tests for the pace governor (issue #274): hive-pace.sh states (AHEAD / ON_PACE / BEHIND at several points of the
# window, the weekly guard, a missing or stale snapshot), the zero-token pace log, window close, tuning bounds, the report
# table, the beacon fields, the false "no real numbers" ASK, and that nothing here can invoke claude.
# Scratch HIVE_STATE_DIR, curl and claude shims first on PATH, HIVE_NOW pins the clock. No network. macOS, Linux, Git Bash.
#   bash tools/agents/tests/pace-governor.sh
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/hive-pace-test.XXXXXX") || exit 1; trap 'rm -rf "$T"' EXIT
hive_fixture "$T" || exit 1
mkdir -p "$T/bin" "$T/state"
printf '#!/bin/bash\necho "claude $*" >> "%s/claude-calls.log"\nexit 0\n' "$T" > "$T/bin/claude"
cp "$T/bin/claude" "$T/bin/claude.exe"
cat > "$T/bin/curl" <<'STUB'
#!/bin/bash
cfg=$(cat | tr '\n' ' '); echo "curl $* | $cfg" >> "$HIVE_TEST_LOG"
code=${HIVE_TEST_CODE:-200}; hdr=""; w=""
while [ $# -gt 0 ]; do case $1 in -D) hdr=$2; shift;; -w) w=$2; shift;; esac; shift; done
if [ -n "$hdr" ]; then
  { printf 'HTTP/1.1 %s X\r\n' "$code"; [ -n "${HIVE_TEST_RA:-}" ] && printf 'retry-after: %s\r\n' "$HIVE_TEST_RA"; printf '\r\n'; } > "$hdr"
fi
[ -n "$w" ] && printf '%s' "$code"
exit 0
STUB
printf '#!/bin/bash\nexit 0\n' > "$T/bin/gh"
chmod +x "$T/bin/claude" "$T/bin/claude.exe" "$T/bin/curl" "$T/bin/gh"
git init -q "$T/repo"
export HIVE_TEST_LOG=$T/state/curl.log PATH="$T/bin:$PATH" HIVE_STATE_DIR=$T/state REPO_PATH=$T/repo HIVE_ACCOUNT=alice WATCH_PEERS=bob
S=$T/state; PACE="$AG/hive-pace.sh"; SNAP=$S/usage-snapshot.json
now=$(date -u +%s); export HIVE_NOW=$now
pass=0; fail=0
fmt_e() { ( . "$AG/hive-env.sh" && hive_fmt "$1" "$2" ); }
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
# snap <used5> <secs left in the 5h window | 0 = none> <used7|?> <secs left in the week | 0 = none>; fresh unless a 5th arg (age s)
snap() {
  local r5=0 r7=0 u7=$3
  [ "$2" -gt 0 ] && r5=$((now + $2)); [ "$4" -gt 0 ] && r7=$((now + $4))
  [ "$u7" = "?" ] && u7=null
  printf '{"rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":%s},"seven_day":{"used_percentage":%s,"resets_at":%s}}}' "$1" "$r5" "$u7" "$r7" > "$SNAP"
  [ -n "${5:-}" ] && touch -t "$(fmt_e $((now - $5)) +%Y%m%d%H%M.%S)" "$SNAP"
  return 0
}
st() { bash "$PACE" state; }
WK=604800; HALFWK=302400
# weekly fixture: used7 20 at half the week: well under the weekly pace, so only the 5h pace decides
W7="20 $HALFWK"

# 1 early in the window (10% elapsed, target 10): used 0 is on pace, 30 is ahead
snap 0 16200 $W7;  check "early 0% ON_PACE" "$(st)" ON_PACE
snap 20 16200 $W7; check "early 20% ON_PACE (edge)" "$(st)" ON_PACE
snap 21 16200 $W7; check "early 21% AHEAD" "$(st)" AHEAD
snap 30 16200 $W7; check "early 30% AHEAD" "$(st)" AHEAD
# 2 mid window (50% elapsed, target 50)
snap 20 9000 $W7;  check "mid 20% BEHIND" "$(st)" BEHIND
snap 39 9000 $W7;  check "mid 39% BEHIND" "$(st)" BEHIND
snap 40 9000 $W7;  check "mid 40% ON_PACE (edge)" "$(st)" ON_PACE
snap 50 9000 $W7;  check "mid 50% ON_PACE" "$(st)" ON_PACE
snap 60 9000 $W7;  check "mid 60% ON_PACE (edge)" "$(st)" ON_PACE
snap 61 9000 $W7;  check "mid 61% AHEAD" "$(st)" AHEAD
# 3 late in the window (90% elapsed, target 90)
snap 70 1800 $W7;  check "late 70% BEHIND" "$(st)" BEHIND
snap 85 1800 $W7;  check "late 85% ON_PACE" "$(st)" ON_PACE
snap 100 1800 $W7; check "late 100% ON_PACE" "$(st)" ON_PACE
# 4 no 5h window yet (r5 = 1970, 0% used, real weekly): BEHIND; so is a window that already ended
snap 0 0 $W7;      check "no window BEHIND" "$(st)" BEHIND
printf '{"rate_limits":{"five_hour":{"used_percentage":50,"resets_at":%s},"seven_day":{"used_percentage":20,"resets_at":%s}}}' $((now - 60)) $((now + HALFWK)) > "$SNAP"
check "ended window BEHIND" "$(st)" BEHIND
# 5 weekly guard wins: 5h says BEHIND, but the week is ahead (used7 > elapsed7 x 100 + 5)
snap 20 9000 55 $HALFWK; check "weekly 55 at 50% of the week: not ahead" "$(st)" BEHIND
snap 20 9000 56 $HALFWK; check "weekly 56 at 50% of the week: AHEAD wins over 5h BEHIND" "$(st)" AHEAD
snap 0 0 90 $HALFWK;     check "weekly AHEAD even with no 5h window" "$(st)" AHEAD
snap 20 9000 "?" 0;      check "weekly unknown: 5h pace only" "$(st)" BEHIND
snap 20 9000 90 0;       check "weekly reset unknown: pace not judged" "$(st)" BEHIND
# the weekly stop (100 - MIN_WEEKLY_REMAINING_FOR_TICKETS, the hub's) scales the on-pace line: stop 80 at half the week is 45
export MIN_WEEKLY_REMAINING_FOR_TICKETS=20
snap 20 9000 45 $HALFWK; check "stop 80: weekly 45 at 50% of the week: not ahead" "$(st)" BEHIND
snap 20 9000 46 $HALFWK; check "stop 80: weekly 46 at 50% of the week: AHEAD" "$(st)" AHEAD
snap 20 9000 80 $((2 * 86400)); check "stop 80: at the stop 2 days out: AHEAD" "$(st)" AHEAD
snap 20 9000 95 36000;   check "stop 80: in the reset grace window, line and stop ignored" "$(st)" BEHIND
snap 20 9000 100 36000;  check "100% in the reset grace window: AHEAD" "$(st)" AHEAD
export MIN_WEEKLY_REMAINING_FOR_TICKETS=100; snap 0 0 0 0; check "min-remaining 100: always AHEAD" "$(st)" AHEAD
unset MIN_WEEKLY_REMAINING_FOR_TICKETS
# 6 missing, unreadable or stale snapshot: ON_PACE, never a burst
rm -f "$SNAP";      check "missing snapshot ON_PACE" "$(st)" ON_PACE
echo "not json" > "$SNAP"; check "garbage snapshot ON_PACE" "$(st)" ON_PACE
echo "{\"model\":{\"display_name\":\"x\"}}" > "$SNAP"; check "snapshot without rate_limits ON_PACE" "$(st)" ON_PACE
printf '{"rate_limits":{"five_hour":{"resets_at":%s},"seven_day":{"used_percentage":99,"resets_at":%s}}}' $((now + 9000)) $((now + HALFWK)) > "$SNAP"; check "5h used unknown: weekly guard still AHEAD" "$(st)" AHEAD
snap 0 0 $W7 7200;  check "stale snapshot (2h, would be BEHIND) ON_PACE" "$(st)" ON_PACE
snap 0 0 $W7 600;   check "10 min old snapshot still counts" "$(st)" BEHIND
snap 0 0 $W7 0; touch -t "$(fmt_e $((now + 600)) +%Y%m%d%H%M.%S)" "$SNAP"; check "future mtime is fresh" "$(st)" BEHIND
# 7 margin: PACE_MARGIN and the tuning override
snap 56 9000 $W7; check "margin 10 mid 56 ON_PACE" "$(st)" ON_PACE
check "AHEAD margin 5 mid 56 AHEAD" "$(PACE_MARGIN=5 st)" AHEAD
snap 40 9000 $W7; check "AHEAD margin does not move the BEHIND edge" "$(PACE_MARGIN=5 st)" ON_PACE
printf 'PACE_MARGIN=5\nMAX_WORKERS=2\n' > "$S/pace-tuning.conf"
snap 56 9000 $W7; check "pace-tuning.conf overrides margin" "$(st)" AHEAD; check "pace-tuning.conf overrides max" "$(bash "$PACE" max)" 2
rm -f "$S/pace-tuning.conf"
check "max defaults to 3" "$(bash "$PACE" max)" 3
check "max clamped to 6" "$(MAX_WORKERS=9 bash "$PACE" max)" 6
printf 'MAX_WORKERS=5\n' > "$S/pace-tuning.conf"
check "the tuner never exceeds the ceiling" "$(bash "$PACE" max)" 3
check "...a higher ceiling lets it through" "$(MAX_WORKERS=6 bash "$PACE" max)" 5
mkdir -p "$T/studio"; echo "* max_workers=2" > "$T/studio/account-limits.conf"
check "the account's hub max_workers is the ceiling over the tuner" "$(STUDIO_REPO=x/studio HIVE_STUDIO_CACHE=$T/studio bash "$PACE" max)" 2
rm -f "$S/pace-tuning.conf"
# 8 target for the status line
snap 34 10800 $W7; check "target 40" "$(bash "$PACE" target)" 40
snap 0 0 $W7;      check "target empty without a window" "$(bash "$PACE" target)" ""
rm -f "$SNAP";     check "target empty without a snapshot" "$(bash "$PACE" target)" ""

# 9 pace log: one row per tick, ready_tickets from the status cache, no duplicate within a minute, 60-day prune
rm -f "$S"/pace-*.csv "$S/.pace-window"; snap 34 10800 $W7
echo "agents 1/3 · ready me 4 / bob 2 · PRs 0" > "$S/status-cache.txt"
bash "$PACE" log 2
check "log header" "$(head -n 1 "$S/pace-log.csv")" "epoch,used5,elapsed5,used7,elapsed7,agents,pace_state,ready_tickets"
check "log row" "$(sed -n 2p "$S/pace-log.csv")" "$now,34,0.400,20,0.500,2,ON_PACE,4"
HIVE_NOW=$((now + 30)) bash "$PACE" log 2; check "no second row within a minute" "$(wc -l < "$S/pace-log.csv" | tr -d ' ')" 2
HIVE_NOW=$((now + 90)) bash "$PACE" log 0 7; check "second row after a minute" "$(wc -l < "$S/pace-log.csv" | tr -d ' ')" 3
check "explicit ready arg" "$(tail -n 1 "$S/pace-log.csv" | cut -d, -f8)" 7
echo "agents 0/2 · triage 0 · ready 9 · doing 0" > "$S/status-cache.txt"
HIVE_NOW=$((now + 200)) bash "$PACE" log 0; check "local-tracker cache ready" "$(tail -n 1 "$S/pace-log.csv" | cut -d, -f8)" 9
old=$((now - 61 * 86400)); keep=$((now - 59 * 86400))
{ head -n 1 "$S/pace-log.csv"; echo "$old,50,0.5,10,0.1,1,ON_PACE,0"; echo "$keep,50,0.5,10,0.1,1,ON_PACE,0"; tail -n +2 "$S/pace-log.csv"; } > "$S/x" && mv "$S/x" "$S/pace-log.csv"
HIVE_NOW=$((now + 400)) bash "$PACE" log 1
check "prune drops the 61-day row" "$(grep -c "^$old," "$S/pace-log.csv")" 0
check "prune keeps the 59-day row" "$(grep -c "^$keep," "$S/pace-log.csv")" 1
check "prune keeps the header" "$(head -n 1 "$S/pace-log.csv" | cut -d, -f1)" epoch
rm -f "$SNAP"; n=$(wc -l < "$S/pace-log.csv"); bash "$PACE" log 1; check "no snapshot: no row" "$(wc -l < "$S/pace-log.csv")" "$n"

# 10 window close: ticks through one window, then a new r5 closes it with one row and tunes
rm -f "$S"/pace-*.csv "$S/.pace-window" "$S/pace-tuning.conf"
ws=$((now - 3600)); we=$((ws + 18000))      # window A started an hour ago
tick() { # tick <epoch> <used5> <agents> <ready> [reset epoch]
  HIVE_NOW=$1; export HIVE_NOW
  printf '{"rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":%s},"seven_day":{"used_percentage":20,"resets_at":%s}}}' "$2" "${5:-$we}" "$((now + HALFWK))" > "$SNAP"
  touch -t "$(fmt_e "$1" +%Y%m%d%H%M.%S)" "$SNAP"
  bash "$PACE" log "$3" "$4" >/dev/null
}
tick $((ws + 60))   10 0 3     # idle with ready work: 5 min until the next row
tick $((ws + 360))  40 2 3
tick $((ws + 3600)) 70 2 3     # a long gap: the idle accounting is capped per row
tick $((ws + 7200)) 100 0 2    # hit 100 at minute 120; idle with ready work, but the gap to the next row counts at most 15 min
tick $((we - 120))  100 0 0
tick $((we + 100))  0 0 0 $((we + 18000))   # window B: closes A
check "one closed window" "$(wc -l < "$S/pace-windows.csv" | tr -d ' ')" 2
check "window header" "$(head -n 1 "$S/pace-windows.csv")" "window_start,final_used5,minutes_to_100,idle_min_with_ready_work,margin,max_workers"
check "window row" "$(sed -n 2p "$S/pace-windows.csv")" "$ws,100,120,20,10,3"
check "lastwin" "$(bash "$PACE" lastwin)" "100 20"
tick $((we + 200)) 5 1 0 $((we + 18002))   # same window (reset jitter): no second close
check "jitter does not close a window" "$(wc -l < "$S/pace-windows.csv" | tr -d ' ')" 2
# one closed window is too little history to tune (needs 3)
check "conf written after the first close" "$(grep -c MAX_WORKERS "$S/pace-tuning.conf" 2>/dev/null)" "1"
check "no change with 1 window" "$(grep -c '^# last change: none' "$S/pace-tuning.conf")" 1
export HIVE_NOW=$now

# 11 tuning: one knob per window, within bounds
winfile() { # winfile <rows...> of "start,final,min100,idle"
  { echo "window_start,final_used5,minutes_to_100,idle_min_with_ready_work,margin,max_workers"; for r in "$@"; do echo "$r,10,3"; done; } > "$S/pace-windows.csv"
}
tuned() { sed -n "s/^$1=//p" "$S/pace-tuning.conf"; }
rm -f "$S/pace-tuning.conf"
winfile 1000,100,200,0 2000,100,250,0 3000,100,260,0 4000,80,,0
bash "$PACE" tune >/dev/null
check "hit-early majority: max_workers 3 -> 2" "$(tuned MAX_WORKERS)" 2; check "margin untouched (one knob)" "$(tuned PACE_MARGIN)" 10
bash "$PACE" tune >/dev/null; check "same window: no second change" "$(tuned MAX_WORKERS)" 2
echo "5000,100,100,0,10,2" >> "$S/pace-windows.csv"; bash "$PACE" tune >/dev/null; check "next window: workers 2 -> 1" "$(tuned MAX_WORKERS)" 1
echo "6000,100,100,0,10,1" >> "$S/pace-windows.csv"; bash "$PACE" tune >/dev/null
check "workers at floor: margin 10 -> 5" "$(tuned PACE_MARGIN)" 5; check "workers stay 1" "$(tuned MAX_WORKERS)" 1
echo "7000,100,100,0,5,1" >> "$S/pace-windows.csv"; bash "$PACE" tune >/dev/null
check "both at the floor: margin stays 5" "$(tuned PACE_MARGIN)" 5; check "max_workers stays 1" "$(tuned MAX_WORKERS)" 1
# under-used majority with ready work idle: loosen
rm -f "$S/pace-tuning.conf"
winfile 1000,60,,40 2000,70,,30 3000,85,,20 4000,100,200,0
printf 'MAX_WORKERS=3\nPACE_MARGIN=10\n' > "$S/pace-tuning.conf"
bash "$PACE" tune >/dev/null; check "under-used at the ceiling (3): margin 10 -> 15, workers stay" "$(tuned PACE_MARGIN)/$(tuned MAX_WORKERS)" 15/3
printf 'MAX_WORKERS=3\nPACE_MARGIN=10\n' > "$S/pace-tuning.conf"; export MAX_WORKERS=4   # ceiling 4 from here
bash "$PACE" tune >/dev/null; check "under-used: max_workers 3 -> 4" "$(tuned MAX_WORKERS)" 4; check "margin untouched on loosen" "$(tuned PACE_MARGIN)" 10
echo "5000,60,,40,10,4" >> "$S/pace-windows.csv"; bash "$PACE" tune >/dev/null
check "workers at 4: margin 10 -> 15" "$(tuned PACE_MARGIN)" 15; check "workers cap 4" "$(tuned MAX_WORKERS)" 4
echo "6000,60,,40,15,4" >> "$S/pace-windows.csv"; bash "$PACE" tune >/dev/null; check "margin 15 -> 20" "$(tuned PACE_MARGIN)" 20
echo "7000,60,,40,20,4" >> "$S/pace-windows.csv"; bash "$PACE" tune >/dev/null; check "margin capped at 20" "$(tuned PACE_MARGIN)" 20
unset MAX_WORKERS
# under 90% but no ready work idle: not a reason to loosen; mixed history: no change
rm -f "$S/pace-tuning.conf"; winfile 1000,60,,0 2000,60,,0 3000,60,,0
bash "$PACE" tune >/dev/null; check "under-used but never idle with work: no change" "$(sed -n 's/^# last change: //p' "$S/pace-tuning.conf")" none
rm -f "$S/pace-tuning.conf"; winfile 1000,100,100,0 2000,60,,30 3000,95,,0 4000,60,,30
bash "$PACE" tune >/dev/null; check "mixed history: no change" "$(sed -n 's/^# last change: //p' "$S/pace-tuning.conf")" none
check "no change still records the window (no re-evaluation)" "$(tuned PACE_TUNED_WINDOW)" 4000

# 12 report from a sample inbox
rm -f "$S/pace-tuning.conf"
iso() { TZ=UTC fmt_e "$1" +%Y-%m-%dT%H:%M:%SZ; }
far=$(iso $((now + 86400)))
{ echo "$((now - 300))|alice|USAGE|34% 20% $far r5=$far agents=2 at=$(iso $((now - 300))) pace=BEHIND win5=97 idle=45"
  echo "$((now - 9000))|alice|USAGE|10% 20% $far r5=$far agents=2 at=$(iso $((now - 9000))) pace=AHEAD"
  echo "$((now - 7300))|bob|USAGE|80% 30% $far r5=$far agents=1 at=$(iso $((now - 7300))) pace=AHEAD win5=100 idle=0 claude_at=$(iso $((now - 100)))"
  echo "$((now - 60))|carol|USAGE|5% 10% $far r5=$far agents=0 at=$(iso $((now - 60)))"
  echo "$((now - 60))|carol|HELLO|carol"; } > "$S/msg-inbox.log"
rep=$(bash "$PACE" report)
check "report header" "$(echo "$rep" | head -n 1 | tr -s ' ')" "account 5h pace final5 idle_min beacon"
check "report alice (newest line wins)" "$(echo "$rep" | grep '^alice' | tr -s ' ')" "alice 34% BEHIND 97 45 5m old"
check "report bob" "$(echo "$rep" | grep '^bob' | tr -s ' ')" "bob 80% AHEAD 100 0 2h old"
check "report carol (no pace fields yet)" "$(echo "$rep" | grep '^carol' | tr -s ' ')" "carol 5% - - - 1m old"
check "report has one row per account" "$(echo "$rep" | wc -l | tr -d ' ')" 4

# 13 the beacon carries pace= and the last window; the log tick runs from it
rm -f "$S"/pace-*.csv "$S"/.usage-last-sent "$S"/.pace-window "$S/msg-inbox.log" "$S/curl.log"; : > "$S/curl.log"
echo "HIVE_MSG_TOPIC=hive-testtopic" > "$S/msg.conf"
snap 0 0 $W7; touch "$SNAP"
bash "$AG/hive-beacon.sh"
check "beacon sent" "$(grep -c '^curl ' "$S/curl.log")" 1
check "beacon text has pace=BEHIND" "$(grep -c 'USAGE .* pace=BEHIND' "$S/curl.log")" 1
check "beacon without a closed window has no win5=" "$(grep -c 'win5=' "$S/curl.log")" 0
check "beacon tick logged a pace row" "$(grep -c "^$now," "$S/pace-log.csv")" 1
echo "100,97,120,45,10,3" >> "$S/pace-windows.csv"; rm -f "$S"/.usage-last-sent
HIVE_NOW=$((now + 700)) bash "$AG/hive-beacon.sh"
check "beacon carries the last window" "$(grep -c 'pace=.* win5=97 idle=45' "$S/curl.log")" 1
check "hive_beacon parses pace" "$(. "$AG/hive-env.sh"; echo "x|bob|USAGE|1% 2% $far r5=$far agents=0 at=$(iso $now) pace=AHEAD win5=9 idle=1" > "$S/msg-inbox.log"; HIVE_INBOX=$S/msg-inbox.log; hive_beacon bob; echo "$b_pace/$b_p5")" "AHEAD/1"

# 14 the false ASK: r5=1970 (no 5h window started yet) with a real weekly % never triggers the ASK; a missing weekly still does
rm -f "$S"/.msg-* "$S/msg-inbox.log"; : > "$S/curl.log"; unset HIVE_NOW

sent_ask() { grep -c " ASK " "$S/curl.log"; }
echo "$(date -u +%s)|bob|USAGE|0% 31% $far r5=1970-01-01T00:00:00Z agents=0 at=$(iso $now)" > "$S/msg-inbox.log"
bash "$AG/hive-msg.sh" heartbeat >/dev/null 2>&1; check "r5=1970 with a real weekly: no ASK" "$(sent_ask)" 0
check "r5=1970 with a real weekly: no nudge stamp" "$(ls "$S"/.msg-usage-nudge-* 2>/dev/null | wc -l | tr -d ' ')" 0
echo "$(date -u +%s)|bob|USAGE|0% ?% 1970-01-01T00:00:00Z r5=1970-01-01T00:00:00Z agents=0 at=$(iso $now)" > "$S/msg-inbox.log"
bash "$AG/hive-msg.sh" heartbeat >/dev/null 2>&1; check "weekly unknown (reset 1970): ASK" "$(sent_ask)" 1
rm -f "$S"/.msg-usage-nudge-* "$S"/.msg-last-sent* ; : > "$S/curl.log"
echo "$(date -u +%s)|bob|USAGE|5% ? $far r5=$far agents=0 at=$(iso $now)" > "$S/msg-inbox.log"
bash "$AG/hive-msg.sh" heartbeat >/dev/null 2>&1; check "weekly ? : ASK (bare ? too)" "$(sent_ask)" 1
rm -f "$S"/.msg-usage-nudge-* "$S"/.msg-last-sent*; : > "$S/curl.log"
echo "$(date -u +%s)|bob|USAGE|5% ?% $far r5=$far agents=0 at=$(iso $now)" > "$S/msg-inbox.log"
bash "$AG/hive-msg.sh" heartbeat >/dev/null 2>&1; check "weekly ?% : ASK" "$(sent_ask)" 1
rm -f "$S"/.msg-usage-nudge-*; : > "$S/curl.log"
echo "$(date -u +%s)|bob|USAGE|? 31% $far r5=$far agents=0 at=$(iso $now)" > "$S/msg-inbox.log"
bash "$AG/hive-msg.sh" heartbeat >/dev/null 2>&1; check "5h ? with a real weekly: no ASK" "$(sent_ask)" 0

# 15 zero tokens: nothing in hive-pace.sh can invoke claude, statically or at run time
code=$(grep -v '^[[:space:]]*#' "$PACE")
check "no claude command in hive-pace.sh" "$(printf '%s\n' "$code" | grep -Ec '(^|[;&|(`]|\$\()[[:space:]]*(claude|claude\.exe|npx|node)([[:space:]]|$)|claude -p|--print|anthropic|api\.anthropic')" 0
: > "$T/claude-calls.log"; export HIVE_NOW=$now; snap 34 10800 $W7
for c in state target explain max "log 1 2" tune lastwin report; do bash "$PACE" $c >/dev/null 2>&1; done
check "no claude shim call at run time" "$(wc -l < "$T/claude-calls.log" | tr -d ' ')" 0
check "no network call from hive-pace.sh" "$(grep -Ec 'curl|wget|gh ' <<<"$code")" 0

echo "pace tests: $pass passed, $fail failed"
[ "$fail" = 0 ]
