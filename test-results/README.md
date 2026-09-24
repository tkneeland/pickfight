# Proof of work -- issue #19, four more stages

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. Earlier packages'
artifacts stay in git history -- the weapon-head render from #13, for
instance, is `git show 9342878:test-results/issue-13/weapon-heads.png`.

Built on `feat/issue-19-part-stages` off `main` at `9342878` (tkneeland), then
handed off to agage-JG, who merged `main` @ `0467425` in and captured the final
evidence at `8b88f7a` on Windows, local headless Godot 4.6.2.

| Criterion | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| rotation-is-11 | `scenes/Main.tscn` `stage_scenes` and `STAGE_PATHS` both list the same 11 stages in the same interleaved order | `issue-19/rotation.txt` | PASS |
| sweep-spawns-safe | `stage_spawns_are_safe` over all 11 | `issue-19/scenario-suite.txt` | PASS |
| sweep-ringout-all | `every_stage_can_ring_out` over all 11 | `issue-19/scenario-suite.txt` | PASS |
| erosion-still-standable | `erosion_island_survives_full_erosion` | `issue-19/scenario-suite.txt` | PASS |
| suite-green | `--all`, 39/39 | `issue-19/scenario-suite.txt` | PASS (see the note below) |
| boot-check-fresh-clone | `godot --headless --path . --quit` with no `.godot` present | `issue-19/boot-check.txt` | PASS |

## The four stages

| Stage | Part it is built on | The idea |
| --- | --- | --- |
| Ferry | `MovingPlatform` | Two pads, 600 px of water, one 160 px barge crossing on a 4 s leg. Whoever is on the dock when it arrives gets to cross. |
| Erosion | `CrumblingLedge` | A wide floor of four crumbling ledges around one small permanent island. Standing still is the mistake. |
| Furnace | `Hazard` | A narrow floor between two full-height hazard columns. Knockback kills long before the kill zone does. |
| Cascade | `MovingPlatform` | A high start and a low floor bridged by three staggered ping-pong platforms. Height is something you ride down and have to re-earn. |

Rotation order: Flatlands, Pillars, **Ferry**, Highrise, **Erosion**, Islands,
**Furnace**, Gauntlet, **Cascade**, Slant, Bowl. No two parts-driven stages
run back to back.

## Note on `roster_heads_do_not_tunnel_head`

This scenario is not a #19 regression, and it is not reliably green anywhere.
It is tracked as #27.

- Windows, this branch: passed in all three `--all` runs (two before the merge
  from `main`, one at `8b88f7a`).
- Windows, untouched `main` @ `0467425`: **failed** in `--all`, with one sword
  charge at 1800 px/s crossing clean through the other head
  (`issue-19/main-baseline.txt`).
- macOS (tkneeland), this branch: failed in every `--all` run and passed every
  standalone run, with sword 1/12 and axe 2/12.

So whether it passes depends on the machine and on which scenarios ran first
in the same process. #19 touches no head physics, only stage scenes,
`Main.tscn` and `STAGE_PATHS`. The earlier theory in this file, load from
concurrent workers, was disproved: the macOS failures reproduce with nothing
else running.
