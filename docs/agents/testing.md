<!-- atlas-v3:testing:start -->
# Testing and proof of work

This document is the authoritative repository policy for verification commands,
acceptance evidence, and `PASS`, `FAIL`, `BLOCKED`, and `SKIPPED` verdict
semantics.

Run surface: **local only**.

Read this guide while planning acceptance criteria, Definition of Done,
fixtures, and verification. Resolve the applicable commands and evidence rules
into each execution packet; implementation workers execute that packet without
rereading this guide.

## Commands

| Check | Command | Coverage | When | Status |
|---|---|---|---|---|
| boot-check | `godot --headless --quit` | Catches GDScript parse errors and broken scene/resource references at project boot | Before opening a PR | verified |

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
