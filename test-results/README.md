# Proof of work: issue #75, sound effects

This root holds only the latest work package's evidence, cleared and
recaptured per the evidence policy in `docs/agents/testing.md`. Earlier
evidence is in git history:

- #52: `cb30530:test-results/`
- #59: `d2fa0a7:test-results/`
- #47, #61 and damage-display: `8f32c86:test-results/`

Branch `feat/issue-75-sound-effects`, rebased on `origin/main` `9ed7319`. Run on macOS with local Godot 4.6.2, headless.

Headless can't hear anything. So the scenarios spy on what was *requested* of
the `Sfx` autoload, through its `start_recording()` / `recorded()` test hook.

| Change (issue #75) | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| A damaging strike, swung or shot, requests the attacker's weapon's hit. A 0-damage contact is silent. The sound is placed at the strike point. | `sfx_strike_sounds_as_attackers_weapon` | `issue-75/scenario-suite.txt` | PASS |
| A head flying into a wall requests `head_terrain`. Two heads meeting request exactly one `clash`. | `sfx_head_meets_terrain_and_head` | `issue-75/scenario-suite.txt` | PASS |
| A 320 px drop requests one `land` at the floor, and none while resting. An elimination requests `eliminated` where the player was. | `sfx_landing_and_elimination` | `issue-75/scenario-suite.txt` | PASS |
| A real boomstick shot requests `fire_boomstick`, then `bullet_impact` on a bar | `sfx_boomstick_shot_and_impact` | `issue-75/scenario-suite.txt` | PASS |
| A real round requests `round_start` and `modifier` once each, then `round_win` | `sfx_round_events` | `issue-75/scenario-suite.txt` | PASS |
| The lava requests `countdown` ×3, then `lava_rise`. A player in the lava requests `lava_sizzle`. | `sfx_lava_countdown_rise_and_sizzle` | `issue-75/scenario-suite.txt` | PASS |
| A join requests `join`. `ControllerServer` declares and emits `player_joined`. | `sfx_join_sounds` | `issue-75/scenario-suite.txt` | PASS |
| Strength scales volume: the curve rises monotonically, spans at least 6 dB, and a 54-damage hit is louder and lower-pitched than a 6-damage one | `sfx_strength_scales_volume` | `issue-75/scenario-suite.txt` | PASS |
| The overlap cap holds: 12 rapid clashes never exceed 3 playing, and the cap is reached | `sfx_overlap_cap_holds` | `issue-75/scenario-suite.txt` | PASS |
| The six weapons have six distinct sound sets and share no file | `sfx_weapon_sound_sets_distinct` | `issue-75/scenario-suite.txt` | PASS |
| Every referenced file exists and loads, every sound the hooks name is in the table, no shipped file is unused, and the total is 587 KB | `sfx_sound_files_exist` | `issue-75/scenario-suite.txt` | PASS |
| The slider sets the Master bus volume, Mute mutes it, and sounds play on the `SFX` bus | `sfx_volume_slider_and_mute` | `issue-75/scenario-suite.txt` | PASS |
| Nothing else regressed | Full suite: 119 of 121 pass. The 2 failures are not #75's (see below). There is no "ObjectDB leaked" warning at exit. | `issue-75/scenario-suite.txt` | PASS |
| A fresh clone (no `.godot/`) boots with no `SCRIPT ERROR` or `Failed to load script`, both before and after `--import` | the CLAUDE.md boot check | `issue-75/fresh-clone-boot.txt`, `issue-75/fresh-clone-boot-after-import.txt` | PASS |
| How it all sounds | a listen test on the host | none | NEEDS PLAYTEST |

Neither failure in the full suite comes from #75:

- **`axe_head_holds_side_near_vertical` (#71)** fails even when run alone,
  both on this branch and on untouched `origin/main` `9ed7319`. See
  `issue-75/rerun-axe_head_holds_side_near_vertical.txt` and
  `issue-75/baseline-main-9ed7319-axe_head_holds_side_near_vertical.txt`.
- **`roster_heads_do_not_tunnel_head_reversed`** is the known intermittent
  failure. It passes when run alone: see
  `issue-75/rerun-roster_heads_do_not_tunnel_head_reversed.txt`. A parallel
  main-baseline run on another branch failed the same two scenarios.
