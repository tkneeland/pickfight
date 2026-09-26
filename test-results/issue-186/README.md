# Issue #186 evidence: CI scenario workflow

## Local full suite

`full-suite.txt` is the full `SCENARIO_NAMES` list (219 scenarios) run on
branch `ci/issue-186-scenario-workflow`, off main `33cb339`, as 5 parallel
shards of `godot --headless --fixed-fps 60 --path . -s tools/scenario_runner.gd -- --scenarios=<list>`
(Windows, Godot 4.6.2).

Result: **219 passed, 0 failed, 219 total.**

Fresh-clone boot check (`godot --headless --path <clone> --quit`): the only
ERROR is qrencode "Could not create child process", which is
environment-only (qrencode is not installed on this machine).

This change touches no game scripts or scenarios, only
`.github/workflows/scenarios.yml`, `tools/list_scenarios.sh` and
`docs/agents/collaboration.md`.

## CI

The PR's own runs of `.github/workflows/scenarios.yml` on ubuntu-latest
(4 contiguous shards of 54/55/55/55):

- Green: https://github.com/tkneeland/pickfight/actions/runs/36266492996
- Red, on a scratch commit that made `aim_angle` fail (commit `71c298f`,
  since dropped from the branch): https://github.com/tkneeland/pickfight/actions/runs/36266665909
  (shard 0 failed with `FAIL  aim_angle`).
- Green again after dropping the scratch commit: see the PR body.
