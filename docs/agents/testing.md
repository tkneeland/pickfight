<!-- atlas-v3:testing:start -->
# Testing and proof of work

This document is the authoritative repository policy for verification commands,
acceptance evidence, and `PASS`, `FAIL`, `BLOCKED`, and `SKIPPED` verdict
semantics.

Run surface: **local, plus GitHub Actions CI** (`.github/workflows/scenarios.yml`).

Read this guide while planning acceptance criteria, Definition of Done,
fixtures, and verification. Resolve the applicable commands and evidence rules
into each execution packet; implementation workers execute that packet without
rereading this guide.

## Commands

| Check | Command | Coverage | When | Status |
|---|---|---|---|---|
| boot-check | `godot --headless --quit` | Catches GDScript parse errors and broken scene/resource references at project boot | Before opening a PR | verified |
| runner parse check | `godot --headless --path . --check-only -s tools/scenario_runner.gd 2>&1 \| grep -E "SCRIPT ERROR\|Parse Error"` (must print nothing) | Parse errors in the scenario runner, which the boot check does not load | After editing the runner | verified |
| scenarios | `godot --headless --fixed-fps 60 --path . -s tools/scenario_runner.gd -- --scenarios=<a>,<b>` (or `--scenario=<name>`) | The named scenarios against the real game | While working on them | verified |
| full suite | `godot --headless --fixed-fps 60 --path . -s tools/scenario_runner.gd -- --all` | Every scenario in `SCENARIO_NAMES`; ends with `N passed, M failed, T total` | Before opening a PR | verified |
| CI | `.github/workflows/scenarios.yml`, on every PR and push to main | Import, boot check and runner parse check, then the suite in 4 parallel shards (`tools/list_scenarios.sh <i> 4`), each under `--fixed-fps 60` on Linux | Automatic; should be green before merging | verified |

Always pass `--fixed-fps 60` to the runner (#182/#183): every rendered frame
is then exactly one physics tick, so timing-sensitive scenarios behave the
same on any machine. The full suite takes a while on one process; to run it
faster, split the names from `tools/list_scenarios.sh` into contiguous shards
(`tools/list_scenarios.sh <i> <k>` prints shard `i` of `k` as a comma list)
and run each shard in its own clone of the repo, as CI does. Scenarios that
save settings point `Sfx`/`Music` at a temp file and must never write the
real `user://audio.cfg`.

`verified` means the command ran successfully here. `inferred` means configuration names it but setup did not execute it. `unavailable` is an explicit gap.

## Evidence policy

- Repository-local proof-artifact root: `test-results`.
- Clear the entire proof-artifact root before capturing evidence for each work
  package. It intentionally contains only the latest work package's evidence.
- For UI screenshots and videos, use one directory per test name beneath the
  proof-artifact root. Rerunning a test replaces that test directory.
- Visual/browser behavior: screenshot when visual state matters; video only when motion, timing, or a multi-step interaction cannot be proved by a still image.
- Integration and non-UI behavior: committed machine-readable report or captured test output when an artifact is needed beyond the command result.
- External integration: not applicable - no external/deployed target for this local game prototype.
- Sensitive data: not applicable - no real user data in this prototype; sanitize any save/profile data if that's added later.
- Any screenshot, video, test report, captured output, or other artifact cited as
  `PASS` evidence is saved beneath `test-results` and committed
  on the feature branch. The PR links to the committed path; it never describes
  an uncommitted local file as attached evidence.
- Screenshot is the default visual proof. Add video only when motion, timing, or
  a multi-step interaction is material and a still image cannot prove it. Do not
  require screenshots or video when the repository has no UI/browser surface.
- Failure-only diagnostics not cited as `PASS` evidence, such as large traces,
  may remain uncommitted when repository policy says so.
- A blocked or skipped check records the attempted command and raw failure.
- `BLOCKED`, `SKIPPED`, ambiguity, and worker self-report are never `PASS`.

Run formatting before lint review, avoid unrelated reformatting, and rerun
affected tests after automatic fixes. Give every real integration seam at least
one criterion against the real dependency. Name test accounts, seed data,
confirmation flows, and cleanup. Human-gated criteria name the prerequisite,
human action, expected result, and post-action check. Runnable work must be
startable and exercisable by a fresh context using committed instructions.

Use `PASS` when evidence proves the criterion, `FAIL` when observable behavior is
incorrect, `BLOCKED` when it cannot be observed or exercised, and `SKIPPED` only
for an approved exception with the attempted command and reason. Sanitize every
retained artifact before storage or sharing.
<!-- atlas-v3:testing:end -->
