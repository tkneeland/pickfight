#!/bin/bash
# Windows runner helper (also fine on macOS/Linux): keeps one AT watcher alive, replacing `screen`.
#   hive-supervise.sh triage     runs hive-triage-watch.sh; when it exits with its one wake line, records the line in
#                              $HIVE_STATE/triage-wake.txt (latest, with a UTC time), appends it to triage-wake.log,
#                              updates triage-status.json, waits 5 min (so an unhandled MYTICKET does not spin), restarts it.
#   hive-supervise.sh automerge  runs hive-automerge.sh and restarts it if it dies.
#   hive-supervise.sh beacon     every 5 min: refreshes usage-snapshot.json from the usage endpoint (hive-usage.sh) when the
#                              status line hasn't written it in that time, then runs hive-beacon.sh, which sends the USAGE
#                              message on the private channel only on a change or hourly. On Windows the status line's own
#                              refresh can stop, which froze the beacon at 0%.
#   hive-supervise.sh msg        keeps `hive-msg.sh listen` alive (private ntfy channel) and runs `hive-msg.sh heartbeat` every 60 s.
#                              Holds msg-run.pid (shared with `hive-msg.sh run`): a second channel supervisor exits at once.
#                              The other kinds hold supervise-<kind>.pid the same way.
#                              macOS: screen -dmS hive-msg-<repo>-<account> bash tools/agents/windows/hive-supervise.sh msg
#   hive-supervise.sh voice      keeps the hub voice runner (hive-voice.mjs) alive and rewrites voice-status.json every 60 s.
#                              Only on a machine whose $HIVE_STATE/hub.conf (or env) has HUB_URL and HUB_VOICE_TOKEN; it
#                              exits at once otherwise. Node 20.10-21 gets --experimental-websocket. Runner log: voice.log.
# Needs HIVE_ACCOUNT in the environment (windows/hive-start.ps1 sets it). Output goes to $HIVE_STATE/*.log.
. "$(dirname "$0")/../hive-env.sh" || exit 1
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
status() {  # status <state> [line]
  jq -n --arg s "$1" --arg l "${2:-}" --arg t "$(now)" --arg a "$HIVE_ACCOUNT" '{account:$a,state:$s,line:$l,at:$t}' > "$HIVE_STATE/$KIND-status.json"
}
KIND=${1:-}
# one supervisor per kind per state dir (msg uses hive-msg.sh's own lock below). A second copy, e.g. one started under
# an older screen name, exits at once instead of looping beside the first.
SLOCK=""
case $KIND in triage|automerge|beacon|voice)
  SLOCK=$HIVE_STATE/supervise-$KIND.pid
  hive_pidlock "$SLOCK" || { echo "$KIND supervisor already running (pid $(cat "$SLOCK" 2>/dev/null)); not starting a second" >&2; exit 0; }
  trap 'hive_pidunlock "$SLOCK"' EXIT;;
esac
case $KIND in
  state) echo "$HIVE_STATE"; exit 0;;
  triage)
    while true; do
      status watching
      line=$(bash "$HIVE_DIR/hive-triage-watch.sh" 2>>"$HIVE_STATE/triage-watch.err" | tail -n 1)
      if [ -n "$line" ]; then
        echo "$(now) $line" > "$HIVE_STATE/triage-wake.txt"; echo "$(now) $line" >> "$HIVE_STATE/triage-wake.log"
        status woke "$line"; sleep 300
      else
        status exited-no-output; sleep 60
      fi
    done;;
  automerge)
    while true; do
      status running
      bash "$HIVE_DIR/hive-automerge.sh" >> "$HIVE_STATE/automerge.log" 2>&1
      status exited; sleep 60
    done;;
  beacon)
    [ "$SINGLE_ACCOUNT" = 1 ] && { echo "single-account mode: no beacon" >&2; exit 0; }
    while true; do
      snap=$HIVE_STATE/usage-snapshot.json
      [ $(( $(date +%s) - $(hive_mtime "$snap" 2>/dev/null || echo 0) )) -ge 300 ] && bash "$HIVE_DIR/hive-usage.sh" --no-beacon
      if bash "$HIVE_DIR/hive-beacon.sh"; then status ok; else status failed "see beacon.log"; fi
      sleep 300
    done;;
  msg)
    [ "$SINGLE_ACCOUNT" = 1 ] && { echo "single-account mode: no channel" >&2; exit 0; }
    LOCK=$HIVE_STATE/msg-run.pid   # the same lock as hive-msg.sh run: one channel supervisor per state dir
    hive_pidlock "$LOCK" || { echo "channel supervisor already running (pid $(cat "$LOCK" 2>/dev/null)); not starting a second" >&2; exit 0; }
    lp=""
    # the listener runs in its own process group (set -m) so stopping it also stops its curl | reader pipeline
    stop_listener() { [ -n "$lp" ] && kill -- -"$lp" 2>/dev/null; kill "$lp" 2>/dev/null; }
    trap 'stop_listener; exit 0' INT TERM
    trap 'stop_listener; hive_pidunlock "$LOCK"' EXIT
    while true; do
      if [ -z "$lp" ] || ! kill -0 "$lp" 2>/dev/null; then
        [ -n "$lp" ] && kill -- -"$lp" 2>/dev/null   # sweep a half-dead pipeline before restarting
        set -m; bash "$HIVE_DIR/hive-msg.sh" listen >> "$HIVE_STATE/msg-listen.log" 2>&1 & lp=$!; set +m
      fi
      bash "$HIVE_DIR/hive-msg.sh" heartbeat >> "$HIVE_STATE/msg-heartbeat.log" 2>&1 || true
      bash "$HIVE_DIR/hive-msg.sh" status "listener pid $lp"   # msg-status.json, with quota (the 429 backoff) when blocked
      sleep 60 & wait $!   # interruptible, so a stop signal is handled at once
    done;;
  voice)
    if [ -z "${HUB_URL:-}" ] || [ -z "${HUB_VOICE_TOKEN:-}" ]; then
      for k in HUB_URL HUB_VOICE_TOKEN; do   # presence only: the token is never read into this script or printed
        grep -Eq "^[[:space:]]*(export[[:space:]]+)?$k=[^[:space:]]" "$HIVE_STATE/hub.conf" 2>/dev/null \
          || { echo "no hub.conf with HUB_URL and HUB_VOICE_TOKEN: no voice runner" >&2; status off "no hub.conf"; exit 0; }
      done
    fi
    command -v node >/dev/null 2>&1 || { echo "node not found: no voice runner" >&2; status failed "node not found"; exit 1; }
    major=$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null)
    flags=(); [ "${major:-0}" -lt 22 ] && flags=(--experimental-websocket)
    vp=""
    stop_runner() { [ -n "$vp" ] && kill "$vp" 2>/dev/null; }
    trap 'stop_runner; exit 0' INT TERM
    trap 'stop_runner; hive_pidunlock "$SLOCK"' EXIT
    while true; do
      if [ -z "$vp" ] || ! kill -0 "$vp" 2>/dev/null; then
        [ -n "$vp" ] && echo "$(now) runner exited; restarting" >> "$HIVE_STATE/voice-runner.log"
        node "${flags[@]}" "$HIVE_DIR/hive-voice.mjs" >> "$HIVE_STATE/voice-runner.log" 2>&1 & vp=$!
      fi
      status running "runner pid $vp"
      sleep 60 & wait $!   # interruptible, so a stop signal is handled at once
    done;;
  *) echo "usage: hive-supervise.sh triage|automerge|beacon|msg|voice" >&2; exit 2;;
esac
