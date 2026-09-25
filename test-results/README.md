# Proof of work: issue #53, falling and breaking stage parts

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. #55's evidence is in
history at `3c192d4:test-results/issue-55/`.

Branch `feat/issue-53-falling-breaking-parts`, Windows 11, local Godot 4.6.2.

| Criterion (issue #53) | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| Falling rock warns (shaking rock + flashing landing marker on the ground) for its configured lead time, deals nothing before it ends, then damages (exactly the configured amount, through `take_damage` + `strike_landed`, so a hitmarker is drawn) and knocks the player aside; lethal only on a player already low; one pooled rock, no node churn | `falling_rock_warns_then_strikes` | `issue-53/scenario-suite.txt`, `issue-53/01-rock-warning-floor-warning.png` | PASS |
| Collapsing floor, `timed`: solid and grey, amber warning while still holding, then collision off, the player falls, and it is still gone well past CrumblingLedge's return time | `collapsing_floor_timed_gives_way_for_good` | `issue-53/scenario-suite.txt`, `issue-53/05-wall-broken-floor-gone.png` | PASS |
| Collapsing floor, `stood_on`: stays solid while empty, warns after the configured standing time, holds through the warning, then gone for good | `collapsing_floor_stood_on_gives_way_for_good` | `issue-53/scenario-suite.txt`, `issue-53/01-rock-warning-floor-warning.png` | PASS |
| Breakable wall: each head hit takes off the damage a player would take for the same hit (checked against `Player._strike_damage`); light pokes leave it standing; hard swings break it in 3 where weak ones had not in 10; cracks and darkens as HP drops; flashes, then no collision, and stays broken | `breakable_wall_breaks_on_weapon_hits` | `issue-53/scenario-suite.txt`, `issue-53/02-wall-cracked-50hp.png`, `03-wall-cracked-20hp.png`, `04-wall-break-flash.png`, `05-wall-broken-floor-gone.png` | PASS |
| Breakable wall ignores bodies: pushed and slammed by a player, it stays at full HP, uncracked and solid | `breakable_wall_ignores_bodies` | `issue-53/scenario-suite.txt` | PASS |
| CrumblingLedge unchanged | `crumbling_ledge_three_phases`, `erosion_island_survives_full_erosion` | `issue-53/scenario-suite.txt` | PASS |
| Phone buzz on a rock hit | Rock emits on the victim's `strike_landed`, which `RoundManager` already turns into a `struck` buzz; not driven by a scenario | - | NEEDS PLAYTEST |
| Boots, and boots on a fresh clone | `godot --headless --quit`; fresh `git clone` of the branch, grep for `SCRIPT ERROR` / `Failed to load script` | `issue-53/boot-check.txt` | PASS |

Screenshots were captured with a throwaway windowed script modelled on
`tools/capture_damage_screenshots.gd` (not committed). The rock and floor
states in them are the real parts running; the wall's worn and flashing
states were set directly on the wall (its HP and wear display) rather than
reached by scripted swings, which the scenario covers.

Full suite after rebasing onto `origin/main` at `8f32c86` (#47, #48, #49, #50,
#55, #61): 102 passed, 1 failed (`issue-53/scenario-suite.txt`). The one failure,
`axe_head_holds_side_near_vertical`, is pre-existing: untouched `origin/main` at
`8f32c86` fails it the same way in a full run, 97 of 98 with the same two
assertions (`issue-53/baseline-main-8f32c86-suite.txt`). Run alone, it passes
on both main and this branch, so it looks order-dependent within the suite. It
is in the other dev's lane, and nothing in this branch touches heads or the axe.
All five #53 scenarios pass.
