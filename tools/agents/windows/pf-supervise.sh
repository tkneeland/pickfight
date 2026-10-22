#!/bin/bash
# Windows runner helper (also fine on macOS/Linux): keeps one AT watcher alive, replacing `screen`.
#   pf-supervise.sh triage     runs pf-triage-watch.sh; when it exits with its one wake line, records the line in
#                              $PF_STATE/triage-wake.txt (latest, with a UTC time), appends it to triage-wake.log,
#                              updates triage-status.json, waits 5 min (so an unhandled MYTICKET does not spin), restarts it.
#   pf-supervise.sh automerge  runs pf-automerge.sh and restarts it if it dies.
# Needs PF_ACCOUNT in the environment (windows/pf-start.ps1 sets it). Output goes to $PF_STATE/*.log.
. "$(dirname "$0")/../pf-env.sh" || exit 1
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
status() {  # status <state> [line]
  jq -n --arg s "$1" --arg l "${2:-}" --arg t "$(now)" --arg a "$PF_ACCOUNT" '{account:$a,state:$s,line:$l,at:$t}' > "$PF_STATE/$KIND-status.json"
}
KIND=${1:-}
case $KIND in
  triage)
    while true; do
      status watching
      line=$(bash "$PF_DIR/pf-triage-watch.sh" 2>>"$PF_STATE/triage-watch.err" | tail -n 1)
      if [ -n "$line" ]; then
        echo "$(now) $line" > "$PF_STATE/triage-wake.txt"; echo "$(now) $line" >> "$PF_STATE/triage-wake.log"
        status woke "$line"; sleep 300
      else
        status exited-no-output; sleep 60
      fi
    done;;
  automerge)
    while true; do
      status running
      bash "$PF_DIR/pf-automerge.sh" >> "$PF_STATE/automerge.log" 2>&1
      status exited; sleep 60
    done;;
  *) echo "usage: pf-supervise.sh triage|automerge" >&2; exit 2;;
esac
