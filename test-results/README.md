# Proof of work: issue #61, weapon heads block bullets

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. #55's evidence is in
history at `7f55b96:test-results/issue-55/`.

Branch `feat/issue-61-heads-block-bullets`, macOS, local Godot 4.6.2.

| Change (issue #61) | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| An opponent's head between the shooter and the victim stops the bullet at the head (x 114, with the sword's anchor at 175 and the body face at 196). The victim takes 0, is not shoved (0.0 px) and no strike is reported. The bullet is freed | `boomstick_head_blocks_bullet` | `issue-61/scenario-suite.txt` | PASS |
| The shooter's own head never blocks. The same bullet across the same head hits the player past it (35) when the holder fired it, and stops at the head when anyone else did | `boomstick_own_head_never_blocks`, `boomstick_bullet_never_hits_shooter` | `issue-61/scenario-suite.txt` | PASS |
| A head thinner than one tick of flight still blocks: the staff's 5.9 px head against 15 px a tick, lined up so that no tick ends touching it | `boomstick_thin_head_blocks_bullet` | `issue-61/scenario-suite.txt` | PASS |
| Owner's addition: the boomstick bullet is 900 px/s with a 5 px radius (was 1800 px/s and 3 px). The 8 px terrain bar is still thinner than a tick and still stops every shot | `boomstick_bullet_stops_on_terrain`, `boomstick_bullet_damages_and_shoves` | `issue-61/scenario-suite.txt` | PASS |
| Nothing else regressed | full suite on df1d322: 89 of 89 | `issue-61/scenario-suite.txt` | PASS |
| Boots on a fresh clone | `git clone`, `godot --headless --path <clone> --quit`, grep for `SCRIPT ERROR` / `Failed to load script` | `issue-61/boot-check.txt` | PASS |

The one `ERROR: Lambda capture ... was freed` line in the suite log comes from
the rising kill zone scenarios, which #61 does not touch. The same line is in
#55's log on main.
