# #849 verification: bundled CJK font subsets

- Subset build (`python3 -I tools/subset_cjk_font.py`, fontTools 4.67.0 in a venv, sources from google/fonts 45e3d52, sha256-checked): NotoSansSC-Subset.ttf 282 KB, NotoSansJP-Subset.ttf 383 KB, NotoSansKR-Subset.ttf 183 KB, 849 KB in all (limits: 600 KB each, 1.5 MB total).
- Scenarios (`godot --headless --fixed-fps 60 --log-file ... -s tools/scenario_runner.gd -- --scenarios=...`): `cjk_subsets_cover_every_translated_character_849`, `cjk_subset_check_reports_an_uncovered_character_849`, `cjk_fallback_chain_starts_with_bundled_subset_849`, `language_picker_draws_cjk_names_in_every_locale_849`, `ui_fonts_allow_system_fallback_for_cjk_688`, `settings_panel_language_row_lists_languages_and_switches_live_688`, `credits_screen_opens_and_closes_721`: all PASS.
- `export_presets.cfg` exclude filters are `test-results/*, docs/*, tools/*`, so `art/fonts/` still exports (checked in the coverage scenario too).
- Coverage rule: only the characters named in `CJK_UNCOVERED_EXEMPT_849` (just `▸`, which no bundled font has in any language) are exempt; they still come from the system fonts as before. Any other uncovered symbol fails the check.
- Language picker: only its popup gets the picker font (the locale's own chain, then all three subsets), rebuilt on a language change; the closed row keeps the theme font and its line height.
- Subset script re-run after the staging change (fontTools 4.x, `--src` cache): identical cmaps and sizes to the committed subsets (only the `head.modified` timestamp differs), so the committed fonts were kept.
- Fresh-clone boot check (`git clone` of the branch, `godot --headless --quit`, grep `SCRIPT ERROR|Failed to load script`): no output.
- Full suite: CI on the PR.
