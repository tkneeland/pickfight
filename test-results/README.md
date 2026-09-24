# Proof of work: issue #45, first-playtest tuning

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. #16's evidence is in
history at `c55e6db:test-results/issue-16/`.

Branch `feat/issue-45-playtest-tuning`, macOS, local Godot 4.6.2.

| Change (issue #45) | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| Weapon stats per the owner's final table (sword, axe, staff, pickaxe, dagger) | `weapon_damage_matches_roster`, the roster tier scenarios (bands re-derived: reach spread 16, damage spread 13, answer reach 70) | `issue-45/scenario-suite.txt` | PASS |
| Dagger wins only against the staff when heads clash (force 5000) | `heavy_weapon_wins_clash`, `clash_higher_drive_force_wins` | `issue-45/scenario-suite.txt` | PASS |
| Heads: sword blade ×2.5, axe ×1.75 (still flips), dagger blade ×1.5, pickaxe ×1.25 tip to tip and no thicker. Every circle is inside the art | `weapon_head_circles_within_art`, `axe_head_mirrors_with_aim`, `axe_head_holds_side_near_vertical` | `issue-45/scenario-suite.txt` | PASS |
| No head tunnels another at the new sizes and speeds | `roster_heads_do_not_tunnel_head` (+ `_reversed`), with a 90-tick charge settle so the slow axe is aimed first | `issue-45/scenario-suite.txt` | PASS |
| Lava: grace 50 s, rise 80 s, more opaque with an edge line, drawn from round start | kill-zone scenarios; ADR-0012 updated | `issue-45/scenario-suite.txt` | PASS |
| Between-rounds scoreboard shows only claimed, connected players | manual playtest (no scenario drives the scoreboard) | - | NEEDS PLAYTEST |
| Gauntlet: ceiling spans only the gaps (±350), underside 210 px up so a staff can cross hanging from it | `every_stage_can_ring_out`, `hazard_never_rises`; crossing feel needs a playtest | `issue-45/scenario-suite.txt` | PASS / NEEDS PLAYTEST |
| Nothing else regressed | full suite on f1a9447: 78 of 78 | `issue-45/scenario-suite.txt` | PASS |
| Boots on a fresh clone | `git clone`, `godot --headless --path <clone> --quit`, grep for `SCRIPT ERROR` / `Failed to load script` | `issue-45/boot-check.txt` | PASS |

Known gap: #47. The #38 head-tunnel regression is no longer caught by any
scenario.
