# Proof of work: issue #52, bounce pad, wind zone, rotating platform

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. Earlier evidence (#47, #61 and
damage-display) is in history at `8f32c86:test-results/`.

Branch `feat/issue-52-bounce-wind-rotate-parts`, Windows 11, local Godot 4.6.2.

| Change (issue #52) | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| Bounce pad launches a landing body well past its drop height, once per landing, and flashes | `bounce_pad_launches_body` | `issue-52/scenario-suite.txt` | PASS |
| A rotated pad launches along its own local up (30 deg pad: 3.8 deg off) | `bounce_pad_rotated_launches_diagonally` | `issue-52/scenario-suite.txt` | PASS |
| Heads: a head planted on a pad is plain ground, no launch, ordinary push-off (~490 px/s) | `bounce_pad_head_plant_is_plain_ground` | `issue-52/scenario-suite.txt` | PASS |
| The pad carries the weapon with the body, so every weapon launches alike (within 20%) | `bounce_pad_launch_same_for_every_weapon` | `issue-52/scenario-suite.txt` | PASS |
| Wind: calm, then a tell that brightens and speeds its streaks, then a gust that pushes, then calm; calm and tell never push | `wind_gust_tell_then_push` | `issue-52/scenario-suite.txt`, `issue-52/wind-phases.png` | PASS |
| `steady` wind pushes every tick with the cue drawn | `wind_steady_pushes_constantly` | `issue-52/scenario-suite.txt`, `issue-52/wind-phases.png` | PASS |
| Heads: wind never pushes a head (aim holds exactly with the head in a gust) | `wind_does_not_push_heads` | `issue-52/scenario-suite.txt` | PASS |
| Rotating platform SPIN turns at the set rate (60.00 deg in 120 ticks at 30 deg/s) | `rotating_platform_spins_at_rate` | `issue-52/scenario-suite.txt` | PASS |
| SEESAW tips toward a body on either end (~15 deg) and returns to level once it leaves | `seesaw_tips_toward_weight_and_levels` | `issue-52/scenario-suite.txt` | PASS |
| Heads: a player standing on its head on a see-saw end tips it | `seesaw_tips_under_planted_head` | `issue-52/scenario-suite.txt` | PASS |
| Heads: no boost swing tunnels a head through a spinning 20 px slab (0 of 48) | `head_does_not_tunnel_rotating_platform` | `issue-52/scenario-suite.txt` | PASS |
| Placeholder visuals read (pad green with chevrons, flash/squash; purple striped slab with a hub; see-saw tilted under a player) | windowed capture | `issue-52/parts-overview.png` | PASS / NEEDS PLAYTEST |
| Nothing else regressed | full suite: 107 of 109; the 2 failures are not #52's (see below) | `issue-52/scenario-suite.txt`, `issue-52/preexisting-failures.txt` | PASS |
| Boots | `godot --headless --path . --quit`; the only error is the missing `qrencode` binary on this machine | `issue-52/boot-check.txt` | PASS |

Tuning for a playtest: pad `launch_speed` 2000 (about 500 px up); wind
`strength` 1800 px/s^2, calm 2.5 s, tell 1.0 s, gust 1.5 s; spin 30 deg/s;
see-saw max tilt 25 deg, settle 0.6 s.

Full-suite failures, neither from #52:

- `four_phones_claim_four_slots`: other suites were running at the same time
  on the shared controller port. It passes when run alone.
- `axe_head_holds_side_near_vertical`: this one depends on order. It fails
  when it runs in the same process after `four_phones_claim_four_slots`, and
  the same happens on untouched origin/main `8f32c86`. It passes alone. The
  first full run failed on this scenario only (108 of 109).
- `roster_heads_do_not_tunnel_head_reversed`, the known pre-existing failure,
  passes on this base.
