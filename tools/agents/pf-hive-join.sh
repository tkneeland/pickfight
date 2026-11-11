#!/bin/bash
# SessionStart hook (#1209): every Claude session on this machine joins the hive.
#   1. reminds the agent to read docs/agents/team-memory.md
#   2. restarts this machine's dead private-channel supervisor (listener + heartbeat), and on Windows the
#      triage/automerge/beacon supervisors too (reusing windows/pf-start.ps1; macOS: `screen` + windows/pf-supervise.sh)
#   3. prints `pf-hive.sh status --short` (#1210) when that script exists, else a one-line local status
# Silent on success apart from the status. Never blocks or fails the session: the whole check runs under a watchdog
# (PF_HIVE_TIMEOUT seconds, default 4) and the exit code is always 0. No network use of its own.
# Env (tests): PF_HIVE_OS=windows|unix, PF_HIVE_TIMEOUT, PF_STATE_DIR, PF_ACCOUNT, PF_HIVE_STALE (msg status max age s, default 180).
AG=$(cd "$(dirname "$0")" && pwd)
if [ -z "${PF_HIVE_INNER:-}" ]; then
  out=$(mktemp "${TMPDIR:-/tmp}/pf-hive-join.XXXXXX" 2>/dev/null) || exit 0
  PF_HIVE_INNER=1 bash "$0" "$@" > "$out" 2>/dev/null < /dev/null & pid=$!
  tries=$(( ${PF_HIVE_TIMEOUT:-4} * 5 )); i=0
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt "$tries" ]; do sleep 0.2; i=$((i + 1)); done
  if kill -0 "$pid" 2>/dev/null; then
    pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null
    echo "hive: join check timed out after ${PF_HIVE_TIMEOUT:-4}s, session continues (run tools/agents/pf-hive-join.sh to retry)"
  fi
  cat "$out" 2>/dev/null; rm -f "$out"; exit 0
fi

echo "hive: read docs/agents/team-memory.md (the hive's shared memory) before working."
. "$AG/pf-env.sh" >/dev/null 2>&1 || { echo "hive: no account conf for this machine (set PF_ACCOUNT), not joined"; exit 0; }

case ${PF_HIVE_OS:-$(uname -s)} in MINGW*|MSYS*|CYGWIN*|windows) WIN=1;; *) WIN=0;; esac
age() { local m; m=$(pf_mtime "$1") || { echo 999999; return; }; echo $(( $(date +%s) - m )); }
restarted=""
# restart_kind <kind>: start that supervisor, detached
restart_kind() {
  local kind=$1 name="pf-$1-$PF_ACCOUNT"
  if [ "$WIN" = 1 ]; then
    command -v powershell.exe >/dev/null 2>&1 || command -v powershell >/dev/null 2>&1 || return 0
    local ps=powershell.exe; command -v powershell.exe >/dev/null 2>&1 || ps=powershell
    "$ps" -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$AG/windows/pf-start.ps1" 2>/dev/null || echo "$AG/windows/pf-start.ps1")" -Account "$PF_ACCOUNT" -Only "$kind" >/dev/null 2>&1
  elif command -v screen >/dev/null 2>&1; then
    screen -ls 2>/dev/null | grep -q "[0-9]\.$name[[:space:]]" && return 0   # a live session of that name: leave it alone
    screen -dmS "$name" bash "$AG/windows/pf-supervise.sh" "$kind" >/dev/null 2>&1
  else
    nohup bash "$AG/windows/pf-supervise.sh" "$kind" >/dev/null 2>&1 &
  fi
  restarted="$restarted $kind"
}
# msg: the listener + heartbeat supervisor rewrites msg-status.json every 60 s
if [ -f "$PF_STATE/pf-msg.conf" ] && [ "$(age "$PF_STATE/msg-status.json")" -gt "${PF_HIVE_STALE:-180}" ]; then restart_kind msg; fi
# Windows keeps every AT watcher under pf-start.ps1 (it skips one that is already running); macOS runs those in the AT session
if [ "$WIN" = 1 ]; then
  for kind in beacon automerge triage; do
    [ -f "$PF_STATE/$kind-status.json" ] || continue
    lim=900; [ "$kind" = triage ] && lim=3600   # triage sleeps 5 min after each wake
    [ "$(age "$PF_STATE/$kind-status.json")" -gt "$lim" ] && restart_kind "$kind"
  done
fi
[ -n "$restarted" ] && echo "hive: restarted dead${restarted}"

if [ -f "$AG/pf-hive.sh" ]; then
  bash "$AG/pf-hive.sh" status --short 2>/dev/null || echo "hive: status unavailable"
else
  m=$(age "$PF_STATE/msg-status.json"); [ "$m" -gt "${PF_HIVE_STALE:-180}" ] && ms=down || ms=ok
  i=$(age "$PF_STATE/msg-inbox.log"); [ "$i" = 999999 ] && is=none || is="$((i / 60))m ago"
  echo "hive: $PF_ACCOUNT channel=$ms last-message=$is"
fi
exit 0
