# Proof of work -- issue #33, hitmarkers and debug damage numbers

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. #27's evidence is in
history at `be5ed60:test-results/issue-27/`.

Branch `feat/issue-33-hitmarkers`, Windows, local Godot 4.6.2.

| Criterion (issue #33) | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| A damaging strike draws a hitmarker at the contact point in the attacker's colour, and its number reads the damage dealt | `strike_shows_hitmarker_and_number` (a real swing) | `issue-33/scenario-suite.txt` | PASS |
| A lethal strike's marker is the red, bigger variant, and only that one | `lethal_strike_marker_is_distinct` | `issue-33/scenario-suite.txt` | PASS |
| A too-slow swing (300 to 700 px/s) shows a `0` and no marker; a slower graze shows nothing | `slow_contact_shows_zero_not_marker` | `issue-33/scenario-suite.txt` | PASS |
| With numbers off, markers still show and no numbers appear | `damage_numbers_switch_off` | `issue-33/scenario-suite.txt` | PASS |
| Repeated `0`s within the cooldown draw once; damage is never rate-limited | `zero_numbers_rate_limited` | `issue-33/scenario-suite.txt` | PASS |
| Works in the real game | windowed smoke run of `Main.tscn` with two WebSocket phones: natural `0`s during play, then a clean, too-slow and lethal strike, each screenshotted | `issue-33/smoke.txt`, `issue-33/*.png` | PASS |
| Nothing else regressed | full suite, 57 scenarios | `issue-33/scenario-suite.txt` | PASS |
| Boots on a fresh clone | `godot --headless --path . --quit`, no `.godot` present | `issue-33/boot-check.txt` | PASS |

## Notes

- The signal is named `strike_landed`, not the `struck` in the issue. A
  local variable in `_score_swept_strike` is already called `struck`, and
  renaming it would edit a file shared with #16 more than needed.
- The switch is `const SHOW_DAMAGE_NUMBERS` in `scripts/HitFeedback.gd`, as
  agreed. An instance variable starts from it, so a scenario can prove the
  off state without editing the file.
- Four scenarios drive `Player._land_strike` directly at a chosen head speed.
  That is the one function both hit paths go through, and physics cannot
  reliably produce a swing in the 300 to 700 px/s band. The real-swing
  scenario and the smoke run cover the physics end.
- Strikes on consecutive frames stack their numbers on top of each other
  (see `3-lethal.png`, where the smoke script fired two in a row). This is
  rare in real play; spreading them out is left for later if it shows up.
