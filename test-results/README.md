# Proof of work: issue #49, axe intensify

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. #45's evidence is in
history at `466a78aest-results/issue-45/`.

Branch `feat/issue-49-axe-intensify`, macOS, local Godot 4.6.2.

| Change (issue #49) | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| Axe damage 90 (the per-strike cap), so two hits always kill | `weapon_damage_matches_roster`, roster tier scenarios | `issue-49/scenario-suite.txt` | PASS |
| Axe much more sluggish (drive 9, extend 300, return 150) | roster tier scenarios, `roster_heads_do_not_tunnel_head` (+ `_reversed`); feel needs a playtest | `issue-49/scenario-suite.txt` | PASS / NEEDS PLAYTEST |
| Head redrawn as an axe (poll, neck, curved edge), 16 circles inside the art, still flips with aim | `weapon_head_circles_within_art`, `axe_head_mirrors_with_aim`, `axe_head_holds_side_near_vertical` | `issue-49/scenario-suite.txt` | PASS |
| Nothing else regressed | full suite on 126dda4: 78 of 78 | `issue-49/scenario-suite.txt` | PASS |
| Boots on a fresh clone | `git clone`, `godot --headless --path <clone> --quit`, grep for `SCRIPT ERROR` / `Failed to load script` | `issue-49/boot-check.txt` | PASS |

Known gap: #47 (in progress). The #38 head-tunnel regression is not yet caught by any scenario.
