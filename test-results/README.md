# Test results

Evidence for the latest work package only: issue #182 (one game clock; the suite runs under `--fixed-fps 60`).

- `issue-182/full-suite-realtime.txt`: fresh-clone boot check plus the full suite in 4 parallel shards on `feat/issue-182-game-clock` 445eff6, the way `psuite.sh` runs it today. Boot is clean and the suite passes 216/216 in 10:21.
- `issue-182/full-suite-fixed-fps-60.txt`: the same, with `--fixed-fps 60` on the scenario runner's command line. It passes 216/216 in 2:30.
- `issue-182/main-baseline-realtime.txt`: main e91ab17 in realtime for comparison: 215/215 in 10:01.

Previous package: issue #175 (RoundManager split), `issue-175/`, in `git show e91ab17`.
