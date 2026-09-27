# Issue #180 evidence

Branch `feat/issue-180-stall-force-v2`, on top of main `6d4ec9d`: tkneeland's two #180 commits from #197, cherry-picked with authorship kept, plus one commit of CI fixes.

## What was run

Windows 11, Godot 4.6.2-stable, headless, `--fixed-fps 60`.

- `full-suite.txt`: the full scenario list (243 scenarios) in 5 parallel round-robin shards. **243 passed, 0 failed, 243 total.**
- `ci-shards-0-3.txt`: CI's own 4-way contiguous split (`tools/list_scenarios.sh <s> 4`), shards 0 and 3. These are the shards that failed on #197's CI. Shard 0: 60/60. Shard 3: 61/61. Shards 1 and 2 were also run: 61/61 each.

Figures the fixes are about, taken from these logs:
- `match_seed_replays_bot_match`: the two runs are identical, with a 1 px / 1 tick tolerance (was 48 px / 30 ticks).
- `weapon_damage_matches_roster`: the flail hits at 2178 px/s in every shard order, inside the 2200 ± 50 band. Before, it read 2144 in CI shard 0; alone it read 2178, and main reads 2174.
- `heads_do_not_tunnel_head`: passes. It was also stress-tested across 112 perturbed physics histories, all passing.

## Fresh-clone boot

A throwaway clone with no `.godot/`, `godot --headless --quit`. The only error:

```
ERROR: Could not create child process: qrencode -o .../join_qr.png -s 8 -m 2 http://<lan-ip>:8080/
```

That is the join-QR helper, which is not installed on this box. There is no SCRIPT ERROR and no "Failed to load script".
