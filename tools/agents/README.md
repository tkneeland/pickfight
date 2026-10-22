# tools/agents

Account-agnostic helpers for AT mode (rules: `docs/agents/autotriage.md`). Every script sources `pf-env.sh`, which
picks the account from env `PF_ACCOUNT` or `gh api user -q .login` and loads `accounts/<handle>.conf`. macOS (BSD `date`/`stat`) only.

- `accounts/<handle>.conf`: per-account settings (role, timezone, night hours, thresholds); `accounts/_shared.conf` holds shared thresholds.
- `pf-env.sh`: sourced by all; resolves the account, conf, `PF_STATE` dir and helpers (`pf_budget_ok`, `pf_daynight`, `pf_is_triagemaster`).
- `pf-at-mode.sh`: prints `AT·day`, `AT·night` or `MT`.
- `pf-triage-watch.sh`: zero-token poller; exits with one line (UNTRIAGED, MYTICKET, FEATURES? PR, PEER_BEACON, IDLE_SLOTS, AUSTIN_QUEUE_LOW) when Claude must act.
- `pf-automerge.sh`: merges green mergeable PRs, comments on conflicting ones; leaves conflict-risk PRs to the triagemaster.
- `pf-ship.sh <issue> "<title>" "<body>"`: merges main into the worktree branch, opens the PR with a Resource Usage section, waits for CI, merges.
- `pf-atlas.sh`: Atlas bookkeeping (`accept`, `closeout`, `tests`, `run`).
- `pf-rate.sh`: source it to set `PF_RATE` / `PF_WEEK` for PR bodies.
- `pf-watch-peers.sh`: triagemaster watcher for peer activity, stale peers and unowned tickets.
- `statusline-usage.sh`: Claude Code statusLine command; also saves the usage snapshot and updates the #432 beacon.
- `pf-status-refresh.sh`: background cache for status-line lines 2+; run by `statusline-usage.sh`.
- `pf-succession.sh`: computes the current triagemaster from the #432 beacons and writes it to `$PF_STATE/pf-triagemaster`.
- `pf-dupe-check.sh "<keywords>"`: run before filing a ticket; exit 1 means something plausible already exists.
- `pf-scenario-merge.sh [file...]`: during `git merge origin/main`, resolves conflicts in append-only `tools/scenario_runner.gd` / `docs/FEATURES.md` by re-inserting this branch's added blocks into main's copy; exit 1 = resolve by hand.
