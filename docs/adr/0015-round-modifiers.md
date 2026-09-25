# 15. Some rounds get a random modifier

- Status: Accepted
- Date: 2026-09-24

## Context

The owner wants more variety in play (issue #50). Stage rotation (ADR-0008,
ADR-0011) already changes the geometry every round. A second axis of variety
is to change the rules of an occasional round: lower gravity, heavier weapons,
bigger heads, faster lava, a slippery floor. The name is shown on screen at
round start so nobody is confused by it.

Two constraints shaped the design. A round must never leak into the next one:
rounds run back to back forever (ADR-0004), and a modifier that is not fully
undone would change every round after it. `scripts/RoundManager.gd` and
`scenes/Main.tscn` are shared hot files, so the hook has to be small and the
scene cannot be edited.

## Decision

- **`scripts/RoundModifiers.gd`** holds the modifiers. Each is a small object
  with `apply(round_manager, players, stage)` and `undo()`. It remembers what
  it changed and restores exactly that. Both calls are idempotent. It is
  preloaded by path, like every other script (CLAUDE.md, #21).
- **At most one modifier per round.** `RoundManager` rolls at round start with
  chance `modifier_chance` (default 0.35) and picks uniformly among the
  modifiers. It uses its own RNG (`modifier_seed`, -1 for random), never the
  stage rotation's, so a roll can never shift a seeded rotation.
- **When it applies and undoes.** `apply()` runs right after the round's
  players are spawned, in the same frame, before `start_round()`'s deferred rig
  build and before the kill zone is armed. `undo()` runs where the round ends,
  beside `_stop_kill_zone_rise()`, once every player has gone inert and its rig
  is freed. So nothing live has to be rebuilt either way. `RoundManager` also
  undoes on `_exit_tree()`.
- **Weapons are modified through the player, never through the resource.**
  `Player.set_weapon_stats_modifier(callable)` makes the rig build from
  `callable.call(weapon_stats)`, a modified copy, for every weapon the player
  holds until it is cleared. `Player.weapon_stats` stays the shared `.tres`.
  So the round's winner carries the real weapon into the next round
  (ADR-0005), and a weapon picked up mid-round (ADR-0009) is modified too.
- **The modifiers:**

  | Id | On screen | What it changes |
  |---|---|---|
  | `low_gravity` | LOW GRAVITY | Each player's `gravity_scale` ×0.5. The rig copies it at build time. |
  | `heavy_weapons` | HEAVY WEAPONS | Weapon `mass` ×1.6, `max_drive_force` ×1.4. Slower to answer, harder in a clash and harder on the body. |
  | `big_heads` | BIG HEADS | Head circle offsets and radii and every art-outline point ×1.5, about the head's anchor. Reach is unchanged. |
  | `fast_lava` | FAST LAVA | `kill_zone_grace_sec` ×0.4 and `kill_zone_rise_sec` ×0.5 (50 s / 80 s become 20 s / 40 s), restored at round end. |
  | `slippery_floor` | SLIPPERY FLOOR | Each player body gets a `PhysicsMaterial` with friction 0.05. |

- **The announcement is built in code.** `RoundManager` adds its own
  `CanvasLayer` (layer 10) with a large outlined `Label` the first time it
  needs it. It shows the modifier's name for `modifier_announce_sec` (3 s),
  then hides it with a child `Timer`. It is also hidden when the round ends.
  `scenes/Main.tscn` is not touched.
- **Determinism seams.** `forced_modifier` (an id) gives every round that
  modifier, whatever the chance. A static `RoundManager.modifier_rolls_enabled`
  switches random rolls off for every `RoundManager`. The game never touches
  it. The scenario runner turns it off at startup, so every scenario written
  before #50 plays exactly as it did. The modifier scenarios force one, or
  switch rolls back on for themselves.

## Consequences

- Big heads keep ADR-0010's guarantee by construction. A circle inside a
  polygon stays inside it when both are scaled by the same factor about the
  same point. `round_modifier_big_heads_applies_and_undoes` checks every
  roster weapon anyway.
- Slippery floor is on the body only. Godot combines two bodies' friction by
  taking the lower value, so a low value on the body works against every
  floor. Heads keep their grip on purpose: a head that slid off everything it
  planted on would take away the only way to move. Linear damping (1.5) still
  stops a body in the air and on the ground, so the effect is a slide of a few
  body-widths, not ice.
- Low gravity sends swings higher. The only death boundary is the floor, so a
  player launched high comes back down; nothing new can ring them out.
- `fast_lava` adjusts the rotation-wide rise exports for one round. A future
  per-stage rise override (ADR-0012 leaves one open) would have to be scaled
  the same way.
- Modifiers do not stack, and a new one is only a new class in
  `RoundModifiers.gd`. It must restore everything it touches in `_undo()` and
  get an off/on/off scenario like the others.
- The chance and the factors are first guesses and need a playtest.

## Alternatives considered

**Duplicate the `WeaponStats` resource and hand it over with
`set_weapon_stats()`.** It needs no change to `Player`, but a pickup collected
mid-round would drop the modifier, and the winner would carry the modified
copy into the next round unless every exit path swapped it back.

**Change global physics (the default space's gravity).** A single undo, but
it reaches everything in the world, including scenario fixtures, and it gives
no route for the weapon modifiers.

**Put the label in `scenes/Main.tscn`.** This fits how the HUD is authored
elsewhere, but the scene is being edited in parallel (#54), and `.tscn` files
merge badly.
