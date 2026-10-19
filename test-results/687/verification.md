# #687 verification
- Worker commit f31dc09; orchestrator fix on top: per-block blob seed salt, so stacked lava blocks don't move in sync. Furnace was recaptured to show it.
- Full suite on f31dc09: only the known `axe_wins_clash_against_every_weapon` fails. Two other failures (`every_stage_has_a_preview_647`, `music_loops_have_no_silent_seam`) came from the worktree's missing import cache; after `--import` both pass (2/2).
- Fresh-clone boot check: clean (on both commits).
- perf_probe Furnace physics_ms mean is 1.758 before and 1.857 after (noise; draw cost is not measured headless and not measured on a Deck).
- Screenshots: before/ and after/ (Furnace, Gantry, Footbridge, Gauntlet, Flatlands), plus before/rise/ and after/rise/ (Flatlands, Gantry).
- Collision shapes, damage and timing are unchanged.
