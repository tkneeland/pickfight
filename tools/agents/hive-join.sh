#!/bin/bash
# SessionStart hook: every Claude session on this machine joins the hive. Installed into .claude/settings.json by install.sh:
#   {"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"f=\"$CLAUDE_PROJECT_DIR/tools/agents/hive-join.sh\"; [ -f \"$f\" ] && bash \"$f\"; exit 0","timeout":8}]}]}}
#   1. reminds the agent to read docs/agents/team-memory.md
#   2. restarts this machine's dead private-channel supervisor (listener + heartbeat), and on Windows the
#      triage/automerge/beacon supervisors too (reusing windows/hive-start.ps1; macOS/Linux: `screen` +
#      windows/hive-supervise.sh msg), and the hub voice runner (supervise.sh voice) where $HIVE_STATE/hub.conf exists. The account comes from HIVE_ACCOUNT or the cached `gh` login (hive-env.sh).
#   3. prints `hive.sh status --short --cached` (the last status at once, refreshed in the background) when
#      that script exists, else a one-line local status
# Silent on success apart from the status. Never blocks or fails the session: the whole check runs under a watchdog
# (HIVE_JOIN_TIMEOUT seconds, default 6: the settings.json hook timeout is 8 s and the kill needs the rest) and the exit code is always 0. On timeout the watchdog kills the hung check's
# process tree, except the detached nohup launches and the status refresh it records (screen sessions detach themselves). No network use of its own; the cached status
# starts a detached refresh (hive.sh: at most once a minute, one at a time) that outlives the watchdog by design.
# Env (tests): HIVE_JOIN_NO_START=1 (never start a supervisor; only report what would restart), HIVE_JOIN_OS=windows|unix, HIVE_JOIN_TIMEOUT, HIVE_STATE_DIR, HIVE_ACCOUNT, HIVE_JOIN_STALE (msg status max age s, default 180).
# SINGLE_ACCOUNT (and PRIVATE) mode: only the team-memory reminder and the local status line; no channel to restart.
AG=$(cd "$(dirname "$0")" && pwd)
if [ -z "${HIVE_JOIN_INNER:-}" ]; then
  out=$(mktemp "${TMPDIR:-/tmp}/hive-join.XXXXXX" 2>/dev/null) || exit 0
  HIVE_JOIN_INNER=1 HIVE_JOIN_KEEP="$out.keep" bash "$0" "$@" > "$out" 2>/dev/null < /dev/null & pid=$!
  end=$((SECONDS + ${HIVE_JOIN_TIMEOUT:-6}))   # wall clock: counting 0.2 s sleeps overran badly on loaded Windows, where each sleep forks (#384)
  while kill -0 "$pid" 2>/dev/null && [ "$SECONDS" -lt "$end" ]; do sleep 0.2; done
  if kill -0 "$pid" 2>/dev/null; then
    # Kill the hung check's whole tree, parents first, so the inner bash cannot fork a fallback branch or a launch while its
    # children die. The list is collected before the first kill (on Linux/macOS children are reparented once a parent dies).
    # Pids in $out.keep (detached supervisor launches and the --cached status refresh) are spared with their subtrees.
    # Same idea as tests/lib.sh hive_kill_tree, but collect-then-kill and fork-free: forks are slow on Windows (#384).
    # /proc/<pid>/ppid exists only on Cygwin/MSYS (tested first, so a pgrep on PATH cannot blind the scan); Linux/macOS use
    # pgrep -P. 2>/dev/null before the <: a process may exit mid-scan.
    snap=" "; if [ -e /proc/self/ppid ]; then for c in /proc/[0-9]*; do p=; read -r p 2>/dev/null < "$c/ppid"; snap="$snap${c#/proc/}:${p//[$'\r ']/} "; done; fi
    keepl=" "; if [ -e "$out.keep" ]; then while read -r k || [ -n "$k" ]; do keepl="$keepl${k%$'\r'} "; done < "$out.keep" 2>/dev/null; fi
    kill_list=""
    collect() { local e k; case $keepl in *" $1 "*) return 0;; esac
      kill_list="$kill_list $1"
      if [ -e /proc/self/ppid ]; then for e in $snap; do [ "${e#*:}" = "$1" ] && collect "${e%:*}"; done
      else for k in $(pgrep -P "$1" 2>/dev/null); do collect "$k"; done; fi; return 0; }
    collect "$pid"
    for k in $kill_list; do kill "$k" 2>/dev/null; done
    echo "hive: join check timed out after ${HIVE_JOIN_TIMEOUT:-6}s, session continues (run tools/agents/hive-join.sh to retry)"
  fi
  cat "$out" 2>/dev/null; rm -f "$out" "$out.keep"; exit 0
fi

unset HIVE_JOIN_INNER   # do not leak into supervisors we spawn
KEEP=${HIVE_JOIN_KEEP:-}; unset HIVE_JOIN_KEEP
keep() { [ -n "$KEEP" ] && echo "$1" >> "$KEEP"; return 0; }   # record a detached launch so the watchdog spares it
. "$AG/hive-env.sh" >/dev/null 2>&1 || { echo "hive: no account conf for this machine (set HIVE_ACCOUNT), not joined"; exit 0; }
echo "hive: read docs/agents/team-memory.md (the hive's shared memory) before working."
# where this project's scripts live, so the voice runner (any project's) can run a hub button here (hive-control.sh)
[ "$(cat "$HIVE_STATE/checkout" 2>/dev/null)" = "$AG" ] || echo "$AG" > "$HIVE_STATE/checkout" 2>/dev/null
# first, before the slow steps, so the watchdog cannot cut the banner off
if hive_control_panel; then
  echo "hive: CONTROL PANEL session. This account's always-on keepalive session does all AT work; follow this instead of the AT prompt."
  echo "  ALLOWED: send and read hive messages (hive-msg.sh send/inbox, hive-ask.sh); hive.sh status; file or comment on tickets; grill; run the game for playtests; pass instructions to the always-on session with a ticket or PR comment, or by typing into its screen session (an INFO/ASK to your own handle is dropped by the listener)."
  echo "  FORBIDDEN: claim tickets, start workers, mark reviews, merge."
fi

case ${HIVE_JOIN_OS:-$(uname -s)} in MINGW*|MSYS*|CYGWIN*|windows) WIN=1;; *) WIN=0;; esac
age() { local m; m=$(hive_mtime "$1") || { echo 999999; return; }; echo $(( $(date +%s) - m )); }
restarted=""
# one restarter at a time: sessions opened together (AT, workers, reserve) race otherwise. mkdir is atomic everywhere.
LOCK=$HIVE_STATE/.hive-join.lock
if ! mkdir "$LOCK" 2>/dev/null; then
  [ $(( $(date +%s) - $(hive_mtime "$LOCK" || echo 0) )) -gt 60 ] && { rmdir "$LOCK" 2>/dev/null; mkdir "$LOCK" 2>/dev/null; } || LOCKED=1
fi
[ -z "${LOCKED:-}" ] && trap 'rmdir "$LOCK" 2>/dev/null' EXIT
# start_unix <kind>: macOS/Linux supervisor in a detached screen; any live session named hive-<kind> or hive-<kind>-<account> counts
start_unix() {
  local kind=$1
  if command -v screen >/dev/null 2>&1; then
    screen -ls 2>/dev/null | grep -Eq "[0-9]\.hive-$kind(-$HIVE_ACCOUNT)?[[:space:]]" && return 0
    screen -dmS "hive-$kind-$HIVE_ACCOUNT" bash "$AG/windows/hive-supervise.sh" "$kind" >/dev/null 2>&1
  else
    nohup bash "$AG/windows/hive-supervise.sh" "$kind" >/dev/null 2>&1 &
    keep $!
  fi
  restarted="$restarted $kind"
}
# any running `hive-msg.sh listen` (bare, launchd, keepalive or our supervisor) is alive: never start a second one
listener_running() { LC_ALL=C pgrep -f 'hive-msg.sh listen' >/dev/null 2>&1 || ps -ax -o command 2>/dev/null | grep -q '[h]ive-msg.sh listen' \
  || ps -W 2>/dev/null | grep -q '[h]ive-msg.sh listen'; }
need=""
# msg: the listener + heartbeat supervisor rewrites msg-status.json every 60 s
if [ "$SINGLE_ACCOUNT" != 1 ] && [ -f "$HIVE_STATE/msg.conf" ] && [ "$(age "$HIVE_STATE/msg-status.json")" -gt "${HIVE_JOIN_STALE:-180}" ] && ! listener_running; then need="$need msg"; fi
# voice: the hub voice runner's supervisor rewrites voice-status.json every 60 s; only machines with a hub.conf run one
voice_running() { LC_ALL=C pgrep -f 'hive-voice.mjs' >/dev/null 2>&1 || ps -ax -o command 2>/dev/null | grep -q '[h]ive-voice.mjs' \
  || ps -W 2>/dev/null | grep -q '[h]ive-voice.mjs'; }
if [ -f "$HIVE_STATE/hub.conf" ] && [ "$(age "$HIVE_STATE/voice-status.json")" -gt "${HIVE_JOIN_STALE:-180}" ] && ! voice_running; then need="$need voice"; fi
# Windows keeps every AT watcher under hive-start.ps1; same liveness signals as hive-tm-check.sh
if [ "$WIN" = 1 ]; then
  [ -f "$HIVE_STATE/triage-status.json" ] && [ "$(age "$HIVE_STATE/.triage-watch-alive")" -gt 900 ] && need="$need triage"
  [ -f "$HIVE_STATE/automerge-status.json" ] && [ "$(age "$HIVE_STATE/automerge-status.json")" -gt 86400 ] \
    && ! hive_pid_alive "$(cat "$HIVE_STATE/automerge.pid" 2>/dev/null | tr -d '\r')" && need="$need automerge"
  [ -f "$HIVE_STATE/beacon-status.json" ] && [ "$(age "$HIVE_STATE/beacon-status.json")" -gt 900 ] && need="$need beacon"
fi
if [ -n "$need" ] && [ -n "${HIVE_JOIN_NO_START:-}" ]; then echo "hive: would restart${need} (HIVE_JOIN_NO_START set, nothing started)"
elif [ -n "$need" ] && [ -z "${LOCKED:-}" ]; then
  if [ "$WIN" = 1 ]; then
    # one detached hive-start.ps1 for everything (it skips watchers that already run), so the watchdog never cuts a launch in half
    ps=powershell.exe; command -v powershell.exe >/dev/null 2>&1 || ps=powershell
    if command -v "$ps" >/dev/null 2>&1; then
      nohup "$ps" -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$AG/windows/hive-start.ps1" 2>/dev/null || echo "$AG/windows/hive-start.ps1")" -Account "$HIVE_ACCOUNT" >/dev/null 2>&1 &
      keep $!
      restarted=$need
    fi
  else
    for kind in $need; do start_unix "$kind"; done
  fi
fi
[ -n "$restarted" ] && echo "hive: restarted dead${restarted}"

# the cached hive status (hive.sh refreshes it in the background and records that refresh in $KEEP, so the watchdog spares it); with none cached yet, the one-line local status
if ! { [ -f "$AG/hive.sh" ] && HIVE_JOIN_KEEP="$KEEP" bash "$AG/hive.sh" status --short --cached 2>/dev/null; }; then
  m=$(age "$HIVE_STATE/msg-status.json"); [ "$m" -gt "${HIVE_JOIN_STALE:-180}" ] && ms=down || ms=ok
  i=$(age "$HIVE_STATE/msg-inbox.log"); [ "$i" = 999999 ] && is=none || is="$((i / 60))m ago"
  if [ "$SINGLE_ACCOUNT" = 1 ]; then echo "hive: $HIVE_ACCOUNT single-account · $(bash "$AG/hive-at-mode.sh" 2>/dev/null)"
  else echo "hive: $HIVE_ACCOUNT channel=$ms last-message=$is"; fi
fi
exit 0
