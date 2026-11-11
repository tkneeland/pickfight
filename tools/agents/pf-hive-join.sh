#!/bin/bash
# SessionStart hook (#1209): every Claude session on this machine joins the hive.
#   1. reminds the agent to read docs/agents/team-memory.md
#   2. restarts this machine's dead private-channel supervisor (listener + heartbeat), and on Windows the
#      triage/automerge/beacon supervisors too (reusing windows/pf-start.ps1; macOS: `screen` + windows/pf-supervise.sh)
#   3. prints `pf-hive.sh status --short --cached` (#1208: the last status at once, refreshed in the background) when
#      that script exists, else a one-line local status
# Silent on success apart from the status. Never blocks or fails the session: the whole check runs under a watchdog
# (PF_HIVE_TIMEOUT seconds, default 4) and the exit code is always 0. No network use of its own; the cached status
# starts a detached refresh (pf-hive.sh: at most once a minute, one at a time) that outlives the watchdog by design.
# Env (tests): PF_HIVE_OS=windows|unix, PF_HIVE_TIMEOUT, PF_STATE_DIR, PF_ACCOUNT, PF_HIVE_STALE (msg status max age s, default 180).
AG=$(cd "$(dirname "$0")" && pwd)
if [ -z "${PF_HIVE_INNER:-}" ]; then
  out=$(mktemp "${TMPDIR:-/tmp}/pf-hive-join.XXXXXX" 2>/dev/null) || exit 0
  PF_HIVE_INNER=1 bash "$0" "$@" > "$out" 2>/dev/null < /dev/null & pid=$!
  tries=$(( ${PF_HIVE_TIMEOUT:-4} * 5 )); i=0
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt "$tries" ]; do sleep 0.2; i=$((i + 1)); done
  if kill -0 "$pid" 2>/dev/null; then
    command -v pkill >/dev/null 2>&1 && pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null
    echo "hive: join check timed out after ${PF_HIVE_TIMEOUT:-4}s, session continues (run tools/agents/pf-hive-join.sh to retry)"
  fi
  cat "$out" 2>/dev/null; rm -f "$out"; exit 0
fi

unset PF_HIVE_INNER   # do not leak into supervisors we spawn
echo "hive: read docs/agents/team-memory.md (the hive's shared memory) before working."
. "$AG/pf-env.sh" >/dev/null 2>&1 || { echo "hive: no account conf for this machine (set PF_ACCOUNT), not joined"; exit 0; }

case ${PF_HIVE_OS:-$(uname -s)} in MINGW*|MSYS*|CYGWIN*|windows) WIN=1;; *) WIN=0;; esac
age() { local m; m=$(pf_mtime "$1") || { echo 999999; return; }; echo $(( $(date +%s) - m )); }
restarted=""
# one restarter at a time: sessions opened together (AT, workers, reserve) race otherwise. mkdir is atomic everywhere.
LOCK=$PF_STATE/.hive-join.lock
if ! mkdir "$LOCK" 2>/dev/null; then
  [ $(( $(date +%s) - $(pf_mtime "$LOCK" || echo 0) )) -gt 60 ] && { rmdir "$LOCK" 2>/dev/null; mkdir "$LOCK" 2>/dev/null; } || LOCKED=1
fi
[ -z "${LOCKED:-}" ] && trap 'rmdir "$LOCK" 2>/dev/null' EXIT
# start_unix <kind>: macOS/Linux supervisor in a detached screen; any live session named pf-<kind> or pf-<kind>-<account> counts
start_unix() {
  local kind=$1
  if command -v screen >/dev/null 2>&1; then
    screen -ls 2>/dev/null | grep -Eq "[0-9]\.pf-$kind(-$PF_ACCOUNT)?[[:space:]]" && return 0
    screen -dmS "pf-$kind-$PF_ACCOUNT" bash "$AG/windows/pf-supervise.sh" "$kind" >/dev/null 2>&1
  else
    nohup bash "$AG/windows/pf-supervise.sh" "$kind" >/dev/null 2>&1 &
  fi
  restarted="$restarted $kind"
}
# any running `pf-msg.sh listen` (bare, launchd, keepalive or our supervisor) is alive: never start a second one
listener_running() { pgrep -f 'pf-msg.sh listen' >/dev/null 2>&1 || ps -ax -o command 2>/dev/null | grep -q '[p]f-msg.sh listen' \
  || ps -W 2>/dev/null | grep -q '[p]f-msg.sh listen'; }
# pid_alive <pid>: Git Bash-safe (ps -W lists Windows pids); unknown when neither tool works counts as alive
pid_alive() { [ -n "$1" ] || return 1; kill -0 "$1" 2>/dev/null && return 0
  if ps -W >/dev/null 2>&1; then ps -W 2>/dev/null | awk -v p="$1" '$1==p||$4==p{f=1} END{exit !f}'; else return 1; fi; }
need=""
# msg: the listener + heartbeat supervisor rewrites msg-status.json every 60 s
if [ -f "$PF_STATE/pf-msg.conf" ] && [ "$(age "$PF_STATE/msg-status.json")" -gt "${PF_HIVE_STALE:-180}" ] && ! listener_running; then need="$need msg"; fi
# Windows keeps every AT watcher under pf-start.ps1; same liveness signals as pf-tm-check.sh
if [ "$WIN" = 1 ]; then
  [ -f "$PF_STATE/triage-status.json" ] && [ "$(age "$PF_STATE/.triage-watch-alive")" -gt 900 ] && need="$need triage"
  [ -f "$PF_STATE/automerge-status.json" ] && [ "$(age "$PF_STATE/automerge-status.json")" -gt 86400 ] \
    && ! pid_alive "$(cat "$PF_STATE/automerge.pid" 2>/dev/null | tr -d '\r')" && need="$need automerge"
  [ -f "$PF_STATE/beacon-status.json" ] && [ "$(age "$PF_STATE/beacon-status.json")" -gt 900 ] && need="$need beacon"
fi
if [ -n "$need" ] && [ -z "${LOCKED:-}" ]; then
  if [ "$WIN" = 1 ]; then
    # one detached pf-start.ps1 for everything (it skips watchers that already run), so the watchdog never cuts a launch in half
    ps=powershell.exe; command -v powershell.exe >/dev/null 2>&1 || ps=powershell
    if command -v "$ps" >/dev/null 2>&1; then
      nohup "$ps" -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$AG/windows/pf-start.ps1" 2>/dev/null || echo "$AG/windows/pf-start.ps1")" -Account "$PF_ACCOUNT" >/dev/null 2>&1 &
      restarted=$need
    fi
  else
    for kind in $need; do start_unix "$kind"; done
  fi
fi
[ -n "$restarted" ] && echo "hive: restarted dead${restarted}"

# the cached hive status (pf-hive.sh refreshes it in the background); with none cached yet, the one-line local status
if ! { [ -f "$AG/pf-hive.sh" ] && bash "$AG/pf-hive.sh" status --short --cached 2>/dev/null; }; then
  m=$(age "$PF_STATE/msg-status.json"); [ "$m" -gt "${PF_HIVE_STALE:-180}" ] && ms=down || ms=ok
  i=$(age "$PF_STATE/msg-inbox.log"); [ "$i" = 999999 ] && is=none || is="$((i / 60))m ago"
  echo "hive: $PF_ACCOUNT channel=$ms last-message=$is"
fi
exit 0
