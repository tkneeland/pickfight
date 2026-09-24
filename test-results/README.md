# Proof of work -- issue #16, one-sided axe that flips with aim

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. #38's evidence is in
history at `92b485a:test-results/issue-38/`.

Branch `feat/issue-16-axe-flip`, macOS, local Godot 4.6.2.

| Criterion (issue #16) | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| US1: the axe has one bit, as drawn (16 circles, forward extent 11.00 px unchanged) | `weapon_head_circles_within_art`, `axe_head_mirrors_with_aim` | `issue-16/scenario-suite.txt` | PASS |
| US2/3/5: the bit leads on both sides, and the circles match the drawn art mirrored and unmirrored | `axe_head_mirrors_with_aim` | `issue-16/scenario-suite.txt` | PASS |
| US4: no flicker near vertical (a ±4° wobble gives 0 flips; 25° past vertical flips within 2 ticks) | `axe_head_holds_side_near_vertical` | `issue-16/scenario-suite.txt` | PASS |
| US6: symmetric heads are unaffected | `symmetric_head_ignores_aim_side` | `issue-16/scenario-suite.txt` | PASS |
| The axe's stats stand: a full-speed strike deals 54.3 of 55 | `weapon_damage_matches_roster` (victim now levelled with the leading circle) | `issue-16/scenario-suite.txt` | PASS |
| Nothing else regressed | full suite: 59 of 60 | `issue-16/scenario-suite.txt` | FAIL: axe graze in `roster_heads_do_not_tunnel_head`, #38 |
| Boots on a fresh clone | `git clone` of the branch, `godot --headless --path <clone> --quit`, grep for `SCRIPT ERROR` / `Failed to load script` | `issue-16/boot-check.txt` | PASS |
