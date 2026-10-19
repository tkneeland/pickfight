# #681 verification: opt-out crash reporting (Sentry Godot SDK)

- Scenarios `681|428|688|settings|notice`: 40 passed, 0 failed (macOS, Godot 4.6.2 headless).
- Full suite: 854 passed, 1 failed of 855; the only local failure is `axe_wins_clash_against_every_weapon`, which already fails on macOS (CI on main is green).
- Fresh-clone boot check (no `.godot/`): no SCRIPT ERROR or Failed to load script.
- The SDK is fetched by `tools/fetch_sentry.sh` (pinned 2.3.0, sha256 checked) into the git-ignored `addons/sentry/`. Nothing binary is committed.
- Dormant without a DSN: `CrashReporting.should_init` is false while the DSN is empty, under the runner and headless, or when the player unticks "Send crash reports".

Owner-only steps (not done, no data sent anywhere):
1. Create the Sentry project, paste its DSN into the project setting, and tick "Prevent storing IP addresses".
2. Run `--crash-test` once on an exported build and check that the event arrives.
