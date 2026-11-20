#!/bin/bash
# Offline test for hive-reserve.sh --dry and the peer's weekly ticket cap (#226, rule 5): a regular dev whose weekly
# remaining (100 - 7d%) is at or below its own MIN_WEEKLY_REMAINING_FOR_TICKETS (account conf, else _shared.conf) is
# unable and never the hand-back target; one just under its cap still is. Scratch HIVE_STATE_DIR, stub curl and gh,
# a scratch git repo with a local origin. No network. macOS, Linux and Git Bash.   bash tools/agents/tests/reserve-cap.sh
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/hive-reservecap-test.XXXXXX") || exit 1; trap 'rm -rf "$T"' EXIT
hive_fixture "$T" || exit 1
mkdir -p "$T/bin" "$T/state"
printf '#!/bin/bash\ncat >/dev/null; exit 0\n' > "$T/bin/curl"
printf '#!/bin/bash\ncase "$*" in "issue list"*|"pr list"*) echo "[]";; *) exit 1;; esac\n' > "$T/bin/gh"
chmod +x "$T/bin/curl" "$T/bin/gh"
git init -q --bare "$T/origin.git"; git init -q "$T/repo"
git -C "$T/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$T/repo" branch -M main; git -C "$T/repo" remote add origin "$T/origin.git"; git -C "$T/repo" push -q origin main
export PATH="$T/bin:$PATH" HIVE_STATE_DIR=$T/state REPO_PATH=$T/repo
echo "HIVE_MSG_TOPIC=hive-testtopic" > "$T/state/msg.conf"
# caps: bob has its own (30), carol falls back to _shared.conf (20), alice has none (shared 20)
printf '
%s
' "MIN_WEEKLY_REMAINING_FOR_TICKETS=30  # own cap" >> "$AG/accounts/bob.conf"
printf '
%s
' "MIN_WEEKLY_REMAINING_FOR_TICKETS=20" >> "$AG/accounts/_shared.conf"
HIVE_ACCOUNT=alice . "$AG/hive-env.sh" || exit 1
now=$(date +%s); iso() { TZ=UTC hive_epoch_fmt "$1" +%Y-%m-%dT%H:%M:%SZ; }
far=$(iso $((now + 4 * 86400))); soon=$(iso $((now + 3600))); fresh=$((now - 600))
INBOX=$T/state/msg-inbox.log
usage() { echo "$fresh|$1|USAGE|10% $2% $far r5=$soon agents=1"; }   # usage <handle> <7d used>
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
reserve() { HIVE_ACCOUNT=dave bash "$AG/hive-reserve.sh" --dry | sed 's/ run_any=.*best=\([a-z]*\) .*/ best=\1/; s/ take_new=[01]//'; }

{ usage alice 60; usage bob 69; usage carol 79; } > "$INBOX"
check "all under cap" "$(reserve)" "alice:able bob:able carol:able | needed=0 best=alice"
{ usage alice 60; usage bob 70; usage carol 79; } > "$INBOX"
check "bob at own cap (30): able, not best, needed unchanged" "$(reserve)" "alice:able bob:able carol:able | needed=0 best=alice"
{ usage alice 60; usage bob 10; usage carol 80; } > "$INBOX"
check "carol at shared cap (20): skipped as best" "$(reserve)" "alice:able bob:able carol:able | needed=0 best=bob"
{ usage alice 60; usage bob 75; usage carol 80; } > "$INBOX"
check "over cap, lowest used skipped" "$(reserve)" "alice:able bob:able carol:able | needed=0 best=alice"
{ usage alice 80; usage bob 71; usage carol 84; } > "$INBOX"
check "everyone at or over cap: no best" "$(reserve)" "alice:able bob:able carol:able | needed=0 best="
# unknown 7d: capped peers (bob 30, carol 20, alice 20) are never chosen
{ usage alice 60; echo "$fresh|bob|USAGE|10% ? $far r5=$soon agents=1"; usage carol 79; } > "$INBOX"
check "unknown 7d with cap: not best" "$(reserve)" "alice:able bob:able carol:able | needed=0 best=alice"
{ echo "$fresh|alice|USAGE|10% ? $far r5=$soon agents=1"; echo "$fresh|bob|USAGE|10% ? $far r5=$soon agents=1"; echo "$fresh|carol|USAGE|10% ? $far r5=$soon agents=1"; } > "$INBOX"
check "all unknown 7d, all capped: no best" "$(reserve)" "alice:able bob:able carol:able | needed=0 best="
# malformed cap falls back to shared (20): carol at 79 used (21 left) is fine, 80 used is not
printf '\n%s\n' "MIN_WEEKLY_REMAINING_FOR_TICKETS=abc" >> "$AG/accounts/carol.conf"
{ usage alice 80; usage bob 75; usage carol 79; } > "$INBOX"
check "malformed cap -> shared, eligible" "$(reserve)" "alice:able bob:able carol:able | needed=0 best=carol"
{ usage alice 80; usage bob 75; usage carol 80; } > "$INBOX"
check "malformed cap -> shared, at cap" "$(reserve)" "alice:able bob:able carol:able | needed=0 best="
# a real unable peer (stale beacon) still sets needed
{ usage alice 60; usage bob 10; echo "$((now - 30 * 3600))|carol|USAGE|10% 10% $far r5=$soon agents=1"; } > "$INBOX"
check "stale beacon: needed=1, best=bob" "$(reserve)" "alice:able bob:able carol:unable | needed=1 best=bob"

echo "reserve-cap: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
