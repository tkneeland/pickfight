// Issue #244 probe: laptop mouse drives the arm through the same code path as a
// touch drag. Run:  npm install playwright (anywhere; point NODE_PATH at its node_modules),
// then  node test-results/issue-244/probe.js  with Google Chrome installed.
// Installed Google Chrome, headless. The host is a Playwright-routed stub
// WebSocket (no server): it assigns slot 0 and a "playing" lobby, and records
// the binary input frames (2 x float32 LE) the page streams.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const HTML = fs.readFileSync(path.join(__dirname, '../../controller/index.html'), 'utf8').replace('__WS_PORT__', '9999');
const OUT = __dirname;
let failed = 0;
function check(name, ok, detail) {
  console.log((ok ? 'PASS ' : 'FAIL ') + name + (detail ? '  ' + detail : ''));
  if (!ok) failed++;
}
const near = (a, b) => Math.abs(a - b) < 1e-4;
const vecEq = (a, b) => near(a[0], b[0]) && near(a[1], b[1]);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function open(browser, opts) {
  const ctx = await browser.newContext(opts);
  const frames = [];
  await ctx.addInitScript(() => {
    localStorage.setItem('pickfight-name', 'Probe');
    localStorage.setItem('pickfight-name-chosen', '1');
    localStorage.setItem('pickfight-look-chosen', '1');
  });
  await ctx.routeWebSocket(/.*/, (ws) => {
    ws.onMessage((m) => {
      if (typeof m !== 'string' && m.length === 8) frames.push([m.readFloatLE(0), m.readFloatLE(4)]);
    });
    setTimeout(() => {
      ws.send(JSON.stringify({ slot: 0 }));
      ws.send(JSON.stringify({ t: 'lobby', phase: 'playing', match: 1, host: -1, paused: false,
        players: [{ slot: 0, name: 'Probe', claim: 1 }], alive: [0], in_round: [0] }));
    }, 100);
  });
  const page = await ctx.newPage();
  await page.route('http://pf.test/', (r) => r.fulfill({ contentType: 'text/html', body: HTML }));
  await page.goto('http://pf.test/');
  await sleep(600);
  return { ctx, page, frames };
}

// Distinct consecutive vectors, after the first (0,0) "not touching" frame.
function steps(frames, from) {
  const out = [];
  for (const f of frames.slice(from)) if (!out.length || !vecEq(out[out.length - 1], f)) out.push(f);
  return out;
}

// Synthetic pointer lock: headless Chrome will not grant a real lock without a
// user-activated gesture, so the page's requestPointerLock() is stubbed to set
// document.pointerLockElement and fire pointerlockchange, as the browser would.
const STUB_LOCK = () => {
  let locked = null;
  Object.defineProperty(document, 'pointerLockElement', { get: () => locked, configurable: true });
  Element.prototype.requestPointerLock = function () { locked = this; document.dispatchEvent(new Event('pointerlockchange')); };
  document.exitPointerLock = function () { locked = null; document.dispatchEvent(new Event('pointerlockchange')); };
  window.__lockCalls = 0;
  const orig = Element.prototype.requestPointerLock;
  Element.prototype.requestPointerLock = function () { window.__lockCalls++; return orig.call(this); };
};

// Mouse totals as fractions of the drag radius (0.35 of the short viewport edge).
const STEPS = [[100, -20], [40, -30], [0, -20]]; // px of mouse movement at 1x, desktop 1000x800 (R=280)
const R_DESKTOP = 0.35 * 800;
const R_MOBILE = 0.35 * 390;

async function desktopRun(browser, sens) {
  const { ctx, page, frames } = await open(browser, { viewport: { width: 1000, height: 800 } });
  await page.evaluate(STUB_LOCK);
  const shown = await page.isVisible('#mouse-capture');
  if (sens !== undefined) {
    await page.$eval('#mouse-sens', (el, v) => { el.value = v; el.dispatchEvent(new Event('input')); }, String(sens));
  }
  await page.screenshot({ path: path.join(OUT, 'desktop-playing.png') });
  await page.click('#mouse-capture');
  await sleep(150);
  const start = frames.length;
  for (const [dx, dy] of STEPS) {
    await page.evaluate(([x, y]) => document.dispatchEvent(new MouseEvent('mousemove', { movementX: x, movementY: y })), [dx, dy]);
    await sleep(120);
  }
  const s = steps(frames, start);
  const locks = await page.evaluate(() => window.__lockCalls);
  const hiddenWhileLocked = !(await page.isVisible('#mouse-capture'));
  // Esc: the browser exits the lock; the page drops the drag and shows the affordance again.
  await page.evaluate(() => document.exitPointerLock());
  await sleep(150);
  const back = await page.isVisible('#mouse-capture');
  const last = frames[frames.length - 1];
  await ctx.close();
  return { shown, s, locks, hiddenWhileLocked, back, afterEsc: last };
}

(async () => {
  const browser = await chromium.launch({ channel: 'chrome', headless: true });

  // Touch reference: mobile-emulated context, equivalent drag via CDP touch events.
  const m = await open(browser, { viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, deviceScaleFactor: 2 });
  const mobileAffordance = await m.page.isVisible('#mouse-capture');
  const fine = await m.page.evaluate(() => matchMedia('(pointer: fine)').matches);
  await m.page.screenshot({ path: path.join(OUT, 'mobile-playing.png') });
  const cdp = await m.ctx.newCDPSession(m.page);
  const ax = 195, ay = 400;
  const touch = (type, x, y) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x, y }] });
  await touch('touchStart', ax, ay);
  await sleep(120);
  const tStart = m.frames.length;
  let cx = 0, cy = 0;
  for (const [dx, dy] of STEPS) {
    cx += dx; cy += dy;
    await touch('touchMove', ax + cx * R_MOBILE / R_DESKTOP, ay + cy * R_MOBILE / R_DESKTOP);
    await sleep(120);
  }
  const touchSteps = steps(m.frames, tStart).filter((v, i) => !(i === 0 && vecEq(v, [0, 0]))); // drop the touch-down (0,0)
  await touch('touchEnd');
  await m.ctx.close();

  const d1 = await desktopRun(browser);

  // Expected vectors are worked literals: cumulative mouse px / R = (100,-20)/280, (140,-50)/280, (140,-70)/280.
  const expected = [[100 / 280, -20 / 280], [140 / 280, -50 / 280], [0.5, -0.25]];
  const eq = (a, b) => a.length === b.length && a.every((v, i) => vecEq(v, b[i]));
  console.log('touch steps  ', JSON.stringify(touchSteps));
  console.log('mouse steps  ', JSON.stringify(d1.s));
  check('(a) desktop: capture affordance shown in play (fine pointer)', d1.shown === true);
  check('(a) clicking it calls requestPointerLock once', d1.locks === 1, 'calls=' + d1.locks);
  check('(a) affordance hidden while captured', d1.hiddenWhileLocked);
  check('(a) locked mouse moves produce the worked-literal vectors', eq(d1.s, expected));
  check('(a) same input messages as the equivalent touch drag in the mobile context', eq(d1.s, touchSteps));
  check('(a) Esc (exit lock) zeroes the input and shows the affordance again', vecEq(d1.afterEsc, [0, 0]) && d1.back);

  const half = await desktopRun(browser, 0.5);
  const dbl = await desktopRun(browser, 2);
  console.log('0.5x mouse steps', JSON.stringify(half.s));
  console.log('2x mouse steps  ', JSON.stringify(dbl.s));
  check('(b) sensitivity 0.5x halves every vector', eq(half.s, expected.map((v) => [v[0] / 2, v[1] / 2])));
  check('(b) sensitivity 2x doubles the first move (200,-40)/280', vecEq(dbl.s[0], [200 / 280, -40 / 280]));

  check('(c) mobile context: no fine pointer', fine === false);
  check('(c) mobile context: capture affordance not shown', mobileAffordance === false);

  await browser.close();
  console.log(failed ? `${failed} FAILED` : 'ALL PASSED');
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
