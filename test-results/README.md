# Test results

Evidence for the latest work package only: issue #115 (a head trapped on the far side of terrain phases home after a held release).

- `issue-115/targeted.txt`: after rebasing onto main (SHA in the file header), `trapped_head_phases_home_after_release` plus the head, clipping and grip scenarios.
- `issue-115/base-red.txt`: the new scenario against the pre-change code (`is_head_phased()` stubbed to false): the head never phases and stays under the slab at y 196.8.

The full suite is run by the coordinator at integration.

Previous package: issue #109 (heads clipping through thin platforms), `issue-109/` at commit ada044f. Read it from git history (`git show ada044f`).
