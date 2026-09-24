# Technical plan: #6 Only the round winner keeps their weapon

- Work package: GitHub issue [#6](https://github.com/tkneeland/pickfight/issues/6)
  (stable contract; not duplicated here)
- Plan status: **APPROVED** by tkneeland 2026-09-23 (D2 = drop override)
- Planned against: `main` @ `2130b3f`
- #5 merged in #7 (main @ 70c5e0f); implement on post-#5 main
  first (see section 6)
- Run surface: **local only**
- Red-team review: not required by default (`docs/agents/planning.md`); run
  `/atlas-red-team` manually if wanted

## 1. Intent

Make round start follow ADR-0005 and `CONTEXT.md`: *everyone starts a round
holding a pickaxe; the previous round's winner keeps whatever they held.*
Today `Player.start_round()` never touches `weapon_stats`, so every player
keeps their weapon. Players can't see the rule yet because the pickaxe is the
only weapon, so the proof is one headless scenario that uses a test-only
`WeaponStats` built in the runner. No new weapon ships to players.

## 2. Affected areas and interfaces

| Area | Change |
|---|---|
| `scripts/Player.gd` | New `const DEFAULT_WEAPON_STATS = preload("res://resources/pickaxe.tres")`. This is the one place the default weapon is named. `start_round()` gains a trailing `keeps_weapon: bool = false` parameter. When it is false, the player's stats go back to the default before the (already deferred) rig build. The non-deferred half of `set_weapon_stats()` is pulled out into a private `_assign_weapon_stats(stats)`, so a respawn builds the rig once, not twice. The `_ready()` fallback changes from `WeaponStatsType.new()` to `DEFAULT_WEAPON_STATS`. The comment above `start_round()` that says carry-over is automatic gets rewritten. |
| `scripts/RoundManager.gd` | New `var _last_winner_slot: int = -1`. The winner branch of `_check_round_end` sets it to `winner_slot`. The no-survivors branch sets it to `-1`. The `_try_start_round` loop passes `slot == _last_winner_slot` to `start_round()`, then clears the value to `-1` once the round starts (it applies to one round only). In the `ROUND_END` → `WAITING` transition, after `expire_disconnected_claims()`, it is also cleared if that slot is no longer in `claimed_slots()` (D3). |
| `scenes/Player.tscn` | Remove the `weapon_stats = ExtResource("2")` override and its pickaxe `ext_resource` line, so `DEFAULT_WEAPON_STATS` is the only reference to the path (D2) |
| `tools/scenario_runner.gd` | One new scenario, `round_winner_keeps_weapon` (section 4), plus a small stub roster |
| `tools/stub_roster.gd` (new) | Test double for `ControllerServer`'s roster seam. It is `extends Node` with `var slots: Array[int]`, `func claimed_slots() -> Array[int]` and `func expire_disconnected_claims() -> void`. `RoundManager` only ever calls those two methods (duck-typed through `controller_server_path`). It is preloaded by path, never by `class_name`. |
| `test-results/issue-6/` | Committed evidence |

Domain terms are used as `CONTEXT.md` defines them (round, roster, weapon,
player). No terminology changes. "Default weapon" is an implementation name for
CONTEXT.md's "starts a round holding a pickaxe", not a new domain concept.

Exclusions (from the issue): pickups, dropping weapons on death, new weapon
content or art, and anything involving scoring or the scoreboard.

## 3. Technical decisions (confirm at approval)

- **D1: The winner is decided in RoundManager and the default lives in Player.**
  `RoundManager` owns the round lifecycle and already knows who won.
  `Player` owns what it holds. The boolean parameter keeps the reset on
  `start_round()`, which is the single re-entry path (`leave_round()` doc).
  RoundManager therefore never names a weapon resource. `keeps_weapon`
  defaults to `false` because a plain round entry means "starts holding a
  pickaxe", per CONTEXT.md.
- **D2: Drop the `Player.tscn` override.** *Recommended.* If it stayed, the
  pickaxe path would be written in two places. Both resolve to the same
  cached resource, so behaviour is identical either way. Alternative: keep
  the override and accept it as scene data rather than a call site. That
  would be a one-line change, and D2 is the only thing that touches
  `Player.tscn`.
- **D3: A winner claim that expires does not pass the weapon on.** Claims are
  only dropped at the round boundary (ADR-0007), and a new phone can later
  claim the freed slot. Without this guard, the newcomer would inherit the old
  winner's keep-status and weapon. The guard costs one line, and the scenario
  checks it (phase C).
- **Test-only weapon.** It is built in the runner as `WeaponStatsType.new()`
  with the existing `STUB_MIN_REACH`/`STUB_MAX_REACH` (40/60). No `.tres`
  file is committed.

## 4. Ordered steps

0. **Precondition:** #5 merged. `git fetch && git rebase origin/main` (or
   branch fresh from post-#5 `main`). Re-read the seams listed in section 6
   before editing.
1. **Player.gd:** add `DEFAULT_WEAPON_STATS`, extract `_assign_weapon_stats`
   (so `set_weapon_stats` becomes `_assign_weapon_stats` plus the deferred
   `_build_rig`), add `keeps_weapon` to `start_round()`, change the `_ready()`
   fallback, and fix the `start_round()` doc comment. Remove the override from
   `Player.tscn` (D2).
   - Checkpoint: boot-check is clean and the full suite still passes. Existing
     scenarios never call `start_round()` with a non-default weapon at
     2130b3f. If #5's new scenarios do, pass `true` there only when that
     scenario means to keep the weapon.
2. **RoundManager.gd:** add `_last_winner_slot` and wire it in (section 2 row).
3. **Scenario `round_winner_keeps_weapon`** with `tools/stub_roster.gd`.
   Register it in `SCENARIO_NAMES` and `_run_scenario()`.
   - Build `_new_stage()` and two players via `_spawn_player()`. Add a
     `RoundManager` node (script preloaded by path) with `player_paths`
     relative to it, two `spawn_points` in clear air above the ground,
     `controller_server_path` pointing at a stub roster with `slots = [0, 1]`,
     `round_end_pause_sec = 0.0`, and label or scoreboard paths left empty.
     Add it to the stage.
   - Wait a few ticks so round 1 starts. Only then give **both** players the
     test weapon with `set_weapon_stats()`. Doing it earlier would be undone by
     round 1's own reset.
   - **Phase A (winner):** `p2.eliminate()`, then wait for the next round to
     start (poll `p1.alive and p2.alive`, bounded ticks). Assert
     `p1.weapon_stats` is the test instance and `p2.weapon_stats.resource_path
     == "res://resources/pickaxe.tres"`. That literal is written down
     independently, following the runner's own convention. Also assert
     `_reach_of(p2)` at full drag against the pickaxe reach and `_reach_of(p1)`
     against `STUB_MAX_REACH`. This proves the rig was actually rebuilt, not
     just the field changed.
   - **Phase B (no survivors):** `p1` still holds the test weapon. Call
     `p1.eliminate()` and `p2.eliminate()` in the same tick, wait for the next
     round, and assert both hold the pickaxe.
   - **Phase C (expired winner, D3):** give `p1` the test weapon, run a round
     that `p1` wins, and set the stub's `slots = [1]` before the pause expires.
     This simulates the claim dropping, so the next round can't start. Wait a few
     ticks for `ROUND_END` → `WAITING`, then set `slots = [0, 1]` to simulate a
     newcomer taking slot 0. Assert `p1` now
     holds the pickaxe. Both edits happen while `pause = 0`, so do them
     straight after the `eliminate()` call and before yielding. If that timing
     proves flaky, set `round_end_pause_sec` to a few ticks for this phase.
   - `_teardown(stage)`.
4. **Evidence:** clear `test-results/` (policy: it holds only the latest work
   package's evidence), then run section 5's commands and save their output
   under `test-results/issue-6/`.

Declared scope: `scripts/Player.gd`, `scripts/RoundManager.gd`,
`scenes/Player.tscn`, `tools/scenario_runner.gd`, `tools/stub_roster.gd`,
`test-results/issue-6/`. Nothing else.

## 5. Verification map

| # | Criterion (issue Outcome) | Surface / command | Expected | Evidence | Checkpoint | Invalidated by |
|---|---|---|---|---|---|---|
| V1 | Winner keeps `weapon_stats`; other rostered players reset to pickaxe | `godot --headless --path . -s tools/scenario_runner.gd -- --scenario=round_winner_keeps_weapon` (phase A) | pass, exit 0 | `test-results/issue-6/scenario-round_winner_keeps_weapon.txt` | Step 3 | Edits to `start_round`, `_check_round_end`, `_try_start_round`, the scenario |
| V2 | No survivors, so everyone resets | same scenario, phase B | pass | same file | Step 3 | same |
| V3 | Default weapon has one named source of truth | `git grep -nE 'res://resources/pickaxe\.tres"' -- scripts scenes` (code references only; comment mentions do not count) | exactly one hit: `DEFAULT_WEAPON_STATS` in `scripts/Player.gd` | `test-results/issue-6/default-weapon-grep.txt` | Step 1 | Any new reference to the path |
| V4 | Proven with a test-only `WeaponStats`, and no new weapon for players | `git diff --stat origin/main -- resources/` is empty, and the scenario builds `WeaponStatsType.new()` | no `resources/` changes | included in the PR description | Step 3 | Adding a `.tres` |
| V5 | D3 guard | same scenario, phase C | pass | same file as V1 | Step 3 | Changes to the `ROUND_END` transition |
| V6 | No regressions | `godot --headless --path . -s tools/scenario_runner.gd -- --all` | all pass (post-#5 count), exit 0 | `test-results/issue-6/scenario-all.txt` | Steps 1, 2, 3 | Any script or scene edit |
| V7 | Boot check (`testing.md`) | `godot --headless --quit` | no parse or load errors in the output (exit 0 alone is not proof) | `test-results/issue-6/boot-check.txt` | Before PR | Any script or scene edit |
| V8 | Fresh-clone parse (CLAUDE.md `class_name` rule) | `mv .godot .godot.bak && godot --headless --quit; godot --headless --path . -s tools/scenario_runner.gd -- --scenario=round_winner_keeps_weapon; mv .godot.bak .godot` | no "could not find type" or parse errors, and the scenario passes | `test-results/issue-6/fresh-clone.txt` | Before PR | New type references |

- Real dependencies: the real `Player.tscn`, `Arena.tscn` and
  `RoundManager.gd` round loop. Only `ControllerServer` is stubbed, because its
  real form opens LAN sockets and the runner is headless. `RoundManager`
  reaches it only through `claimed_slots()` and
  `expire_disconnected_claims()`, and the stub implements exactly those.
- Human-gated criteria: **none.** The rule is unobservable in live play until
  a second weapon exists (see the issue). A live round is optional smoke and
  is not required evidence.
- Fixtures and cleanup: everything is created inside the scenario stage and
  freed by `_teardown()`. There are no files or accounts.
- Candidate evidence from planning: none was run. The main checkout holds #5's
  uncommitted edits, so no check was executed against `2130b3f`.

## 6. Conflict surface with #5 (rebase notes)

When this plan was written, #5 was in flight on
`fix/issue-5-respawn-scoreboard`. Its final shape may differ, so re-read these
seams after rebasing:

- `Player.start_round()`: #5 adds a respawn fix (the shape was undecided,
  e.g. spawn grace). Put `keeps_weapon` **last**, after any parameter #5 adds,
  and keep the stats reset **before** the deferred `_build_rig` (and before any
  grace or teleport logic #5 adds).
- `Player.set_weapon_stats()` (about line 297 at `2130b3f`): the extraction in
  step 1. Check whether #5 touched it.
- `RoundManager._check_round_end()`: #5 replaces
  `_set_round_end_text(...)` with `_show_scoreboard()` in both the winner and
  no-survivors branches. The `_last_winner_slot` assignments go next to those
  calls, and nothing about the scoreboard changes.
- `RoundManager._try_start_round()` loop: the `start_round(spawn, ...)` call
  gains the `slot == _last_winner_slot` argument.
- The `RoundManager` export `round_end_label_path` becomes `scoreboard_path`.
  The scenario leaves it empty, so the post-#5 `_ready()` and
  `_show_scoreboard()` must tolerate a null scoreboard, as the label code does
  today. If they don't, the scenario must supply a minimal node, which stays
  inside this plan's scope.
- `tools/scenario_runner.gd`: #5 adds scenarios. This is an append-only merge
  in `SCENARIO_NAMES` and `_run_scenario()`.

## 7. Unresolved decisions

- D2 (drop the `Player.tscn` override): recommended yes.
- The exact `start_round` signature depends on #5's merged shape. This is
  mechanical and follows section 6.
