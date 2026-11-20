#!/bin/bash
# Offline test for hive-join.sh: stub screen/powershell on PATH, scratch HIVE_STATE_DIR. No network.
# macOS, Linux and Git Bash.   bash tools/agents/tests/hive-join.sh
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/hive-join-test.XXXXXX") || exit 1; trap 'rm -rf "$T"' EXIT
hive_fixture "$T" || exit 1
mkdir -p "$T/bin" "$T/state"
# the real tools, captured before the stubs shadow them (pgrep is absent on Git Bash)
real_pgrep=$(command -v pgrep); real_ps=$(command -v ps)
for s in screen powershell.exe; do printf '#!/bin/bash\necho "%s $*" >> "$HIVE_TEST_LOG"\n[ "%s" = screen ] && [ "$1" = -ls ] && cat "$HIVE_TEST_SCREENLS" 2>/dev/null\n[ "%s" = powershell.exe ] && [ -n "$HIVE_TEST_PS_SLEEP" ] && sleep "$HIVE_TEST_PS_SLEEP"\nexit 0\n' "$s" "$s" "$s" > "$T/bin/$s"; chmod +x "$T/bin/$s"; done   # HIVE_TEST_PS_SLEEP (powershell stub only) makes it linger, like a real hive-start.ps1 launch
# pgrep stub: the listener check is scripted; any other lookup (the watchdog's child scan) goes to the real pgrep
printf '#!/bin/bash\ncase "$*" in *hive-msg.sh*) [ -n "$HIVE_TEST_PGREP" ] && echo "$HIVE_TEST_PGREP" && exit 0; exit 1;; esac\n[ -n "%s" ] && exec "%s" "$@"\nexit 1\n' "$real_pgrep" "$real_pgrep" > "$T/bin/pgrep"; chmod +x "$T/bin/pgrep"
printf '#!/bin/bash\nexit 0\n' > "$T/bin/ps"; chmod +x "$T/bin/ps"   # no real processes visible to the hook
export PATH="$T/bin:$PATH" HIVE_STATE_DIR=$T/state HIVE_ACCOUNT=alice HIVE_TEST_LOG=$T/calls.log HIVE_TEST_SCREENLS=$T/screenls
export HIVE_DRY_RUN=1   # hive.sh --cached starts no background refresh (no network)
: > "$T/calls.log"; fails=0
ok() { if [ "$2" = 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
# Pin the OS the unix cases exercise; uname is MINGW on Git Bash, which would take the windows path. Windows cases set HIVE_JOIN_OS=windows.
# the hook itself takes 3-6 s on a loaded Windows box, so cases that are not about the timeout get a roomy one (#384)
export HIVE_JOIN_TIMEOUT=20
run() { HIVE_JOIN_OS=${HIVE_JOIN_OS:-unix} bash "$AG/hive-join.sh"; }
echo "HIVE_MSG_TOPIC=x" > "$T/state/msg.conf"

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
: > "$T/calls.log"; HIVE_TEST_PGREP=4242 run > "$T/o.txt"
[ ! -s "$T/calls.log" ]; ok "bare/keepalive hive-msg.sh listen running: no second listener" $?
! grep -q restarted "$T/o.txt"; ok "...and no false restarted line" $?
out=$(run)
grep -Eq "screen -dmS hive-msg-[^ ]+-alice" "$T/calls.log"; ok "stale msg (unix): screen restart, named per repo" $?
sname=$(grep -Eo "hive-msg-[^ ]+-alice" "$T/calls.log" | head -n 1)
case $out in *"restarted dead msg"*) ok "restart announced" 0;; *) ok "restart announced" 1;; esac

: > "$T/calls.log"; printf '123.%s\t(Detached)\n' "$sname" > "$T/screenls"
run >/dev/null; ! grep -q "dmS" "$T/calls.log"; ok "live screen of that name: not duplicated" $?
printf '124.hive-msg-alice\t(Detached)\n125.hive-msg-othergame-alice\t(Detached)\n' > "$T/screenls"; : > "$T/calls.log"
run >/dev/null; grep -q "dmS" "$T/calls.log"; ok "another game's (or a pre-repo-name) msg screen doesn't block this repo's" $?
rm -f "$T/screenls"

# Windows: one hive-start.ps1 call (no -Only) when anything is stale
: > "$T/calls.log"; echo '{}' > "$T/state/beacon-status.json"; touch -t 202001010000 "$T/state/beacon-status.json"
HIVE_JOIN_OS=windows run >/dev/null
# the launch is detached: wait (up to ~5s) for its log line, then 1s more so a duplicate would show. A fixed sleep 1 let a
# slow launch log late, failing this check and then "no launch when all alive" below (seen on Linux under all.sh).
i=0; until grep -q powershell.exe "$T/calls.log" || [ "$i" -ge 25 ]; do sleep 0.2; i=$((i + 1)); done; sleep 1
[ "$(grep -c powershell.exe "$T/calls.log")" = 1 ]; ok "windows: exactly one hive-start.ps1 launch" $?
! grep -q -- "-Only" "$T/calls.log"; ok "windows: no -Only (starts whatever is down)" $?
sleep 1
# idle healthy triage / automerge must not be reported restarted
: > "$T/calls.log"; touch "$T/state/msg-status.json" "$T/state/beacon-status.json" "$T/state/.triage-watch-alive"
for k in triage automerge; do echo '{}' > "$T/state/$k-status.json"; touch -t 202001010000 "$T/state/$k-status.json"; done
echo $$ > "$T/state/automerge.pid"; touch "$T/state/.triage-watch-alive"; touch -t 202601010000 "$T/state/automerge-status.json"
out=$(HIVE_JOIN_OS=windows run); case $out in *restarted*) ok "windows: healthy triage/automerge not restarted" 1;; *) ok "windows: healthy triage/automerge not restarted" 0;; esac
sleep 1; [ ! -s "$T/calls.log" ]; ok "windows: no launch when all alive" $?
touch -t 202001010000 "$T/state/.triage-watch-alive"
out=$(HIVE_JOIN_OS=windows run); case $out in *"restarted dead triage"*) ok "windows: dead triage heartbeat restarts" 0;; *) ok "windows: dead triage heartbeat restarts" 1;; esac

# stale automerge with a dead pid file is restarted; an alive pid is not
touch "$T/state/msg-status.json" "$T/state/beacon-status.json" "$T/state/.triage-watch-alive"; echo 99999999 > "$T/state/automerge.pid"; touch -t 202001010000 "$T/state/automerge-status.json"
out=$(HIVE_JOIN_OS=windows run); case $out in *"restarted dead automerge"*) ok "windows: dead automerge pid restarts" 0;; *) ok "windows: dead automerge pid restarts" 1;; esac
echo $$ > "$T/state/automerge.pid"
out=$(HIVE_JOIN_OS=windows run); case $out in *automerge*) ok "windows: live automerge pid not restarted" 1;; *) ok "windows: live automerge pid not restarted" 0;; esac
sed -n 3p "$AG/hive-join.sh" | grep -q SessionStart && ! sed -n 3p "$AG/hive-join.sh" | grep -q matcher; ok "hook has no matcher (resume/clear sessions join too)" $?

# a hive.sh that hangs must not hang the session
cp -R "$AG" "$T/ag"; printf '#!/bin/bash\nbash "%s/bin/hang"\n' "$T" > "$T/ag/hive.sh"   # two levels, temp dir in every argv: a direct-children-only kill leaves bin/hang
printf '#!/bin/bash\n: > "%s/hang.started"\nwhile :; do sleep 1; done\n' "$T" > "$T/bin/hang"; chmod +x "$T/bin/hang"
# the real default deadline (6 s): a shorter one can fire before the slow Windows inner even reaches hive.sh, and then the
# kill below is never exercised (#384). hang.started proves the hung tree existed when the watchdog fired.
s=$(date +%s); HIVE_JOIN_TIMEOUT=6 bash "$T/ag/hive-join.sh" > "$T/hang.out"; rc=$?; e=$(date +%s)
ok "hung status script: exit 0" "$rc"; [ $((e - s)) -le 9 ]; ok "hung status script: returns within 9s (deadline 6 s + kill)" $?
[ -f "$T/hang.started" ]; ok "hung status script: the hung tree was running when the watchdog fired" $?
grep -q "timed out" "$T/hang.out"; ok "timeout noted, session continues" $?
# ps_has <text>: does any real process's command line contain it? (listing goes to a file first, so the grep is never listed)
ps_has() { "$real_ps" -ef > "$T/ps.out" 2>/dev/null; grep -qF -- "$1" "$T/ps.out"; }
# wait_gone <text>: poll up to ~5s because Windows process teardown lags the kill (#384)
wait_gone() { local i=0; while ps_has "$1" && [ "$i" -lt 25 ]; do sleep 0.2; i=$((i + 1)); done; ! ps_has "$1"; }
wait_gone "$T/ag/hive.sh" && wait_gone "$T/bin/hang"; ok "hung status script: no hive.sh or nested hang left running" $?
# a failed kill must not cascade into the spare case below
for p in $(grep -F -e "$T/ag/hive.sh" -e "$T/bin/hang" "$T/ps.out" | awk '{print $2}'); do hive_kill_tree "$p"; done

# the timeout must spare the detached hive-start launch it recorded (windows path), while killing the hung hive.sh
: > "$T/calls.log"; touch "$T/state/msg-status.json" "$T/state/beacon-status.json" "$T/state/.triage-watch-alive"
touch -t 202001010000 "$T/state/beacon-status.json"
HIVE_JOIN_OS=windows HIVE_JOIN_TIMEOUT=10 HIVE_TEST_PS_SLEEP=30 bash "$T/ag/hive-join.sh" > "$T/spare.out"
ps_has "$T/bin/powershell.exe"; ok "timeout spares the detached hive-start launch" $?
wait_gone "$T/ag/hive.sh" && wait_gone "$T/bin/hang"; ok "timeout with a launch: hung hive.sh and nested hang gone" $?
ps_has "$T/bin/powershell.exe" && for p in $(grep -F "$T/bin/powershell.exe" "$T/ps.out" | awk '{print $2}'); do hive_kill_tree "$p"; done
touch "$T/state/beacon-status.json"

# hive.sh output is passed through
printf '#!/bin/bash\necho "hive: 3 machines up"\n' > "$T/ag/hive.sh"
bash "$T/ag/hive-join.sh" | grep -q "3 machines up"; ok "hive.sh status --short passed through" $?

# unknown account: silent exit 0
HIVE_ACCOUNT=nobody bash "$AG/hive-join.sh" >/dev/null; ok "unknown account: exit 0" $?
wait_gone "$T"; ok "no process with the test's temp dir in its command line survives" $?
if grep -qF -- "$T" "$T/ps.out"; then   # a failing run still cleans up
  grep -F -- "$T" "$T/ps.out"; for p in $(grep -F -- "$T" "$T/ps.out" | awk '{print $2}'); do hive_kill_tree "$p"; done
fi
[ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
