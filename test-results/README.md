# Test results

Evidence for the latest work package only: issue #116 (landing dust, head motion trails, clash sparks).

- `issue-116/full-suite.txt`: full scenario suite on `feat/issue-116-juice` rebased on main 3e700e5: 143/146. The 3 failures (`weapon_damage_matches_roster`, `roster_heads_do_not_tunnel_thin_platform`, `axe_swing_deals_damage`, all axe) are the known pre-existing reds on main. The three new scenarios (`juice_sparks_on_clash_capped`, `juice_dust_on_hard_landing_only`, `juice_trail_capped_and_frees`) pass.
- `issue-116/focused-on-a0e32ba.txt`: after main moved to a0e32ba (#130 clipping), the branch was rebased again and the three new scenarios plus eight related ones (sound hooks, hitmarkers, head clash and clipping, backdrops, spawn protection) re-run: 11/11. The full suite was not re-run on a0e32ba, at the integrator's request.

Previous package: issue #109 (head clipping), `issue-109/`. Read it from git history (`git show ada044f`).
