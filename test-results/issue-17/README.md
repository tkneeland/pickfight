# Proof of work -- issue #17, four more stages

Produced on `feat/issue-17-more-stages`, stacked on `feat/issue-13-weapon-roster`,
local headless Godot 4.6.2.

| Criterion | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| V1 The project boots with the seven-stage rotation wired into `Main.tscn` | `godot --headless --path . --quit`, exit 0 | `boot-check.txt` | PASS |
| V2 Every stage in the rotation spawns both players on solid ground and they settle there | `stage_spawns_are_safe`, sweeping all seven via `STAGE_PATHS` | `scenario-suite.txt` | PASS |
| V3 Every stage in the rotation can ring a player out | `every_stage_can_ring_out`, sweeping all seven | `scenario-suite.txt` | PASS |
| V4 The rotation still rotates | `stage_rotates_each_round` | `scenario-suite.txt` | PASS |
| V5 Full suite green, no regressions | `--all`, 32/32 | `scenario-suite.txt` | PASS |
| V6 Fresh clone parses (CLAUDE.md `class_name` rule) | this worktree has never had a `.godot/` global class cache at all -- see the `ls -d .godot` at the foot of the boot check -- so every run above already *is* the fresh-clone condition | `boot-check.txt` | PASS |
| V7 **HUMAN GATE** -- the seven stages read as seven different fights | all seven drawn from their shipped `.tscn` geometry | `stage-sheet.png` | **PENDING the owner's look** |

## A note on V6

The usual check is `mv .godot .godot.bak`, run, restore. That could not be run
here because there was nothing to move: Godot 4.6.2 headless does not build the
global class cache, and this worktree was created fresh and never opened in the
editor. The boot check records `ls -d .godot` returning "No such file or
directory" immediately after a successful run, which is the same guarantee
arrived at from the other direction, and a stronger one -- the suite did not
merely survive the cache being hidden, it never had one.

## What V7 is asking of the owner

`stage-sheet.png` draws all seven stages from their shipped `.tscn` values:
grey is the drawn geometry, green dashed is what actually collides, red dashed
is the kill zone, and each yellow ring is a spawn point inside the 48 px player
box. The question is whether the four new ones (Pillars, Islands, Slant, Bowl)
each read as a *different fight* rather than as a rearrangement of the same
one.

The arguments they are each making:

- **Pillars** -- no floor across the middle at all, so every crossing is a
  committed swing over a fall. Standing on a column top is safe and attacking
  off it is not.
- **Islands** -- four platforms at exactly one height, so the height advantage
  every other stage hands out is simply absent and only spacing is left. The
  most ring-out-prone stage in the rotation and the shortest rounds.
- **Slant** -- the only asymmetric stage. The two slots are deliberately not
  playing the same stage as each other; the asymmetry is meant to be noticed
  and complained about, not balanced away.
- **Bowl** -- walls on both sides and one 120 px drain at the bottom centre, so
  this is the one stage where damage rather than geometry usually decides the
  round. It exists so the rotation is not entirely a ring-out game.

## Two things the work itself found

**The first cut of `every_stage_can_ring_out` was fake.** It dropped a body
from a row of x positions above each stage and required one to reach the kill
zone. All seven passed -- every one of them from x = -760, which is clear of
all the geometry on every stage. It was measuring that the kill zone is wide,
not that the stage has an exit. The shipped version starts at the stage's own
declared spawn points and shoves left and right at 1800 px/s, which is the way
a knockback actually moves someone. Bowl now passes only on a rightward shove,
having slid down its steps into the drain; the other six go out over an edge.

**The first cut of Bowl had three more ways out than its description claimed.**
It was built as four floating step slabs plus two walls, which left 40 px of
open air between each tier and the next. Each half is now a single
`CollisionPolygon2D` staircase, for the same reason Slant's landmass is one
polygon: a shape drawn in one piece cannot develop a gap it was not drawn with.
