# Issue #139 evidence

- `full-suite.txt`: every scenario in `SCENARIO_NAMES`, run on main `f3d1e91` plus #138 as parallel `--scenarios=` shards. 158 passed, 0 failed, 158 total.
- Fresh-clone boot: the only ERROR is qrencode "Could not create child process", which is an environment issue (qrencode isn't installed here).
