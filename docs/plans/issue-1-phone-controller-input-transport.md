# Technical plan: #1 Phone-as-controller input transport

- Work package: GitHub issue [#1](https://github.com/tkneeland/pickfight/issues/1)
  (stable contract; not duplicated here)
- Plan status: **DRAFT, awaiting human approval** (`atlas:plan-review`)
- Planned against: `main` @ `5e1e5d4` plus the uncommitted Atlas setup files
  in the working tree (see "Repository state hazards")
- Run surface: **local only**
- Red-team review: not required by default (`docs/agents/planning.md`); run
  `/atlas-red-team` manually if wanted

## 1. Intent

Implement the thin input relay that ADR-0001/0002/0003 commit to, so that a
phone browser on the LAN drives one player's **arm** in the running Godot
**host** via a relative **input vector**. This plan turns the issue's scope and
six acceptance criteria into ordered steps and a criterion-level verification
map. It makes no product decisions; the technical interpretations it does make
are listed in section 3 for confirmation at approval.

## 2. Affected areas, interfaces, domain concepts

| Area | Change |
|---|---|
| `scripts/Player.gd` | Arm is driven by a unit-disc `input_vector`; mouse and keyboard become host-side debug sources; release returns arm to rest smoothly |
| `scripts/ControllerServer.gd` (new) | Non-blocking HTTP page server + WebSocket input server + slot binding, polled from `_process` |
| `controller/index.html` (new) | Full-screen touch surface streaming a binary vector at display rate |
| `scenes/Main.tscn` | Add `ControllerServer` node wired to `Player1`/`Player2`; per-player body colour; on-screen join URL label |
| `tools/ws_probe_client.gd` (new) | Headless Godot WebSocket client used as the agent-runnable real-dependency probe |
| `README.md` | Remove the stale "code still uses the old mouse/keyboard scheme" note; document how to run host + join |
| `test-results/` | Committed evidence, one directory per test name (policy: `docs/agents/testing.md`) |

Domain terms used as defined in `CONTEXT.md`: host, controller, player, arm,
swing, input vector. New implementation-level term introduced by this plan:
**player slot** (index into the host's ordered player list that a controller is
bound to in join order). Not a glossary change; flagged for `/domain-modeling`
if it outlives this work package.

Interfaces introduced:

- `Player.set_input_vector(v: Vector2)` — `v` is clamped to the unit disc;
  `(0,0)` means "not touching".
- `Player.bind_controller()` / `Player.unbind_controller()` — while bound, the
  debug source is ignored; on unbind the vector is zeroed.
- Wire payload phone→host: one binary WebSocket frame per controller frame,
  **8 bytes**: `float32 x, float32 y`, little-endian, unit-disc normalised.
- Wire payload host→phone (on bind only): one text frame `{"slot":<int>}` so
  the page can display which player it controls (needed to make AC3 evidence
  legible).
- Ports: HTTP `8080`, WebSocket `8081` (both `@export`ed). Two ports because
  `StreamPeerTCP` cannot peek; once bytes are read for HTTP routing they are
  gone, and `WebSocketPeer.accept_stream` must read the handshake itself.

## 3. Technical decisions made in this plan (confirm at approval)

These do not change the contract; they resolve things it leaves open.

1. **"Rest" (AC4)** = arm extension at `arm_min_length`, angle held at its
   last value. While dragging, angle/extension follow the vector directly (no
   smoothing, to protect AC5 snappiness). On release the extension returns to
   rest at a rate-limited speed (`move_toward`, new `@export rest_return_speed`)
   so it neither snaps nor overshoots; the page keeps streaming exact `(0,0)`
   while untouched, so nothing can drift.
2. **Slot policy**: lowest free slot in join order; a disconnect frees its slot
   and zeroes that player's vector. Join/leave UI stays out of scope.
3. **Wake Lock (ADR-0002 constraint) cannot be fully honoured over plain HTTP.**
   The Screen Wake Lock API is restricted to secure contexts, and the host
   serves `http://<lan-ip>:8080/`. Plan: call `navigator.wakeLock.request` on a
   best-effort basis (works if the page is ever served over HTTPS/localhost),
   record the limitation in the PR and on the issue, and do **not** add HTTPS
   or a NoSleep video hack in this work package. Players raise their phone's
   auto-lock during testing. This is an explicit deviation from the letter of
   ADR-0002; surfaced here rather than silently dropped. Alternatives if the
   human prefers: (b) NoSleep-style hidden looping video fallback, or (c) HTTPS
   with a self-signed cert (adds a certificate-warning step per phone).
4. **Debug sources** (`Player.debug_source: NONE | MOUSE | KEYBOARD`): mouse
   maps `(mouse - body) / mouse_drag_radius` onto the unit disc, so it exercises
   the exact same code path as the phone. Keyboard keeps A/D rotate, W/S
   extend, integrating into a synthetic vector. `Main.tscn`: `Player1 = MOUSE`,
   `Player2 = NONE`. A bound controller always overrides the debug source.
5. **Join URL on screen** (small `Label`) plus `print()` of
   `http://<ip>:8080/` for every non-loopback IPv4 from
   `IP.get_local_addresses()`. QR onboarding stays out of scope.
6. **Distinguishable players**: set `Body.color`/`modulate` per instance in
   `Main.tscn` (Player1 blue, Player2 orange) so AC3 video can show which phone
   drives which body. Not art direction; a test affordance.
7. **`--log-input` host flag** (`OS.get_cmdline_user_args()`): server prints
   `slot=<i> v=(x, y)` per decoded packet and `slot <i> bound/unbound`; Player
   prints `arm angle=<rad> len=<px>` when either changes. This is what the
   agent-runnable checks assert on.
8. **Page served from `res://controller/index.html` via `FileAccess`** at
   request time, with `__WS_PORT__` substituted, so drag-radius tuning does not
   need a host restart. Export note: `*.html` must be added to export include
   filters if the project is ever exported; not needed to run from the project
   directory.

## 4. Repository state hazards (resolve before `/atlas-implement`)

- The Atlas setup (`CLAUDE.md`, `CONTEXT.md`, `docs/`, `.atlas/`,
  `.gitattributes`, and edits to `.gitignore`, `README.md`, `project.godot`) is
  **uncommitted on `main`**. A feature branch cut from `main` would not carry
  `docs/agents/*` or the `test-results/` gitignore re-include. Commit that
  setup to `main` first (human action).
- No Atlas lifecycle labels exist in the repo; only GitHub defaults plus
  `wontfix`. See section 9.

## 5. Ordered implementation steps

Dependencies are strictly top-down; each step must keep `godot --headless
--quit` clean.

1. **Player input-vector refactor** — `scripts/Player.gd`
   - Add `input_vector`, `has_controller`, `debug_source`, `mouse_drag_radius`,
     `rest_return_speed`, `set_input_vector`, `bind_controller`,
     `unbind_controller`.
   - Rewrite `_update_arm_input` per decision 1/4; remove the direct
     `get_global_mouse_position()` aiming and the stale "real local multiplayer
     needs a gamepad" comment (superseded by ADR-0003).
   - Update `scenes/Main.tscn`: replace `use_mouse = false` on `Player2` with
     `debug_source` values; set per-player colours (decision 6).
   - Checkpoint: boot-check; mouse still swings Player1 in a windowed run.
2. **Host servers** — `scripts/ControllerServer.gd`, `scenes/Main.tscn`
   - `@export http_port := 8080`, `@export ws_port := 8081`,
     `@export players: Array[NodePath]` (`[Player1, Player2]`).
   - `_ready`: `listen()` both; print join URLs; set `Label` text.
   - `_process`: (a) HTTP — accept, accumulate per-client bytes until
     `\r\n\r\n` (cap 8 KiB), answer `GET /` and `GET /index.html` with
     `200 text/html; charset=utf-8`, `Content-Length`, `Connection: close`,
     `Cache-Control: no-store`; anything else `404`; then
     `disconnect_from_host()`. (b) WS — accept → `WebSocketPeer.new()`
     `.accept_stream(tcp)` → pending until `STATE_OPEN` → bind lowest free slot,
     send `{"slot":i}`; each frame drain **all** packets and keep only the last
     8-byte one (latest wins), `player.set_input_vector(Vector2(
     pkt.decode_float(0), pkt.decode_float(4)))`; on `STATE_CLOSED` unbind.
     Ignore frames that are not exactly 8 bytes.
   - `--log-input` behaviour (decision 7).
   - GDScript gotcha found during planning: `Array[T].duplicate()` returns an
     untyped `Array`, so `for c in arr.duplicate(): var n := c.method()` fails
     to parse ("Cannot infer the type"). Type the loop variable
     (`for c: StreamPeerTCP in ...`) or the local.
   - Checkpoint: `curl -s -D - http://127.0.0.1:8080/` returns 200 with the
     page; probe (step 4) binds slot 0.
3. **Controller page** — `controller/index.html` (single file, inline CSS/JS)
   - `<meta name="viewport" content="width=device-width, initial-scale=1,
     viewport-fit=cover">`; `html,body{height:100%;margin:0;touch-action:none;
     user-select:none;-webkit-user-select:none;overscroll-behavior:none}`.
   - Pointer events: `pointerdown` stores the anchor (relative drag per
     ADR-0003); `pointermove` uses the last of `getCoalescedEvents()` when
     available; `pointerup`/`pointercancel`/`blur` zero the vector.
     `touchstart`/`touchmove` listeners registered with `{passive:false}` and
     calling `preventDefault()`.
   - `vector = clampToUnitDisc((cur - anchor) / DRAG_RADIUS_PX)`,
     `DRAG_RADIUS_PX = 0.35 * min(innerWidth, innerHeight)` as a named
     tunable (ADR-0003 expects tuning).
   - Send loop: `requestAnimationFrame` sends the current vector every frame
     while `ws.readyState === OPEN` (60–120 Hz by display) as
     `new Float32Array([x, y]).buffer`. Reconnect 1 s after close.
   - On text frame `{"slot":n}` show "P<n+1>" large, tinted to match the host
     colours from decision 6. Draw anchor and current touch point.
   - Wake Lock best-effort per decision 3.
   - Checkpoint: Claude Browser pane loads `http://127.0.0.1:8080/`, a
     `left_click_drag` produces `slot=0 v=(...)` lines under `--log-input`.
4. **Probe fixture** — `tools/ws_probe_client.gd` (`extends SceneTree`)
   - Args: `--port=8081`, `--sequence=<name>` selecting one of:
     `direction` `[(1,0),(0,-1),(-1,0),(0,1)]`, `reach` `[(0.25,0),(0.5,0),
     (1,0)]`, `release` `[(1,0) x 30 frames, (0,0) x 60 frames]`; sends one
     frame per `_process` tick, then closes with code 1000.
   - Run: `godot --headless --path . -s tools/ws_probe_client.gd --
     --sequence=direction`.
   - Two concurrent probe processes bind slots 0 and 1 (AC3 candidate check).
5. **README** — replace the "predates these decisions / being replaced" note
   with: run the host (`godot --path .` or from the editor), read the URL on
   screen, open it on a phone on the same Wi-Fi (prefer 5 GHz or the host's
   hotspot per ADR-0002), drag to swing; mention `--log-input` and the probe.
6. **Evidence and handoff** — clear `test-results/`, run the verification
   map (section 7), collect human evidence (AC1–AC5), commit evidence on the
   feature branch, open the PR (`gh pr create --base main --head <branch>`),
   write `[PROGRESS]`/`[CLOSEOUT]` records per `docs/agents/issue-tracker.md`.

## 6. Scope

In scope (files/surfaces): `scripts/Player.gd`, `scripts/ControllerServer.gd`,
`controller/index.html`, `scenes/Main.tscn`, `tools/ws_probe_client.gd`,
`README.md`, `test-results/**`, plus the auto-generated `*.gd.uid` files Godot
creates for new scripts.

Explicitly excluded: rounds, scoring, stage rotation, weapons, join/leave UI,
QR onboarding, HTTPS, WebRTC DataChannel (documented upgrade path only),
gamepad support, any change to `scenes/Arena.tscn`, `scripts/KillZone.gd`,
`scenes/Player.tscn` geometry, physics tuning beyond what the input change
requires, ADR edits (the Wake Lock deviation is recorded on the issue/PR, not
by amending ADR-0002).

## 7. Verification map

Evidence root `test-results/` (cleared first; one directory per test name;
committed on the feature branch; PR links the paths). `BLOCKED`/`SKIPPED`/
worker self-report are never `PASS`. Invalidators common to every check:
any change to `scripts/Player.gd`, `scripts/ControllerServer.gd`,
`controller/index.html`, `scenes/Main.tscn`, `project.godot`, or the Godot
binary (`4.6.2.stable.official.71f334935`).

Host under test for agent checks: `godot --headless --path . -- --log-input`
(started in the background, stdout captured to the evidence dir, killed after
the check). For human checks: the same project windowed, `godot --path .`.

| # | Criterion | Surface / real dependency | Command or action | Expected | Evidence path | Earliest checkpoint | Human gate |
|---|---|---|---|---|---|---|---|
| V1 | AC6 boot-check | local, Godot | `godot --headless --quit` | exit 0, no `SCRIPT ERROR`/`ERROR:` lines | `test-results/boot-check/output.txt` | after every step | no |
| V2 | AC1 (agent pre-check) page reachable over the real LAN interface | local, real TCP over `en0` | `curl -s -D - -o body.html http://<lan-ip>:8080/` (lan-ip from host stdout; `172.20.1.170` at planning time) | `HTTP/1.1 200`, `Content-Type: text/html`, body contains `<title>` and `new WebSocket(` | `test-results/ac1-page-reachable/headers.txt`, `body.html` | after step 3 | no |
| V3 | AC1 page loads on a phone | phone browser (iOS Safari or Android Chrome), LAN | human opens the URL shown on the host screen | page renders full-screen, shows "P1" after connecting | `test-results/ac1-controller-page-loads/phone-screenshot.png` (human supplies) | after step 3 | yes: prereq host running + phone on same Wi-Fi; action open URL; expected page + "P1"; post-check screenshot file present and committed |
| V4 | AC2 (agent candidate) direction and reach mapping | local, real WS via Godot probe | run host with `--log-input`; `... ws_probe_client.gd -- --sequence=direction` then `--sequence=reach` | log shows `slot 0 bound`; angles ≈ `0, -1.5708, 3.1416, 1.5708` (±0.01) for direction; `len` ≈ `50, 80, 140` (min 20 + t·120) for reach | `test-results/ac2-vector-mapping/host.log`, `probe.log` | after step 4 | no |
| V5 | AC2 (agent candidate) real browser page drives the host | Claude Browser pane (Chromium) ↔ host over loopback | open `http://127.0.0.1:8080/`; `left_click_drag` from centre to +200 px right; screenshot page | host log shows `slot=0 v=(≈1.0, ≈0.0)` then `v=(0, 0)` after release | `test-results/ac2-browser-drag/host.log`, `page.png` | after step 3 | no |
| V6 | AC2 drag moves the arm, direction and reach match | phone + host screen | human drags in four directions and at two distances | arm follows; video | `test-results/ac2-drag-moves-arm/video.mp4` (human supplies) | after step 3 | yes: prereq V3 passed; action drag; expected arm direction/reach match; post-check video committed, reviewer confirms content matches criterion |
| V7 | AC3 (agent candidate) two controllers, no cross-talk | local, two concurrent probe processes | start probe A `--sequence=direction` and probe B `--sequence=reach` concurrently | log shows `slot 0 bound`, `slot 1 bound`; every `slot=0` line carries only direction-sequence vectors and every `slot=1` line only reach-sequence vectors | `test-results/ac3-two-slots/host.log` | after step 4 | no |
| V8 | AC3 two phones drive two players independently | two phones + host | human: both phones join; each drags in turn, then both at once | P1 phone moves only blue body, P2 only orange; video | `test-results/ac3-two-phones/video.mp4` (human supplies) | after step 3 | yes: prereq two phones on same Wi-Fi; action as described; expected no cross-talk; post-check video committed |
| V9 | AC4 (agent candidate) release returns to rest, no snap or drift | local, probe | `--sequence=release` | after the `(0,0)` frames begin, `len` decreases monotonically over ≥3 physics frames to `20` and then stays constant for ≥30 frames; `angle` unchanged | `test-results/ac4-release-to-rest/host.log` | after step 4 | no |
| V10 | AC4 release returns arm to rest without snapping or drift | phone + host | human drags then lifts thumb several times | arm eases to rest and stays; video | `test-results/ac4-release-to-rest-phone/video.mp4` (human supplies) | after step 3 | yes: prereq V3; action drag/release ×5; expected ease-out, no drift; post-check video committed |
| V11 | AC5 latency feels snappy (**human-gated per issue**) | phone on 5 GHz or host hotspot + host | human drags continuously ~15 s and attempts a deliberate swing | no perceptible lag or stutter | `test-results/ac5-latency-feel/verdict.md` (verdict, Wi-Fi band, phone model, browser) and the same recorded as an issue comment | after step 3 | yes: prereq host running, phone on 5 GHz (host was on 5 GHz ch. 44 at planning time; re-check with `system_profiler SPAirPortDataType`); action as described; expected snappy; post-check verdict + band recorded on issue #1. On FAIL record it; WebRTC DataChannel is the documented upgrade path, not a silent re-architecture |
| V12 | DoD: evidence committed, PR opened | local git + GitHub | `git ls-files test-results` on the branch; `gh pr view --json url` | every `PASS` path above is tracked; PR body links them | PR description | step 6 | no |

Real-dependency coverage of integration seams: HTTP seam — V2 (real LAN
interface via curl), V3 (phone); WebSocket seam — V4/V7/V9 (real WS from a
separate Godot process), V5 (real browser WS), V6/V8/V10 (phones).

Fixtures: `tools/ws_probe_client.gd` (committed); no accounts, seed data, or
external services. Provisioning: none beyond starting the host. Cleanup: kill
the background host process; leave no stray listeners on 8080/8081 (`lsof
-nP -iTCP:8080 -iTCP:8081 -sTCP:LISTEN` must return nothing after checks).

Anti-churn: do not write the issue number into files under `test-results/`;
record the verified commit SHA in the PR/closeout record, not in an evidence
file.

## 8. Candidate evidence gathered during planning

Reusable by `/atlas-implement` when no invalidator has fired. Environment for
all: macOS Darwin 24.6.0, Godot `4.6.2.stable.official.71f334935` at
`/usr/local/bin/godot`, project dir `.`.

| Id | What it proves | Command (scratchpad scripts, not in repo) | Result | Invalidators |
|---|---|---|---|---|
| CE1 | Every engine API this plan relies on exists in the installed build, `PackedByteArray.encode_float/decode_float` round-trips, `TCPServer.listen` works headless, `IP.get_local_addresses()` yields the LAN IPv4 | `godot --headless --path . -s api_probe.gd` (ClassDB `class_exists`/`class_has_method` for `TCPServer`, `StreamPeerTCP`, `WebSocketPeer.accept_stream/get_ready_state/get_available_packet_count/connect_to_url`, `FileAccess`, `IP`) | `PROBE_RESULT: ALL_OK`, LAN IPv4 `172.20.1.170`, ephemeral listen OK | Godot binary change |
| CE2 | Two-port design works headless end to end: hand-rolled HTTP answers `curl` with `200 text/html; charset=utf-8` and correct `Content-Length`; `WebSocketPeer.accept_stream` completes a handshake with a Godot `connect_to_url` client; three 8-byte LE float32 frames decode exactly (`(0.5,0)`, `(0,-1)`, `(-0.7071,0.7071)`) | `godot --headless --path . -s spike_server.gd -- --client=spike_client.gd --curl-out=...` (ports 8765/8766, loopback) | `SPIKE_RESULT: PASS http_served=1 packets=3 elapsed=1.03s`; curl headers `HTTP/1.1 200 OK`, `Content-Length: 61`, `Connection: close` | Godot binary change. Does **not** prove a browser's WS handshake (V5/V3 do) |
| CE3 | Baseline boot-check passes on the pre-change tree and the command works in this environment | `godot --headless --quit` | clean exit, 0.74 s | any code/scene change (so this is a command-viability proof only; V1 must be rerun) |
| CE4 | AC5 prerequisite: host Wi-Fi is on 5 GHz | `system_profiler SPAirPortDataType` | `Channel: 44 (5GHz, 80MHz)`, `802.11ac` | network change; re-check immediately before V11 |
| CE5 | Ports 8080/8081 are free on the host at planning time | `lsof -nP -iTCP:8080 -iTCP:8081 -sTCP:LISTEN` | none | any process later binding them |

Known-good API sequence from CE2 (for the implementer): `srv.listen(port)` →
per frame `while srv.is_connection_available(): tcp = srv.take_connection()`;
WS: `peer = WebSocketPeer.new(); peer.accept_stream(tcp)`; per frame
`peer.poll()`; state via `peer.get_ready_state()`; packets via
`while peer.get_available_packet_count() > 0: pkt = peer.get_packet()`; HTTP:
`tcp.poll()`, `tcp.get_status() == STATUS_CONNECTED`, `tcp.get_data(n)[1]`,
`tcp.put_data(bytes)`, `tcp.disconnect_from_host()`.

## 9. Tracker and repository mutations (preview)

Performed only after the human says go; none have been executed yet.

1. Create the configured lifecycle labels missing from the repo:
   `atlas:planning`, `atlas:plan-review`, `needs-triage`, `needs-info`,
   `ready-for-agent`, `ready-for-human` (`gh label create <name>
   --description "<meaning from docs/agents/issue-tracker.md>"`).
2. `gh issue edit 1 --add-label atlas:planning` then, as the plan is complete,
   `gh issue edit 1 --remove-label atlas:planning --add-label atlas:plan-review`.
3. `gh issue comment 1` with an `[EXECUTION PLAN]` record pointing at this
   file, listing section 3 decisions for confirmation and section 4 hazards.
4. This file (already written as a permitted draft, uncommitted).

No assignee is set during planning so the "ready to implement" rule (labeled
`ready-for-agent` with no assignee) stays satisfiable.

## 10. Next invocation

After confirming section 3 (especially the Wake Lock deviation) and committing
the Atlas setup to `main`: `/atlas-implement 1`. Invoking it approves this
plan; the tracker moves to `ready-for-agent` when implementation starts.
