#!/bin/bash
# Offline tests for the channel-only usage beacon (#1153): pf_beacon, pf-succession.sh (+ --post TM) and
# pf-reserve.sh --dry read USAGE lines from msg-inbox.log, and backfill an empty inbox from the ntfy poll.
# Scratch PF_STATE_DIR, stub curl and gh first on PATH (gh logs and fails on any issues/432 call), a scratch git repo
# with a local origin. No network. macOS, Linux and Git Bash.   bash tools/agents/tests/beacon-channel.sh
AG=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/pf-beacon-test.XXXXXX"); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/state"
cat > "$T/bin/curl" <<'STUB'
#!/bin/bash
cfg=$(cat); echo "curl $* | $cfg" >> "$PF_TEST_LOG"
case $cfg in *poll=1*) cat "$PF_TEST_NTFY" 2>/dev/null;; esac
exit 0
STUB
cat > "$T/bin/gh" <<'STUB'
#!/bin/bash
echo "gh $*" >> "$PF_TEST_LOG"
case "$*" in *432*) exit 1;; "issue list"*|"pr list"*|"api --paginate repos/"*"/issues?"*) echo '[]';; *) exit 1;; esac
STUB
chmod +x "$T/bin/curl" "$T/bin/gh"
git init -q --bare "$T/origin.git"; git init -q "$T/repo"
git -C "$T/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$T/repo" branch -M main; git -C "$T/repo" remote add origin "$T/origin.git"; git -C "$T/repo" push -q origin main
export PATH="$T/bin:$PATH" PF_STATE_DIR=$T/state REPO_PATH=$T/repo PF_TEST_LOG=$T/calls.log PF_TEST_NTFY=$T/ntfy.json
PF_ACCOUNT=tkneeland . "$AG/pf-env.sh" || exit 1
echo "PF_MSG_TOPIC=pf-testtopic" > "$T/state/pf-msg.conf"
now=$(date +%s); iso() { TZ=UTC pf_epoch_fmt "$1" +%Y-%m-%dT%H:%M:%SZ; }
far=$(iso $((now + 4 * 86400))); soon=$(iso $((now + 3600)))   # weekly resets: outside / inside the 24h grace window
INBOX=$T/state/msg-inbox.log
usage() { echo "$1|$2|USAGE|$3% $4% $5 r5=${6:-$soon} agents=1"; }   # usage <epoch> <handle> <5h> <7d> <7d reset> [5h reset]
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
tm() { rm -f "$T/state/pf-triagemaster"; PF_ACCOUNT=$1 bash "$AG/pf-succession.sh" ${2:-}; }
fresh=$((now - 600)); stale=$((now - 7 * 3600))

# 1-6 run as tommykneeland (rank 4, no snapshot of its own), so ranks 1-3 all come from the inbox
# 1 rank 1 under 85% keeps the role
{ usage $fresh tkneeland 10 50 "$far"; usage $fresh agage-JG 10 20 "$far"; usage $fresh schans2 5 10 "$far"; } > "$INBOX"
check "under 85%" "$(tm tommykneeland)" tkneeland
# 2 rank 1 at 85%, reset far: role passes to rank 2; an older line for the same handle is ignored
{ usage $((now - 3000)) tkneeland 10 40 "$far"; usage $fresh tkneeland 10 85 "$far"; usage $fresh agage-JG 10 20 "$far"; usage $fresh schans2 5 10 "$far"; } > "$INBOX"
check "at 85%" "$(tm tommykneeland)" agage-JG
# 3 rank 1 at 85% inside the grace window keeps it; at 95% it passes anyway
{ usage $fresh tkneeland 10 90 "$soon"; usage $fresh agage-JG 10 20 "$far"; usage $fresh schans2 5 10 "$far"; } > "$INBOX"
check "85% in grace" "$(tm tommykneeland)" tkneeland
{ usage $fresh tkneeland 10 95 "$soon"; usage $fresh agage-JG 10 20 "$far"; usage $fresh schans2 5 10 "$far"; } > "$INBOX"
check "95% in grace" "$(tm tommykneeland)" agage-JG
# 4 rank 2 stale (7h) or itself at 85%: skip to rank 3
{ usage $fresh tkneeland 10 95 "$far"; usage $stale agage-JG 10 20 "$far"; usage $fresh schans2 5 10 "$far"; } > "$INBOX"
check "rank 2 stale" "$(tm tommykneeland)" schans2
{ usage $fresh tkneeland 10 95 "$far"; usage $fresh agage-JG 10 86 "$far"; usage $fresh schans2 5 10 "$far"; } > "$INBOX"
check "rank 2 at 85%" "$(tm tommykneeland)" schans2
# 5 rank 1 stale: no evidence it is over budget, it keeps the role
{ usage $stale tkneeland 10 99 "$far"; usage $fresh agage-JG 10 20 "$far"; } > "$INBOX"
check "rank 1 stale" "$(tm tommykneeland)" tkneeland
# 6 at= (snapshot time) wins over the message time: a fresh message carrying a 7h-old snapshot is stale
{ usage $fresh tkneeland 10 95 "$far"; echo "$fresh|agage-JG|USAGE|10% 20% $far r5=$soon agents=0 at=$(iso $stale)"; usage $fresh schans2 5 10 "$far"; } > "$INBOX"
check "at= stale" "$(tm tommykneeland)" schans2
# 7 own numbers come from the usage snapshot, not the inbox (the listener skips our own messages)
echo "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":10,\"resets_at\":$((now + 3600))},\"seven_day\":{\"used_percentage\":96,\"resets_at\":$((now + 3600))}}}" > "$T/state/usage-snapshot.json"
usage $fresh agage-JG 10 20 "$far" > "$INBOX"
check "own snapshot" "$(tm tkneeland)" agage-JG
# 8 empty inbox: backfill from the ntfy poll (since=12h), skipping our own messages, then decide
rm -f "$INBOX"; : > "$PF_TEST_LOG"
{ echo "{\"event\":\"open\"}"
  echo "{\"id\":\"a\",\"time\":$fresh,\"event\":\"message\",\"message\":\"tkneeland USAGE 10% 90% $far r5=$soon agents=0\"}"
  echo "{\"id\":\"b\",\"time\":$fresh,\"event\":\"message\",\"message\":\"agage-JG USAGE 10% 20% $far r5=$soon agents=2\"}"
  echo "{\"id\":\"c\",\"time\":$fresh,\"event\":\"message\",\"message\":\"schans2 HELLO schans2\"}"; } > "$PF_TEST_NTFY"
check "backfill holder" "$(tm schans2)" agage-JG
check "backfill polled" "$(grep -c 'json?poll=1&since=12h' "$PF_TEST_LOG")" 1
check "backfill skips own" "$(grep -c '|schans2|' "$INBOX")" 0
check "backfill lines" "$(wc -l < "$INBOX" | tr -d ' ')" 2
tm schans2 >/dev/null; check "fresh inbox: no second poll" "$(grep -c 'poll=1' "$PF_TEST_LOG")" 1
PF_ACCOUNT=schans2 bash "$AG/pf-msg.sh" backfill; check "backfill dedupes" "$(wc -l < "$INBOX" | tr -d ' ')" 2
# 9 --post: the stand-in sends TM on the channel (never GitHub); PF_DRY_RUN sends nothing
{ usage $fresh tkneeland 10 95 "$far"; usage $fresh agage-JG 10 20 "$far"; } > "$INBOX"; : > "$PF_TEST_LOG"
rm -f "$T/state/pf-triagemaster"; PF_DRY_RUN=1 PF_ACCOUNT=schans2 bash "$AG/pf-succession.sh" --post >/dev/null
check "dry run sends nothing" "$(grep -c 'TM' "$PF_TEST_LOG")" 0
{ usage $fresh tkneeland 10 95 "$far"; usage $fresh schans2 10 20 "$far"; } > "$INBOX"
check "post holder" "$(tm agage-JG --post)" schans2
{ usage $fresh tkneeland 10 95 "$far"; usage $fresh agage-JG 10 20 "$far"; } > "$INBOX"; : > "$PF_TEST_LOG"
check "not the holder: no post" "$(tm schans2 --post)" agage-JG
check "no TM from a non-holder" "$(grep -c TM "$PF_TEST_LOG")" 0
echo "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":5,\"resets_at\":$((now + 3600))},\"seven_day\":{\"used_percentage\":20,\"resets_at\":$((now + 4 * 86400))}}}" > "$T/state/usage-snapshot.json"
usage $fresh tkneeland 10 95 "$far" > "$INBOX"
rm -f "$T/state/pf-triagemaster"; PF_ACCOUNT=agage-JG bash "$AG/pf-succession.sh" --post >/dev/null
check "TM sent" "$(grep -c "agage-JG TM agage-JG until $far" "$PF_TEST_LOG")" 1
# 10 pf-reserve.sh --dry decides from the same inbox lines (as the reserve account tommykneeland)
reserve() { PF_ACCOUNT=tommykneeland bash "$AG/pf-reserve.sh" --dry | sed 's/ *| needed=\([01]\).*/ needed=\1/'; }
{ usage $fresh tkneeland 10 50 "$far"; usage $fresh agage-JG 10 20 "$far"; usage $fresh schans2 5 10 "$far"; } > "$INBOX"
check "reserve all able" "$(reserve)" "agage-JG:able schans2:able tkneeland:able needed=0"
{ usage $fresh tkneeland 10 85 "$far"; usage $stale agage-JG 10 20 "$far"; usage $fresh schans2 100 10 "$far" "$(iso $((now + 7200)))"; } > "$INBOX"
check "reserve unable" "$(reserve)" "agage-JG:unable schans2:unable tkneeland:unable needed=1"
{ usage $fresh tkneeland 10 95 "$soon"; usage $fresh agage-JG 10 20 "$far"; usage $fresh schans2 5 10 "$far"; } > "$INBOX"
check "reserve grace" "$(reserve)" "agage-JG:able schans2:able tkneeland:able needed=0"
# 11 status line: peers' usage from the inbox (line 3); nothing anywhere touched issue 432
{ usage $fresh agage-JG 12 34 "$far"; usage $stale schans2 5 10 "$far"; } > "$INBOX"
PF_ACCOUNT=tkneeland bash "$AG/pf-status-refresh.sh"
check "status peers" "$(sed -n 2p "$T/state/pf-status-cache.txt")" "peers agage-JG 5h 12% 7d 34% · schans2 5h 5% 7d 10% (7h old) · tommykneeland ?"
check "no #432 call" "$(grep -c 432 "$PF_TEST_LOG")" 0
echo "beacon-channel: $pass passed, $fail failed"; [ "$fail" = 0 ]
