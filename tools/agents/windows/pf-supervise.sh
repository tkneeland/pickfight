#!/bin/bash
# Windows runner helper (also fine on macOS/Linux): keeps one AT watcher alive, replacing `screen`.
#   pf-supervise.sh triage     runs pf-triage-watch.sh; when it exits with its one wake line, records the line in
#                              $PF_STATE/triage-wake.txt (latest, with a UTC time), appends it to triage-wake.log,
#                              updates triage-status.json, waits 5 min (so an unhandled MYTICKET does not spin), restarts it.
#   pf-supervise.sh automerge  runs pf-automerge.sh and restarts it if it dies.
#   pf-supervise.sh beacon     every 5 min: refreshes usage-snapshot.json from the usage endpoint (pf-usage.sh) when the
#                              status line hasn't written it in that time, then runs pf-beacon.sh (the USAGE message on the
#                              private channel). On Windows the status line's own refresh can stop, which froze the beacon at 0%.
#   pf-supervise.sh msg        keeps `pf-msg.sh listen` alive (private ntfy channel) and runs `pf-msg.sh heartbeat` every 60 s.
#                              macOS: screen -dmS pf-msg bash tools/agents/windows/pf-supervise.sh msg
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
  beacon)
    while true; do
      snap=$PF_STATE/usage-snapshot.json
      [ $(( $(date +%s) - $(pf_mtime "$snap" 2>/dev/null || echo 0) )) -ge 300 ] && bash "$PF_DIR/pf-usage.sh" --no-beacon
      if bash "$PF_DIR/pf-beacon.sh"; then status ok; else status failed "see beacon.log"; fi
      sleep 300
    done;;
  msg)
    lp=""
    # the listener runs in its own process group (set -m) so stopping it also stops its curl | reader pipeline
    stop_listener() { [ -n "$lp" ] && kill -- -"$lp" 2>/dev/null; kill "$lp" 2>/dev/null; }
    trap 'stop_listener; exit 0' INT TERM
    trap stop_listener EXIT
    while true; do
      if [ -z "$lp" ] || ! kill -0 "$lp" 2>/dev/null; then
        [ -n "$lp" ] && kill -- -"$lp" 2>/dev/null   # sweep a half-dead pipeline before restarting
        set -m; bash "$PF_DIR/pf-msg.sh" listen >> "$PF_STATE/msg-listen.log" 2>&1 & lp=$!; set +m
      fi
      bash "$PF_DIR/pf-msg.sh" heartbeat >> "$PF_STATE/msg-heartbeat.log" 2>&1 || true
      status running "listener pid $lp"
      sleep 60 & wait $!   # interruptible, so a stop signal is handled at once
    done;;
  *) echo "usage: pf-supervise.sh triage|automerge|beacon|msg" >&2; exit 2;;
esac
