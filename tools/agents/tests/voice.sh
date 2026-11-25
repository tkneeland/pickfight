#!/bin/bash
# Offline tests for hive-voice.mjs (docs/hub/voice-protocol.md): the Authorization header arrives on the upgrade, hello
# is sent first, an ask streams deltas then done with the full text, a failing claude gives error and a hung one times out (asks
# wait their turn), the context's stream is trimmed to 60, pings are answered, the runner retries a refused (401) upgrade and reconnects after the hub closes, the
# token never reaches voice.log, and SIGTERM stops it. A fake hub (node http plus a hand-rolled RFC 6455 text-frame
# server) on 127.0.0.1 and a fake claude that prints stream-json. No network.   bash tools/agents/tests/voice.sh
AG=$(cd "$(dirname "$0")/.." && pwd)
command -v node >/dev/null 2>&1 || { echo "voice: SKIP, no node on PATH"; exit 0; }
T=$(mktemp -d "${TMPDIR:-/tmp}/hive-voice-test.XXXXXX") && [ -d "$T" ] || { echo "voice: cannot make a scratch dir" >&2; exit 1; }
T=$(cd "$T" && pwd) && case $T in */hive-voice-test.*) ;; *) echo "voice: odd scratch dir '$T'" >&2; exit 1;; esac
HP=""; RP=""
kill $HP 2>/dev/null; wait $HP 2>/dev/null; HP=""
trap 'kill -9 $HP $RP 2>/dev/null; rm -rf "$T"' EXIT
NODE=(node)
node -e 'process.exit(typeof WebSocket === "undefined" ? 1 : 0)' 2>/dev/null || NODE=(node --experimental-websocket)
"${NODE[@]}" -e 'process.exit(typeof WebSocket === "undefined" ? 1 : 0)' 2>/dev/null || { echo "voice: SKIP, node $(node --version) has no WebSocket"; exit 0; }
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
# wait_for <pattern> <file> [tenths]: until a line matches (default 10 s)
wait_for() { for _ in $(seq 1 "${3:-100}"); do grep -q "$1" "$2" 2>/dev/null && return 0; sleep 0.1; done; return 1; }

# ---- the fake hub: logs one line per event to $HUB_LOG ----------------------------------------------------------
cat > "$T/hub.mjs" <<'EOF'
import http from "node:http";
import crypto from "node:crypto";
import fs from "node:fs";
const LOG = process.env.HUB_LOG, PORTFILE = process.env.HUB_PORTFILE, TOKEN = process.env.HUB_TOKEN;
const log = (s) => fs.appendFileSync(LOG, s.replace(/\n/g, "\\n") + "\n");
const frame = (op, payload) => {
  const b = Buffer.from(payload); let h;
  if (b.length < 126) h = Buffer.from([0x80 | op, b.length]);
  else if (b.length < 65536) { h = Buffer.alloc(4); h[0] = 0x80 | op; h[1] = 126; h.writeUInt16BE(b.length, 2); }
  else { h = Buffer.alloc(10); h[0] = 0x80 | op; h[1] = 127; h.writeBigUInt64BE(BigInt(b.length), 2); }
  return Buffer.concat([h, b]);
};
const stream = Array.from({ length: 70 }, (_, i) => ({ id: `m${i}`, time: 0, from: "bob", type: "INFO", text: `STREAM-ENTRY-${i}.` }));
const context = (q) => ({ hiveName: "Hivey", studioName: "Test Studio", tab: "game1",
  project: { id: "game1", name: "Game One", repo: "example/game1", stream }, studio: { repo: "example/studio", activity: [] }, history: [] });
let conns = 0, refused = false;   // the first upgrade is refused (401): the runner must back off and retry
const server = http.createServer((req, res) => { res.writeHead(404); res.end(); });
server.on("upgrade", (req, sock) => {
  log(`UPGRADE ${req.url} auth=${req.headers.authorization ?? "-"}`);
  if (!refused) { refused = true; log("REFUSED"); sock.end("HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\n\r\n"); return; }
  if (req.headers.authorization !== `Bearer ${TOKEN}`) { sock.end("HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\n\r\n"); return; }
  const accept = crypto.createHash("sha1").update(req.headers["sec-websocket-key"] + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest("base64");
  sock.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
  const n = ++conns; let buf = Buffer.alloc(0); const answered = new Set();
  const send = (o) => sock.write(frame(1, JSON.stringify(o)));
  const onText = (s) => {
    const m = JSON.parse(s);
    if (m.type === "hello") log(`HELLO ${n} ${m.handle} v${m.version}`);
    else if (m.type === "delta") log(`DELTA ${n} ${m.id} ${m.text}`);
    else if (m.type === "done") log(`DONE ${n} ${m.id} ${m.text}`);
    else if (m.type === "error") log(`ERROR ${n} ${m.id} ${m.error}`);
    else log(`OTHER ${n} ${s}`);
    if (m.type === "hello" && n === 1) {
      send({ type: "role", active: true });
      sock.write(frame(9, "are-you-there"));
      send({ type: "ask", id: "a1", from: "alice", tab: "game1", text: "how is this game going?", context: context() });
      send({ type: "ask", id: "a2", from: "bob", tab: "game1", text: "PLEASE FAIL", context: context() });
      send({ type: "ask", id: "a3", from: "bob", tab: "studio", text: "PLEASE HANG", context: context() });
      send({ type: "ask", id: "a4", from: "bob", tab: "studio", text: "HOOK FAILS", context: context() });
    }
    if (m.type === "hello" && n === 2) {
      send({ type: "control", id: "c1", repo: "example/other", action: "ticketmaker", value: "off" });
      send({ type: "control", id: "c2", repo: "example/other", action: "shell", value: "rm -rf /" });
      send({ type: "control", id: "c3", repo: "example/other", action: "toString", value: "x" });
      send({ type: "control", id: "c4", repo: "example/other", action: "__proto__", value: "x" });
    }
    if (m.type === "done" || m.type === "error") answered.add(m.id);
    if (n === 1 && answered.size === 4) { log("CLOSING 1"); sock.end(frame(8, Buffer.from([0x03, 0xe8]))); }
  };
  sock.on("data", (d) => {
    buf = Buffer.concat([buf, d]);
    for (;;) {
      if (buf.length < 2) return;
      const op = buf[0] & 0x0f, masked = buf[1] & 0x80; let len = buf[1] & 0x7f, off = 2;
      if (len === 126) { if (buf.length < 4) return; len = buf.readUInt16BE(2); off = 4; }
      else if (len === 127) { if (buf.length < 10) return; len = Number(buf.readBigUInt64BE(2)); off = 10; }
      const mask = masked ? buf.subarray(off, off + 4) : null; if (masked) off += 4;
      if (buf.length < off + len) return;
      const p = Buffer.from(buf.subarray(off, off + len)); buf = buf.subarray(off + len);
      if (mask) for (let i = 0; i < p.length; i++) p[i] ^= mask[i & 3];
      if (op === 1) onText(p.toString("utf8"));
      else if (op === 10) log(`PONG ${n} ${p.toString("utf8")}`);
      else if (op === 8) { log(`CLIENT-CLOSE ${n}`); sock.end(); }
    }
  });
  sock.on("error", () => {});
});
server.listen(0, "127.0.0.1", () => fs.writeFileSync(PORTFILE, String(server.address().port)));
EOF

# ---- the fake claude: saves its args and stdin, streams "Hello" + " world", or fails on PLEASE FAIL --------------
cat > "$T/claude" <<'EOF'
#!/bin/bash
n=1; until mkdir "$FAKE_DIR/slot.$n" 2>/dev/null; do n=$((n+1)); done   # atomic: asks on different tabs run at once
printf '%s\n' "$@" > "$FAKE_DIR/args.$n"; pwd > "$FAKE_DIR/cwd.$n"; cat > "$FAKE_DIR/stdin.$n"
env | grep -c HUB_VOICE_TOKEN > "$FAKE_DIR/tokenenv.$n"
if grep -q 'PLEASE FAIL' "$FAKE_DIR/stdin.$n"; then echo "fake claude: boom" >&2; exit 3; fi
if grep -q 'PLEASE HANG' "$FAKE_DIR/stdin.$n"; then exec sleep 30; fi
echo '{"type":"system","subtype":"init"}'
echo '{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}}'
echo 'not json at all'
echo '{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" world"}}}'
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Hello world"}]}}'
echo '{"type":"result","subtype":"success","is_error":false,"result":"Hello world"}'
if grep -q 'HOOK FAILS' "$FAKE_DIR/stdin.$n"; then echo 'SessionEnd hook failed: Hook cancelled' >&2; exit 1; fi
EOF
chmod +x "$T/claude"
ST=$T/hive/example__game1/tester   # a state folder laid out like the real one (<hive>/<owner__repo>/<handle>)
mkdir -p "$ST" "$T/fake"
HL=$T/hub.log; : > "$HL"
HUB_LOG=$HL HUB_PORTFILE=$T/port HUB_TOKEN=s3cret-voice-token node "$T/hub.mjs" & HP=$!
for _ in $(seq 1 50); do [ -s "$T/port" ] && break; sleep 0.1; done
[ -s "$T/port" ] || { echo "FAIL fake hub did not start"; exit 1; }
printf 'HUB_URL=http://127.0.0.1:%s/\nHUB_VOICE_TOKEN=s3cret-voice-token\n' "$(cat "$T/port")" > "$ST/hub.conf"

# another project's checkout, recorded the way hive-join.sh does, with a fake hive-control.sh
mkdir -p "$T/hive/example__other/tester" "$T/otherag"
echo "$T/otherag" > "$T/hive/example__other/tester/checkout"
printf '#!/bin/bash\necho "$HIVE_ACCOUNT $* token=${HUB_VOICE_TOKEN:-none}" >> "%s/control.log"\necho "{\\"ticketmaker\\":\\"$2\\"}"\n' "$T/fake" > "$T/otherag/hive-control.sh"
env -u HUB_URL -u HUB_VOICE_TOKEN -u HIVE_VOICE_MODEL HIVE_VOICE_TIMEOUT=2 HIVE_STATE="$ST" HIVE_HANDLE=tester HIVE_VOICE_CLAUDE="$T/claude" FAKE_DIR="$T/fake" \
  "${NODE[@]}" "$AG/hive-voice.mjs" 2>"$T/runner.err" & RP=$!

wait_for '^HELLO 2 ' "$HL" 150 || echo "FAIL no reconnect hello (hub log: $(tr '\n' '|' < "$HL"))"
# 1 auth header and path
check "auth header" "$(grep -c '^UPGRADE /voice/ws auth=Bearer s3cret-voice-token$' "$HL")" 3
check "retried after 401" "$(grep -c '^REFUSED$' "$HL")" 1
# 2 hello is the first message on each connection
check "hello first" "$(grep -E '^(HELLO|DELTA|DONE|ERROR|OTHER) 1 ' "$HL" | head -n 1)" "HELLO 1 tester v1"
# 3 deltas then done with the full text, in order, for a1
check "a1 stream" "$(grep -E '^(DELTA|DONE) 1 a1 ' "$HL" | tr '\n' '|')" "DELTA 1 a1 Hello|DELTA 1 a1  world|DONE 1 a1 Hello world|"
# 4 the failing claude gives error for a2, after a1 finished (one at a time)
check "a2 error" "$(grep -c '^ERROR 1 a2 claude exited 3: fake claude: boom$' "$HL")" 1
l1=$(grep -n '^DONE 1 a1' "$HL" | cut -d: -f1); l2=$(grep -n '^ERROR 1 a2' "$HL" | cut -d: -f1)
check "a2 after a1" "$([ -n "$l1" ] && [ -n "$l2" ] && [ "$l1" -lt "$l2" ] && echo yes)" yes
check "no deltas for a2" "$(grep -c '^DELTA 1 a2' "$HL")" 0
# 4b a hung claude is killed after HIVE_VOICE_TIMEOUT and gives error
check "a3 timeout" "$(grep -c '^ERROR 1 a3 timed out after 2s$' "$HL")" 1
# 4b2 tabs run in parallel: a3 (studio) started before a1 (game1) finished
s3=$(grep -n 'ask a3 from' "$ST/voice.log" | head -n 1 | cut -d: -f1); d1=$(grep -n 'ask a1: done' "$ST/voice.log" | head -n 1 | cut -d: -f1)
check "tabs in parallel" "$([ -n "$s3" ] && [ -n "$d1" ] && [ "$s3" -lt "$d1" ] && echo yes)" yes
# 4c a finished answer stands when claude then exits non-zero (a SessionEnd hook failed after the result)
check "a4 done despite exit 1" "$(grep -c '^DONE 1 a4 Hello world$' "$HL")" 1
# 5 ping answered (undici replies at protocol level)
check "pong" "$(grep -c '^PONG 1 are-you-there$' "$HL")" 1
# 6 the claude run: flags, scratch cwd (removed after), prompt content, trimmed stream, no token in its env
N=$(grep -l 'how is this game going' "$T"/fake/stdin.* 2>/dev/null | head -n 1 | sed 's/.*\.//')   # a1's run (tabs start in any order)
A=$T/fake/args.$N
check "model flag" "$(grep -A1 -x -- '--model' "$A" | tail -n 1)" sonnet
check "stream-json" "$(grep -A1 -x -- '--output-format' "$A" | tail -n 1)" stream-json
check "partial msgs" "$(grep -cx -- '--include-partial-messages' "$A")" 1
check "allowed tools" "$(grep -cx 'Bash(gh issue create:\*)' "$A")" 1
check "voice prompt names the hive" "$(grep -c 'You are Hivey, the one voice of the Test Studio hive' "$A")" 1
check "voice prompt open tab" "$(grep -c 'open tab tells you which game' "$A")" 1
check "voice prompt never code" "$(grep -c 'Never write code, merge, push or change files' "$A")" 1
case $(cat "$T/fake/cwd.$N") in "$PWD"|"$AG"*) check "scratch cwd" repo scratch;; *) check "scratch cwd" scratch scratch;; esac
check "scratch dir removed" "$([ -d "$(cat "$T/fake/cwd.$N")" ] && echo kept || echo removed)" removed
S=$T/fake/stdin.$N
check "prompt who and tab" "$(grep -c '^alice asked this with the Game One tab (project id game1, repo example/game1) open\.$' "$S")" 1
check "prompt question" "$(grep -c '^how is this game going?$' "$S")" 1
check "stream trimmed to 60" "$(grep -o 'STREAM-ENTRY-[0-9]*\.' "$S" | wc -l | tr -d ' ')" 60
check "oldest dropped" "$(grep -c 'STREAM-ENTRY-9\.' "$S")" 0
check "newest kept" "$(grep -c 'STREAM-ENTRY-69\.' "$S")" 1
check "token not in claude env" "$(cat "$T/fake/tokenenv.$N")" 0
# 7 the token never reaches the log; the log exists and records the role
check "voice.log written" "$(grep -c 'role: active' "$ST/voice.log")" 1
check "token not logged" "$(grep -c 's3cret-voice-token' "$ST/voice.log" "$T/runner.err" | awk -F: '{s+=$2} END {print s}')" 0
check "reconnect logged" "$(grep -c 'reconnecting in 1s' "$ST/voice.log")" 2
# 7b controls: none is allowlisted any more (the ticket-maker mode is the studio's hive/ticket-maker.conf), so every frame,
# including the old ticketmaker one and prototype names, is refused cleanly and hive-control.sh never runs
wait_for 'control-result.*c4' "$HL" 50
for c in c1 c2 c3 c4; do
  check "control $c refused" "$(grep -c "\"type\":\"control-result\",\"id\":\"$c\",\"ok\":false,\"error\":\"not an allowed control\"" "$HL")" 1
done
check "control never ran" "$(cat "$T/fake/control.log" 2>/dev/null)" ""
# 8 SIGTERM stops it cleanly
kill -TERM $RP; for _ in $(seq 1 30); do kill -0 $RP 2>/dev/null || break; sleep 0.1; done
check "sigterm exit" "$(kill -0 $RP 2>/dev/null && echo running || { wait $RP; echo "exit $?"; })" "exit 0"
RP=""
kill $HP 2>/dev/null; wait $HP 2>/dev/null; HP=""

[ "$fail" = 0 ] && echo "voice: $pass checks passed" || { echo "voice: $fail failed, $pass passed"; exit 1; }
