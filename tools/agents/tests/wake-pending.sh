#!/bin/bash
# Offline tests for hive-wake-pending.sh (issue #398): the zero-token wake check for headless claude -p sessions.
# New relevant lines print once (exit 0), then nothing (exit 1); lines for other accounts are ignored; a rotated inbox resets.
#   bash tools/agents/tests/wake-pending.sh
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/hive-wakepending-test.XXXXXX") || exit 1; trap 'rm -rf "$T"' EXIT
hive_fixture "$T" || exit 1
mkdir -p "$T/state"; git init -q "$T/repo"
export HIVE_STATE_DIR=$T/state REPO_PATH=$T/repo
S=$T/state; P="$AG/hive-wake-pending.sh"; now=$(date +%s)
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }

# bob is a plain dev
export HIVE_ACCOUNT=bob
out=$(bash "$P"); check "nothing at all: exit" "$?" 1; check "nothing at all: silent" "$out" ""
echo '2026-11-19T14:00:00Z TRIAGE ready #12' > "$S/triage-wake.txt"
cat > "$S/msg-inbox.log" <<EOF2
$now|alice|ASK|@bob [q1] can you take #5?
$now|alice|ASK|@carol [q2] not for bob
$now|alice|INFO|TM says hello
$now|carol|ANSWER|@bob [q9] done
$((now - 7200))|alice|ASK|@bob [q0] ancient
$now|bob|ASK|@bob [q3] my own
EOF2
out=$(bash "$P"); rc=$?
check "first: exit" "$rc" 0
check "first: triage line" "$(printf '%s\n' "$out" | grep -c '^TRIAGE 2026-11-19T14:00:00Z TRIAGE ready #12$')" 1
check "first: ask for me" "$(printf '%s\n' "$out" | grep -c 'q1\] can you take #5')" 1
check "first: answer for me" "$(printf '%s\n' "$out" | grep -c 'q9\] done')" 1
check "first: other account ignored" "$(printf '%s\n' "$out" | grep -c 'q2')" 0
check "first: TM line ignored for a dev" "$(printf '%s\n' "$out" | grep -c 'TM says')" 0
check "first: old history skipped" "$(printf '%s\n' "$out" | grep -c 'q0')" 0
check "first: own line skipped" "$(printf '%s\n' "$out" | grep -c 'q3')" 0
out=$(bash "$P"); rc=$?
check "second: exit 1" "$rc" 1; check "second: silent" "$out" ""

echo "$now|alice|ASK|@bob [q4] again" >> "$S/msg-inbox.log"
out=$(bash "$P"); check "append: only the new line" "$out" "MSG $now|alice|ASK|@bob [q4] again"
echo '2026-11-19T15:00:00Z TRIAGE new' > "$S/triage-wake.txt"
out=$(bash "$P"); check "new wake text prints" "$out" "TRIAGE 2026-11-19T15:00:00Z TRIAGE new"

# rotation: the file is now smaller than the cursor
echo "$now|alice|ASK|@bob [q5] after rotate" > "$S/msg-inbox.log"
out=$(bash "$P"); rc=$?
check "rotated: exit 0" "$rc" 0; check "rotated: read from 0" "$out" "MSG $now|alice|ASK|@bob [q5] after rotate"

# the triagemaster (alice) also sees TM / triagemaster lines
rm -f "$S"/wake-pending.*
export HIVE_ACCOUNT=alice
printf '%s|bob|ASK|TM, which ticket next?\n%s|bob|INFO|nothing for alice\n%s|carol|ASK|@triagemaster [q6] hi\n' "$now" "$now" "$now" > "$S/msg-inbox.log"
out=$(bash "$P"); rc=$?
check "tm: exit" "$rc" 0
check "tm: TM line" "$(printf '%s\n' "$out" | grep -c 'which ticket next')" 1
check "tm: triagemaster line" "$(printf '%s\n' "$out" | grep -c 'q6')" 1
check "tm: unrelated ignored" "$(printf '%s\n' "$out" | grep -c 'nothing for alice')" 0

echo "wake-pending tests: $((pass + fail)) checks, $fail failed"
[ "$fail" -eq 0 ]
