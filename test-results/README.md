# Proof of work -- issue #20, shuffled stage rotation with a fixed opener

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. #33's evidence is in
history at `136061d:test-results/issue-33/`.

Branch `feat/issue-20-shuffled-rotation`, macOS, local Godot 4.6.2.

| Criterion (issue #20 decision) | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| Every session opens on `stage_scenes[0]` (Flatlands), under any seed | `stage_rotation_opener_is_first_stage` (5 seeds), `stage_rotates_each_round` | `issue-20/scenario-suite.txt` | PASS |
| Shuffled bags: every stage exactly once per bag | `stage_rotates_each_round` (3 bags) | `issue-20/scenario-suite.txt` | PASS |
| No stage twice in a row, across bag boundaries and out of the opener; 1-stage repeats, 2-stage alternates | `stage_rotation_never_repeats_back_to_back` | `issue-20/scenario-suite.txt` | PASS |
| Seedable for tests: same seed gives the same order, a different seed gives a different one | `stage_rotation_seeded_is_deterministic` | `issue-20/scenario-suite.txt` | PASS |
| Nothing else regressed | full suite: 59 of 60 | `issue-20/scenario-suite.txt` | PASS, except the known failure below |
| Boots on a fresh clone | `git clone` of the branch, `godot --headless --path <clone> --quit`, grep for `SCRIPT ERROR` / `Failed to load script` | `issue-20/boot-check.txt` | PASS |

## Known failure, not from this work

`roster_heads_do_not_tunnel_head_reversed` fails deterministically on macOS on
clean `main` too (dagger 1/12). Tracked in #38.
