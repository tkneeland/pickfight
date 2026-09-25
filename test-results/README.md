# Test results

Evidence for the latest work package only: issue #118 (music and settings menu). The previous package was issue #119 (exported builds), in commit 26e4b07.

- `issue-118/full-suite.txt`: full scenario suite on `feat/issue-118-music-settings` rebased on main 8dad787.
  Result: 134 passed, 3 failed, 137 total. All three failures are axe scenarios (#99): `weapon_damage_matches_roster`, `roster_heads_do_not_tunnel_thin_platform` and `axe_swing_deals_damage`. The same three also fail on main 8dad787. The `Lambda capture ... was freed` ERROR during `rising_kill_zone_resets_each_round`, which passes, also shows on main 8dad787. No leaked-instance warnings at exit.
