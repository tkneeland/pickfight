# Proof of work: issue #48, sword blade clips through platforms

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. #55's evidence is in
history at `3c192d4:test-results/issue-55/`.

Branch `fix/issue-48-sword-clipping`, macOS, local Godot 4.6.2.

| Change (issue #48) | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| Red first: every roster head over a 24 px slab (slams, braced and standing swings, flings; 94 trials per weapon) goes through on base code: staff 1, sword 1, axe 2 | `roster_heads_do_not_tunnel_thin_platform` on the new test with `origin/main`'s `WeaponHead.gd` | `issue-48/red-before-fix.txt` | FAIL (expected) |
| With the fix, no head goes through | `roster_heads_do_not_tunnel_thin_platform` | `issue-48/scenario-suite.txt` | PASS |
| Nothing else regressed | full suite on d21c5c3 (rebased onto #55): 87 of 87 | `issue-48/scenario-suite.txt` | PASS |
| Boots on a fresh clone | `git clone`, `godot --headless --path <clone> --quit`, grep for `SCRIPT ERROR` / `Failed to load script` | `issue-48/boot-check.txt` | PASS |
