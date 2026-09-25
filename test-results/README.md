# Test results

Evidence for the latest work package only: issue #117 (stage backgrounds). The previous package was issue #108 (smoothness and physics interpolation), in commit 9c3abc8.

- `issue-117/full-suite.txt`: full scenario suite on `feat/issue-117-backgrounds` rebased on main b659ff9, 135/138. The 3 failures are the axe scenarios (#99: `weapon_damage_matches_roster`, `roster_heads_do_not_tunnel_thin_platform`, `axe_swing_deals_damage`) and fail identically on main.
- `issue-117/main-full-suite.txt`: the same suite on main b659ff9, 134/137, for comparison.
- `issue-117/backgrounds/<Stage>.png`: every stage in the rotation with four players at their spawns, captured windowed (headless does not render), downscaled to 1600 px wide. Shows each backdrop behind the stage and the players, dim enough that geometry and identity colours stay readable.
- `stage_backgrounds_draw_behind_everything`: all 17 stages in Main's rotation have a backdrop with 2-3 layers covering the camera view, brightest colour luminance 0.15-0.27 (limit 0.30), drawn at z -1000 against everything else at z >= 0.
