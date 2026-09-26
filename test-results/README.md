# Test results

Evidence for the latest work package only: issue #136 (every weapon but the axe more responsive; values only).

- `issue-136/full-suite.txt`: fresh-clone boot check plus the full suite in 4 parallel shards on `feat/issue-136-responsive` c538078, rebased on main 74ed45f. Boot is clean and the suite passes 211/211.
- `issue-136/traversal-before.txt` and `issue-136/traversal-after.txt`: the new `roster_traversal_is_measured`, run with main's weapon resources and with the branch's. It reports aim settle, extension, vault height and ledge climbs per weapon. It is red on main's resources, because the boomstick vaults 69 px, under the 80 px ledge.
- `issue-136/perf-probe.txt`: `tools/perf_probe.gd`, 3600 frames with eight bots, main resources against the branch, interleaved runs.

Previous package: issue #168 (harness fixes), `issue-168/`, in `git show 74ed45f`.
