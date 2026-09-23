# Issue #6 evidence (code at 8835161)

| # | Criterion | Evidence | Result |
|---|---|---|---|
| V1 | Winner keeps weapon, others reset (phase A) | scenario-round_winner_keeps_weapon.txt | PASS |
| V2 | No survivors, so everyone resets (phase B) | same | PASS |
| V3 | One named default-weapon source | default-weapon-grep.txt | 1 hit: Player.gd `DEFAULT_WEAPON_STATS` |
| V4 | Test-only WeaponStats, no resources/ change | resources-diff.txt | empty diff |
| V5 | Expired winner claim does not pass the weapon on (phase C) | scenario-round_winner_keeps_weapon.txt | PASS |
| V6 | No regressions | scenario-all.txt | 23/23 |
| V7 | Boot check | boot-check.txt | exit 0, no parse/load errors |
| V8 | Fresh-clone parse | fresh-clone.txt | PASS with `.godot/` removed |

Negative control (implementation worker): forcing `start_round` to always reset made phase A FAIL ("winner p1 did not keep its weapon_stats instance").

Note: the `ControllerServer: cannot listen on port 8080/8081` lines in boot-check and fresh-clone are socket binds failing because another game instance held the ports. They are not script errors. No human gates: the rule is invisible in live play until a second weapon exists.
