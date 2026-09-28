// Issue #231 probe: serve a controller page with a stub WebSocket host, drive
// it lobby -> playing as the host phone, tap the gear with touch, and check
// the menu, the swing frames and the gear/status layout.
// Usage: node probe.js <index.html> <label> [chromium|webkit|all]
const fs = require("fs");
const http = require("http");
const path = require("path");
const { WebSocketServer } = require("ws");
const pw = require("playwright");

const file = process.argv[2];
const label = process.argv[3] || "run";
const which = process.argv[4] || "all";
const shotDir = process.env.SHOTS || path.join(__dirname, "shots");
fs.mkdirSync(shotDir, { recursive: true });

function lobbyState(phase, extra) {
  return Object.assign({
    t: "lobby", phase: phase, host: 0, target: 5, count: 3, match: 1, paused: false,
    players: [{ slot: 0, name: "Poop", ready: phase !== "lobby", claim: 1 },
              { slot: 1, name: "Bot", ready: true, claim: 2, bot: true }],
    in_round: phase === "playing" ? [0, 1] : [], alive: phase === "playing" ? [0, 1] : [],
  }, extra || {});
}

async function main() {
  const wss = new WebSocketServer({ port: 0 });
  const wsPort = wss.address().port;
  let sock = null;
  const log = [];  // {text} or {vx,vy}
  wss.on("connection", (s) => {
    sock = s;
    s.on("message", (data, isBinary) => {
      if (isBinary) {
        const b = Buffer.from(data);
        log.push({ vx: b.readFloatLE(0), vy: b.readFloatLE(4) });
      } else {
        const m = JSON.parse(String(data));
        log.push({ text: m });
        if (m.id) {
          s.send(JSON.stringify({ slot: 0 }));
          s.send(JSON.stringify(lobbyState("lobby")));
        }
      }
    });
  });
  const html = fs.readFileSync(file, "utf8").replace("__WS_PORT__", String(wsPort));
  const server = http.createServer((req, res) => { res.writeHead(200, { "content-type": "text/html" }); res.end(html); });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const url = "http://127.0.0.1:" + server.address().port + "/";

  const engines = which === "all" ? ["chromium", "webkit"] : [which];
  const results = [];
  for (const engine of engines) {
    const launch = engine === "chromium" ? pw.chromium.launch({ channel: "chrome" }) : pw.webkit.launch();
    const browser = await launch;
    for (const width of [375, 390, 430]) {
      const ctx = await browser.newContext({
        viewport: { width: width, height: width === 430 ? 932 : 812 }, deviceScaleFactor: 3,
        hasTouch: true, isMobile: engine === "chromium",
        userAgent: engine === "webkit" ? "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1" : undefined,
      });
      await ctx.addInitScript(() => {
        localStorage.setItem("pickfight-name", "Poop");
        localStorage.setItem("pickfight-name-chosen", "1");
        localStorage.setItem("pickfight-look-chosen", "1");
      });
      const page = await ctx.newPage();
      const errors = [];
      page.on("pageerror", (e) => errors.push(String(e)));
      await page.goto(url);
      await page.waitForFunction(() => document.getElementById("gear").classList.contains("show"));
      const r = { engine, width, errors };
      // Lobby: a tap opens the menu (the path that worked in the playtest).
      await page.tap("#gear");
      await page.waitForTimeout(100);
      r.lobbyTapOpens = await page.evaluate(() => document.getElementById("host-menu").classList.contains("show"));
      await page.evaluate(() => document.getElementById("menu-close").click());
      // Playing.
      sock.send(JSON.stringify(lobbyState("playing", { count: 0 })));
      await page.waitForTimeout(200);
      const layout = await page.evaluate(() => {
        const g = document.getElementById("gear").getBoundingClientRect();
        const s = document.getElementById("status").getBoundingClientRect();
        const cx = g.left + g.width / 2, cy = g.top + g.height / 2;
        const top = document.elementFromPoint(cx, cy);
        return {
          gear: [g.left, g.top, g.right, g.bottom].map(Math.round),
          status: [s.left, s.top, s.right, s.bottom].map(Math.round),
          overlap: !(g.right <= s.left || s.right <= g.left || g.bottom <= s.top || s.bottom <= g.top),
          hitAtGearCentre: top ? (top.id || top.tagName) : null,
          statusText: document.getElementById("status").textContent,
        };
      });
      r.layout = layout;
      await page.screenshot({ path: path.join(shotDir, `${label}-${engine}-${width}-playing.png`) });
      if (engine === "chromium") {
        // A finger that lands on the gear and slides off onto the pad.
        const cdpS = await ctx.newCDPSession(page);
        const g = layout.gear;
        const bS = log.length;
        await cdpS.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: (g[0] + g[2]) / 2, y: (g[1] + g[3]) / 2 }] });
        for (let i = 1; i <= 5; i++) {
          await cdpS.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x: (g[0] + g[2]) / 2 - i * 40, y: (g[1] + g[3]) / 2 + i * 60 }] });
          await page.waitForTimeout(30);
        }
        await cdpS.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
        await page.waitForTimeout(100);
        r.slideOffOpens = await page.evaluate(() => document.getElementById("host-menu").classList.contains("show"));
        r.slideOffSwings = log.slice(bS).some((m) => m.vx !== undefined && (m.vx !== 0 || m.vy !== 0));
      }
      // Tap the gear mid-round.
      const before = log.length;
      await page.tap("#gear");
      await page.waitForTimeout(300);
      r.playTapOpens = await page.evaluate(() => document.getElementById("host-menu").classList.contains("show"));
      r.swingFramesFromTap = log.slice(before).filter((m) => m.vx !== undefined && (m.vx !== 0 || m.vy !== 0)).length;
      r.textFramesFromTap = log.slice(before).filter((m) => m.text).map((m) => JSON.stringify(m.text));
      await page.screenshot({ path: path.join(shotDir, `${label}-${engine}-${width}-after-gear-tap.png`) });
      if (!r.playTapOpens && engine === "chromium") {
        // Before the fix: does holding the gear (GEAR_HOLD_MS) open it?
        const cdp0 = await ctx.newCDPSession(page);
        const gc0 = layout.gear;
        const pt = { x: (gc0[0] + gc0[2]) / 2, y: (gc0[1] + gc0[3]) / 2 };
        await cdp0.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [pt] });
        await page.waitForTimeout(900);
        r.holdOpens = await page.evaluate(() => document.getElementById("host-menu").classList.contains("show"));
        await cdp0.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
      }
      if (r.playTapOpens) {
        // Pause then Resume closes and returns to play.
        await page.tap("#menu-pause");
        sock.send(JSON.stringify(lobbyState("playing", { count: 0, paused: true })));
        await page.waitForTimeout(150);
        r.resumeLabel = await page.evaluate(() => document.getElementById("menu-pause").textContent);
        await page.tap("#menu-pause");
        sock.send(JSON.stringify(lobbyState("playing", { count: 0, paused: false })));
        await page.waitForTimeout(150);
        r.menuClosedAfterResume = await page.evaluate(() => !document.getElementById("host-menu").classList.contains("show"));
        r.hostCmds = log.filter((m) => m.text && m.text.t === "host").map((m) => m.text.cmd);
        // A drag after resuming still swings.
        if (engine === "chromium") {
          const cdp = await ctx.newCDPSession(page);
          const b2 = log.length;
          await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: width / 2, y: 500 }] });
          for (let i = 1; i <= 5; i++) {
            await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x: width / 2 + i * 20, y: 500 }] });
            await page.waitForTimeout(30);
          }
          await page.waitForTimeout(60);
          await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
          r.dragAfterResumeSwings = log.slice(b2).some((m) => m.vx !== undefined && m.vx > 0.1);
          // A finger landing on the gear mid-drag is ignored.
          await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: width / 2, y: 500, id: 1 }] });
          const gc = layout.gear;
          const gx = (gc[0] + gc[2]) / 2, gy = (gc[1] + gc[3]) / 2;
          await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: width / 2, y: 500, id: 1 }, { x: gx, y: gy, id: 2 }] });
          await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [{ x: width / 2, y: 500, id: 1 }] });
          await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
          await page.waitForTimeout(100);
          r.gearMidDragIgnored = await page.evaluate(() => !document.getElementById("host-menu").classList.contains("show"));
        }
      }
      results.push(r);
      await ctx.close();
    }
    await browser.close();
  }
  console.log(JSON.stringify(results, null, 1));
  wss.close();
  server.close();
}
main().catch((e) => { console.error(e); process.exit(1); });
