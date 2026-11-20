#!/bin/bash
# Offline test for `hive-supervise.sh voice` and hive-join.sh's voice restart: stub node/screen on PATH, scratch state.
# macOS, Linux and Git Bash.   bash tools/agents/tests/voice-supervise.sh
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/hive-voicesup-test.XXXXXX") || exit 1
hive_fixture "$T" || exit 1
mkdir -p "$T/bin" "$T/state"
# node stub: answers the version probe, else records its args and stays up like a runner
cat > "$T/bin/node" <<'S'
#!/bin/bash
[ "$1" = -p ] && { echo "${HIVE_TEST_NODE_MAJOR:-20}"; exit 0; }
echo "node $*" >> "$HIVE_TEST_LOG"; exec sleep 30
S
printf '#!/bin/bash\necho "screen $*" >> "$HIVE_TEST_LOG"\nexit 0\n' > "$T/bin/screen"
printf '#!/bin/bash\nexit 1\n' > "$T/bin/pgrep"; printf '#!/bin/bash\nexit 0\n' > "$T/bin/ps"
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH" HIVE_STATE_DIR=$T/state HIVE_ACCOUNT=alice HIVE_TEST_LOG=$T/calls.log HIVE_DRY_RUN=1
unset HUB_URL HUB_VOICE_TOKEN
fails=0; sp=""
trap '[ -n "$sp" ] && kill "$sp" 2>/dev/null; rm -rf "$T"' EXIT
ok() { if [ "$2" = 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
sup() { bash "$AG/windows/hive-supervise.sh" voice; }
waitfor() { local i=0; while [ $i -lt 50 ]; do grep -q "$1" "$2" 2>/dev/null && return 0; sleep 0.1; i=$((i + 1)); done; return 1; }

: > "$T/calls.log"
sup 2>/dev/null; ok "no hub.conf: exits 0" $?
[ ! -s "$T/calls.log" ]; ok "no hub.conf: no runner started" $?
grep -q '"off"' "$T/state/voice-status.json"; ok "no hub.conf: status off" $?

printf 'HUB_URL=http://hub.test\n' > "$T/state/hub.conf"
sup 2>/dev/null; [ ! -s "$T/calls.log" ]; ok "hub.conf without a token: no runner" $?

printf 'HUB_URL=http://hub.test\nHUB_VOICE_TOKEN=s3cret-token\n' > "$T/state/hub.conf"
bash "$AG/windows/hive-supervise.sh" voice 2>"$T/sup.err" & sp=$!
waitfor hive-voice.mjs "$T/calls.log"; ok "hub.conf: runner started" $?
grep -q -- "--experimental-websocket" "$T/calls.log"; ok "node 20: --experimental-websocket" $?
waitfor running "$T/state/voice-status.json"; ok "status running" $?
! grep -rq s3cret-token "$T/calls.log" "$T/sup.err" "$T/state/voice-status.json" "$T/state/voice-runner.log" 2>/dev/null; ok "token never printed" $?
kill "$sp"; wait "$sp" 2>/dev/null; sp=""
sleep 0.3; ! pgrep -qf "hive-voicesup-test.*supervise" 2>/dev/null; ok "stop signal ends the supervisor" $?

: > "$T/calls.log"
HIVE_TEST_NODE_MAJOR=22 bash "$AG/windows/hive-supervise.sh" voice 2>/dev/null & sp=$!
waitfor hive-voice.mjs "$T/calls.log"; ! grep -q -- "--experimental-websocket" "$T/calls.log"; ok "node 22: no flag" $?
kill "$sp"; wait "$sp" 2>/dev/null; sp=""

# hive-join.sh: restarts a stale voice supervisor only where hub.conf exists
join() { bash "$AG/hive-join.sh"; }
: > "$T/calls.log"; touch -t 202001010000 "$T/state/voice-status.json"
out=$(join); grep -Eq "screen -dmS hive-voice-[^ ]+-alice" "$T/calls.log"; ok "join: stale voice restarted in screen" $?
case $out in *"restarted dead voice"*) ok "join: restart announced" 0;; *) ok "join: restart announced" 1;; esac
: > "$T/calls.log"; touch "$T/state/voice-status.json"
join >/dev/null; ! grep -q hive-voice "$T/calls.log"; ok "join: fresh voice status left alone" $?
: > "$T/calls.log"; rm -f "$T/state/hub.conf"; touch -t 202001010000 "$T/state/voice-status.json"
join >/dev/null; ! grep -q hive-voice "$T/calls.log"; ok "join: no hub.conf, no voice" $?
[ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
