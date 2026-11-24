#!/bin/bash
# Offline tests for the channel-only usage beacon: hive_beacon, hive-succession.sh (+ --post TM) and
# hive-reserve.sh --dry read USAGE lines from msg-inbox.log, and backfill an empty inbox from the ntfy poll.
# Scratch HIVE_STATE_DIR, stub curl and gh first on PATH (gh logs and fails on any issues/432 call), a scratch git repo
# with a local origin. No network. macOS, Linux and Git Bash.   bash tools/agents/tests/beacon-channel.sh
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/hive-beacon-test.XXXXXX"); trap 'rm -rf "$T"' EXIT
hive_fixture "$T" || exit 1
echo "MIN_WEEKLY_REMAINING_FOR_TICKETS=15" >> "$AG/accounts/_shared.conf"   # every account's weekly stop: 85% used
mkdir -p "$T/bin" "$T/state"
cat > "$T/bin/curl" <<'STUB'
#!/bin/bash
cfg=$(cat); echo "curl $* | $cfg" >> "$HIVE_TEST_LOG"
case $cfg in *poll=1*) cat "$HIVE_TEST_NTFY" 2>/dev/null;; esac
case " $* " in *" -w "*) printf 200;; esac   # send reads the HTTP code (-w)
exit 0
STUB
cat > "$T/bin/gh" <<'STUB'
#!/bin/bash
echo "gh $*" >> "$HIVE_TEST_LOG"
case "$*" in *432*) exit 1;; "issue list"*|"pr list"*|"api --paginate repos/"*"/issues?"*) echo '[]';; *) exit 1;; esac
STUB
chmod +x "$T/bin/curl" "$T/bin/gh"
git init -q --bare "$T/origin.git"; git init -q "$T/repo"
git -C "$T/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$T/repo" branch -M main; git -C "$T/repo" remote add origin "$T/origin.git"; git -C "$T/repo" push -q origin main
export PATH="$T/bin:$PATH" HIVE_STATE_DIR=$T/state REPO_PATH=$T/repo HIVE_TEST_LOG=$T/calls.log HIVE_TEST_NTFY=$T/ntfy.json
HIVE_ACCOUNT=alice . "$AG/hive-env.sh" || exit 1
echo "HIVE_MSG_TOPIC=hive-testtopic" > "$T/state/msg.conf"
now=$(date +%s); iso() { TZ=UTC hive_epoch_fmt "$1" +%Y-%m-%dT%H:%M:%SZ; }
far=$(iso $((now + 4 * 86400))); soon=$(iso $((now + 3600)))   # weekly resets: outside / inside the 24h grace window
INBOX=$T/state/msg-inbox.log
usage() { echo "$1|$2|USAGE|$3% $4% $5 r5=${6:-$soon} agents=1"; }   # usage <epoch> <handle> <5h> <7d> <7d reset> [5h reset]
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
tm() { rm -f "$T/state/triagemaster"; HIVE_ACCOUNT=$1 bash "$AG/hive-succession.sh" ${2:-}; }
fresh=$((now - 600)); stale=$((now - 7 * 3600))

# 1-6 run as dave (rank 4, no snapshot of its own), so ranks 1-3 all come from the inbox
# 1 rank 1 under its 85% weekly stop keeps the role
{ usage $fresh alice 10 50 "$far"; usage $fresh bob 10 20 "$far"; usage $fresh carol 5 10 "$far"; } > "$INBOX"
check "under 85%" "$(tm dave)" alice
# 2 rank 1 at 85%, reset far: role passes to rank 2; an older line for the same handle is ignored
{ usage $((now - 3000)) alice 10 40 "$far"; usage $fresh alice 10 85 "$far"; usage $fresh bob 10 20 "$far"; usage $fresh carol 5 10 "$far"; } > "$INBOX"
check "at 85%" "$(tm dave)" bob
# 3 rank 1 over its stop inside the grace window keeps it; at 100% it passes anyway
{ usage $fresh alice 10 90 "$soon"; usage $fresh bob 10 20 "$far"; usage $fresh carol 5 10 "$far"; } > "$INBOX"
check "85% in grace" "$(tm dave)" alice
{ usage $fresh alice 10 100 "$soon"; usage $fresh bob 10 20 "$far"; usage $fresh carol 5 10 "$far"; } > "$INBOX"
check "100% in grace" "$(tm dave)" bob
# 4 rank 2 stale (7h) or itself at 85%: skip to rank 3
{ usage $fresh alice 10 95 "$far"; usage $stale bob 10 20 "$far"; usage $fresh carol 5 10 "$far"; } > "$INBOX"
check "rank 2 stale" "$(tm dave)" carol
{ usage $fresh alice 10 95 "$far"; usage $fresh bob 10 86 "$far"; usage $fresh carol 5 10 "$far"; } > "$INBOX"
check "rank 2 at 85%" "$(tm dave)" carol
# 5 rank 1 stale: offline, so the next viable account holds the role
{ usage $stale alice 10 20 "$far"; usage $fresh bob 10 20 "$far"; } > "$INBOX"
check "rank 1 stale" "$(tm dave)" bob
# 6 at= (snapshot time) wins over the message time: a fresh message carrying a 7h-old snapshot is stale
{ usage $fresh alice 10 95 "$far"; echo "$fresh|bob|USAGE|10% 20% $far r5=$soon agents=0 at=$(iso $stale)"; usage $fresh carol 5 10 "$far"; } > "$INBOX"
check "at= stale" "$(tm dave)" carol
# 7 own numbers come from the usage snapshot, not the inbox (the listener skips our own messages)
echo "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":10,\"resets_at\":$((now + 3600))},\"seven_day\":{\"used_percentage\":100,\"resets_at\":$((now + 3600))}}}" > "$T/state/usage-snapshot.json"
usage $fresh bob 10 20 "$far" > "$INBOX"
check "own snapshot" "$(tm alice)" bob
# 8 empty inbox: backfill from the ntfy poll (since=12h), skipping our own messages, then decide
rm -f "$INBOX"; : > "$HIVE_TEST_LOG"
{ echo "{\"event\":\"open\"}"
  echo "{\"id\":\"a\",\"time\":$fresh,\"event\":\"message\",\"message\":\"alice USAGE 10% 90% $far r5=$soon agents=0\"}"
  echo "{\"id\":\"b\",\"time\":$fresh,\"event\":\"message\",\"message\":\"bob USAGE 10% 20% $far r5=$soon agents=2\"}"
  echo "{\"id\":\"c\",\"time\":$fresh,\"event\":\"message\",\"message\":\"carol HELLO carol\"}"; } > "$HIVE_TEST_NTFY"
check "backfill holder" "$(tm carol)" bob
check "backfill polled" "$(grep -c 'json?poll=1&since=12h' "$HIVE_TEST_LOG")" 1
check "backfill skips own" "$(grep -c '|carol|' "$INBOX")" 0
check "backfill lines" "$(wc -l < "$INBOX" | tr -d ' ')" 2
tm carol >/dev/null; check "fresh inbox: no second poll" "$(grep -c 'poll=1' "$HIVE_TEST_LOG")" 1
HIVE_ACCOUNT=carol bash "$AG/hive-msg.sh" backfill; check "backfill dedupes" "$(wc -l < "$INBOX" | tr -d ' ')" 2
# 9 --post: the stand-in sends TM on the channel (never GitHub); HIVE_DRY_RUN sends nothing
{ usage $fresh alice 10 95 "$far"; usage $fresh bob 10 20 "$far"; } > "$INBOX"; : > "$HIVE_TEST_LOG"
rm -f "$T/state/triagemaster"; HIVE_DRY_RUN=1 HIVE_ACCOUNT=carol bash "$AG/hive-succession.sh" --post >/dev/null
check "dry run sends nothing" "$(grep -c 'TM' "$HIVE_TEST_LOG")" 0
{ usage $fresh alice 10 95 "$far"; usage $fresh carol 10 20 "$far"; } > "$INBOX"
check "post holder" "$(tm bob --post)" carol
{ usage $fresh alice 10 95 "$far"; usage $fresh bob 10 20 "$far"; } > "$INBOX"; : > "$HIVE_TEST_LOG"
check "not the holder: no post" "$(tm carol --post)" bob
check "no TM from a non-holder" "$(grep -c TM "$HIVE_TEST_LOG")" 0
echo "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":5,\"resets_at\":$((now + 3600))},\"seven_day\":{\"used_percentage\":20,\"resets_at\":$((now + 4 * 86400))}}}" > "$T/state/usage-snapshot.json"
usage $fresh alice 10 95 "$far" > "$INBOX"
rm -f "$T/state/triagemaster"; HIVE_ACCOUNT=bob bash "$AG/hive-succession.sh" --post >/dev/null
check "TM sent" "$(grep -c "bob TM bob until " "$HIVE_TEST_LOG")" 1
# 10 hive-reserve.sh --dry decides from the same inbox lines (as the reserve account dave)
reserve() { HIVE_ACCOUNT=dave bash "$AG/hive-reserve.sh" --dry | sed 's/ *| needed=\([01]\).*/ needed=\1/'; }
{ usage $fresh alice 10 50 "$far"; usage $fresh bob 10 20 "$far"; usage $fresh carol 5 10 "$far"; } > "$INBOX"
check "reserve all able" "$(reserve)" "alice:able bob:able carol:able needed=0"
{ usage $fresh alice 10 85 "$far"; usage $stale bob 10 20 "$far"; usage $fresh carol 100 10 "$far" "$(iso $((now + 7200)))"; } > "$INBOX"
check "reserve unable" "$(reserve)" "alice:unable bob:unable carol:unable needed=1"
{ usage $fresh alice 10 95 "$soon"; usage $fresh bob 10 20 "$far"; usage $fresh carol 5 10 "$far"; } > "$INBOX"
check "reserve grace" "$(reserve)" "alice:able bob:able carol:able needed=0"
# 11 no fresh channel data -> no decision: reserve exits quietly, succession keeps the current holder
nodec() { rm -f "$T/state/triagemaster"; echo bob > "$T/state/triagemaster"; HIVE_ACCOUNT=dave bash "$AG/hive-succession.sh"; }
# A: no channel configured, empty inbox
mv "$T/state/msg.conf" "$T/conf.bak"; rm -f "$INBOX" "$T/state/.msg-backfill-last"
check "A reserve no decision" "$(reserve)" "no fresh channel data: no decision"
check "A succession keeps holder" "$(nodec)" bob
mv "$T/conf.bak" "$T/state/msg.conf"
# B: listener down; a backfill 10 min ago found nothing new; newest peer USAGE now 6h05m old
old=$((now - 6 * 3600 - 300))
{ usage $old alice 10 95 "$far"; usage $old bob 10 20 "$far"; usage $old carol 5 10 "$far"; } > "$INBOX"
touch "$T/state/.msg-backfill-last"; : > "$HIVE_TEST_LOG"
check "B reserve no decision" "$(reserve)" "no fresh channel data: no decision"
check "B succession keeps holder" "$(nodec)" bob
check "B rate-limited: no poll" "$(grep -c 'poll=1' "$HIVE_TEST_LOG")" 0
# B2: same inbox, 15 min later (stamp gone): backfill polls again, finds fresh lines, merges them in time order
rm -f "$T/state/.msg-backfill-last"
check "B2 succession decides" "$(tm dave)" bob
check "B2 polled" "$(grep -c 'poll=1' "$HIVE_TEST_LOG")" 1
check "B2 inbox time-ordered" "$(cut -d'|' -f1 "$INBOX" | sort -n | tr '\n' ' ')" "$(cut -d'|' -f1 "$INBOX" | tr '\n' ' ')"
check "B2 merged" "$(wc -l < "$INBOX" | tr -d ' ')" 6
# 12 status line: peers' usage from the inbox (line 3); nothing anywhere touched issue 432
{ usage $fresh bob 12 34 "$far"; usage $stale carol 5 10 "$far"; } > "$INBOX"
HIVE_ACCOUNT=alice bash "$AG/hive-status-refresh.sh"
check "status peers" "$(sed -n 2p "$T/state/status-cache.txt")" "peers bob 5h 12% 7d 34% · carol 5h 5% 7d 10% (7h old) · dave ?"
check "no #432 call" "$(grep -c 432 "$HIVE_TEST_LOG")" 0
echo "beacon-channel: $pass passed, $fail failed"; [ "$fail" = 0 ]
