# Proof of work -- issue #2, combat foundations

Cleared and recaptured in full at the closeout commit, per the evidence policy
in `docs/agents/testing.md`: this root holds only the latest work package's
evidence. Everything below was produced at parent commit `03ae52ce13cc900401d3a7eafe0a91a71ac92ad8` on
`feat/combat-foundations`, local headless Godot 4.6.2 (the only run surface
this project has).

| Criterion | Proven by | Evidence |
| --- | --- | --- |
| AC-1 aim angle follows the input vector | `aim_angle` | `scenario-suite/output.txt` |
| AC-2 the body does not spin | `body_no_rotation` | `scenario-suite/output.txt` |
| AC-3 reach tracks drag distance | `extension_tracks_drag` | `scenario-suite/output.txt` |
| AC-4 release eases back to rest | `release_eases_to_rest` | `scenario-suite/output.txt` |
| AC-5 the head plants against terrain | `head_plants_terrain` | `scenario-suite/output.txt` |
| AC-6 the head plants against a player | `head_plants_player` | `scenario-suite/output.txt` |
| AC-7 strike damage scales with head speed | `head_strike_damage_scales` | `scenario-suite/output.txt` |
| AC-8 bodies collide without dealing damage | `body_collision_knockback_no_damage` | `scenario-suite/output.txt` |
| AC-9 accumulated damage kills | `damage_kills` | `scenario-suite/output.txt` |
| AC-10 a ring-out kills at full health | `ringout_kills_at_full_health` | `scenario-suite/output.txt` |
| AC-11 heads do not interpenetrate | `heads_do_not_interpenetrate` | `scenario-suite/output.txt` |
| AC-12 the stronger drive wins a clash | `clash_higher_drive_force_wins` | `scenario-suite/output.txt` |
| AC-13 non-finite input is rejected | `non_finite_input_rejected` | `scenario-suite/output.txt` |
| AC-14 the haft collides with nothing | `haft_is_non_colliding` | `scenario-suite/output.txt` |
| AC-15 weapon stats are swappable at runtime | `weapon_stats_are_swappable` | `scenario-suite/output.txt` |
| AC-16 damage reddens the fill, identity persists | `damage_reddens_fill_identity_persists` + screenshots | `scenario-suite/output.txt`, `damage-display/*.png` |
| AC-17 host identity colours match the phone | `identity_colours_match_controller_page` | `scenario-suite/output.txt` |
| HG-1 aim tracks the finger | operator on a real phone | `human-gates/verdict.md` |
| HG-2 no clipping under hard play | operator on a real phone | `human-gates/verdict.md` |
| HG-3 the weapon reads as a weapon | operator on a real phone | `human-gates/verdict.md` |
| HG-4 a hurt player is identifiable | operator on a real phone | `human-gates/verdict.md` |
| DoD-1 the project boots | `godot --headless --path . --quit` | `boot-check/output.txt` |
| DoD-2 the whole suite passes | `--all`, 21/21 | `scenario-suite/output.txt` |
| DoD-3 evidence committed on the branch | this commit | this directory |

All 24: **PASS**.

Two things worth reading rather than counting:

- `boot-check/output.txt` also runs the suite with `.godot/` moved aside,
  simulating a clone that has never been opened in the editor. 21/21 there
  too. That check exists because a `class_name` reference resolves through
  the gitignored global class cache, and `godot --headless --quit` exits 0
  even when scripts fail to parse -- so the boot check alone is a false green.
  See the rule in `CLAUDE.md`.
- `scenario-suite/output.txt` prints a warning for `CapsuleShape2D` during
  `weapon_silhouette_matches_head_shape`. That is the scenario deliberately
  feeding a shape with no hand-drawn silhouette to prove the bounding-box
  fallback fires and says so, rather than drawing something wrong in silence.
