# 8. Stage authoring format

- Status: Accepted
- Date: 2026-09-23

## Context

CONTEXT.md's design intent calls rapid stage rotation a feature, not
scaffolding: short rounds on varied geometry are what make a swing-based
moveset stay interesting. Issue #8 asks for at least three stages that rotate
every round, each declaring its own spawn points and death boundary. Both the
stage authoring format and the roster of stages were listed under CONTEXT.md's
"Deliberately not decided."

Atlas isn't installed in this environment, so this decision was settled
directly with the operator rather than through `/grill-with-docs`, following
the issue's own recommended starting point.

## Decision

A stage is one `.tscn` scene under `scenes/stages/`. Its root is a `Node2D`
with `scripts/Stage.gd` attached (preloaded by path — no `class_name`, per
CLAUDE.md). It carries:

- Arena geometry, following `scenes/Arena.tscn`'s existing node shape
  (`StaticBody2D` + `CollisionShape2D` + `Polygon2D` per platform).
- `Marker2D` children named `Spawn0`, `Spawn1`, ... declaring spawn points.
  `Stage.gd` exposes `get_spawn_points() -> Array[Vector2]` by collecting and
  sorting them by name.
- A `KillZone` child (`Area2D` + `CollisionShape2D`, `scripts/KillZone.gd`
  reused unmodified) declaring the death boundary, sized to that stage.

`RoundManager` holds an exported `Array[PackedScene]` of stages and rotates
through them **sequentially**, wrapping around, swapping the active stage
into a container node once per round (right before players are placed).

Spawn count is **2 per stage** (`Spawn0`, `Spawn1`), matching the current
2-player roster (`Main.tscn`'s `player_paths`). Camera framing is unchanged —
new stages are authored to fit the existing fixed `Camera2D`.

`scenes/Arena.tscn` is **not** folded into the stage roster and is not
touched by this change. `tools/scenario_runner.gd`'s existing scenarios
preload it directly and assert against its exact geometry (e.g.
`GROUND_TOP = 300.0`, platform positions); reusing it as a rotating stage
would put that suite at risk for no gameplay benefit. Three new, independent
stage scenes are authored instead.

## Consequences

- Adding a stage is adding one `.tscn` file and one line to `RoundManager`'s
  exported array — no code changes.
- Since #17 there is a second line to add: `STAGE_PATHS` in
  `tools/scenario_runner.gd`, which both sweeping stage scenarios
  (`stage_spawns_are_safe` and `every_stage_can_ring_out`) iterate. That is a
  deliberate coupling and a narrow one — the list names stage scenes, it does
  not assert their geometry — so it does not reopen the Arena-fixture
  decoupling below. A stage left out of it still rotates in play but is never
  swept, which is the failure mode the single shared list exists to make
  obvious.
- `Stage.gd` is duck-typed (no `class_name`), consistent with every other
  cross-scene reference in this codebase, so a fresh clone with no editor-built
  class cache still parses and boots.
- The stage roster and the scenario-runner's physics fixture are fully
  decoupled: changing one cannot break the other.
- Growing past 2 players later means growing every stage's spawn markers too
  (ADR-0007 already names this as a future consequence) — not done here,
  since only 2 players are supported today.
- Rotation is deterministic and easy to assert in a scenario (`stage N+1 mod
  count` every round), at the cost of being fully predictable to players.
  Not a concern at 3 stages; revisit if the roster grows and predictability
  becomes noticeable.

## Alternatives considered

**A single data-driven `Stage` resource (`.tres`) describing spawn points and
kill-zone bounds, with geometry built procedurally or from a shared
tilemap.** More flexible and more data-oriented, but there is no shared
tile/tunable-geometry system yet, and it would be built speculatively ahead
of a second stage type actually needing it. `.tscn` per stage matches how
`Arena.tscn` is already authored and needs no new tooling.

**Folding `scenes/Arena.tscn` itself into `scenes/stages/` as the first
stage.** Rejected — see Decision and Context above; it would couple the
gameplay stage roster to the scenario suite's physics fixture.

**Shuffled rotation without immediate repeats.** Viable, and worth revisiting
once the roster grows past a handful of stages where sequential order becomes
noticeably predictable. Adds nothing observable yet and complicates the one
scenario that asserts rotation order.
