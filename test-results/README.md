# Proof of work: issue #77, the boomstick "head tunnel"

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. #75's evidence is in
history at `5f163a0:test-results/issue-75/`.

Branch `fix/issue-77-boomstick-head-tunnel`, macOS, local Godot 4.6.2,
rebased on `origin/main` at `a3c8fed`.

## What #77 turned out to be

It was a bug in how the test measures, not a physics tunnel. On the failing
tick of `roster_heads_do_not_tunnel_head_reversed`, the attacker's boomstick
head (mass 0.1) had just been stopped on the blocker's body, and its own body,
held at 1800 px/s by the charge, ran on past it. The anchor ended up 13 px
behind its body while the haft still pointed forward (real facing 0.44 rad).
`_head_circles_world()` rebuilt the facing from the body to the anchor and got
2.82 rad. That turned the barrel round onto the other head and read -4.8 px of
overlap. On the physics' own circles the heads were 28-30 px apart before the
step and never closer than 19.9 px through it, so `WeaponHead`'s pair sweep
was right to do nothing. The fix makes `_head_circles_world()` return
`Player.weapon_head_circles_world()`, the circles where the physics has them.
`WeaponHead.gd` is unchanged.

| Criterion | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| The #77 failure reproduces on unchanged main | suite prefix up to and including `roster_heads_do_not_tunnel_head_reversed` | `issue-77/red-main-suite-prefix.txt` (main `a9f0887`; identical numbers to the #69/#70 runs) | FAIL on main, as reported |
| A deterministic standalone reproduction goes red before the fix | `charge_measures_heads_where_physics_has_them`: the exact captured pose, no dependence on history | `issue-77/red-new-scenario.txt` (-4.80 px measured vs 19.95 px real) | FAIL before fix |
| ...and green after | same scenario | `issue-77/green-new-scenario.txt` (19.95 px both ways) | PASS |
| Full suite, including every scenario using `_head_circles_world` | `--all` | `issue-77/scenario-suite.txt`: 127 passed, 1 failed. The failure is `axe_head_holds_side_near_vertical`, the known #71 order leak, with the same two assertions as on main. Every head-tunnel scenario passes, including `roster_heads_do_not_tunnel_head_reversed` in full suite order | PASS (except #71) |
| The tunnel checks still catch a real breach | `d582dce` (the #38 fix) reverted in a scratch clone of this branch | `issue-77/revert-38-world-stopped.txt`: `world_stopped_head_blocks_arriving_head` FAILS. `issue-77/revert-38-head-tunnel-scenarios.txt`: `heads_do_not_tunnel_head` FAILS. The two roster sweeps pass in that isolated history, as the #38 breach always depended on suite history (#47) | PASS (red when the physics is broken) |
| Boots on a fresh clone | `godot --headless --path <fresh clone> --quit`, grep `SCRIPT ERROR` / `Failed to load script` | `issue-77/boot-check.txt` (no matches) | PASS |

`red-main-suite-prefix.txt` was run as
`godot --headless --path . -s tools/scenario_runner.gd -- --scenarios=<SCENARIO_NAMES up to and including roster_heads_do_not_tunnel_head_reversed>`.
