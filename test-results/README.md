# Proof of work: issue #51, the Gauntlet rebuilt from scratch

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. The evidence from
#55, #47 and #61 is in history on `main` before this branch.

Branch `fix/issue-51-gauntlet-rebuild`, Windows 11, local Godot 4.6.2.
Only `scenes/stages/Gauntlet.tscn` changed.

| Change (issue #51) | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| The stage can still be rung out of | `every_stage_can_ring_out` (Gauntlet: spawn 0 shoved left, out after 35 ticks) | `issue-51/scenario-suite.txt` | PASS |
| Every pickup spot is clear of geometry, the hazard and the kill zone | `stage_pickup_spawns_are_safe` | `issue-51/scenario-suite.txt` | PASS |
| The ceiling hazard never rises with the floor | `hazard_never_rises` | `issue-51/scenario-suite.txt` | PASS |
| Four spawns on solid ground inside the fixed camera, settling together | `stage_spawns_are_safe`, `stage_four_spawns_settle_together` | `issue-51/scenario-suite.txt` | PASS |
| What the stage looks like under the game's fixed camera, with a player on each spawn | windowed render of the stage (throwaway script, not committed) | `issue-51/gauntlet.png` | PASS |
| Every platform is easy to get on and off, and nothing traps anyone when the lava rises | reach arithmetic in the scene's header comment, plus a throwaway headless probe (below) | - | NEEDS PLAYTEST |
| Nothing else regressed | full suite: 97 of 98. The one failure, `axe_head_holds_side_near_vertical`, fails the same way on untouched `origin/main` (8f32c86) on this machine and passes run alone; it uses no stage | `issue-51/scenario-suite.txt`, `issue-51/pre-existing-axe-failure.txt` | PASS (one pre-existing failure) |
| Boots, and boots on a fresh clone | `godot --headless --quit`; `git clone`, `godot --headless --path <clone> --quit`, grep for `SCRIPT ERROR` / `Failed to load script` | `issue-51/boot-check.txt` | PASS |

`boot-check.txt` shows a `qrencode` error and warning. That is this Windows
machine having no `qrencode` on PATH, which only means no join QR code. It
is not a script or scene error.

## The accessibility probe (not committed)

A throwaway headless script dropped one player on each surface and tried a
short, fixed hook-and-pull move: reach over the lip, press the head onto the
top, haul in, push down to roll over. It swept 36 variants (where the head
lands, how fast the pull is, how hard the push is) and counted how many
ended with the player resting on the target. It is a rough proxy for "easy",
not a proof. Pickaxe, as the default weapon:

| Move | Old Gauntlet | New Gauntlet | Highrise ground to first ledge, for comparison |
| --- | --- | --- | --- |
| Bank to middle, across a gap | 0 / 36 | 12 / 36 | - |
| Middle to bank | - | 14 / 36 | - |
| Bank to low ledge | - | 3 / 36 | 3 / 36 |
| Low ledge to high ledge | - | 6 / 36 | - |
| High ledge to ceiling top | - | 10 / 36 | - |

A random-input search over the same moves (240 random three-step inputs per
move) found getting off every ledge, and off the ceiling top, back onto a
bank, with the pickaxe and the sword. On the old layout the same search
found no way across a gap for the pickaxe, sword or dagger in 240 tries,
and one for the staff.
