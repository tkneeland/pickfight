#!/usr/bin/env node
// hive-voice.mjs: the voice runner (docs/hub/voice-protocol.md, "The runner"). Connects out to the hub's /voice/ws,
// says hello, and answers each `ask` with a one-shot `claude -p` run in a scratch dir, streaming deltas back.
//   node --experimental-websocket tools/agents/hive-voice.mjs     (Node 20.10-21; plain `node` from Node 22)
// Config: HUB_URL from env, else $HIVE_STATE/hub.conf (KEY=value), else hive.conf. Sign-in: HUB_VOICE_TOKEN (env or
// hub.conf) if set, else the member's own `gh auth token` (the hub checks it with GitHub and drops it). After hello it
// reports this machine's game channel topics (each ~/.claude/hive/<owner>__<game>/<handle>/msg.conf), so nobody copies a
// topic to the hub by hand. Handle: HIVE_HANDLE, else
// HIVE_ACCOUNT, else `gh api user -q .login`. HIVE_STATE: env HIVE_STATE / HIVE_STATE_DIR, else resolved by hive-env.sh.
// Knobs: HIVE_VOICE_CLAUDE (claude binary, default claude), HIVE_VOICE_MODEL (default sonnet), HIVE_VOICE_TIMEOUT
// (seconds per ask, default 180). Logs to $HIVE_STATE/voice.log (and stderr on a TTY). The token is never logged.
// No npm dependencies.
import { spawn, execFile, execFileSync } from "node:child_process";
import { appendFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const VERSION = "1";
const HERE = dirname(fileURLToPath(import.meta.url));
const ALLOWED_TOOLS = ["Bash(gh issue create:*)", "Bash(gh issue list:*)", "Bash(gh issue view:*)", "Bash(gh pr list:*)", "Bash(gh pr view:*)"];
const STREAM_KEEP = 60;

if (typeof WebSocket === "undefined") {
  console.error(`hive-voice: no global WebSocket in Node ${process.versions.node}. On Node 20.10-21 run it as ` +
    "`node --experimental-websocket hive-voice.mjs`; Node 22+ has it built in.");
  process.exit(1);
}

// ---- config ------------------------------------------------------------------------------------------------
function sh(cmd, args, env) {
  try { return execFileSync(cmd, args, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], env: env ?? process.env }).trim(); }
  catch { return ""; }
}
const handle = process.env.HIVE_HANDLE || process.env.HIVE_ACCOUNT || sh("gh", ["api", "user", "-q", ".login"]);
if (!handle) { console.error("hive-voice: no handle (set HIVE_HANDLE, or log in with gh)"); process.exit(1); }

let state = process.env.HIVE_STATE || process.env.HIVE_STATE_DIR || "";
if (!state) {
  state = sh("bash", ["-c", '. "$1/hive-env.sh" >/dev/null 2>&1 && printf %s "$HIVE_STATE"', "hive-voice", HERE],
    { ...process.env, HIVE_ACCOUNT: handle });
}
if (!state) { console.error("hive-voice: cannot resolve HIVE_STATE (set HIVE_STATE, or check hive.conf and accounts/<handle>.conf)"); process.exit(1); }
mkdirSync(state, { recursive: true });

function readConf(file) {
  const out = {};
  let text = "";
  try { text = readFileSync(file, "utf8"); } catch { return out; }
  for (const raw of text.split(/\r?\n/)) {
    const m = raw.match(/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (!m) continue;
    let v = m[2].trim();
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) v = v.slice(1, -1);
    out[m[1]] = v;
  }
  return out;
}
const conf = readConf(join(state, "hub.conf"));
const hubUrl = process.env.HUB_URL || conf.HUB_URL ||
  sh("bash", ["-c", '. "$1/hive-env.sh" >/dev/null 2>&1 && printf %s "${HUB_URL:-}"', "hive-voice", HERE], { ...process.env, HIVE_ACCOUNT: handle });
const shared = process.env.HUB_VOICE_TOKEN || conf.HUB_VOICE_TOKEN || "";
const token = shared || sh("gh", ["auth", "token"]);
const authHeader = shared ? `Bearer ${shared}` : `GitHub ${token}`;
if (!hubUrl) { console.error(`hive-voice: no HUB_URL (hive.conf, ${join(state, "hub.conf")} or env)`); process.exit(1); }
if (!token) { console.error("hive-voice: no sign-in: log in with `gh auth login` (or set HUB_VOICE_TOKEN)"); process.exit(1); }
const wsUrl = hubUrl.replace(/^http(s?):\/\//i, "ws$1://").replace(/\/+$/, "") + "/voice/ws";
const claudeBin = process.env.HIVE_VOICE_CLAUDE || "claude";
const model = process.env.HIVE_VOICE_MODEL || "sonnet";
const timeoutSec = Number(process.env.HIVE_VOICE_TIMEOUT) > 0 ? Number(process.env.HIVE_VOICE_TIMEOUT) : 180;

// ---- this machine's channel topics, repo -> topic (secrets: sent to the hub only, never logged) -----------------
let topicCache = null;
function topics() {
  if (topicCache) return topicCache;
  const out = {};
  const root = join(homedir(), ".claude", "hive");
  let slugs = [];
  try { slugs = readdirSync(root); } catch {}
  for (const slug of slugs) {
    const m = slug.match(/^([\w.-]+)__([\w.-]+)$/);
    if (!m) continue;
    const t = readConf(join(root, slug, handle, "msg.conf")).HIVE_MSG_TOPIC || "";
    if (/^[A-Za-z0-9_-]{8,64}$/.test(t)) out[`${m[1]}/${m[2]}`] = t;
  }
  return (topicCache = out);
}

// ---- log -----------------------------------------------------------------------------------------------------
const logFile = join(state, "voice.log");
function log(msg) {
  let text = String(msg).split(token).join("[token]");
  for (const t of Object.values(topics())) text = text.split(t).join("[topic]");
  const line = `${new Date().toISOString()} ${text}\n`;
  try { appendFileSync(logFile, line); } catch {}
  if (process.stderr.isTTY) process.stderr.write(line);
}

// ---- the voice prompt and the ask prompt ---------------------------------------------------------------------
function voicePrompt(ctx) {
  const hive = ctx?.hiveName || "the hive";
  const studio = ctx?.studioName || "the studio";
  return [
    `You are ${hive}, the one voice of the ${studio} hive. Members of the studio talk to you in a shared chat on the hive hub.`,
    "Answer from the context you are given (the hub's live state of the projects, the studio and the recent chat); be brief.",
    "Say so plainly when the context does not hold the answer; do not guess.",
    'The open tab tells you which game "this game" or "this project" means: context.tab is a project id, or "studio".',
    "You may file tickets with `gh issue create --label needs-triage` (and read issues and PRs with gh). A ticket goes to the open " +
      "project's repo (context.project.repo), or to the studio repo (context.studio.repo) when the tab is studio. Always pass " +
      "--repo explicitly; you are not in a checkout. Reply with the new issue's link.",
    "You can pass a message to the dev sessions (the Claude Code sessions running the hive on members' machines). Do it " +
      "when the member asks you to tell, ask or assign something to the hive, a session, the triagemaster or an account, or " +
      "when the answer needs a session's own knowledge that the context lacks. End your reply with one line per message: " +
      "`@relay <project id> <handle or tm> <message>` (tm = that project's triagemaster). Keep the message under 180 " +
      "characters, self-contained, and name the issue or PR number. The hub strips the line, posts it on the project's " +
      "channel and shows the session's answer in this chat. Say in your reply that you passed it on. Never relay secrets.",
    "Never write code, merge, push or change files.",
    "Never repeat SSNs, EINs, bank or card numbers, even when the context or the question holds one.",
    "Humans do filings, payments and signatures: you can remind, summarise and file a ticket, never do them.",
  ].join("\n");
}

function trimContext(ctx) {
  const c = structuredClone(ctx ?? {});
  if (Array.isArray(c.project?.stream) && c.project.stream.length > STREAM_KEEP) c.project.stream = c.project.stream.slice(-STREAM_KEEP);
  if (Array.isArray(c.studio?.activity) && c.studio.activity.length > STREAM_KEEP) c.studio.activity = c.studio.activity.slice(-STREAM_KEEP);
  return c;
}

function askPrompt(ask) {
  const ctx = ask.context ?? {};
  const tab = ask.tab || ctx.tab || "studio";
  const where = tab === "studio" || !ctx.project
    ? `the studio tab${ctx.studio?.repo ? ` (studio repo ${ctx.studio.repo})` : ""}`
    : `the ${ctx.project.name || tab} tab (project id ${tab}, repo ${ctx.project.repo})`;
  return [
    `${ask.from} asked this with ${where} open.`,
    "",
    "Context (JSON, from the hub):",
    "```json",
    JSON.stringify(trimContext(ctx), null, 1),
    "```",
    "",
    `Question from ${ask.from}:`,
    ask.text,
  ].join("\n");
}

// ---- one ask -------------------------------------------------------------------------------------------------
let current = null; // {id, child, dir, finished}
const queue = [];

function runAsk(ask, send) {
  return new Promise((resolve) => {
    const dir = mkdtempSync(join(tmpdir(), "hive-voice-"));
    const job = { id: ask.id, child: null, dir, finished: false, timer: null, resolve };
    current = job;
    let full = "", result = null, resultError = false, stderr = "", buf = "", timedOut = false;
    const finish = (msg) => {
      if (job.finished) return;
      job.finished = true;
      clearTimeout(job.timer);
      try { rmSync(dir, { recursive: true, force: true }); } catch {}
      if (msg) send(msg);
      current = null;
      resolve();
    };
    const env = { ...process.env };
    delete env.HUB_VOICE_TOKEN;
    const args = ["-p", "--output-format", "stream-json", "--include-partial-messages", "--verbose", "--model", model,
      "--append-system-prompt", voicePrompt(ask.context), "--allowedTools", ...ALLOWED_TOOLS];
    let child;
    try { child = spawn(claudeBin, args, { cwd: dir, env, stdio: ["pipe", "pipe", "pipe"] }); }
    catch (e) { log(`ask ${ask.id}: spawn failed: ${e.message}`); finish({ type: "error", id: ask.id, error: `could not start claude: ${e.message}` }); return; }
    job.child = child;
    job.timer = setTimeout(() => {
      timedOut = true;
      log(`ask ${ask.id}: timed out after ${timeoutSec}s`);
      child.kill("SIGTERM");
      setTimeout(() => { if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL"); }, 5000).unref();
    }, timeoutSec * 1000);
    const onLine = (line) => {
      if (!line.trim()) return;
      let o;
      try { o = JSON.parse(line); } catch { return; }
      if (o.type === "stream_event" && o.event?.type === "content_block_delta" && o.event.delta?.type === "text_delta") {
        const t = o.event.delta.text ?? "";
        if (t) { full += t; send({ type: "delta", id: ask.id, text: t }); }
      } else if (o.type === "result") {
        result = typeof o.result === "string" ? o.result : null;
        resultError = !!o.is_error;
      }
    };
    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (d) => {
      buf += d;
      let i;
      while ((i = buf.indexOf("\n")) >= 0) { onLine(buf.slice(0, i)); buf = buf.slice(i + 1); }
    });
    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (d) => { stderr = (stderr + d).slice(-2000); });
    child.on("error", (e) => {
      log(`ask ${ask.id}: spawn error: ${e.message}`);
      finish({ type: "error", id: ask.id, error: `could not start claude: ${e.message}` });
    });
    child.stdin.on("error", () => {});
    child.on("close", (code, signal) => {
      if (buf) onLine(buf);
      if (job.finished) return;
      if (timedOut) return finish({ type: "error", id: ask.id, error: `timed out after ${timeoutSec}s` });
      if (code !== 0 || resultError) {
        const why = stderr.trim().split("\n").slice(-3).join(" ") || (resultError && result) || "";
        log(`ask ${ask.id}: claude exited ${code ?? signal}${why ? `: ${why}` : ""}`);
        return finish({ type: "error", id: ask.id, error: `claude exited ${code ?? signal}${why ? `: ${why.slice(0, 300)}` : ""}` });
      }
      const text = result ?? full;
      log(`ask ${ask.id}: done (${text.length} chars)`);
      finish({ type: "done", id: ask.id, text });
    });
    child.stdin.end(askPrompt(ask));
  });
}

// abort the running ask (connection lost or shutting down): its reply is re-queued by the hub, so nothing is sent
function abortCurrent() {
  const job = current;
  if (!job) return;
  job.finished = true;
  clearTimeout(job.timer);
  if (job.child && job.child.exitCode === null && job.child.signalCode === null) job.child.kill("SIGTERM");
  try { rmSync(job.dir, { recursive: true, force: true }); } catch {}
  current = null;
  job.resolve();
}

// ---- controls (the hub's buttons) ---------------------------------------------------------------------------
// Only these verbs and values run, through hive-control.sh in the checkout of the project the button was pressed for:
// this runner's own, or the one hive-join.sh recorded in that project's state folder (<hive dir>/<owner__repo>/<handle>/checkout).
const CONTROLS = { ticketmaker: ["on", "off"] };
const REPO_RE = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
function checkoutFor(repo) {
  const slug = repo.replace("/", "__");
  if (slug.toLowerCase() === basename(dirname(state)).toLowerCase()) return HERE;
  try {
    const dir = readFileSync(join(dirname(dirname(state)), slug, basename(state), "checkout"), "utf8").trim();
    if (dir && existsSync(join(dir, "hive-control.sh"))) return dir;
  } catch {}
  return null;
}
function runControl(msg, send) {
  const reply = (ok, extra) => send({ type: "control-result", id: msg.id, ok, ...extra });
  if (!CONTROLS[msg.action]?.includes(msg.value) || !REPO_RE.test(msg.repo ?? "")) {
    log(`control ${msg.id}: refused (${String(msg.action).slice(0, 20)} ${String(msg.value).slice(0, 20)})`);
    return reply(false, { error: "not an allowed control" });
  }
  const dir = checkoutFor(msg.repo);
  if (!dir) {
    log(`control ${msg.id}: no ${msg.repo} checkout`);
    return reply(false, { error: `no ${msg.repo} checkout on this machine` });
  }
  const env = { ...process.env, HIVE_ACCOUNT: handle };
  delete env.HUB_VOICE_TOKEN;
  log(`control ${msg.id}: ${msg.action} ${msg.value} for ${msg.repo}`);
  execFile("bash", [join(dir, "hive-control.sh"), msg.action, msg.value], { env, timeout: 30000 }, (err, stdout, stderr) => {
    if (err) {
      const why = String(stderr || err.message).trim().split("\n").slice(-1)[0].slice(0, 200);
      log(`control ${msg.id}: failed: ${why}`);
      return reply(false, { error: why || "hive-control.sh failed" });
    }
    let st = null;
    try { st = JSON.parse(String(stdout).trim().split("\n").slice(-1)[0]); } catch {}
    log(`control ${msg.id}: done`);
    reply(true, st ? { state: st } : {});
  });
}

// ---- the connection ------------------------------------------------------------------------------------------
let ws = null, backoff = 1000, reconnectTimer = null, stopping = false, pumping = false;

function send(msg) {
  if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(msg));
  else log(`dropped ${msg.type}${msg.id ? ` for ${msg.id}` : ""}: not connected`);
}

async function pump() {
  if (pumping) return;
  pumping = true;
  const conn = ws;
  while (queue.length && !stopping && ws === conn) {
    const ask = queue.shift();
    log(`ask ${ask.id} from ${ask.from} (tab ${ask.tab})`);
    await runAsk(ask, send);
  }
  pumping = false;
  if (queue.length && !stopping) pump();
}

function connect() {
  reconnectTimer = null;
  if (stopping) return;
  log(`connecting to ${wsUrl} as ${handle}`);
  let sock;
  try { sock = new WebSocket(wsUrl, { headers: { Authorization: authHeader } }); }
  catch (e) { log(`connect failed: ${e.message}`); return scheduleReconnect(); }
  ws = sock;
  sock.onopen = () => {
    backoff = 1000;
    log("connected; hello");
    sock.send(JSON.stringify({ type: "hello", handle, version: VERSION }));
    topicCache = null;
    const t = topics();
    if (Object.keys(t).length) {
      sock.send(JSON.stringify({ type: "topics", topics: t }));
      log(`reported channel topics for ${Object.keys(t).join(", ")}`);
    }
  };
  sock.onmessage = (ev) => {
    let msg;
    try { msg = JSON.parse(typeof ev.data === "string" ? ev.data : Buffer.from(ev.data).toString("utf8")); }
    catch { return log("ignored a non-JSON frame"); }
    if (msg.type === "role") {
      log(msg.active ? "role: active (answering)" : "role: standby");
    } else if (msg.type === "control" && msg.id) {
      runControl(msg, send);
    } else if (msg.type === "ask" && msg.id) {
      if (current || queue.length) log(`ask ${msg.id} queued behind ${current?.id ?? queue[0].id}`);
      queue.push(msg);
      pump();
    } else {
      log(`ignored message type ${msg.type}`);
    }
  };
  // a refused upgrade (401, hub down) fires error without close on Node 20's undici, so either event ends the connection
  const lost = (why) => {
    if (ws !== sock) return;
    ws = null;
    log(`disconnected (${why})`);
    try { sock.close(); } catch {}
    queue.length = 0;
    abortCurrent();
    scheduleReconnect();
  };
  sock.onerror = (ev) => lost(`error${ev?.message ? `: ${ev.message}` : ""}`);
  sock.onclose = (ev) => {
    // 4000: another runner for this member (another game's supervisor, another machine) took the slot; stand by for
    // 10 minutes instead of taking it back at once, so two runners don't knock each other off every few seconds
    if (ev.code === 4000 && ws === sock) { backoff = 600000; log("another runner for this account took over the hub connection"); }
    lost(`code ${ev.code}${ev.reason ? ` ${ev.reason}` : ""}`);
  };
}

function scheduleReconnect() {
  if (stopping || reconnectTimer) return;
  log(`reconnecting in ${backoff / 1000}s`);
  reconnectTimer = setTimeout(connect, backoff);
  backoff = Math.min(backoff * 2, 60000);
}

function shutdown(sig) {
  if (stopping) return;
  stopping = true;
  log(`${sig}: stopping`);
  clearTimeout(reconnectTimer);
  queue.length = 0;
  abortCurrent();
  try { ws?.close(1000, "runner stopping"); } catch {}
  setTimeout(() => process.exit(0), 300).unref();
}
process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));

log(`hive-voice ${VERSION} starting (node ${process.versions.node}, model ${model})`);
connect();
