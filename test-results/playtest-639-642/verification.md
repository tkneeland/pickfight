# playtest-639-642 verification (2026-10-08)

Integrated HEAD: 59371e6. It is made of:
- merges of D639–D642;
- e477467: host weapon toggles hide the retired spear;
- the review-fix commit.

## Deliverables (accepted)
| Issue | Commit | Summary |
|---|---|---|
| #639 | 1e2f143 | The victory prompt names only the continue inputs that are seated. |
| #640 | e6a7f90 | Left click is a second binding for the Space action tap: host PC seat, Online client, and Continue on the victory screen. |
| #641 | f4c6e96 | Fishing rod `launch_range` 400 → 800, about 0.83 s before it auto-retracts. |
| #642 | d8f299f + e477467 | Spear retired from every pickup pool, random weapons and host weapon toggles; its code and resource are kept. |
| review | 59371e6 | A left click after Esc recaptures the mouse again. Victory hint now reads "Space or click". Space and click have separate host timers. New scenario for the victory click. FEATURES wording fixed. |

## Checks
- Boot check: no output in the worktree. No output in a fresh clone of 59371e6.
- Full suite:
  - e477467: `769 passed, 1 failed, 770 total`.
  - 59371e6: `772 passed, 1 failed, 773 total`.
  - The only failure in both runs is `axe_wins_clash_against_every_weapon`. It fails on Mac only, also fails locally on main 92a1278, and passes in CI on main.
- Red before green: both new `ControllerServer` regression scenarios failed before the fix.
- Aggregate review covered correctness and contract. Every finding was fixed in 59371e6.
