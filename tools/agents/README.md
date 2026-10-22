# tools/agents

Account-agnostic helpers for AT mode (rules: `docs/agents/autotriage.md`). Every script sources `pf-env.sh`, which
picks the account from env `PF_ACCOUNT` or `gh api user -q .login` and loads `accounts/<handle>.conf`. macOS, Linux and Windows (Git Bash); see the support matrix below.

- `accounts/<handle>.conf`: per-account settings (role, timezone, night hours, thresholds); `accounts/_shared.conf` holds shared thresholds.
- `pf-env.sh`: sourced by all; resolves the account, conf, `PF_STATE` dir and helpers (`pf_budget_ok`, `pf_daynight`, `pf_is_triagemaster`).
- `pf-at-mode.sh`: prints `AT·day`, `AT·night` or `MT`.
- `pf-triage-watch.sh`: zero-token poller; exits with one line (UNTRIAGED, MYTICKET, FEATURES? PR, PEER_BEACON, IDLE_SLOTS, AUSTIN_QUEUE_LOW, MSG) when Claude must act.
- `pf-automerge.sh`: merges green mergeable PRs, comments on conflicting ones; leaves conflict-risk PRs to the triagemaster.
- `pf-ship.sh <issue> "<title>" "<body>"`: merges main into the worktree branch, opens the PR with a Resource Usage section, waits for CI, merges.
- `pf-atlas.sh`: Atlas bookkeeping (`accept`, `closeout`, `tests`, `run`).
- `pf-rate.sh`: source it to set `PF_RATE` / `PF_WEEK` for PR bodies.
- `pf-watch-peers.sh`: triagemaster watcher for peer activity, stale peers and unowned tickets.
- `statusline-usage.sh`: Claude Code statusLine command; also saves the usage snapshot and updates the #432 beacon.
- `pf-status-refresh.sh`: background cache for status-line lines 2+; run by `statusline-usage.sh`.
- `pf-succession.sh`: computes the current triagemaster from the #432 beacons and writes it to `$PF_STATE/pf-triagemaster`.
- `pf-dupe-check.sh "<keywords>"`: run before filing a ticket; exit 1 means something plausible already exists.
- `pf-msg.sh init|send <TYPE> <text>|claim <n>|release <n>|listen|claimed <n>|heartbeat`: private ntfy channel between accounts, a doorbell only (verify on GitHub). Setup: run `pf-msg.sh init` on one machine, share the printed topic out of band (never commit it), and on the other machine write the same `PF_MSG_TOPIC=<topic>` line into its `$PF_STATE/pf-msg.conf` (optional `PF_MSG_SERVER`, default `https://ntfy.sh`). `listen` fills `msg-inbox.log` and writes CLAIM/ASK/FIRE lines to `msg-wake.txt`, which `pf-triage-watch.sh` turns into a `MSG <TYPE> ...` wake within 10 s. Keep it alive with `windows/pf-supervise.sh msg` (macOS: `screen -dmS pf-msg bash tools/agents/windows/pf-supervise.sh msg`).
- `pf-msg-leakcheck.sh [dir]`: exit 1 (`TOPIC LEAK: <files>`) when the channel topic is in tracked files, the staged diff or commits not yet on main; `pf-ship.sh` runs it before every push.
- `pf-scenario-merge.sh [file...]`: during `git merge origin/main`, resolves conflicts in append-only `tools/scenario_runner.gd` / `docs/FEATURES.md` by re-inserting this branch's added blocks into main's copy; exit 1 = resolve by hand.

## Platform support

| | macOS | Windows 11 (Git Bash) | Linux |
|---|---|---|---|
| All `pf-*.sh` scripts, `statusline-usage.sh` | yes | yes | yes (GNU tools, same path as Git Bash) |
| Long-lived watchers | `screen` | `windows/pf-start.ps1` (hidden processes, no `screen`) | `screen`/`tmux` |
| `pf-scenario-merge.sh` | yes | needs `python3` installed | yes |
| Desktop banner on a conflicting PR | yes (`osascript`) | no | no |

`pf-env.sh` carries the portable helpers (`pf_mtime`, `pf_iso_to_epoch`, `pf_epoch_fmt`, `pf_notify`), picks GNU or BSD
`date`/`stat` at load time, maps IANA `TZ` names Git Bash cannot read, and strips the CRLF Windows `jq.exe` emits. Use them
instead of `stat -f`, `date -j` or `date -r` in any new script. `PF_STATE_DIR=<dir>` points any script at a scratch state folder (tests). `PF_DRY_RUN=1` stops `statusline-usage.sh` and
`pf-succession.sh --post` from writing to GitHub. Windows setup, Task Scheduler and the status line:
[`windows/README.md`](windows/README.md).
- `pf-reserve.sh`: reserve-account supervisor (`RESERVE=1`), one pass every 10 min under launchd (`--install`; `--dry` prints the decision). Hands unstarted tickets back while every regular dev can work, and starts a headless AT session (prompt: `pf-reserve-prompt.md`) only when this account is needed or has in-flight tickets. Zero tokens while idle.
- `pf-beacon.sh`: writes this account's #432 usage beacon once (finds the comment if the id file is missing; errors to `beacon.log`).
