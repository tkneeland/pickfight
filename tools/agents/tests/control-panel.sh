#!/bin/bash
# Offline test for control-panel mode (issue #300): banner and the CLAIM / mark-review / `hive-pace.sh start` guards.
# Stub gh/curl/screen on PATH log every call; scratch HIVE_STATE_DIR. macOS, Linux and Git Bash.   bash tools/agents/tests/control-panel.sh
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/control-panel-test.XXXXXX") || exit 1
KA=""; trap '[ -n "$KA" ] && kill $KA 2>/dev/null; kill $RC 2>/dev/null; rm -rf "$T"' EXIT
hive_fixture "$T" || exit 1
mkdir -p "$T/bin" "$T/state"
for s in gh curl screen powershell powershell.exe pwsh; do printf '#!/bin/bash\necho "%s $*" >> "$HIVE_TEST_LOG"\n[ "%s" = curl ] && echo 200\nexit 0\n' "$s" "$s" > "$T/bin/$s"; chmod +x "$T/bin/$s"; done
export PATH="$T/bin:$PATH" HIVE_STATE_DIR=$T/state HIVE_ACCOUNT=alice HIVE_TEST_LOG=$T/calls.log HIVE_DRY_RUN=1 HIVE_JOIN_NO_START=1 HIVE_NO_START=1 HIVE_JOIN_TIMEOUT=30
unset HIVE_SESSION; : > "$T/calls.log"; fails=0
ok() { if [ "$2" = 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
echo "HIVE_MSG_TOPIC=x" > "$T/state/msg.conf"; echo '{}' > "$T/state/msg-status.json"
# a live process whose command line contains hive-keepalive.sh, and a live unrelated one
mkdir "$T/ka"; printf '#!/bin/bash\nwhile true; do sleep 1; done\n' > "$T/ka/hive-keepalive.sh"
bash "$T/ka/hive-keepalive.sh" & KA=$!
sleep 300 & RC=$!; disown $KA $RC 2>/dev/null
sleep 1
join() { bash "$AG/hive-join.sh" 2>&1; }
pace() { bash "$AG/hive-pace.sh" start 2>"$T/err.txt"; }
refused() { [ -s "$T/err.txt" ] && grep -q refused "$T/err.txt"; }
nocalls() { [ ! -s "$T/calls.log" ]; }

# --- control panel: live keepalive, HIVE_SESSION unset
echo "$KA" > "$T/state/keepalive.pid"
out=$(join); rc=$?
case $out in *"CONTROL PANEL"*"FORBIDDEN"*) ok "banner shown" 0;; *) ok "banner shown" 1;; esac
ok "join exits 0" "$rc"
: > "$T/calls.log"
bash "$AG/hive-msg.sh" send CLAIM 5 2>"$T/err.txt"; rc=$?; [ "$rc" != 0 ]; ok "send CLAIM refused (rc=$rc)" $?; refused; ok "send CLAIM says refused" $?; nocalls; ok "send CLAIM: no network call" $?
bash "$AG/hive-msg.sh" claim 5 2>"$T/err.txt"; rc=$?; [ "$rc" != 0 ] && refused && nocalls; ok "claim 5 refused, no call" $?
(. "$AG/hive-env.sh"; GRILL_DOC=docs/grill-decisions.md; hive_mark_review o/r 1 passed) 2>"$T/err.txt"; rc=$?; [ "$rc" != 0 ] && refused && ! grep -q 'pr edit' "$T/calls.log"; ok "hive_mark_review refused, no label edit" $?
pace >/dev/null; rc=$?; [ "$rc" != 0 ] && refused; ok "pace start refused" $?
out=$(bash "$AG/hive-pace.sh" 2>&1); case $out in AHEAD|ON_PACE|BEHIND) ok "bare pace stays open" 0;; *) ok "bare pace stays open ($out)" 1;; esac
# grill-log PR: allowed only for that exact file (GRILL_DOC) by this account (stub gh answers `pr view` from GRILL_PR)
printf '#!/bin/bash\necho "gh $*" >> "$HIVE_TEST_LOG"\ncase "$*" in "pr view"*) echo "$GRILL_PR";; esac\nexit 0\n' > "$T/bin/gh"
grill() { : > "$T/calls.log"; (. "$AG/hive-env.sh"; GRILL_DOC=docs/grill-decisions.md; hive_mark_review o/r 1 passed) 2>"$T/err.txt"; }
export GRILL_PR="alice docs/grill-decisions.md"; grill; rc=$?; [ "$rc" = 0 ] && grep -q 'pr edit' "$T/calls.log"; ok "control panel: grill-decisions-only PR by this account allowed" $?
export GRILL_PR="alice docs/grill-decisions.md,scripts/a.gd"; grill; rc=$?; [ "$rc" != 0 ] && refused && ! grep -q 'pr edit' "$T/calls.log"; ok "control panel: mixed diff refused" $?
export GRILL_PR="alice docs/design.md"; grill; rc=$?; [ "$rc" != 0 ] && refused && ! grep -q 'pr edit' "$T/calls.log"; ok "control panel: other file refused" $?
export GRILL_PR="mallory docs/grill-decisions.md"; grill; rc=$?; [ "$rc" != 0 ] && refused && ! grep -q 'pr edit' "$T/calls.log"; ok "control panel: other author refused" $?
unset GRILL_PR; : > "$T/calls.log"

# --- always-on: same keepalive, HIVE_SESSION=always-on
export HIVE_SESSION=always-on; : > "$T/calls.log"
out=$(join); case $out in *"CONTROL PANEL"*) ok "no banner when always-on" 1;; *) ok "no banner when always-on" 0;; esac
bash "$AG/hive-msg.sh" send CLAIM 5 >/dev/null 2>&1; grep -q '^curl' "$T/calls.log"; ok "always-on: CLAIM reaches curl" $?
: > "$T/calls.log"; (. "$AG/hive-env.sh"; hive_mark_review o/r 1 passed) 2>/dev/null; grep -q 'pr edit' "$T/calls.log"; ok "always-on: mark-review calls gh" $?
out=$(pace); case $out in AHEAD|ON_PACE|BEHIND) ok "always-on: pace start prints a state" 0;; *) ok "always-on: pace start ($out)" 1;; esac
unset HIVE_SESSION

# --- not a control panel: no file, dead pid, recycled pid, garbage
allowed() {  # $1 label
  local out; : > "$T/calls.log"; out=$(join)
  case $out in *"CONTROL PANEL"*) ok "$1: no banner" 1;; *) ok "$1: no banner" 0;; esac
  bash "$AG/hive-msg.sh" send CLAIM 5 >/dev/null 2>&1; grep -q '^curl' "$T/calls.log"; ok "$1: CLAIM allowed" $?
  : > "$T/calls.log"; (. "$AG/hive-env.sh"; hive_mark_review o/r 1 passed) 2>/dev/null; grep -q 'pr edit' "$T/calls.log"; ok "$1: mark-review allowed" $?
  out=$(pace); case $out in AHEAD|ON_PACE|BEHIND) ok "$1: pace start allowed" 0;; *) ok "$1: pace start allowed" 1;; esac
}
rm -f "$T/state/keepalive.pid"; allowed "no pid file"
echo 99999999 > "$T/state/keepalive.pid"; allowed "dead pid"
echo "$RC" > "$T/state/keepalive.pid"; allowed "recycled live pid (sleep)"
echo "abc" > "$T/state/keepalive.pid"; allowed "non-numeric pid"
# PowerShell keepalive format "<pid> <ticks>" with CRLF still counts
printf '%s 639000000000\r\n' "$KA" > "$T/state/keepalive.pid"
case $(join) in *"CONTROL PANEL"*) ok "pid + ticks + CRLF format: banner" 0;; *) ok "pid + ticks + CRLF format: banner" 1;; esac

# --- ps -W shim: a Windows pid that kill -0 cannot see; ps -p fails
mkdir "$T/winbin"
cat > "$T/winbin/ps" <<'EOP'
#!/bin/bash
[ "$1" = -W ] && { echo "      PID    PPID    PGID     WINPID   TTY         UID    STIME COMMAND"; echo "        1       0       1       $HIVE_TEST_WINCMD"; exit 0; }
exit 1
EOP
chmod +x "$T/winbin/ps"
echo 99999998 > "$T/state/keepalive.pid"
HIVE_TEST_WINCMD="99999998 1 99999998 99999998 ? 1000 12:00:00 /c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
export HIVE_TEST_WINCMD
case $(PATH="$T/winbin:$PATH" join) in *"CONTROL PANEL"*) ok "ps -W powershell pid: control panel" 0;; *) ok "ps -W powershell pid: control panel" 1;; esac
HIVE_TEST_WINCMD="99999998 1 99999998 99999998 ? 1000 12:00:00 /c/Windows/notepad.exe"
case $(PATH="$T/winbin:$PATH" join) in *"CONTROL PANEL"*) ok "ps -W non-powershell pid: not control panel" 1;; *) ok "ps -W non-powershell pid: not control panel" 0;; esac

# a missing /proc/<pid>/cmdline (PowerShell keepalive pid) is silent
err=$(PATH="$T/winbin:$PATH" bash -c '. "$1/hive-env.sh"; hive_keepalive_running' _ "$AG" 2>&1 >/dev/null)
[ -z "$err" ]; ok "missing /proc cmdline: no stderr noise" $?

# --- Windows keepalive's headless claude is an ancestor (issue #307): HIVE_SESSION is not visible to the Bash tool's shell
mkdir "$T/ancbin"
printf '#!/bin/bash
for p in $HIVE_TEST_ANC; do echo "$p"; done
' > "$T/ancbin/powershell.exe"; chmod +x "$T/ancbin/powershell.exe"
echo "$KA" > "$T/state/keepalive.pid"; echo "$RC" > "$T/state/keepalive-claude.pid"
# ps -W names the claude pid (the real row for RC is "sleep"; HIVE_TEST_RCCMD picks the name)
printf '#!/bin/bash
if [ "$1" = -W ]; then echo "      PID    PPID    PGID     WINPID   TTY         UID    STIME COMMAND"; echo "  $HIVE_TEST_RC 1 $HIVE_TEST_RC $HIVE_TEST_RC ? 1000 12:00:00 $HIVE_TEST_RCCMD"; exit 0; fi
exec /usr/bin/ps "$@"
' > "$T/ancbin/ps"; chmod +x "$T/ancbin/ps"
export HIVE_TEST_RC=$RC HIVE_TEST_RCCMD=/c/Users/x/.local/bin/claude.exe
export HIVE_TEST_ANC="4242 $RC 1"
: > "$T/calls.log"; out=$(PATH="$T/ancbin:$PATH" join)
case $out in *"CONTROL PANEL"*) ok "claude pid is an ancestor: no banner" 1;; *) ok "claude pid is an ancestor: no banner" 0;; esac
PATH="$T/ancbin:$PATH" pace >/dev/null; rc=$?; [ "$rc" = 0 ] && ! refused; ok "claude pid is an ancestor: pace start allowed" $?
(PATH="$T/ancbin:$PATH"; . "$AG/hive-env.sh"; hive_guard x) 2>/dev/null; ok "claude pid is an ancestor: hive_guard allows" $?
export HIVE_TEST_RCCMD=/c/Windows/System32/notepad.exe   # recycled pid: alive and an ancestor, but no longer claude
case $(PATH="$T/ancbin:$PATH" join) in *"CONTROL PANEL"*) ok "recycled claude pid: control panel" 0;; *) ok "recycled claude pid: control panel" 1;; esac
export HIVE_TEST_RCCMD=/c/Users/x/.local/bin/claude.exe
export HIVE_TEST_ANC="4242 1"   # interactive terminal on the same machine: claude pid is not an ancestor
case $(PATH="$T/ancbin:$PATH" join) in *"CONTROL PANEL"*) ok "claude pid not an ancestor: control panel" 0;; *) ok "claude pid not an ancestor: control panel" 1;; esac
PATH="$T/ancbin:$PATH" pace >/dev/null; rc=$?; [ "$rc" != 0 ] && refused; ok "claude pid not an ancestor: pace start refused" $?
echo 99999997 > "$T/state/keepalive-claude.pid"; export HIVE_TEST_ANC="4242 99999997"   # dead claude pid never counts
case $(PATH="$T/ancbin:$PATH" join) in *"CONTROL PANEL"*) ok "dead claude pid: control panel" 0;; *) ok "dead claude pid: control panel" 1;; esac
rm -f "$T/state/keepalive-claude.pid"; unset HIVE_TEST_ANC

# --- --print-prompt writes no pid file; the sources set HIVE_SESSION for unattended sessions
rm -f "$T/state/keepalive.pid"; bash "$AG/hive-keepalive.sh" --print-prompt >/dev/null 2>&1
[ ! -e "$T/state/keepalive.pid" ]; ok "--print-prompt creates no keepalive.pid" $?
grep -q 'HIVE_SESSION=always-on' "$AG/hive-keepalive.sh"; ok "hive-keepalive.sh launches with HIVE_SESSION=always-on" $?
grep -q 'HIVE_SESSION = "always-on"' "$AG/windows/hive-keepalive.ps1"; ok "hive-keepalive.ps1 sets HIVE_SESSION" $?
grep -q 'HIVE_SESSION=always-on' "$AG/hive-reserve.sh"; ok "hive-reserve.sh launches with HIVE_SESSION=always-on" $?
grep -q 'HIVE_SESSION=always-on' "$AG/hive-resume.sh"; ok "hive-resume.sh runs with HIVE_SESSION=always-on" $?

# --- a pre-upgrade always-on session (no HIVE_SESSION) is recognised by its screen ancestor, not locked out
echo "$KA" > "$T/state/keepalive.pid"
out=$(bash -c 'exec -a "SCREEN -dmS hive-x-alice bash" bash -c "bash \"$0\" 2>&1; echo \$?" "$1"' "$AG/hive-join.sh" "$AG/hive-join.sh" 2>&1)
if [ -n "$(ps -o ppid= -p $$ 2>/dev/null)" ]; then   # Git Bash ps has no -o: the screen-ancestor check is a no-op there
  case $out in *"CONTROL PANEL"*) ok "screen-session ancestor: no banner (legacy always-on)" 1;; *) ok "screen-session ancestor: no banner (legacy always-on)" 0;; esac
else echo "skip screen-session ancestor (ps -o unavailable)"; fi
case $(join) in *"CONTROL PANEL"*) ok "no screen ancestor: banner stays" 0;; *) ok "no screen ancestor: banner stays" 1;; esac
# --- a second keepalive does not overwrite or delete the first one's pid file
mkdir -p "$T/ka2"; cp "$AG/hive-keepalive.sh" "$T/ka2/" 2>/dev/null; echo "$KA" > "$T/state/keepalive.pid"
[ "$(cat "$T/state/keepalive.pid")" = "$KA" ]; ok "pid file intact with a live keepalive" $?

[ "$fails" = 0 ] && echo "control-panel: all ok" || { echo "control-panel: $fails failed"; exit 1; }
