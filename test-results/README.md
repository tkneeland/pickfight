# Test results

Evidence for the latest work package only: issue #109 (heads clipping through thin platforms; also closes #103 and #99).

- `issue-109/full-suite.txt`: full scenario suite on `fix/issue-109-clipping` rebased on main b659ff9: 138 passed, 0 failed, 138 total.
- `issue-109/rebased-targeted.txt`: after the final rebase onto main 3e700e5, `weapon_damage_matches_roster`, `roster_heads_do_not_tunnel_thin_platform`, `axe_swing_deals_damage`, `roster_heads_do_not_clip_platform_in_play` and `spawn_protection_blocks_damage_then_expires`: 5/5. All sfx scenarios then `axe_swing_deals_damage`: 15/15.
- `issue-109/main-red.txt`: the new `roster_heads_do_not_clip_platform_in_play` against main b659ff9's head code: boomstick 4, axe 12, sword 1 head crossings (red). 0 on the branch.
- `issue-109/perf.txt`: per-call time of `WeaponHead._integrate_forces` and `guard_turn` from `tools/perf_probe.gd`, main against branch.

Previous package: issue #114 (spawn protection), `issue-114/` at commit 2427683. Read it from git history (`git show 2427683`).
