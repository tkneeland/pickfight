#!/bin/bash
# Offline tests for hive-wake.sh: the headless session's bash reading of the triage wake line (no nested PowerShell).
# No wake, an unhandled wake (exit 10), --ack, a CRLF ack as hive-status.ps1 -Ack writes it, and a new wake after an ack.
# Also checks the Windows keepalive's headless prompt names hive-wake.sh and no longer sends the session to PowerShell.
#   bash tools/agents/tests/wake.sh
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/hive-wake-test.XXXXXX") || exit 1; trap 'rm -rf "$T"' EXIT
hive_fixture "$T" || exit 1
mkdir -p "$T/state"; git init -q "$T/repo"
export HIVE_STATE_DIR=$T/state REPO_PATH=$T/repo HIVE_ACCOUNT=alice
S=$T/state; W="$AG/hive-wake.sh"
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }

out=$(bash "$W"); rc=$?
check "no wake: exit" "$rc" 0
check "no wake: line" "$(printf '%s\n' "$out" | tail -n 1)" "no wake"
check "supervisor lines" "$(printf '%s\n' "$out" | grep -c 'no status')" 4

echo '2026-11-18T14:47:13Z MSG ASK bob @alice [q1] busy?' > "$S/triage-wake.txt"
echo '{"state":"woke","line":"MSG ASK","at":"2026-11-18T14:47:13Z"}' > "$S/triage-status.json"
out=$(bash "$W"); rc=$?
check "unhandled: exit 10" "$rc" 10
check "unhandled: WAKE line" "$(printf '%s\n' "$out" | tail -n 1)" "WAKE 2026-11-18T14:47:13Z MSG ASK bob @alice [q1] busy?"
check "triage status shown" "$(printf '%s\n' "$out" | grep -c '^triage *woke MSG ASK at 2026-11-18T14:47:13Z')" 1

out=$(bash "$W" --ack); rc=$?
check "ack: exit" "$rc" 0
out=$(bash "$W"); rc=$?
check "after ack: exit 0" "$rc" 0
check "after ack: handled" "$(printf '%s\n' "$out" | tail -n 1 | cut -c1-8)" "handled "

printf '2026-11-18T14:47:13Z MSG ASK bob @alice [q1] busy?\r\n' > "$S/triage-wake.acked"   # PowerShell's ack
bash "$W" >/dev/null; check "a CRLF ack counts" "$?" 0

echo '2026-11-18T15:00:00Z MYTICKET 12' > "$S/triage-wake.txt"
bash "$W" >/dev/null; check "a new wake after an ack is unhandled" "$?" 10

k="$AG/windows/hive-keepalive.ps1"
check "keepalive prompt names hive-wake.sh" "$(grep -c 'bash tools/agents/hive-wake.sh --ack' "$k")" 1
check "keepalive prompt no longer runs hive-status.ps1" "$(grep -c 'File tools/agents/windows/hive-status.ps1' "$k")" 0

echo "wake tests: $((pass + fail)) checks, $fail failed"
[ "$fail" -eq 0 ]
