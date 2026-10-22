# #849 verification: bundled CJK font subsets

- Subset build (`python3 -I tools/subset_cjk_font.py`, fontTools 4.67.0 in a venv, sources from google/fonts 45e3d52, sha256-checked): NotoSansSC-Subset.ttf 282 KB, NotoSansJP-Subset.ttf 376 KB, NotoSansKR-Subset.ttf 183 KB, 842 KB in all (limits: 600 KB each, 1.5 MB total).
- Scenarios (`godot --headless --fixed-fps 60 --log-file ... -s tools/scenario_runner.gd -- --scenarios=...`): `cjk_subsets_cover_every_translated_character_849`, `cjk_subset_check_reports_an_uncovered_character_849`, `cjk_fallback_chain_starts_with_bundled_subset_849`, `ui_fonts_allow_system_fallback_for_cjk_688`, `credits_screen_opens_and_closes_721`: all PASS.
- `export_presets.cfg` exclude filters are `test-results/*, docs/*, tools/*`, so `art/fonts/` still exports (checked in the coverage scenario too).
- Coverage rule: a character the English string of the same key also uses (only `▸` today) is exempt, since no bundled font has it in any language; it still comes from the system fonts as before.
- Fresh-clone boot check: see PR body. Full suite: CI.
