#!/bin/bash
# Offline test for pf-hive-join.sh (#1209): stub screen/powershell on PATH, scratch PF_STATE_DIR. No network.
# macOS, Linux and Git Bash.   bash tools/agents/tests/hive-join.sh
AG=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/pf-hive-test.XXXXXX") || exit 1; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/state"
for s in screen powershell.exe; do printf '#!/bin/bash\necho "%s $*" >> "$PF_TEST_LOG"\n[ "%s" = screen ] && [ "$1" = -ls ] && cat "$PF_TEST_SCREENLS" 2>/dev/null\nexit 0\n' "$s" "$s" > "$T/bin/$s"; chmod +x "$T/bin/$s"; done
export PATH="$T/bin:$PATH" PF_STATE_DIR=$T/state PF_ACCOUNT=tkneeland PF_TEST_LOG=$T/calls.log PF_TEST_SCREENLS=$T/screenls
: > "$T/calls.log"; fails=0
ok() { if [ "$2" = 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
run() { bash "$AG/pf-hive-join.sh"; }
echo "PF_MSG_TOPIC=x" > "$T/state/pf-msg.conf"

echo '{}' > "$T/state/msg-status.json"
out=$(run); rc=$?
ok "fresh status: exit 0" "$rc"
case $out in *team-memory.md*) ok "reminder printed" 0;; *) ok "reminder printed" 1;; esac
case $out in *"channel=ok"*) ok "fallback status says ok" 0;; *) ok "fallback status says ok" 1;; esac
[ ! -s "$T/calls.log" ]; ok "fresh status: nothing restarted" $?

touch -t 202001010000 "$T/state/msg-status.json"
out=$(run)
grep -q "screen -dmS pf-msg-tkneeland" "$T/calls.log"; ok "stale msg (unix): screen restart" $?
case $out in *"restarted dead msg"*) ok "restart announced" 0;; *) ok "restart announced" 1;; esac

: > "$T/calls.log"; echo "123.pf-msg-tkneeland	(Detached)" > "$T/screenls"
run >/dev/null; ! grep -q "dmS" "$T/calls.log"; ok "live screen of that name: not duplicated" $?
rm -f "$T/screenls"

: > "$T/calls.log"; echo '{}' > "$T/state/beacon-status.json"; touch -t 202001010000 "$T/state/beacon-status.json"
PF_HIVE_OS=windows run >/dev/null
grep -q "powershell.exe .*-Only msg" "$T/calls.log"; ok "stale msg (windows): pf-start.ps1 -Only msg" $?
grep -q "powershell.exe .*-Only beacon" "$T/calls.log"; ok "stale beacon (windows): restarted" $?

# a pf-hive.sh that hangs must not hang the session
cp -R "$AG" "$T/ag"; printf '#!/bin/bash\nsleep 30\n' > "$T/ag/pf-hive.sh"
s=$(date +%s); PF_HIVE_TIMEOUT=2 bash "$T/ag/pf-hive-join.sh" > "$T/hang.out"; rc=$?; e=$(date +%s)
ok "hung status script: exit 0" "$rc"; [ $((e - s)) -le 5 ]; ok "hung status script: returns within 5s" $?
grep -q "timed out" "$T/hang.out"; ok "timeout noted, session continues" $?

# pf-hive.sh output is passed through
printf '#!/bin/bash\necho "hive: 3 machines up"\n' > "$T/ag/pf-hive.sh"
bash "$T/ag/pf-hive-join.sh" | grep -q "3 machines up"; ok "pf-hive.sh status --short passed through" $?

# unknown account: silent exit 0
PF_ACCOUNT=nobody bash "$AG/pf-hive-join.sh" >/dev/null; ok "unknown account: exit 0" $?
pkill -f "$T/ag/pf-hive.sh" 2>/dev/null
[ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
