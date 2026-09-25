# Proof of work: issue #50, round modifiers

Branch `feat/issue-50-round-modifiers`, macOS, local Godot 4.6.2. The #55
section below is left in place. Other branches are in flight, and clearing it
here would only cause merge conflicts.

| Criterion (issue #50) | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| Low gravity applies (fall speed 384 to 192 px/s) and is undone next round | `round_modifier_low_gravity_applies_and_undoes` | `issue-50/scenario-suite.txt` | PASS |
| Heavy weapons apply (recoil 132 to 184 px/s), the held pickaxe resource is untouched, undone next round | `round_modifier_heavy_weapons_applies_and_undoes` | `issue-50/scenario-suite.txt` | PASS |
| Big heads apply (x1.5 circles and art), every roster head stays inside its art (ADR-0010), undone next round | `round_modifier_big_heads_applies_and_undoes` | `issue-50/scenario-suite.txt` | PASS |
| Fast lava applies (sets off at 0.42 s instead of 1.02 s, climbs 2x as fast) and is undone next round | `round_modifier_fast_lava_applies_and_undoes` | `issue-50/scenario-suite.txt` | PASS |
| Slippery floor applies (slide 36 to 150 px) and is undone next round | `round_modifier_slippery_floor_applies_and_undoes` | `issue-50/scenario-suite.txt` | PASS |
| The name is announced big on screen at round start, hides after its time, and is absent on a round with no modifier | `round_modifier_announced_on_screen`; windowed capture | `issue-50/scenario-suite.txt`, `issue-50/announcement-big-heads.png` | PASS |
| `modifier_chance` 0 disables modifiers (0 of 10 rounds; 10 of 10 at chance 1) | `round_modifier_chance_zero_disables` | `issue-50/scenario-suite.txt` | PASS |
| Nothing else regressed (main before this branch: 78 of 78) | full suite on b87bd0b (rebased onto c05fdd8, #49 axe included): 85 of 85 | `issue-50/scenario-suite.txt` | PASS |
| Boots on a fresh clone | clone, `--quit`, grep for script errors | `issue-50/boot-check.txt` | PASS |
| Chance (0.35) and the strength of each modifier feel right | playtest | - | NEEDS PLAYTEST |

# Proof of work: issue #55, the boomstick

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. #49's evidence is in
history at `8327db6:test-results/issue-49/`.

Branch `feat/issue-55-boomstick`, macOS, local Godot 4.6.2.

| Change (issue #55) | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| Fires automatically every 5 s (first shot 301 ticks after pickup, then every 300); weapons without an interval never fire | `boomstick_fires_on_interval` | `issue-55/scenario-suite.txt` | PASS |
| Bullet deals 35, reported once through `strike_landed`, vanishes on the hit, and shoves the victim (99.5 px) | `boomstick_bullet_damages_and_shoves` | `issue-55/scenario-suite.txt` | PASS |
| Bullet stops on terrain, even an 8 px bar against 30 px of travel per tick; the player behind is untouched | `boomstick_bullet_stops_on_terrain` | `issue-55/scenario-suite.txt` | PASS |
| Recoil is a moderate nudge: 72.4 px in clear air, 1.5 body widths | `boomstick_recoil_is_moderate` | `issue-55/scenario-suite.txt` | PASS / NEEDS PLAYTEST |
| Handles like the sword with mass 0.1; melee damage 8 (the pickaxe does 34) | `boomstick_melee_damage_is_low`, roster tier scenarios | `issue-55/scenario-suite.txt` | PASS |
| Never hits its shooter, fired from inside the body or sent back through it | `boomstick_bullet_never_hits_shooter` | `issue-55/scenario-suite.txt` | PASS |
| Firing and bullets stop on elimination and at round end, and the countdown restarts next round | `boomstick_stops_when_shooter_leaves_play` | `issue-55/scenario-suite.txt` | PASS |
| In the pickup pool; gun art with 27 circles inside it | `boomstick_in_pickup_pool`, `weapon_head_circles_within_art`, pickup scenarios | `issue-55/scenario-suite.txt` | PASS |
| Nothing else regressed | full suite on 6e49903: 86 of 86 | `issue-55/scenario-suite.txt` | PASS |
| Boots on a fresh clone | `git clone`, `godot --headless --path <clone> --quit`, grep for `SCRIPT ERROR` / `Failed to load script` | `issue-55/boot-check.txt` | PASS |

The one `ERROR: Lambda capture ... was freed` line in the suite log comes from
`rising_kill_zone_resets_each_round`, which boomstick does not touch. The same
line is in #49's log on main.
