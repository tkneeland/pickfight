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

## Issue #47: deterministic #38 regression scenario

Added on `test/issue-47-issue38-repro`. `world_stopped_head_blocks_arriving_head`
builds the #38 state directly: a head stopped by a world contact while the
other head arrives on it.

| Check | Evidence | Verdict |
| --- | --- | --- |
| Red with d582dce reverted (3 standalone runs, and last in `--all`: 86 passed, 1 failed, the new one, after rebase onto main) | `issue-47/red-without-fix.txt` | PASS |
| Green with the fix (3 standalone runs, 3 times among the tunnel scenarios with `--scenarios`) | `issue-47/green-with-fix.txt` | PASS |
| Full suite green with the fix (87 of 87, after rebase onto main) | `issue-47/scenario-suite.txt` | PASS |
| Boots on a fresh clone | `issue-47/boot-check.txt` | PASS |
