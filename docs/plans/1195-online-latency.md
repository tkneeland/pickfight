# Technical plan: #1195 Online latency: measure and show ping per player, then cut the joiner's input-to-screen delay

- Work package: GitHub issue [#1195](https://github.com/tkneeland/pickfight/issues/1195)
  (stable contract; not duplicated here). `bug`, `p1`, `ready-for-agent`, assigned `agage-JG`.
- Plan status: **DRAFT, revision 3, awaiting owner approval** (repository storage, drafts before
  approval permitted; the issue is already `ready-for-agent`, a later state than `atlas:plan-review`,
  so no label moves)
- Planned against: `origin/main` @ `d3fe392` (2026-11-10)
- Run surface: local headless scenarios plus GitHub Actions CI (`scenarios.yml`); two human-gated real-network checks
- Red-team review: two cycles (section 10); revision 3 answers every finding of both; a third cycle was not run (the skill stops at two), so the owner's approval is the final gate

## 1. Intent

Give every Online match a number for its lag, then shrink the part of the lag
the game itself adds. The plan ships in two PRs, both `--refs #1195` as the
issue allows:

- **PR A (step 1, measure):** an in-match ping readout on the host screen,
  mirrored to every joiner through the existing HUD mirror; a felt
  input-to-screen delay the client measures on the pose it actually draws and
  reports to the host; a host-to-relay round trip so each seat's client leg
  can be told from the host's own (the issue's step 4 "where the players were
  relative to `iad`", answered without location data); per-seat round-trip
  average / p95 / max written to the host's match log and the telemetry
  record at match end.
- **PR B (step 2, cut):** an adaptive interpolation delay in place of the
  fixed 100 ms, the snapshot stream at 60 Hz, and a measured decision on
  input-on-change.

Step 3 (client-side prediction) is conditional in the contract on step 1's
numbers. This plan does not design it: if PR B's numbers trigger it, it is
either a conditional PR C planned then under #1195 or a follow-up ticket;
which one is an owner decision (section 9, D9). The direct-connection
follow-up of step 4 is filed as a ticket at closeout, not built.

What the issue calls "nobody sees it" is partly stale: the round trip already
shows beside each remote player in the lobby (host screen and joiner, #446 and
#1127) and on the end-of-round scoreboard (#446). New in step 1 is the
**in-match** readout, the felt delay, the host leg, and the end-of-match
statistics.

### The delay budget this plan works on

A joiner's input-to-screen delay today, on a steady link, is:

| Part | Today | After PR B (steady link) | Owner |
|---|---|---|---|
| client leg + host leg (relay round trip) | network | unchanged | the route |
| host input smoothing (`INPUT_SMOOTHING_SEC`, one queued packet per host frame) | ~25 ms | unchanged | game |
| snapshot wait (half an interval, `SNAPSHOT_HZ`) | ~17 ms avg, 33 max | ~8 ms avg, 17 max | game |
| interpolation buffer (`INTERP_MSEC`) | 100 ms | 40–55 ms (D3) | game |
| client frame | ~8–16 ms | unchanged | display |
| **game-added total** | **~150 ms** | **~80–95 ms** | |

The expected game-added saving is about 55–70 ms on a steady link, which is
why the acceptance bar of 50 ms is reachable but not comfortable: section 7
gives the contingency, and V7 records "felt minus ping" (the game-added part)
beside the raw number so network variance between sessions cannot hide or
fake the result. Nagle on the client's and host's own WebSocket sockets is an
unverified extra: the relay disables it on accepted sockets
(`Relay.gd:243`), but Godot's `WebSocketPeer.connect_to_url` exposes no
`set_no_delay`; step 2 includes one check of this (V15).

## 2. Affected areas and interfaces

Domain terms follow `CONTEXT.md`: *remote seat*, *host-PC seat*, *Online
match*, *round*, *match*. "Ping" is the existing word for the per-seat round
trip (#446). "Felt delay" (client-measured input-to-screen time) and "host
leg" (host-to-relay round trip) are diagnostics, not new domain objects.

| Area | Change |
|---|---|
| `scripts/PingReadout.gd` (**new**, `extends RefCounted`, no `class_name`, preloaded by path) | `static func make(ui_root: CanvasLayer) -> Label`: returns the existing child named `Ping` or builds it with anchors top-right (`PRESET_TOP_RIGHT`), a fixed offset, `HORIZONTAL_ALIGNMENT_RIGHT`, a 16 px font-size override and the HUD theme; `static func line(name, ping_msec, felt_msec) -> String` joins the seat's name, `PING_MS` and `FELT_MS`. Both the host and the joiner build the label through this one function, so the mirror only ever has to update text and colour on a node that is already placed (red-team B1). |
| `scripts/ControllerServer.gd` (`RemoteSeat`, ping block, snapshot block) | `RemoteSeat` gains `rtt_samples: PackedInt32Array` (cap 4096, oldest dropped), `felt_sum/felt_n` (for a match mean) and `felt_msec: int = -1`. `_on_pong` appends, and reads an optional `"felt"` only when `_is_number` and clamps it to -1..60000 (anything else is -1) and an optional `"share": bool` (D8). Every number `slot_ping_stats` returns (`avg`, `p95`, `max`, `n`, `felt`, and `host_leg` when added) is clamped to -1..60000 so a stalled host clock can never push the record out of the relay's range. New `slot_ping_stats(slot) -> Dictionary` (`{"avg","p95","max","n","felt","share"}`, `{}` for a non-remote seat or no samples), `reset_ping_stats()` (match start), and a match-level `_departed_ping_stats: Array` that `_unbind` appends a seat's stats to (so a joiner who leaves mid-match is still in the end-of-match list, red-team m4); `match_ping_stats() -> Array` returns live plus departed, filtered of `{}`. **Host leg:** `relay_rtt_msec: int = -1`; about once a second while online the host sends the relay `{"t":"echo","n":N}` and times the `{"t":"echo","n":N}` reply (`RelayLink` passes control text through `_handle_control`; one new arm). PR B: `SNAPSHOT_HZ` 30 → 60, `SNAPSHOT_FULL_EVERY` 30 → 60, HUD cadence `_hud_tick % 4` → `% 8`. PR B option: `send_input_on_change` is a client flag, nothing here. |
| `scripts/RelayLink.gd` | `send_control(text)` for the echo, and `echo_received(n)` signal from `_handle_control`. Minimal. |
| `relay/Relay.gd` | Host control message `{"t":"echo","n":N}` answered with the same text to that host only (no forwarding; a client sending it is ignored, as every unknown client text is dropped today). `clean_stats_record` accepts an optional `ping`: an Array of at most `STATS_MAX_PING_ENTRIES = 8` Dictionaries whose `avg`, `p95`, `max`, `n`, `felt`, `host_leg` are numbers in -1..60000, else the record is rejected as today; unknown keys still dropped. **Redeploy needed** for both (`docs/deploy.md`); until then the live relay drops the field and answers no echo (`relay_rtt_msec` stays -1 and the readout shows no host leg), both harmless. |
| `scripts/RemoteClient.gd` | PR A: the felt-delay probe (D2) on the pose `_render` passes to `set_pose` for `player<slot>`; `"felt"` and `"share"` on each pong; `_build_hud()` calls `PingReadout.make(_host_hud)` right after instantiating the scene so the joiner's label exists, placed, before the first `hud` frame. PR B: snapshot gap ring, `_note_snapshot_gap(msec)` (called from `apply_snapshot`), `interp_msec()`, `_slew_interp(now_msec)` (called at the top of `_render`), the constant kept as fallback and ceiling; `effects.delay_msec = interp_msec()` each render. PR B option: `send_input_on_change` flag (D5). |
| `scripts/RemoteEffects.gd` | `delay_msec` written each frame by the client (today set once). One line. |
| `scripts/RoundManager.gd` (**hot shared file**: additive, no reordering) | `_ping_readout_tick()` on a 1 s timer: `PingReadout.make(get_node(score_label_path).get_parent())` (the same HUD root `RemoteHud.capture` mirrors, `RemoteHud.gd:54`), text from `PingReadout.line` per remote seat plus a last line `host leg N ms` when known, colour the worst `LobbyScreen.ping_color` of its lines, hidden with no remote seat bound or off a round; `reset_ping_stats()` where `_match_started_msec` is set; `match_ping_stats()` (plus `relay_rtt_msec` as `host_leg` on each entry) passed to `_write_balance_log` and `send_telemetry`. |
| `scripts/MatchStats.gd` | `balance_log_line(..., ping: Array = [])` writes `"ping": [{"avg","p95","max","n","felt","host_leg"}, ...]` when non-empty; **no slot, name or colour**. |
| `scripts/StatsSender.gd` | `build_record(..., ping: Array = [])`, same list, omitted when empty, entries filtered by D8, and **capped at 8 entries** (the 8 with the highest `n`; a match with rejoins can hold live plus departed entries beyond 8, and the relay rejects a longer list outright). |
| `tools/summarise_stats.py` | Prints "Online ping (remote seats): avg / p95 / max / felt / host leg" over records with `ping`. |
| `tools/perf_probe.gd` | Not edited (it stubs the roster, so it never streams; red-team M1). Capture cost is timed by scenario S8 instead. |
| `translations/strings.csv` | New keys `FELT_MS` = `"delay %d ms"` and `HOST_LEG_MS` = `"host leg %d ms"` with 9 translations each in the style of `PING_MS`; `TELEMETRY_NOTICE` (row 278) gains "and, in Online matches, each connection's ping" in every language (M5), unless the owner records otherwise (D8). |
| `docs/launch/privacy-policy.md` | Section 2's list of what the record contains gains the Online ping statistics and says they carry no name, slot or location (M5). |
| `tools/scenario_runner.gd` (append-only; one necessary minimal in-place edit) | New scenarios, section 5. `snapshot_stream_reaches_remote_client` asserts 25–35 Hz at `scenario_runner.gd:27954`; in PR B that assertion is derived from `ControllerServerScript.SNAPSHOT_HZ ± 5` and the fulls bound stays 2–4 (the one in-place edit, named in Touches; `collaboration.md` makes the list, dispatcher and function order append-only and this changes none of them). The two scenarios that read `INTERP_MSEC` keep passing unchanged because the adaptive value falls back to the constant with fewer than `INTERP_MIN_SAMPLES` gaps (D3). |
| `docs/FEATURES.md` | Online section: the in-match readout (ping, felt delay, host leg), the end-of-match statistics in the balance log and telemetry, the adaptive delay and 60 Hz; telemetry bullet (#372) gains the `ping` field. |
| `docs/deploy.md` | One line: redeploy the relay after PR A. |
| `test-results/issue-1195/` | Committed evidence (section 5). |

Exclusions: client-side prediction (step 3), a direct connection or relay
regions, any location, timezone or IP data, the phone controller page,
`scenes/*.tscn` (`HostHud.tscn` untouched: the label is built at run time on
both sides), `RemotePuppet.gd`, the lobby cards (already show ping),
`tools/perf_probe.gd`, ADR changes (ADR-0019 still holds: the host is the
only simulation and the client predicts nothing).

**Touches** (to be written into #1195's body before the claim, per
`collaboration.md`; a tracker mutation for the owner to approve, section 9):
`scripts/PingReadout.gd` (new), `scripts/ControllerServer.gd`,
`scripts/RelayLink.gd`, `scripts/RemoteClient.gd`, `scripts/RemoteEffects.gd`,
`scripts/RoundManager.gd`, `scripts/MatchStats.gd`, `scripts/StatsSender.gd`,
`relay/Relay.gd`, `tools/summarise_stats.py`, `tools/scenario_runner.gd`
(append plus the one `SNAPSHOT_HZ` assertion), `translations/strings.csv`,
`docs/launch/privacy-policy.md`, `docs/FEATURES.md`, `docs/deploy.md`,
`test-results/issue-1195/`.

## 3. Technical decisions (confirm at approval)

- **D1: One placed readout label, built by the same static function on
  both sides.** `UiMirror` copies a Label's visibility, text, colour, scale,
  pivot and modulate only (`UiMirror.gd:37`), and a node it has to create
  lands at (0,0) with the default font (`_make`, lines 95–111). So the
  readout is not left for the mirror to create: `PingReadout.make()` builds
  and places it on the host (`RoundManager`) and on the joiner
  (`RemoteClient._build_hud()`), and the mirror then only carries text and
  colour. The label is top-right, 16 px, one line per remote seat
  (`<name> <ping> (delay N ms)`), a last line for the host leg, one colour for
  the whole label (the mirror's granularity): the worst of its lines by
  `LobbyScreen.ping_color`. Hidden when no remote seat is bound (Local, Solo)
  and off a round; the lobby covers the HUD and already carries ping.
  Refreshed on a 1 s timer so the `hud` frame does not churn. *Alternative:*
  a column on the scoreboard; rejected, it is only up between rounds.
- **D2: The felt-delay probe watches the drawn pose, not the raw sample.**
  A sample's pose is `[body.position, body.rotation, weapon.head_position,
  weapon.head_rotation]` (`_push_sample`, lines 921–923) and is stamped on
  arrival, before the interpolation delay. The probe therefore reads the
  interpolated `from.lerp(to, alpha)` values `_render` passes to `set_pose`
  for `player<slot>` (the joiner's own puppet), and the arm angle is
  `(head_position - body_position).angle()` (indices 2 and 0). Felt delay =
  wall-clock msec from `_send_input` sending a vector that changed after at
  least 300 ms at rest, to the first render whose drawn arm angle differs
  from the resting angle by more than 0.05 rad. Kept as a match mean
  (`felt_sum/felt_n`) and a last value; `felt_msec()` returns the mean, the
  readout shows the mean, and the log carries the mean (red-team m8). Each
  pong carries `"felt"`. Cosmetic: no input or physics path reads it.
  Headless caveat: under `--fixed-fps 60` game time runs faster than wall
  time, so a scenario proves the probe fires on the drawn pose and reports;
  the value comes from the real-network check (V7).
- **D3: Adaptive interpolation delay.** `_note_snapshot_gap()` records the
  wall-clock gap between consecutive applied snapshots in a ring of 120.
  With fewer than `INTERP_MIN_SAMPLES = 20` gaps, `interp_msec()` is
  `INTERP_MSEC` (100; the join and every existing scenario unchanged).
  Otherwise `target = 2 * mean_gap + jitter`, `jitter` = p95 of
  `|gap - mean_gap|`, clamped to `[INTERP_MIN_MSEC = 40, INTERP_MSEC]`.
  `_slew_interp(now)` moves the live value toward the target at
  `INTERP_SLEW_MS_PER_SEC = 60` wall ms per second (frame-rate independent,
  red-team m1), so the puppets never jump and time never visibly speeds up.
  A gap over 500 ms (a stall, a rejoin) clears the ring and **snaps** the
  live value to 100: the world was frozen for that gap, so there is no
  smooth motion to preserve, and the stale samples would otherwise lie.
  `effects.delay_msec` follows the live value every render (#976). Expected
  settle: 60 Hz steady about 40–55 ms (TCP delivers in bunches at frame
  boundaries, so the jitter term is about 16 ms even on a good link); 30 Hz
  about 70–85; jittery links rise toward 100. *Alternative:* a fixed 50 ms;
  rejected because a jittery TCP link would stutter.
- **D4: 60 Hz is within budget.** Candidate evidence (section 6): 8 players
  at 30 Hz cost 9,679 B/s per seat; deltas dominate, so 60 Hz is about
  19–20 KB/s, under the 40 KB/s per-seat budget of ADR-0019
  (`SNAPSHOT_BUDGET_BPS_251`). The relay's token bucket limits only
  client→host frames (`CLIENT_FRAMES_PER_SEC = 120`). Host CPU: the host
  captures, deltas and encodes once per frame and broadcasts the one payload
  (`_stream_snapshots`, `send_to(0, ...)`), so the cost depends on the rate
  and the player count, not the seat count. S8 times one capture + delta +
  encode on the 8-bot rig and V6 bounds it at 4,000 µs per call (a quarter of
  a 16.7 ms frame); the per-call cost is rate-independent, so it is measured
  once, on PR B. If it exceeds the bound, PR B keeps `SNAPSHOT_HZ` at 30,
  records that as a scope note, and the adaptive delay alone carries step 2.
- **D5: Input-on-change replaces, never adds to, the tick send; off by
  default; decided by a human-gated run.** The host queues every received
  vector and plays one per host frame while calm (`InputSmoother.step`,
  `ControllerServer.gd:299–308`), so an extra send on top of the tick send
  would lengthen that queue by a host frame per packet, adding delay rather
  than removing tick wait (red-team M3). The option, behind a client flag
  `send_input_on_change` (not a user setting), sends at once when the vector
  changes (from `mouse_motion` / `_pad_input`) and sets a `_sent_this_tick`
  latch; `_physics_process` sends only when the latch is clear and then
  clears it, so ticks with no change still send (the keepalive the host's
  10 s remote input timeout needs) and no tick ever sends twice. Rate stays
  at most 60/s, inside the relay's bucket. V8 is human-gated (a V7 rerun);
  the default stays off unless V8 shows felt delay at least 10 ms better and
  no relay drops, in which case PR B flips it and records the numbers.
- **D6: What goes where at match end.** The `ping` list goes into the
  balance log line (`user://balance_stats.jsonl`, #316, written only with
  stats sharing on, #609) and into the telemetry record (#372). Both are per
  remote seat, anonymous (no slot, name or colour), with `felt` and
  `host_leg`; `n` is the sample count. Seats that left mid-match are
  included from `_departed_ping_stats`. Telemetry stays gated exactly as
  today (`StatsSender.should_send`). The host clamps every client-supplied
  number before it can reach the record (M4), and S4 runs
  `Relay.clean_stats_record` on the exact record `build_record` builds.
- **D7: Step 4 answered by legs, not locations.** "Where the players were
  relative to `iad`" is recorded as the host leg (host↔relay round trip,
  from the relay echo) next to each seat's round trip; the client leg is
  their difference. No timezone, region or IP is recorded: the record is
  described as having "no names, colours, devices or IDs"
  (`privacy-policy.md:25`) and location would be a new kind of data. This
  meets the contract's step 4 without the data the plan refuses.
- **D8: Joiner consent (owner decision).** The per-seat numbers describe a
  joiner's connection but are sent under the host's opt-in. Recommended:
  each pong carries `"share": share_stats and telemetry_notice_seen` from the
  joiner's own `HostSettings` (the same two-part consent the host's own
  `StatsSender.should_send` applies; `share_stats` alone defaults to true
  before the notice is seen, `HostSettings.gd:76-77`) and the telemetry list
  includes only seats whose last pong said true (the local balance log keeps
  every seat, it never leaves the host). An older client that sends no flag
  counts as not sharing. Alternative the owner may pick:
  host consent covers the room, no flag. Either way `TELEMETRY_NOTICE` and
  the privacy draft are updated (section 2) unless the owner records that
  the notice text stays.

## 4. Ordered steps

Before the claim: write the Touches list (section 2) into #1195, claim with
`gh issue edit 1195 --add-assignee @me` (already assigned to `agage-JG`),
post a `[CLAIM]` comment, then `tools/agents/pf-msg.sh claim 1195`
(`collaboration.md`).

PR A: branch `feat/issue-1195-ping-readout` from `origin/main`.

1. **Host statistics and host leg.** `ControllerServer.gd`: `RemoteSeat`
   history, `felt` and `share` parsing with clamps, `slot_ping_stats`,
   `reset_ping_stats`, `_departed_ping_stats` on `_unbind`,
   `match_ping_stats`; relay echo through `RelayLink` and `Relay.gd`.
   Checkpoint: boot check clean; `online_ping_reaches_lobby_and_scoreboard_with_warning` passes; S1 passes.
2. **Client felt-delay probe.** `RemoteClient.gd`: rest/step detector in
   `_send_input`, drawn-pose detector in `_render` (D2), `felt_msec()`,
   `"felt"` and `"share"` on the pong. Checkpoint: S3. Also V15 (Nagle check).
3. **Readout.** `scripts/PingReadout.gd`; `RoundManager._ping_readout_tick`;
   `RemoteClient._build_hud` calls `PingReadout.make`; `strings.csv` keys.
   Checkpoint: S2 (text, colour, position, size and font size equal on both sides).
4. **End-of-match statistics.** `MatchStats`, `StatsSender`, `RoundManager`
   collection and reset, `Relay.clean_stats_record`, `summarise_stats.py`,
   `docs/deploy.md`, `privacy-policy.md`, `TELEMETRY_NOTICE`. Checkpoint: S4.
5. **Scenarios, FEATURES, evidence** under `test-results/issue-1195/pr-a/`
   (V1–V4, V9–V14).
6. **Baseline number (human-gated V7, "before").** With PR A's build on the
   live relay (echo answered only once the relay is redeployed; the readout
   works either way), record ping, felt and felt-minus-ping. Put the table in
   PR A's description and `test-results/issue-1195/pr-a/real-network.md`.

PR B: branch `feat/issue-1195-adaptive-interp` from `origin/main` after PR A merges.

7. **Adaptive delay** (D3): ring, `_note_snapshot_gap`, `interp_msec`,
   `_slew_interp`, stall snap; `_render` and `effects.delay_msec` read it.
   Checkpoint: `remote_client_interpolates_100ms_behind` and
   `remote_effects_wait_for_interp_delay_976` pass unchanged; S5, S6.
8. **60 Hz** (D4): run S8 first; if within V6's bound, raise the constants
   and HUD cadence and make the one in-place assertion edit derived from
   `SNAPSHOT_HZ`; otherwise stay at 30 and record it. Checkpoint: the edited
   bandwidth scenario prints bytes/s ≤ 40,960.
9. **Game-added budget check** S9 (headless, deterministic): today's shipped
   budget (fixed `INTERP_MSEC` 100 plus half a 30 Hz interval, 116.7 ms)
   minus PR B's (the settled `interp_msec()` at the shipped `SNAPSHOT_HZ`
   plus half its interval; about 48 ms at 60 Hz, about 83 at 30) is at least
   50 ms. This is the supporting proof that does not depend on the network;
   note that at 30 Hz it comes out near 34 ms, so S9 passing depends on step
   8 raising the rate, which is why step 8 runs first.
10. **Scenarios, FEATURES, evidence** under `test-results/issue-1195/pr-b/`;
    copy PR A's `real-network.md` numbers into
    `test-results/issue-1195/pr-b/real-network.md` first (the evidence root is
    cleared per work package, red-team m5).
11. **"After" number (human-gated V7)** on the same machines and network;
    then **V8** with `send_input_on_change` on (D5). Decide the flag; write
    before/after into the PR description. If after > before − 50 ms on
    felt-minus-ping: section 7's contingency.

Declared scope: the Touches list in section 2. Nothing else. Before each
edit of `scripts/RoundManager.gd` or `tools/scenario_runner.gd`: `git fetch
origin` and rebase; both are hot shared files. Open issues at planning time
whose bodies mention the online scripts: none besides #1195 (#1196 and #1197
touch round start, not these files; confirm at implementation).

## 5. Verification map

Commands run from the repo root. `$GODOT` is the Godot 4.6.2 binary (on this
machine `%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.2-stable_win64_console.exe`;
CI uses `godot`). Scenario names are final; append them at the end of
`SCENARIO_NAMES`, the dispatcher (before the single `_:` arm) and the file;
afterwards `grep -c "^		_:$"` is 1 and the last function ends in
`return failures`.

New scenarios (on the real in-process relay rig `_rc_rig_241` unless said):

- S1 `online_ping_stats_avg_p95_max_1195`: pongs held 0, 100, 300 ms;
  `slot_ping_stats` gives n=3, max≥300, p95≥300, avg in band, `{}` for a bot
  and the host-PC seat; a pong with `"felt": 1e9` and one with `"felt": "x"`
  leave `felt` at -1; `reset_ping_stats()` empties it; a seat unbound after
  sampling appears in `match_ping_stats()`.
- S2 `online_ping_readout_mirrors_to_joiner_1195`: one remote client in a
  round; after the 1 s tick the host HUD's `Ping` label is visible, names the
  client and its round trip, and its right edge is within 40 px of the
  viewport's right edge (so two broken `make()` calls cannot pass by being
  equal); after the next `hud` frame and one more `process_frame` (a Label's
  `size` settles lazily) the joiner's `host_hud()` `Ping` label has identical
  `text`, font colour, `visible`, `position`, `size`, anchors and font-size
  override; in a Local rig (`_snap_main_251` without `go_online`) the label
  stays hidden.
- S3 `remote_client_reports_felt_delay_1195`: the client rests 300 ms (wall,
  the `while Time.get_ticks_msec() < …: await process_frame` pattern of
  `scenario_runner.gd:31538`), moves the mouse, the host moves the player,
  snapshots arrive and `_render` draws them; `felt_msec()` becomes ≥ 0 and
  is **at least `INTERP_MSEC − 1000/SNAPSHOT_HZ − 5` wall ms**: a drawn pose
  cannot move before `render_at` passes the previous sample, so a probe that
  read the raw newest sample would report far less on loopback and fail
  this bound; the next pong carries `felt`; `slot_ping_stats(slot)["felt"]`
  matches.
- S4 `match_end_logs_ping_stats_1195`: a match on the rig with one remote
  seat, `balance_log_path` at a temp file, `telemetry_sink` set; the log
  line and the record carry a `ping` list of one entry with the six fields,
  no slot or name; with the joiner's `share` false, or its
  `telemetry_notice_seen` false, the telemetry list is empty and the log
  still has the entry (D8 recommended form); `build_record` given 9 entries
  keeps the 8 with the highest `n`; `Relay.clean_stats_record` keeps the
  built record and rejects a 9-entry list and a non-numeric `avg`.
- S5 `remote_client_interp_adapts_to_snapshot_rate_1195` (no rig; a fresh
  client from `_rc_client_241("ws://127.0.0.1:1")` **per case**, with
  `set_process(false)` so the real-clock `_render` never runs between the
  fake-clock calls, and no `await` inside a case): drive
  `_note_snapshot_gap` with 40 gaps of 16 ms and `_slew_interp(fake_now)`
  advanced 2 s: `interp_msec()` in [40, 60]; 40 gaps of 33 ms: [66, 100];
  10 gaps: exactly 100; a 600 ms gap after settling: exactly 100 at once;
  then `set_process(true)`, one render, `effects.delay_msec == interp_msec()`.
- S6 `remote_client_interp_slews_not_jumps_1195`: same isolation; from 100
  with target 40, `_slew_interp` advanced 500 ms moves the value by 30 ± 1.
- S8 `snapshot_capture_cost_8_players_1195`: on the 8-bot `_snap_main_251`
  rig, 300 iterations of `SnapshotCapture.capture(rm)`, `delta(world,
  previous)` and `Snapshot.encode` timed with `Time.get_ticks_usec()`;
  prints the mean µs per iteration; fails above 4,000 µs.
- S9 `online_game_added_delay_budget_1195`: pure arithmetic: today's budget
  `INTERP_MSEC + 1000/30/2` (116.7) minus PR B's `settled_60 + 1000/SNAPSHOT_HZ/2`,
  where `settled_60` is S5's value for the shipped rate (expected about 40 at
  60 Hz, giving about 68 ms), is ≥ 50; the printed difference is evidence.

| # | Criterion (issue Acceptance) | Surface / command | Expected | Evidence | Checkpoint | Invalidated by |
|---|---|---|---|---|---|---|
| V1 | Ping statistics per seat (avg, p95, max); hostile `felt` clamped; departed seats kept | `$GODOT --headless --fixed-fps 60 --path . -s tools/scenario_runner.gd -- --scenario=online_ping_stats_avg_p95_max_1195` | PASS | `test-results/issue-1195/pr-a/scenario-S1.txt` | PR A step 1 | `RemoteSeat`, `_on_pong`, `_unbind`, `slot_ping_stats` |
| V2 | Ping visible in a match, identical on host and client (text, colour, placement) | `-- --scenario=online_ping_readout_mirrors_to_joiner_1195` | PASS | `.../pr-a/scenario-S2.txt` | PR A step 3 | `PingReadout`, `UiMirror`, `RemoteHud.capture`, `_build_hud` |
| V3 | Felt delay measured on the drawn pose and reported | `-- --scenario=remote_client_reports_felt_delay_1195` | PASS | `.../pr-a/scenario-S3.txt` | PR A step 2 | `_send_input`, `_render`, pong |
| V4 | End-of-match log records avg, p95, max per player; telemetry carries it under D8; relay keeps it | `-- --scenario=match_end_logs_ping_stats_1195` | PASS | `.../pr-a/scenario-S4.txt` | PR A step 4 | `balance_log_line`, `build_record`, `clean_stats_record`, D8 |
| V5 | 60 Hz within the per-seat budget | the edited `snapshot_stream_reaches_remote_client` | PASS, printed bytes/s ≤ 40,960, Hz within `SNAPSHOT_HZ ± 5` | `.../pr-b/scenario-bandwidth.txt` | PR B step 8 | `SNAPSHOT_HZ`, `SnapshotCapture`, `Snapshot.encode` |
| V6 | Host capture cost per frame (rate-independent) | `-- --scenario=snapshot_capture_cost_8_players_1195` on PR B | PASS: mean capture + delta + encode ≤ 4,000 µs; otherwise D4's stay-at-30 fallback | `.../pr-b/capture-cost.txt` | PR B step 8 | capture, delta or encode code, bot count |
| V7 | **Human-gated.** Felt input-to-screen delay drops ≥ 50 ms on the same network | Prerequisite: a PR A build (before) and a PR B build (after): the owner's builds come from the itch.io release workflow (a release cut from `main` after each PR merges), or an editor run of each branch on both machines; same two machines, or one machine with a second instance joining its own room, through `wss://pickfight-relay.fly.dev`; same network, same hour; on the host, stats sharing on and the first-launch notice seen (else no balance log line is written, #609); the relay redeployed for the host leg (optional). Human action: play two rounds, hold the mouse still 1 s and flick ten times, read the readout's ping, delay and host leg. Expected: after's felt-minus-ping ≤ before's − 50 ms. Post-action check: each match's balance log line `felt` equals the readout's mean within 5 ms. | before/after table with ping, felt, felt−ping, host leg | `.../pr-a/real-network.md`, `.../pr-b/real-network.md` (PR A's numbers copied in), PR B description | PR A step 6, PR B step 11 | interpolation, stream rate, input cadence, smoothing |
| V8 | **Human-gated.** Input-on-change decision (D5) | V7's "after" run repeated with `send_input_on_change` on; plus `-- --scenario=remote_client_mouse_moves_player` and `remote_client_esc_menu_resume_and_leave` with the flag on (keepalive still sends in the menu) | delta recorded; scenarios PASS; default flipped only on D5's numbers | `.../pr-b/input-on-change.md` | PR B step 11 | relay bucket constants, `_send_input`, smoother |
| V9 | No regression in the suite | `$GODOT --headless --fixed-fps 60 --log-file <scratch> --path . -s tools/scenario_runner.gd -- --all` (or four shards via `tools/list_scenarios.sh i 4`) | `N passed, 0 failed` | `.../pr-a/scenario-all.txt`, `.../pr-b/scenario-all.txt` | before each PR | any script edit |
| V10 | Boot check and runner parse check | `$GODOT --headless --quit` ; `$GODOT --headless --path . --check-only -s tools/scenario_runner.gd 2>&1 \| grep -E "SCRIPT ERROR\|Parse Error"` | no parse or load errors; the grep prints nothing | `.../boot-check.txt`, `.../runner-parse.txt` | before each PR | any script edit |
| V11 | Fresh-clone parse (no `class_name`) | `rm -rf <scratch>/pf-fresh && git clone -q . <scratch>/pf-fresh && $GODOT --headless --path <scratch>/pf-fresh --quit 2>&1 \| grep -E "SCRIPT ERROR\|Failed to load script"` | prints nothing | `.../fresh-clone.txt` | before each PR | new type references (`PingReadout` is preloaded by path) |
| V12 | Online-parity rule | S2 plus `git grep -n "PingReadout" -- scripts` | the label is built only through `PingReadout.make`, from `RoundManager.gd` and `RemoteClient.gd`; no other readout drawing | S2 output, grep in the PR | PR A step 3 | a second readout path |
| V13 | Lobby ping, identical on host and client (already shipped, evidenced here) | `-- --scenarios=online_ping_reaches_lobby_and_scoreboard_with_warning,remote_client_lobby_text_follows_the_locale` and the #1127 joiner-lobby scenario(s) (`grep -n "1127" tools/scenario_runner.gd` names them) | PASS | `.../pr-a/scenario-lobby.txt` | PR A step 5 | lobby state, `RemoteLobby` |
| V14 | `docs/FEATURES.md` lists the readout, the logging, the adaptive delay and 60 Hz; privacy draft and notice updated per D8 | `git diff origin/main -- docs/FEATURES.md docs/launch/privacy-policy.md translations/strings.csv` | the bullets and lines are present | PR diff | each PR | — |
| V15 | Nagle on the client and host sockets | Read Godot 4.6.2's `WebSocketPeer` (`modules/websocket/wsl_peer.cpp`, `connect_to_url` path) and record whether `TCP_NODELAY` is set; if not, note it as a follow-up (no fix in this ticket) | one paragraph in `.../pr-a/nagle.md` with the source line | file | PR A step 2 | Godot version |
| V16 | Game-added budget, deterministic, against today's fixed 100 ms at 30 Hz | `-- --scenarios=remote_client_interp_adapts_to_snapshot_rate_1195,online_game_added_delay_budget_1195` | PASS, printed difference ≥ 50 (about 68 expected at 60 Hz) | `.../pr-b/scenario-S9.txt` | PR B step 9 | D3 constants, `SNAPSHOT_HZ` |
| V17 | CI green | `.github/workflows/scenarios.yml` on the PR | green | PR checks | before merge | any push |

- Real dependencies: the real `Relay.gd` on loopback (every `_rc_rig_241`
  scenario), real `ControllerServer`, `RoundManager`, `RemoteClient`,
  `RelayLink`. The live Fly relay is exercised only in V7/V8 by a human.
- Fixtures and cleanup: scenarios build everything in the rig and free it
  with `_rc_close_241`; S4 writes the balance log to a scratch path and uses
  `telemetry_sink`, so nothing reaches the owner's `user://` files or the
  network (`testing.md`).
- Evidence root `test-results/` is cleared before each PR's capture and holds
  only this work package's evidence; committed on the branch. PR B re-copies
  PR A's real-network table.

## 6. Candidate evidence from planning (2026-11-10, this worktree, un-imported, Godot 4.6.2 Windows)

Command: `Godot_v4.6.2-stable_win64_console.exe --headless --fixed-fps 60 --log-file %TEMP%\pf1195-run.log --path . -s tools/scenario_runner.gd -- --scenarios=snapshot_stream_reaches_remote_client,remote_client_interpolates_100ms_behind,online_ping_reaches_lobby_and_scoreboard_with_warning,remote_effects_wait_for_interp_delay_976`

Result: `4 passed, 0 failed, 4 total`. The bandwidth scenario printed
`90 frames in 3000 ms (30.0 Hz), 3 full` and `bandwidth_bytes_per_sec=9679`
(8 players). Resource "Failed loading" lines are the worktree's missing
`.godot/` import cache, not script errors. Invalidated by any change to
`Snapshot.gd`, `SnapshotCapture.gd`, `SNAPSHOT_HZ` or the player count in the
scenario. This is the number behind D4; PR B re-measures it (V5).

## 7. Risks and the 50 ms contingency

- **The 50 ms bar is reachable, not comfortable** (section 1 budget:
  55–70 ms expected on a steady link, less with jitter). If V7's "after"
  felt-minus-ping is not ≥ 50 ms better than "before", in order: (1) lower
  the jitter term to p90 and re-run; (2) lower `INTERP_MIN_MSEC` to 33 and
  re-run; (3) take V8's flag if it helped; (4) if still short, stop and
  bring the numbers to the owner with the two remaining levers named (the
  25 ms input smoother, and step 3's prediction), rather than widening scope.
  V16's deterministic budget check is the supporting evidence in every case.
- **Felt-delay probe false reads.** A snapshot can move the drawn arm for a
  reason other than the client's input (a hit, a gust). The 300 ms rest and
  the own-puppet restriction limit it; the match mean damps outliers. It is a
  readout, never an input path.
- **Adaptive delay under TCP stalls.** A stall delivers a burst at once; the
  ring sees one long gap and tiny ones. The ≥500 ms snap and the p95 jitter
  term push the delay back toward 100; the slew hides smaller changes. S5
  covers the snap; the burst case is checked by hand in V7 (pull the host's
  Ethernet for a second).
- **60 Hz doubles host capture work.** V6 bounds it with S8; D4 names the
  fallback.
- **Hot shared files.** `RoundManager.gd` and `scenario_runner.gd` edits are
  additive (plus the one named assertion edit); rebase before each, re-run
  the suite after each rebase.
- **The relay's stats validator.** A wrong field or an unclamped value
  rejects the whole record (400) and loses telemetry silently. The host
  clamps (M4) and S4 runs the validator on the exact built record.
- **Relay redeploy is an owner action.** Until it happens the echo is
  unanswered (host leg shows nothing) and the `ping` field is dropped. Both
  degrade silently and visibly in the readout, never in play.

## 8. Closeout items beyond the two PRs

- File the direct-connection follow-up ("without the relay, WebRTC or UDP:
  ADR-level") with PR A's and PR B's real-network numbers, including host
  legs, in its body, `p3`, `needs-triage`, when PR B merges.
- If PR B's "after" felt delay is still above ~80 ms on a good connection,
  the contract's step 3 is triggered: per D9 either plan a conditional PR C
  under #1195 (a new `/atlas-plan` pass for the prototype: cosmetic
  prediction of the joiner's own arm behind a setting, physics
  host-authoritative per ADR-0019) or file it as a ticket with the numbers.
- Step 4's evaluation: from the host-leg and client-leg numbers of the two
  real-network runs and the first playtest's telemetry, record in the
  closeout whether most testers were far from `iad` (a client leg well above
  the host leg); if so, file a "regions or host-located room" follow-up;
  if not, record "not far" and no ticket.
- Redeploy the relay (`docs/deploy.md`): owner action.
- If V15 finds Nagle on, file a follow-up.

## 9. Mutations awaiting owner approval

- Issue #1195 body: append the **Touches** section from section 2 (no other
  change to the contract).
- A `[CLAIM]` comment and `tools/agents/pf-msg.sh claim 1195` after the claim.
- Decisions D1–D8 (section 3); D8 needs a recorded owner answer before PR A
  step 4.
- **D9 (owner):** if step 3 is triggered by the numbers, build it as a
  conditional PR C under #1195 (recommended: it keeps the contract whole and
  the numbers in one place) or split it into a follow-up ticket.

## 10. Red-team review (2026-11-10, fresh `atlas-red-team-reviewer`, two cycles)

Cycle 2 (on revision 2): **REVISE**, nothing blocking; it confirmed D1/B1,
D7/M6, D5/M3 and M4 against the code. Its findings and revision 3's answers:

| Finding | Answer |
|---|---|
| M-1 S9 compared adaptive-30 with adaptive-60 (34 ms, under the bar) | S9/V16 now compare today's fixed 100 ms at 30 Hz with PR B (about 68 ms) |
| M-2 V6's ratio was 2.0 by construction; the per-seat fallback did not cut host CPU; units mismatched; S8 did not exist on PR A | V6 is one absolute 4,000 µs per-call bound measured on PR B, S8 includes `delta`, the fallback is "stay at 30 Hz" |
| M-3 `share_stats` defaults true before the notice is seen | D8 sends `share_stats and telemetry_notice_seen`; S4 case |
| M-4 live plus departed entries can exceed 8 and 400 the record | `build_record` caps at 8 by highest `n`; all six numbers clamped on the host; S4 case |
| M-5 S3 could pass with a probe on the raw sample | S3 asserts `felt ≥ INTERP_MSEC − 1000/SNAPSHOT_HZ − 5` wall ms |
| M-6 step 3 moved out of the contract without a decision | D9 owner decision; section 8 names the conditional PR C |
| m1 lazy Label `size`; equal-but-wrong placement | S2 waits a frame and asserts the host label's right edge |
| m2 no `hud_root` in RoundManager | the root is `get_node(score_label_path).get_parent()` |
| m3 on-change cap unstated | `_sent_this_tick` latch in D5 |
| m4 fake clock mixed with the real `_render`; cases sharing a ring | `set_process(false)`, fresh client per case, no `await` inside a case |
| m5 V7 needs sharing on; how the human gets builds | prerequisites name both (itch.io release workflow or editor runs) |
| m6 step 4's "add regions" had no evaluation | section 8 evaluation item |
| m7 `[CLAIM]` comment missing | added to the claim step |

Cycle 1 (on revision 1): **REVISE**. Findings and how revision 2 answered them:

| Finding | Answer |
|---|---|
| B1 the mirrored readout would land at (0,0) in the default font on the joiner (`UiMirror` carries no position or size) | D1: `PingReadout.make()` builds and places the label on both sides; S2 asserts placement |
| B2 the probe read pose index 1 (body rotation) from raw samples, skipping the interpolation delay it must measure | D2: the probe reads the drawn, interpolated pose and the arm angle from indices 2 and 0 |
| M1 `perf_probe.gd` stubs the roster so it never streams | S8 times capture + encode on the 8-bot rig; `perf_probe.gd` not edited |
| M2 the 50 ms criterion may fail with no fail path | Section 1 budget, V7 records felt−ping, S9/V16 deterministic check, section 7 contingency |
| M3 input-on-change would add smoother backlog; V8 was really human-gated | D5: on-change replaces the tick send; V8 marked human-gated; default off |
| M4 an unclamped client `felt` could 400 the whole record | `_on_pong` clamps; `{}` seats filtered; S1 hostile cases |
| M5 privacy draft and `TELEMETRY_NOTICE` would understate the record; joiner consent | Scope adds both documents; D8 owner decision with a recommended joiner flag |
| M6 step 4 dropped rather than answered | D7: host leg via relay echo, client leg by difference, no location data |
| M7 no Touches on #1195 | Section 2 Touches list, section 9 mutation |
| M8 lobby half of criterion 1 unevidenced | V13 |
| m1 instant reset vs slew; per-frame slew | D3: ms per wall second; the stall case snaps deliberately and says why |
| m2 S5 needs a seam | `_note_snapshot_gap`, `_slew_interp` with a fake clock |
| m3 the in-place assertion edit | named as the one necessary minimal edit, derived from `SNAPSHOT_HZ`; S7 dropped |
| m4 departed seats lost | `_departed_ping_stats` on `_unbind` |
| m5 baseline lost when evidence is cleared | PR B copies PR A's table |
| m6 `/tmp` and bare `godot` | `$GODOT` and a scratch path |
| m7 Nagle unexamined | V15 |
| m8 readout mean vs logged last value | both are the match mean |
