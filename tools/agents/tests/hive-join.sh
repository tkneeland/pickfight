#!/bin/bash
# Offline test for pf-hive-join.sh (#1209): stub screen/powershell on PATH, scratch PF_STATE_DIR. No network.
# macOS, Linux and Git Bash.   bash tools/agents/tests/hive-join.sh
AG=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/pf-hive-test.XXXXXX") || exit 1; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/state"
for s in screen powershell.exe; do printf '#!/bin/bash\necho "%s $*" >> "$PF_TEST_LOG"\n[ "%s" = screen ] && [ "$1" = -ls ] && cat "$PF_TEST_SCREENLS" 2>/dev/null\nexit 0\n' "$s" "$s" > "$T/bin/$s"; chmod +x "$T/bin/$s"; done
printf '#!/bin/bash\n[ -n "$PF_TEST_PGREP" ] && echo "$PF_TEST_PGREP" && exit 0\nexit 1\n' > "$T/bin/pgrep"; chmod +x "$T/bin/pgrep"
printf '#!/bin/bash\nexit 0\n' > "$T/bin/ps"; chmod +x "$T/bin/ps"   # no real processes visible to the test
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
mkdir "$T/state/.hive-join.lock"; : > "$T/calls.log"; run >/dev/null
[ ! -s "$T/calls.log" ]; ok "lock held by another session: no second restart" $?
rmdir "$T/state/.hive-join.lock"
: > "$T/calls.log"; PF_TEST_PGREP=4242 run > "$T/o.txt"
[ ! -s "$T/calls.log" ]; ok "bare/keepalive pf-msg.sh listen running: no second listener" $?
! grep -q restarted "$T/o.txt"; ok "...and no false restarted line" $?
out=$(run)
grep -q "screen -dmS pf-msg-tkneeland" "$T/calls.log"; ok "stale msg (unix): screen restart" $?
case $out in *"restarted dead msg"*) ok "restart announced" 0;; *) ok "restart announced" 1;; esac

: > "$T/calls.log"; echo "123.pf-msg-tkneeland	(Detached)" > "$T/screenls"
run >/dev/null; ! grep -q "dmS" "$T/calls.log"; ok "live screen of that name: not duplicated" $?
echo "124.pf-msg	(Detached)" > "$T/screenls"; : > "$T/calls.log"
run >/dev/null; ! grep -q "dmS" "$T/calls.log"; ok "README-named pf-msg session recognised" $?
rm -f "$T/screenls"

# Windows: one pf-start.ps1 call (no -Only) when anything is stale
: > "$T/calls.log"; echo '{}' > "$T/state/beacon-status.json"; touch -t 202001010000 "$T/state/beacon-status.json"
PF_HIVE_OS=windows run >/dev/null; sleep 1   # the launch is detached
[ "$(grep -c powershell.exe "$T/calls.log")" = 1 ]; ok "windows: exactly one pf-start.ps1 launch" $?
! grep -q -- "-Only" "$T/calls.log"; ok "windows: no -Only (starts whatever is down)" $?
sleep 1
# idle healthy triage / automerge must not be reported restarted
: > "$T/calls.log"; touch "$T/state/msg-status.json" "$T/state/beacon-status.json" "$T/state/.triage-watch-alive"
for k in triage automerge; do echo '{}' > "$T/state/$k-status.json"; touch -t 202001010000 "$T/state/$k-status.json"; done
echo $$ > "$T/state/automerge.pid"; touch "$T/state/.triage-watch-alive"; touch -t 202601010000 "$T/state/automerge-status.json"
out=$(PF_HIVE_OS=windows run); case $out in *restarted*) ok "windows: healthy triage/automerge not restarted" 1;; *) ok "windows: healthy triage/automerge not restarted" 0;; esac
sleep 1; [ ! -s "$T/calls.log" ]; ok "windows: no launch when all alive" $?
touch -t 202001010000 "$T/state/.triage-watch-alive"
out=$(PF_HIVE_OS=windows run); case $out in *"restarted dead triage"*) ok "windows: dead triage heartbeat restarts" 0;; *) ok "windows: dead triage heartbeat restarts" 1;; esac

# stale automerge with a dead pid file is restarted; an alive pid is not
touch "$T/state/msg-status.json" "$T/state/beacon-status.json" "$T/state/.triage-watch-alive"; echo 99999999 > "$T/state/automerge.pid"; touch -t 202001010000 "$T/state/automerge-status.json"
out=$(PF_HIVE_OS=windows run); case $out in *"restarted dead automerge"*) ok "windows: dead automerge pid restarts" 0;; *) ok "windows: dead automerge pid restarts" 1;; esac
echo $$ > "$T/state/automerge.pid"
out=$(PF_HIVE_OS=windows run); case $out in *automerge*) ok "windows: live automerge pid not restarted" 1;; *) ok "windows: live automerge pid not restarted" 0;; esac
grep -q matcher "$AG/../../.claude/settings.json"; [ $? != 0 ]; ok "hook has no matcher (resume/clear sessions join too)" $?

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
