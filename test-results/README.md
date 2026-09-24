# Proof of work -- issue #19, four more stages

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. Earlier packages'
artifacts stay in git history -- the weapon-head render from #13, for
instance, is `git show 9342878:test-results/issue-13/weapon-heads.png`.

Produced on `feat/issue-19-part-stages` off `main` at `9342878`, local
headless Godot 4.6.2.

| Criterion | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| rotation-is-11 | `scenes/Main.tscn` `stage_scenes` and `STAGE_PATHS` both list 11 stages in the same order | `issue-19/rotation.txt` | _pending_ |
| sweep-spawns-safe | `stage_spawns_are_safe` over all 11 | `issue-19/scenario-suite.txt` | _pending_ |
| sweep-ringout-all | `every_stage_can_ring_out` over all 11 | `issue-19/scenario-suite.txt` | _pending_ |
| erosion-still-standable | `erosion_island_survives_full_erosion` | `issue-19/scenario-suite.txt` | _pending_ |
| suite-green | `--all` | `issue-19/scenario-suite.txt` | _pending_ |
| boot-check-fresh-clone | `godot --headless --path . --quit` with no `.godot` present | `issue-19/boot-check.txt` | _pending_ |

## The four stages

| Stage | Part it is built on | The idea |
| --- | --- | --- |
| Ferry | `MovingPlatform` | Two pads, 600 px of water, one 160 px barge crossing on a 4 s leg. Whoever is on the dock when it arrives gets to cross. |
| Erosion | `CrumblingLedge` | A wide floor of four crumbling ledges around one small permanent island. Standing still is the mistake. |
| Furnace | `Hazard` | A narrow floor between two full-height hazard columns. Knockback kills long before the kill zone does. |
| Cascade | _pending_ | _pending_ |

## Note on the concurrent-load flake

The D1 worker reported `roster_heads_do_not_tunnel_head` failing in three
consecutive `--all` runs while three sibling worktrees ran the same suite on
the same machine, and passing standalone. It did not reproduce in the
orchestrator's own integrated run. The authoritative `--all` below was taken
with no other worker running.
