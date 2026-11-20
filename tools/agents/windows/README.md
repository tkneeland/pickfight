# AT mode on Windows (Git Bash)

Runs the AT watchers without `screen`. Needs Git for Windows (Git Bash), `gh` (logged in) and `jq` on PATH.
`powershell -ExecutionPolicy Bypass` is needed on machines where script execution is restricted.

```powershell
powershell -ExecutionPolicy Bypass -File tools\agents\windows\hive-start.ps1  -Account <handle>   # hidden watchers
powershell -ExecutionPolicy Bypass -File tools\agents\windows\hive-status.ps1 -Account <handle>   # running? any wake line?
powershell -ExecutionPolicy Bypass -File tools\agents\windows\hive-stop.ps1   -Account <handle>
```

- `hive-start.ps1` launches `hive-supervise.sh triage|automerge|beacon|msg` through Git Bash, hidden, with
  `HIVE_ACCOUNT` set, and records their pids in the account's state folder (`%USERPROFILE%\.claude\hive\<repo>\<handle>\`,
  the folder `hive-env.sh` calls `HIVE_STATE`). `-Only triage` (or `automerge`, `beacon`, `msg`) starts one.
  `hive-automerge.sh` really merges green PRs, so start it on purpose.
- The triage supervisor restarts `hive-triage-watch.sh` after every wake. The one wake line it printed goes to
  `triage-wake.txt` (latest, UTC-stamped) and `triage-wake.log`, and `triage-status.json` shows the state. Claude
  (or you) reads it with `hive-status.ps1`, which exits 10 while an unhandled wake line exists; `hive-status.ps1 -Ack`
  marks it handled. The headless keepalive session uses the bash twin, `bash tools/agents/hive-wake.sh` (`--ack`), since
  it cannot start a nested PowerShell. After a wake the supervisor waits 5 minutes before polling again.
- `hive-supervise.sh automerge` keeps `hive-automerge.sh` running and appends to `automerge.log`.
- `hive-supervise.sh beacon` runs `hive-beacon.sh` every 5 min (refreshing the snapshot with `hive-usage.sh` when the
  status line has not written it) to keep your `USAGE` beacon on the private channel current; the beacon sends only when
  the numbers changed or an hour passed (ntfy's daily quota). The status line's own
  background beacon job can die with the status line process on Windows; failures go to `beacon.log`.
- `hive-supervise.sh msg` keeps `hive-msg.sh listen` alive and runs `hive-msg.sh heartbeat` every 60 s (HELLO on the
  private channel after an hour with no other send, a wake line when a peer goes silent). It needs `msg.conf` in the state folder (`hive-msg.sh init`, then
  share the topic out of band). It fills the inbox the other accounts' beacons are read from.
- `hive-supervise.sh voice` keeps the hub voice runner (`hive-voice.mjs`) alive. It runs only when the state folder's
  `hub.conf` holds `HUB_URL` and `HUB_VOICE_TOKEN` (never commit that file), and exits at once otherwise.
- `hive-stop.ps1` kills the supervisors and sweeps any leftover `hive-*.sh` watcher process on the machine.
- In `SINGLE_ACCOUNT` (and `PRIVATE`) mode the `beacon` and `msg` supervisors exit at once: there is no channel.

## Keep the watchers alive (Task Scheduler)

Run once: `powershell -ExecutionPolicy Bypass -File tools\agents\windows\hive-install-task.ps1 -Account <handle>`. It
registers a task named `hive AT watchers (<repo>, <handle>)` with a logon trigger plus a 5-minute repeat, so a dead listener is
back within 5 minutes, and turns off sleep on AC power. It runs through `conhost --headless`, so no console window
flashes. Remove it with `Unregister-ScheduledTask -TaskName "hive AT watchers (<repo>, <handle>)" -Confirm:$false`.

The `SessionStart` hook (`hive-join.sh`) also restarts dead watchers through `hive-start.ps1` whenever a Claude
session opens.


## Always-on Claude session (no terminal open)

`hive-keepalive.sh` needs `screen`, which Windows does not have. `hive-keepalive.ps1 -Account <handle>` is the stand-in: it
keeps ONE headless `claude -p` session running the AT prompt (the same one `hive-keepalive.sh --print-prompt` prints,
rebuilt for every session). When a session ends, hits a usage limit or crashes, the next one starts after 60 s (10 min
if it ended in under 2 min, so a limit or crash loop never spins). A second copy exits at once (`keepalive.pid`).
`hive-install-task.ps1` (above) registers it as the task `hive AT session (<repo>, <handle>)`, logon plus every 5 minutes, so
nobody has to keep a terminal open; `-NoSession` skips it (use it on a machine where you also run an interactive AT session: two sessions would act on the same account). `hive-stop.ps1` stops the keepalive and its claude, but the task restarts it within 5 minutes; to stop it for good run `Unregister-ScheduledTask -TaskName "hive AT session (<handle>)" -Confirm:$false`. `hive-status.ps1` shows it as `keepalive`; logs are
`keepalive.log` and `keepalive-session.out/.err` in the state folder.

An unattended `claude -p` cannot answer permission prompts. By default it runs under your own Claude settings, whose allow
rules must cover git, gh, bash and the hive scripts; `-SkipPermissions` (an opt-in on the installer or the script) runs it
with `--dangerously-skip-permissions` instead. Extra claude flags go in `-ClaudeArgs` or, per machine and one per line, in `keepalive-args.txt` in the state folder (a scoped allowlist: `--permission-mode`, `acceptEdits`, `--allowedTools`, `Bash(git:*)`, ...). Nothing is ever approved in that session, so the allowlist must match every command it runs, part by part: besides `Bash(git:*)`, `Bash(gh:*)`, `Bash(bash:*)`, `Bash(jq:*)` and your build tool (e.g. `Bash(godot:*)`), allow the read-only helpers it pipes into or chains with (`Bash(cd:*)`, `Bash(cat:*)`, `Bash(head:*)`, `Bash(tail:*)`, `Bash(grep:*)`, `Bash(ls:*)`, `Bash(wc:*)`) and the `Read`, `Glob`, `Grep`, `Edit`, `Write`, `Skill`, `Agent` and `ToolSearch` tools (workers are subagents). The headless prompt already tells it to run scripts bare (`HIVE_ACCOUNT` is set by the keepalive; a `VAR=value` prefix matches no rule), to use the Bash tool only (a nested PowerShell is always refused) and to keep one command per call; a session that still gets refused says which command in `keepalive-session.out`. The session is stateless by design
(AT mode reads GitHub, the channel and the repo), so a fresh session picks up where the last one stopped.

## Talking to the hive from your own Claude

Each machine can have two kinds of Claude session (issue #300).

- **The always-on session**, started by the keepalive (`hive-keepalive.sh` or `hive-keepalive.ps1`), is the only one that does AT work: claim tickets, start workers, review and mark, merge, triage. Both keepalives start it with `HIVE_SESSION=always-on` in its environment (so do the unattended `hive-reserve.sh` and `hive-resume.sh` sessions).
- **Control-panel sessions** are the Claude you open yourself in the repo while the keepalive runs. The SessionStart hook (`hive-join.sh`) prints a CONTROL PANEL banner for them. Allowed: send and read hive messages (`hive-msg.sh send`/`inbox`, `hive-ask.sh`), `hive.sh status`, file or comment on tickets, grill, run the game for playtests, and pass instructions to the always-on session with a comment on the ticket or PR (the always-on session's watchers pick it up), or on macOS/Linux type into its screen session (`screen -r hive-<repo>-<account>`, detach with Ctrl-a d). An INFO/ASK to your own handle does not work: the listener drops messages from your own account. Forbidden: claim tickets, start workers, mark reviews, merge. After pulling this change, restart the keepalive (hive-stop, then hive-start) so its sessions get `HIVE_SESSION=always-on`; until then a Windows always-on run is treated as a control panel.

A session is a control panel when `HIVE_SESSION` is not `always-on` and this account's `keepalive.pid` (in `$HIVE_STATE`) names a live keepalive process (`hive_control_panel` in `hive-env.sh`; the pid's command line is checked so a recycled pid does not count). Three guards refuse with a clear message and exit non-zero in a control panel: `hive-msg.sh send CLAIM` (and `claim <n>`), `hive_mark_review`, and `hive-pace.sh start` (the worker-start path; bare `hive-pace.sh` and `state` stay open for heartbeat checks). With no keepalive running (a machine without one, or MT mode) nothing changes.

The guard is advisory, not a security boundary: anyone can export `HIVE_SESSION=always-on` and bypass it, and it does not cover other routes such as `gh pr merge`. The banner is the real control; a control-panel session is expected to follow it.

## Claude Code status line

In `%USERPROFILE%\.claude\settings.json` (the path is your main checkout, not a worktree):

```json
"statusLine": {
  "type": "command",
  "command": "\"C:/Program Files/Git/bin/bash.exe\" -c \"HIVE_ACCOUNT=<handle> bash /c/Users/<you>/code/<repo>/tools/agents/statusline.sh\""
}
```

It starts Git Bash explicitly, so it works whether Claude Code runs the command through cmd, PowerShell or bash.
`HIVE_DRY_RUN=1` in the environment skips the background refresh, the beacon and every GitHub write (for testing).

## What differs from macOS

- Git Bash ignores IANA timezone names (`TZ=America/New_York` silently means UTC), so `hive-env.sh` maps the common
  zones (US, UK, central Europe, India, Japan, eastern Australia) in `TZ` and `HIVE_TZ` to POSIX rules. Another zone:
  set it to a POSIX string, for example `TZ=EET-2EEST,M3.5.0/3,M10.5.0/4`.
- Windows `jq.exe` ends lines with CRLF, which breaks `for`/`read` loops; `hive-env.sh` wraps it with `jq -b` when it
  detects that.
- `.sh` files and `accounts/*.conf` must stay LF. A CRLF checkout breaks bash. Add `tools/agents/** text eol=lf` and
  `hive.conf text eol=lf` to the repo's `.gitattributes` (install.sh prints this).
- No `bc` (`hive-rate.sh` uses awk), no `pgrep` (the install wait in `hive-automerge.sh` is skipped), no desktop
  notification banner (`hive_desktop_notify` is a no-op without `osascript` or `notify-send`).
