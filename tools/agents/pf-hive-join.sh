#!/bin/bash
# Hive join (#1209): the repo's SessionStart hook (.claude/settings.json) runs this when any Claude session starts.
# Prints only: a reminder to read docs/agents/team-memory.md, any daemon it restarted, and `pf-hive.sh status --short`
# when that script exists. Never blocks the session: no network call of its own, restarts run detached, and it always
# exits 0. The hook's own "timeout": 5 is the backstop. macOS and Git Bash on Windows.
# A daemon is restarted only when its status file shows this machine ran it before (a fresh machine is not set up by a hook).
. "$(dirname "$0")/pf-env.sh" >/dev/null 2>&1 || exit 0
echo "Hive: you are part of the Pickfight hive. Read docs/agents/team-memory.md first and follow it."
age() { local m; m=$(pf_mtime "$1" 2>/dev/null) || { echo 999999; return; }; echo $(( $(date +%s) - m )); }
win=0; case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) win=1;; esac
restart() {  # restart <kind>: msg|triage|automerge|beacon, detached, output to $PF_STATE/hive-join.log
  local kind=$1 sup="$PF_DIR/windows/pf-supervise.sh"
  if [ "$win" = 1 ]; then
    command -v powershell.exe >/dev/null 2>&1 || return 1
    ( nohup powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$PF_DIR/windows/pf-start.ps1" 2>/dev/null || echo "$PF_DIR/windows/pf-start.ps1")" -Account "$PF_ACCOUNT" -Only "$kind" >>"$PF_STATE/hive-join.log" 2>&1 & ) >/dev/null 2>&1
  elif command -v screen >/dev/null 2>&1; then
    screen -dmS "pf-$kind-$PF_ACCOUNT" bash -c "PF_ACCOUNT=$PF_ACCOUNT exec bash '$sup' $kind" >>"$PF_STATE/hive-join.log" 2>&1
  else
    ( PF_ACCOUNT=$PF_ACCOUNT nohup bash "$sup" "$kind" >>"$PF_STATE/hive-join.log" 2>&1 & ) >/dev/null 2>&1
  fi
}
# kind | status or heartbeat file in $PF_STATE | max age in seconds
for spec in "msg|msg-status.json|300" "triage|.triage-watch-alive|900" "automerge|automerge-status.json|86400" "beacon|beacon-status.json|900"; do
  IFS='|' read -r kind f max <<EOT
$spec
EOT
  [ -e "$PF_STATE/$f" ] || continue                 # never set up here
  [ "$(age "$PF_STATE/$f")" -lt "$max" ] && continue
  [ "$kind" = automerge ] && ! pf_is_triagemaster && continue
  restart "$kind" && echo "Hive: restarted the $kind daemon (it was down)."
done
[ -f "$PF_DIR/pf-hive.sh" ] && { bash "$PF_DIR/pf-hive.sh" status --short 2>/dev/null | head -n 5; }
exit 0
