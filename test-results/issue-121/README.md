# Issue #121 evidence

- `full-suite.txt`: every scenario in `SCENARIO_NAMES`, run on main `3e700e5` as 5 parallel `--scenarios=` shards to save time.
- The 3 failures also happen on main, so this branch didn't cause them:
  - `roster_heads_do_not_tunnel_thin_platform`: deterministic, the axe goes through in 5 of 94 trials.
  - `axe_swing_deals_damage` and `weapon_damage_matches_roster`: known axe flakes.
- Fresh-clone boot: the only ERROR is qrencode "Could not create child process", which is an environment issue (qrencode isn't installed here).
