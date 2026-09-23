# Technical plan: #5 Respawn dies instantly on next round start; round-end message should show scoreboard

- Work package: https://github.com/tkneeland/pickfight/issues/5
- Plan status: **DRAFT, awaiting human approval** (would carry `atlas:plan-review` once posted to the tracker; not yet posted)
- Planned against: `2130b3fe727ccd9e8617430a53824e7f9204a7d7`
- Run surface: local only (`docs/agents/testing.md`)
- Red-team review: not required by default for this solo hackathon prototype (`docs/agents/planning.md`). Not invoked. This draft was produced and self-checked in-chat rather than through the `atlas-plan` → `atlas-planner` fork, at the user's explicit request, to avoid routing through the exhausted Atlas `extra_usage` credit pool. There is no separate fresh-context adversarial pass on this draft; treat the "Repository state hazards" and "Technical decisions" sections below as the substitute for that check.

## 1. Intent

Issue #5 bundles three problems surfaced by live play after commit `2130b3f`:

1. A player eliminated by ring-out respawns into the next round and is immediately eliminated again, repeating round after round.
2. No scenario-suite coverage exists for this class of bug (respawn-then-instant-death), or for the previously-fixed "falling offscreen doesn't kill" case, as an ongoing regression guard.
3. The round-end flash shows a plain status string (`RoundManager._set_round_end_text()` → `RoundEndLabel`) instead of a per-player icon + score scoreboard.

The issue explicitly distrusts its own stated hypothesis for (1) ("does not reset `linear_velocity`/`angular_velocity`") and asks for root-cause investigation rather than a pattern-matched fix. That investigation is largely complete as of this draft (see §3.1) and changes the shape of the fix.

## 2. Affected areas, interfaces, domain concepts

| Area | Change |
|---|---|
| `scripts/Player.gd` | `start_round()` gains a spawn-safety mechanism (see §3.2); no change to `_go_inert()`'s deferred-freeze structure, which investigation found is not the bug |
| `scripts/RoundManager.gd` | `_set_round_end_text()` and the single `RoundEndLabel` text path are replaced by a per-player scoreboard update; state machine (`WAITING`/`ROUND_ACTIVE`/`ROUND_END`) is unchanged |
| `scenes/Main.tscn` | `RoundEndLabel` node is replaced with a small scoreboard subtree (one icon + score readout per player slot) |
| `tools/scenario_runner.gd` | New scenario(s) covering ring-out → respawn → survive, chained onto the existing fall-and-ring-out path so it also stands as regression coverage for the previously-fixed offscreen-kill-zone bug |
| `controller/index.html` | Read-only reference for this work: `SLOT_COLORS` (`#2666ff`, `#ff8c1a`) must stay the color source of truth the scoreboard icons are checked against, per the existing `identity_colours_match_controller_page` scenario and the ADR-0005 sync comment in `scenes/Main.tscn` |

No new wire formats or public interfaces. `Player.gd`'s public surface (`start_round`, `eliminate`, `leave_round`, `alive`, `deaths`) is unchanged in shape; only internal behavior of `start_round()` changes.

## 3. Technical decisions made in this plan (confirm at approval)

### 3.1 Root cause of problem #1 — investigated, hypothesis in the issue is disproven

Read in full: `scripts/Player.gd` (`start_round`, `_go_inert`, `eliminate`, `leave_round`, `_build_rig`, `teleport_to`), `scripts/KillZone.gd`, `scripts/RoundManager.gd`, `scenes/Main.tscn`, `scenes/Arena.tscn`.

- The issue's hypothesis is that `start_round()` doesn't reset velocity. It already does: `scripts/Player.gd:404` sets `linear_velocity = Vector2.ZERO` synchronously, and `_go_inert()` (`scripts/Player.gd:385`) also zeroes it synchronously on the way out. The player's own rotation is separately hard-locked per ADR-0006, so a stale `angular_velocity` on the body is not in play either.
- The weapon rig is not a carrier of stale velocity across a respawn: `_go_inert()` calls `_clear_rig()` before freezing, and `_build_rig()` (deferred from `start_round()`) constructs brand-new `_haft`/`_head` `RigidBody2D` nodes at the player's already-updated `global_position`. There is no reused rig body with old velocity.
- `_go_inert()`'s `set_deferred("freeze", true)` (needed because `eliminate()` can run mid-physics-step from `KillZone`'s `body_entered`, and a synchronous freeze change is refused there) resolves within the same frame it's queued — idle-deferred calls run before the next frame starts. `RoundManager`'s `round_end_pause_sec = 2.0` gap between elimination and the next `start_round()` is far larger than that, so a stale deferred freeze from the previous elimination racing the next round's spawn is not the mechanism either.
- `KillZone.gd` is unchanged from its last-known simple form: `body_entered` → `eliminate()` if the body is in the `"players"` group. Only the `Player` root is in that group, not its weapon rig, so the rig's position during rebuild cannot itself re-trigger the kill zone.
- Geometrically, `KillZone`'s shape sits at `y≈460–500` (`scenes/Arena.tscn`); both spawn points are at `y=0` (`scenes/Main.tscn`). `start_round()` sets `collision_layer`/`collision_mask` back to `LAYER_WORLD` and `global_position = spawn_pos` synchronously and in the same call, before any physics step runs, so a respawned player cannot be evaluated by the physics server at its old (possibly still-falling, possibly kill-zone-adjacent) position with live collision.

None of the code paths that materially move or collide the player carry a plausible stale-state bug into the respawn. What the code review does surface, and static reading cannot fully rule in or out, is: **there is no spawn separation or spawn grace period**. Spawn points are only 200px apart (`Vector2(-100,0)` / `Vector2(100,0)`), weapon reach and knockback are easily in that range, weapons carry over round-to-round with no reset (ADR-0005, `start_round()`'s own comment), and both players' `start_round()` calls land in the same `_try_start_round()` loop iteration. A player who respawns while the opponent's weapon (or a lingering hazard interaction near the edge, since these are the same players who were just fighting near a ring-out) is already near the new spawn point can plausibly be hit or knocked back toward the kill zone within the first few ticks of the new round — which would look exactly like "respawn instantly dies again" in live play, repeating round after round because nothing about the setup changes between rounds.

**Decision:** treat "no spawn grace/separation" as the leading, evidence-consistent root cause, but do not commit to a fix design against it blind. Step 1 of implementation (§5) is a scenario that reproduces the reported sequence (ring-out → next round → respawn) under the scenario runner's controlled conditions and inspects per-tick state around the respawn boundary. If it reproduces a re-elimination, the failure trace (which tick, what velocity/position/contact state) confirms or replaces this hypothesis before any fix is written. This keeps faith with the issue's explicit "needs root-cause investigation, not just this hypothesis pattern-matched" instruction, and avoids the plan prescribing a fix for a bug whose mechanism isn't yet directly observed, only inferred from elimination of the alternatives.

### 3.2 Fix shape is conditional on the repro

Two candidate fixes, not both:

- **If the repro confirms a knockback/weapon-contact re-kill:** add a brief post-spawn grace window (e.g. a per-player `_spawn_grace_ticks` counter set in `start_round()` that suppresses `take_damage()`/`eliminate()` via ring-out for a small fixed number of physics ticks, or increases spawn separation). Grace-via-damage-suppression is preferred over invulnerability visuals or moving spawn points, since it's the smallest change that directly addresses "respawn shouldn't die within the first instants of a round" without touching combat feel once the round is underway.
- **If the repro finds a different mechanism** (e.g. something in `_build_rig()`'s deferred timing not yet exercised by existing scenarios, since no existing scenario currently drives a real `eliminate()` → `start_round()` cycle on the same player instance), the plan's implementation step 1 output becomes the actual root-cause note, and step 2 (the fix) targets that mechanism instead.

This is a plan-time decision to defer the exact fix to a confirmed repro rather than a specific code change, because the issue itself flags the risk of shipping a pattern-matched fix for an unconfirmed cause. `/atlas-implement` should treat "reproduce, then fix what the repro shows" as the ordered contract, not "implement the grace-window fix" as a foregone conclusion.

### 3.3 Scoreboard implementation

- Replace `RoundEndLabel` in `scenes/Main.tscn` with a small `HBoxContainer` (or equivalent) holding one entry per player slot: a `ColorRect` or simple generated-shape icon tinted with that player's `identity_color`, plus a `Label` for their score. No new art assets — CONTEXT.md and the issue both call for reusing `identity_color`/generated shapes over new art.
- `RoundManager.gd` keeps its existing `_scores` array and `_update_score_label()`-style bookkeeping; `_set_round_end_text()` is replaced with a method that shows the scoreboard container and refreshes each entry's color and score text, called from the same call sites (`_check_round_end()`'s winner/no-survivors branches) so the `ROUND_END` state machine and `round_end_pause_sec` timing are untouched.
- Icon color source is each `Player`'s exported `identity_color`, read once at `_ready()` alongside the existing player references — consistent with the existing `identity_colours_match_controller_page` scenario's assumption that `Player.identity_color` and `controller/index.html`'s `SLOT_COLORS` are the same two values.

### 3.4 Regression test placement

Add the new scenario(s) to `tools/scenario_runner.gd` following its existing conventions (`_scenario_<name>() -> Array[String]`, `_new_stage()`, `_spawn_player()`, `_await_ticks()`, `_teardown()`), registered in `SCENARIO_NAMES` and `_run_scenario()`. Build it as a direct extension of the existing `_scenario_ringout_kills_at_full_health` fall path (same `RINGOUT_START`/`RINGOUT_TICKS` constants) rather than a parallel implementation: falling and ring-out-dying is exactly the previously-fixed offscreen-kill-zone case the issue also wants guarded going forward, so chaining "fall, die, `start_round()` at a safe spawn, assert still alive after N ticks" onto it gives both guarantees from one scenario with minimal new code, matching the suite's own reuse-first style.

## 4. Repository state hazards (resolve before `/atlas-implement`)

- `test-results/damage-display/*.png.import` are present as untracked files in the working tree (visible in `git status`) — leftover Godot import artifacts from a prior manual test run, not part of this work package. They should be left alone or cleaned up separately; this plan's own evidence goes under a fresh `test-results/` subpath per work package per `docs/agents/testing.md`, not into that existing directory.
- No other uncommitted changes, no open branches beyond `main` as of the planned-against SHA.
- Issue #5 currently has no labels and no comments; nothing blocks it from planning under `docs/agents/issue-tracker.md`'s readiness rule.

## 5. Ordered implementation steps

1. **Reproduce problem #1 under the scenario runner.** Add a scenario (or a throwaway harness reusable as the permanent one) that: spawns a player at `RINGOUT_START`, lets it fall and ring-out (as `_scenario_ringout_kills_at_full_health` does), then calls `start_round()` at a normal spawn point (mirroring `RoundManager._try_start_round()`'s call), then steps a reasonable number of ticks and records `alive`/`deaths`/position/velocity every tick. Run it and read the trace.
   - Checkpoint: `godot --headless --quit` stays clean; the new scenario runs (pass or fail) without engine errors.
2. **Confirm or revise the root-cause hypothesis** from step 1's trace against §3.1/§3.2. Update this plan's fix-shape section in place if the observed mechanism differs from the leading hypothesis, before writing the fix.
3. **Implement the fix** the confirmed mechanism calls for (§3.2), in `scripts/Player.gd` and/or `scripts/RoundManager.gd`.
   - Checkpoint: `godot --headless --quit` stays clean.
4. **Turn the reproduction into a permanent scenario** (`SCENARIO_NAMES` entry + `_scenario_<name>()`), asserting the respawned player is alive and has not accrued a second death within the chosen tick window. Confirm it fails against the pre-fix code (e.g. by temporarily reverting the fix locally) and passes with it, then leave it in the fixed state.
   - Checkpoint: full scenario suite (`--all`) passes, 0 failed.
5. **Replace the round-end text with the scoreboard** (§3.3) in `scenes/Main.tscn` and `scripts/RoundManager.gd`.
   - Checkpoint: `godot --headless --quit` stays clean; full scenario suite still passes (existing scenarios don't touch `RoundEndLabel` directly, so no scenario changes expected here, but confirm no regressions).
6. **Local live-play verification** (human gate — see §7): play at least two full rounds including at least one ring-out elimination and respawn, and confirm the scoreboard displays correctly at round end. This repo's own precedent (commit `2130b3f`'s follow-on bugs) is that the scenario suite alone did not catch either of problems #1 or #3 — live play is required evidence, not optional polish.
7. **Commit evidence** under `test-results/issue-5/` (boot-check log, scenario suite log, a note or screenshot from live-play verification) and open a PR per the repo's standard flow.

## 6. Scope

**In scope:**
- `scripts/Player.gd` (respawn-safety fix, exact mechanism pending step 1/2)
- `scripts/RoundManager.gd` (scoreboard display, round-end call sites)
- `scenes/Main.tscn` (scoreboard nodes replacing `RoundEndLabel`)
- `tools/scenario_runner.gd` (new regression scenario)
- `test-results/issue-5/` (new evidence directory)

**Explicitly excluded:**
- `controller/index.html` — read for `SLOT_COLORS` reference only, not modified
- Weapon-carry-over behavior (ADR-0005 says only the round winner should keep their weapon; current code appears to carry over for everyone, which is a separate conformance gap noticed during investigation, not part of issue #5's three problems)
- Any new art assets, invulnerability visuals, or spawn-point relocation beyond what §3.2's confirmed fix requires
- `KillZone.gd` — read and confirmed unchanged/not implicated; no edit expected

## 7. Verification map

| # | Criterion | Surface / real dependency | Command or action | Expected | Evidence path | Earliest checkpoint | Human gate |
|---|---|---|---|---|---|---|---|
| 1 | Boot check stays clean throughout | Local, Godot headless | `godot --headless --quit` | Exit 0, no errors | `test-results/issue-5/boot-check.log` | After each implementation step | No |
| 2 | Ring-out → respawn → survive is reproduced, then fixed | Local, scenario runner | `godot --headless --path . -s tools/scenario_runner.gd -- --scenario=<new_name>` | FAIL before fix, PASS after | `test-results/issue-5/scenario-respawn.log` (both runs) | Step 4 | No |
| 3 | No regression in existing scenarios | Local, scenario runner | `godot --headless --path . -s tools/scenario_runner.gd -- --all` | `N passed, 0 failed` | `test-results/issue-5/scenario-all.log` | Step 5 | No |
| 4 | Scoreboard shows per-player icon + score, not text, at round end | Local, live play | Play to a round end on the running game | Icon (identity-colored) + score number per player visible; no plain sentence | `test-results/issue-5/live-play-notes.md` (+ screenshot if convenient) | Step 6 | **Yes** |
| 5 | Respawn no longer instantly re-dies in real play | Local, live play | Play through at least one ring-out and its next round | Respawned player survives past the immediate respawn moment | `test-results/issue-5/live-play-notes.md` | Step 6 | **Yes** |

**Real-dependency coverage of integration seams:** the scenario suite already drives players through the real public interface (`set_input_vector`/`bind_controller`) against the real `Arena.tscn`/`Player.tscn` scenes, not mocks; this plan's new scenario does the same, calling the real `start_round()`/`eliminate()` rather than simulating them. `RoundManager` itself is not instantiated by the scenario runner (it drives `Player` directly, matching existing suite convention), so `RoundManager`'s own call sequencing is only exercised by live play (rows 4–5) — this is why both scoreboard and respawn survival criteria carry a human gate, matching this repo's `testing.md` guidance and the issue's own emphasis that live play surfaced both bugs in the first place.

**Fixtures/Provisioning/Cleanup:** none beyond the scenario runner's existing per-scenario `_new_stage()`/`_teardown()` pattern (each scenario builds and frees its own stage). No external services, no persistent fixtures.

**Anti-churn:** no existing passing scenario's assertions change; the new scenario is additive, and the scoreboard change touches only `RoundEndLabel`'s replacement and `_set_round_end_text()`'s call sites, not `RoundManager`'s state machine or scoring logic.

## 8. Candidate evidence gathered during planning

| Id | What it proves | Command | Result | Invalidators |
|---|---|---|---|---|
| E1 | Existing scenario suite is currently green | (cached run, pre-existing) `godot --headless --path . -s tools/scenario_runner.gd -- --all` | `21 passed, 0 failed, 21 total` | Any edit to `Player.gd`/`RoundManager.gd`/`Arena.tscn` since this run |
| E2 | `start_round()` already zeroes `linear_velocity` synchronously | `Read scripts/Player.gd` | Confirmed at line 404 | File edited |
| E3 | `KillZone.gd` is unchanged, simple `body_entered`→`eliminate()` gate | `Read scripts/KillZone.gd` | Confirmed, 17 lines, matches prior description | File edited |
| E4 | Spawn points sit far from the kill zone geometrically | `Read scenes/Main.tscn`, `scenes/Arena.tscn` | Spawn `y=0`; kill zone `y≈460–500` | Scene files edited |
| E5 | `identity_color`/`SLOT_COLORS` are the intended scoreboard color source | `Read scenes/Main.tscn` (ADR-0005 sync comment), `grep SLOT_COLORS controller/index.html` | `#2666ff`/`#ff8c1a` match `Player1`/`Player2`'s `identity_color` | Either file edited without the other |

All evidence above is from static reading, not execution against this plan's own changes (none exist yet); E1 is the most recent full suite run available and predates this plan.

## 9. Tracker and repository mutations (preview — none executed yet)

If approved, this plan would be persisted and previewed to the tracker as:

```bash
# Persist the plan (already written to disk at this path; no mutation needed beyond the file itself)
git add docs/plans/issue-5-respawn-instant-death-and-scoreboard.md

# Comment on the issue linking the plan (exact text to be confirmed with the user before posting)
gh issue comment 5 --repo tkneeland/pickfight --body "Technical plan drafted: docs/plans/issue-5-respawn-instant-death-and-scoreboard.md"

# Optional: label to reflect planning state, if the user wants tracker state to mirror this draft
gh issue edit 5 --repo tkneeland/pickfight --add-label "atlas:planning"
```

None of these have been executed. Per `docs/agents/planning.md` ("drafts before approval: true") and `docs/agents/issue-tracker.md`, nothing here is posted or labeled until the user confirms.

## 10. Next invocation

Once the user confirms:
- The root-cause approach in §3.1/§3.2 (repro-first, fix-what-the-repro-shows, rather than a prescribed fix), and
- The scoreboard approach in §3.3, and
- Whether to post the plan/comment/label per §9,

implementation proceeds with `/atlas-implement 5` (or, per the user's standing "keep it in chat" instruction for this session, continuing implementation directly in this chat without a forked Atlas subagent, at the user's preference).
