# Issue #114 evidence

- `full-suite.txt`: `--all` run of the branch on main `5b90579`. The branch is now rebased on `8dad787`. The only difference is #119, which changes export presets and docs only, with no scripts or scenes.
- Failures that also happen on main `8dad787`, not caused by this branch:
  - `roster_heads_do_not_tunnel_thin_platform`: deterministic, the axe goes through in 5 of 94 trials.
  - `axe_swing_deals_damage` and `weapon_damage_matches_roster`: known axe flakes.
- Fresh-clone boot: the only ERROR is qrencode "Could not create child process", which is an environment issue (qrencode isn't installed here).
