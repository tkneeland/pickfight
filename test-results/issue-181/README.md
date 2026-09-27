# Issue #181: test evidence

**What was run:** the full scenario list (256 scenarios) on branch
`feat/issue-181-pickaxe-grip`, based on main `1ba49ad`. It ran as 5 parallel
shards of `--scenarios=` under `--fixed-fps 60`, on Windows 11 with Godot
4.6.2. The complete output is in `full-suite.txt`.

**Result:** 256 passed, 0 failed, 256 total.

**Fresh-clone boot check** (`git clone` of the branch, then `godot --headless --quit`):
the only ERROR is qrencode's `Could not create child process`. That comes from
the environment (qrencode is not installed on this machine) and has nothing
to do with this change.

**New scenarios** (both fail on main's code and pass on this branch):
- `grip_strength_is_per_weapon`
- `pickaxe_wall_grip_lets_go_at_every_swept_speed`

**The sweep** is in the PR body.

**Other folders:** the older `test-results/issue-*` folders could not be
removed. The permission policy blocked the removal.
