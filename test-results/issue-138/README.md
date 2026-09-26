# Issue #138 evidence

- `full-suite.txt`: every scenario in `SCENARIO_NAMES`, run on main `f3d1e91` as parallel `--scenarios=` shards. 157 passed, 0 failed, 157 total.
- `perf-8-bots.txt` / `perf-4-bots.txt`: `tools/perf_probe.gd --frames=3600` at `--fixed-fps 60` with 8 and then 4 bots. Neither run has a frame over the 16.7 ms budget.
- Fresh-clone boot: the only ERROR is qrencode "Could not create child process", which is an environment issue (qrencode isn't installed here).
