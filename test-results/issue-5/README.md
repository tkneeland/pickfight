# Issue #5 evidence (HEAD 368776a)

- boot-check.log — `godot --headless --path . --quit`, exit 0, no errors (AC-1)
- scenario-respawn-prefix.log — new scenario with the fix line removed: FAIL (AC-2)
- scenario-respawn.log — same scenario with the fix: PASS (AC-2)
- scenario-all.log — `--all`: 22/22 (AC-3)
- fresh-clone-all.log — `--all` with `.godot/` removed: 22/22 (CLAUDE.md fresh-clone rule)
- human-gates.md — live-play verdicts (AC-4, AC-5)
