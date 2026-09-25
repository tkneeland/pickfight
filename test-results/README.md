# Test results

Evidence for the latest work package only: issue #108 (physics interpolation, frame-time spikes).

- `issue-108/full-suite.txt`: full scenario suite on `perf/issue-108-smoothness` rebased on main d0f6597: 127/130. The 3 failures (`weapon_damage_matches_roster`, `roster_heads_do_not_tunnel_thin_platform`, `axe_swing_deals_damage`, all axe) fail identically on main d0f6597.
- `issue-108/perf.txt`: `tools/perf_probe.gd` frame-time runs, before and after, 60 Hz and 120 Hz `--demo`, three seeds each.

Previous package: issue #93 (sound mix), `issue-93/full-suite.txt` at commit 3ab830a, 133/133. Read it from git history (`git show c89a3b0`).
