# Test results

Evidence for the latest work package only: issue #113 (phone input smoothing). The previous package was issue #108 (physics interpolation, frame-time spikes), in commit 9c3abc8.

- `issue-113/full-suite.txt`: full scenario suite on `feat/issue-113-input-smoothing` rebased on main b659ff9.
  Result: 136 passed, 3 failed, 139 total. All three failures are axe scenarios (#99): `weapon_damage_matches_roster`, `roster_heads_do_not_tunnel_thin_platform` and `axe_swing_deals_damage`. The same three also fail on main b659ff9's own `--all` run (134 passed, 3 failed, 137 total). The `Lambda capture ... was freed` ERROR near `rising_kill_zone_*`, whose scenarios pass, also shows on main b659ff9.
  The new scenarios are `phone_jitter_is_smoothed` (angle wobble RMS: raw 0.0478 rad, smoothed 0.0200 rad, which is 42% of raw; the final value is reached 5 ticks after raw input reaches it) and `phone_release_and_flick_are_not_smoothed`.
