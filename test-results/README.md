# Proof of work -- issue #36, four-player capacity

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. #22's evidence is in
history at `0aeeaef:test-results/issue-22/`.

Branch `feat/issue-36-four-players`, macOS, local Godot 4.6.2.

| Criterion (issue #36) | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
<<<<<<< HEAD
| The floor kill zone holds still through the grace period | `kill_zone_holds_during_grace` | `issue-22/scenario-suite.txt` | PASS |
| Then rises steadily at the derived per-stage rate | `kill_zone_rises_after_grace` | `issue-22/scenario-suite.txt` | PASS |
| A holdout on the highest spawn is eventually eliminated (Flatlands and Cascade, short test timings) | `rising_kill_zone_eliminates_holdout` | `issue-22/scenario-suite.txt` | PASS |
| Hazard parts never rise (Furnace and Gauntlet) | `hazard_never_rises` | `issue-22/scenario-suite.txt` | PASS |
| Every round starts fresh | `rising_kill_zone_resets_each_round` | `issue-22/scenario-suite.txt` | PASS |
| Ring-out still means "before the mechanic": the rise never starts outside a round | `every_stage_can_ring_out` unchanged | `issue-22/scenario-suite.txt` | PASS |
| Nothing else regressed | full suite, 64 of 65 after the rebase onto #20 | `issue-22/scenario-suite.txt` | PASS, except the one pre-existing macOS failure `roster_heads_do_not_tunnel_head_reversed`, which also fails on clean main (#38) |
| Boots on a fresh clone | `git clone` of the branch, `godot --headless --path <clone> --quit`, grep for `SCRIPT ERROR` / `Failed to load script` | `issue-22/boot-check.txt` | PASS |

The visible surface and its pulsing warning have no screenshot yet. A
windowed playtest is the check for those.
=======
| A 3rd and 4th phone claim slots 2 and 3; a 5th is refused | `four_phones_claim_four_slots` (real ControllerServer, WebSocket clients) | `issue-36/scenario-suite.txt` | PASS |
| In a 4-player round, the 1st and 2nd eliminations don't end it; only the last survivor scores; all four scoreboard slots are filled | `four_player_round_ends_on_last_survivor` | `issue-36/scenario-suite.txt` | PASS |
| The winner keeps their weapon among four | `four_player_winner_keeps_weapon` | `issue-36/scenario-suite.txt` | PASS |
| Every stage has 4 safe spawns, and four bodies settle at once | `stage_spawns_are_safe` (min 4), `stage_four_spawns_settle_together` (all 11 stages) | `issue-36/scenario-suite.txt` | PASS |
| The pickup cap is 2 for 2-3 players and 3 for 4 | `pickup_cap_scales_with_roster` | `issue-36/scenario-suite.txt` | PASS |
| The four identity colours match the phone page and are distinct | `identity_colours_match_controller_page` (generalised to every slot) | `issue-36/scenario-suite.txt` | PASS |
| 2-player behaviour is unchanged; nothing else regressed | full suite, 62 of 62 | `issue-36/scenario-suite.txt` | PASS |
| Boots on a fresh clone | `git clone` of the branch, `godot --headless --path <clone> --quit`, grep for `SCRIPT ERROR` / `Failed to load script` | `issue-36/boot-check.txt` | PASS |
| Four real phones in the real game | not yet run | none | BLOCKED: needs four phones on the LAN |
>>>>>>> 124cff8 (Record #36 evidence and clear #33 evidence)
