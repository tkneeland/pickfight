#!/bin/bash
# Shared fixture for the offline tests in this folder. Source it, then call hive_fixture <scratch dir>: it copies
# tools/agents (scripts, windows/) into <scratch>/repo/tools/agents with four fixture accounts and a hive.conf, exports
# HIVE_CONF, and sets AG to the copied tools/agents. The real accounts/ and hive.conf of the project are never read.
#   alice  rank 1, the triagemaster, DISPLAY_NAME Alice
#   bob    rank 2, DISPLAY_NAME Bob
#   carol  rank 3, DISPLAY_NAME Carol
#   dave   rank 4, RESERVE=1, DISPLAY_NAME Dave
# hive.conf: REPO=example/project, DECISIONS_ISSUE=500, DISCORD=1 with fake ids (guild 3000000000000000000, bugs channel
# 3000000000000000001, dev channel 3000000000000000002), HIVE_TZ America/New_York labelled ET. Override any key with a
# second argument of KEY=value lines (appended).
HIVE_TEST_SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HIVE_FIX_GUILD=3000000000000000000; HIVE_FIX_BUGS=3000000000000000001; HIVE_FIX_DEV=3000000000000000002
hive_fixture() {
  local d=$1/repo extra=${2:-} h r n res
  mkdir -p "$d/tools/agents/accounts" || return 1
  cp "$HIVE_TEST_SRC"/*.sh "$HIVE_TEST_SRC"/*.md "$d/tools/agents/" 2>/dev/null
  [ -d "$HIVE_TEST_SRC/windows" ] && cp -R "$HIVE_TEST_SRC/windows" "$d/tools/agents/"
  cat > "$d/tools/agents/accounts/_shared.conf" <<'EOF'
RESET_GRACE_HOURS=24
FIVE_H_STOP_USED=90
PEER_QUEUE_MIN=5
BEACON_FRESH_HOURS=6
DIGEST_HOUR=9
EOF
  while read -r h r n res; do
    printf 'ROLE=%s\nTZ=America/New_York\nQUIET_START=20\nQUIET_END=9\nSUCCESSION_RANK=%s\nDISPLAY_NAME="%s"\nRESERVE=%s\n' \
      "$([ "$r" = 1 ] && echo triagemaster || echo dev)" "$r" "$n" "$res" > "$d/tools/agents/accounts/$h.conf"
  done <<EOF
alice 1 Alice 0
bob 2 Bob 0
carol 3 Carol 0
dave 4 Dave 1
EOF
  cat > "$d/hive.conf" <<EOF
REPO=example/project
DECISIONS_ISSUE=500
PROJECT_NAME=Project
OWNER=alice
HIVE_TZ=America/New_York
HIVE_TZ_LABEL=ET
TZ_LABEL=ET
DISCORD=1
DISCORD_GUILD=$HIVE_FIX_GUILD
DISCORD_BUGS_CHANNEL=$HIVE_FIX_BUGS
DISCORD_DEV_CHANNEL=$HIVE_FIX_DEV
EOF
  [ -n "$extra" ] && printf "%s\n" "$extra" >> "$d/hive.conf"
  export HIVE_CONF=$d/hive.conf
  AG=$d/tools/agents
}

# ---- safety net shared by the offline tests (issue #338: three tests hung on Windows Git Bash) -------------------------------
# Sourcing lib.sh does four things, all no-ops on a healthy macOS/Linux box:
#  1 stdin is /dev/null, so nothing a test starts (a curl stub's `cat`, a script's `read`) can block on a terminal or on a pipe
#    that never closes;
#  2 on Git Bash a Windows-style TMPDIR (C:\Users\..\Temp) becomes a POSIX path, because PATH="$T/bin:$PATH" splits on ':' and a
#    drive letter silently drops the stub dir from PATH, so the REAL curl/gh ran (a live Discord error in discord-bugs.sh);
#  3 hive_test_guard <seconds> arms a watchdog that kills the test (and its children) if it is still running, so a hang is a
#    FAIL after HIVE_TEST_MAX s (default 240; 900 on Git Bash, issue #412), never a stuck all.sh. `timeout` does not exist on Git Bash, so it is plain bash;
#  4 hive_test_cleanup (the EXIT trap) kills every background job and child the test started, then removes the scratch dir.
exec </dev/null
# HIVE_OS and HIVE_GNU are probed here once and exported (hive-env.sh reuses them), so a test does not pay uname and `date --version`
# on every script it starts: a spawn is ~10x slower on Git Bash (issue #338). A test that wants the probe unsets them.
HIVE_OS=$(uname -s); if date --version >/dev/null 2>&1; then HIVE_GNU=1; else HIVE_GNU=0; fi; export HIVE_OS HIVE_GNU
case $HIVE_OS in MINGW*|MSYS*|CYGWIN*) HIVE_TEST_WIN=1;; *) HIVE_TEST_WIN=0;; esac
if [ "$HIVE_TEST_WIN" = 1 ] && [ -n "${TMPDIR:-}" ] && command -v cygpath >/dev/null 2>&1; then TMPDIR=$(cygpath -u "$TMPDIR"); export TMPDIR; fi
# hive_kids <pid>: child pids. On Cygwin/MSYS (/proc/self/ppid exists) scan the /proc ppid files, so a test's pgrep stub on PATH
# cannot blind it; elsewhere pgrep -P. 2>/dev/null comes before the < so a process that exits mid-scan does not print
# "/proc/<pid>/ppid: No such file", issue #338
hive_kids() { local c
  if [ -e /proc/self/ppid ]; then for c in /proc/[0-9]*; do [ "$(tr -d '\r[:space:]' 2>/dev/null < "$c/ppid")" = "$1" ] && echo "${c#/proc/}"; done
  else pgrep -P "$1" 2>/dev/null; fi; return 0; }
# hive_kill_tree <pid>: the pid and everything below it (a `sleep` under a trapped bash would otherwise outlive it)
hive_kill_tree() { local k; [ -n "$1" ] || return 0
  for k in $(hive_kids "$1"); do hive_kill_tree "$k"; done
  kill "$1" 2>/dev/null; return 0; }
HIVE_TEST_PIDS=""   # a test may append pids it wants killed on exit
hive_test_cleanup() { local p
  trap - EXIT INT TERM
  [ -n "${HIVE_WD:-}" ] && kill "$HIVE_WD" 2>/dev/null
  for p in $(jobs -p) $HIVE_TEST_PIDS; do hive_kill_tree "$p"; done
  [ -n "${T:-}" ] && rm -rf "$T"; return 0; }
hive_test_guard() {  # hive_test_guard [seconds]: arm the watchdog and the traps
  # default 240 s; 900 s on Git Bash (spawns are ~10x slower, hive-failover.sh alone takes 245-270 s on a loaded box, issue #412)
  local parent=$$ max=${1:-${HIVE_TEST_MAX:-$([ "$HIVE_TEST_WIN" = 1 ] && echo 900 || echo 240)}}
  trap 'hive_test_cleanup' EXIT; trap 'exit 143' INT TERM
  ( i=0; while [ "$i" -lt "$max" ] && kill -0 "$parent" 2>/dev/null; do sleep 1; i=$((i+1)); done
    if kill -0 "$parent" 2>/dev/null; then echo "FAIL watchdog: ${0##*/} still running after ${max}s, killed" >&2; for k in $(hive_kids "$parent"); do [ "$k" = "$BASHPID" ] || hive_kill_tree "$k"; done   # a trap does not run under a foreground child: kill the children first
      kill -TERM "$parent" 2>/dev/null; sleep 3; kill -KILL "$parent" 2>/dev/null; [ -n "${T:-}" ] && rm -rf "$T"; fi
  ) </dev/null &
  HIVE_WD=$!; disown "$HIVE_WD" 2>/dev/null; }   # disowned: no "Terminated" job notice when the cleanup kills it
# hive_stub_jq <bin dir>: Windows jq.exe ends lines with CRLF, which survives $(...) and breaks comparisons in the tests' own jq
# calls and in the stubs; a bin/jq that runs `jq -b` fixes both (hive-env.sh does the same for the scripts). No-op elsewhere.
hive_stub_jq() { local real; real=$(command -v jq) || return 0
  case "$("$real" -n -r '"x","y"' 2>/dev/null)" in *$'\r'*) printf '#!/bin/bash\nexec "%s" -b "$@"\n' "$real" > "$1/jq"; chmod +x "$1/jq";; esac; return 0; }
# hive_require_stub <bin dir> <cmd>...: abort the test unless each command resolves to the stub, so a PATH problem can never
# reach the real network (curl) or the real repo (gh)
hive_require_stub() { local d=$1 c; shift
  for c in "$@"; do [ "$(command -v "$c")" = "$d/$c" ] || { echo "FAIL $c is not the stub (resolves to '$(command -v "$c")'); refusing to run with a real $c" >&2; exit 1; }; done; }
# hive_noop_stub <bin dir> <cmd>...: a stub that does nothing and exits 0
hive_noop_stub() { local d=$1 c; shift; for c in "$@"; do printf '#!/bin/bash\nexit 0\n' > "$d/$c"; chmod +x "$d/$c"; done; }
