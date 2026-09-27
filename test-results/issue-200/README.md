# Issue #200: round flow fixes

Run on branch `fix/issue-200-round-flow` at `2840506`, on top of main `a09e644`.

## Full suite

`full-suite.txt`: every scenario in `SCENARIO_NAMES`, run as 4 parallel shards of
`--scenarios=` under `--fixed-fps 60`, each shard on a fresh clone.

Result: **237 passed, 0 failed, 237 total**. The fresh-clone boot check was clean.

## New scenarios

- `rematch_on_same_seed_deals_same_stages` (item 1): seed 1234 on the shipped
  rotation, at 3 and at 7 players. A fresh launch and three matches in one
  session (the later ones after first matches of different lengths) must deal
  the same 12 stages. Against the branch with the `stage_index = -1` reset
  removed, it fails: each rematch deals `[14, 3, 23, ...]` where the launch
  dealt `[0, 14, 3, 23, ...]`.
- `pickups_skip_and_clear_under_lava` (item 2): one pickup spot above the floor
  kill zone and one below it. None of 40 spot draws lands under the lava, no
  spot is offered once the lava is over both, and a pickup the lava rises over
  is freed on the next `tick()`. With the fix removed, 23 of 40 draws were
  under the lava and 2 submerged pickups stayed live.
- `spawn_places_rotate_each_round` (item 3): four players, 8 rounds on seed 200.
  Every slot starts on at least two different spawns, no two players ever
  share a spawn, and a second run on the same seed gives the same spawns.
- `podium_order_is_strict` (item 4): `podium_before` is never true for a slot
  against itself, or both ways round, and it sorts the winner first and then
  the rest by score.
- `round_flow_drift_trimmed` (item 5): the random-weapons list is the pickaxe
  followed by `PickupWeapons.WEAPON_PATHS`, the banner log keeps its last 32
  entries, a modifier applied by a round manager draws from
  `modifier_rng()`, and a meteor shower over a bare node still gets a
  sensible span.

## Changed scenario

`gap_roster_spawns_in_roster_order` (#163) now accepts slots 0 and 2 on Spawn0
and Spawn1 in either order. The spawn rotation can swap them, but the point of
#163 still holds: the two players start on opposite sides.
