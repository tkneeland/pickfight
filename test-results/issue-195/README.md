# Issue #195: test and CI isolation

Evidence for the branch `fix/issue-195-test-isolation`.

| File | What it shows |
|---|---|
| `full-suite.txt` | Full suite in 4 `--fixed-fps 60` shards (`psuite.sh`): **233 passed, 0 failed**. That's 232 existing scenarios plus the new `script_run_never_touches_owner_settings`. |
| `owner-settings-md5.txt` | The owner's real `user://audio.cfg` has the same md5, mtime and size before and after that full run. |
| `class-cache-proof.txt` | A fresh clone plus a scratch `class_name` dependency (`var _scratch_195: WeaponStats` in `Player.gd`), after `--import`. The boot check is clean while the import's class cache is present, which is the old CI behavior. With the cache deleted, as in the new CI step, it shows `Parse Error` / `Failed to load script`. |

Red/green checks run by hand (not committed as files):

- **Item 2.** With the `-s` branch in `Sfx._ready()` disabled and `Music.gd` from `main`, the new scenario fails. It reports that saving is on, that `settings_path` is the owner's `user://audio.cfg` for both Sfx and Music, and that an unreadable settings file got rewritten. With the fix, it passes.
- **Item 3.** A deliberate `null.free()` after `planted_head_grips_sideways_push`'s first teardown now reports `FAIL ... scenario did not run to completion`. On `main`, it reported PASS.
- **Item 5.** On macOS `/bin/bash` 3.2, `tools/list_scenarios.sh` on `main` fails with `mapfile: command not found`. It now prints all 233 names and the 4 shard lists.
- **Item 8.** `perf_probe` (60 Hz; `--demo` at 120 Hz; `--weapon=flail`) and `ringout_probe` (random and `--brain=bot`) now exit 0 without "ObjectDB instances leaked at exit". `perf_probe --weapon=nosuch` exits 2.
