# AT mode on Windows (Git Bash)

Runs the AT watchers without `screen`. Needs Git for Windows (Git Bash), `gh` (logged in) and `jq` on PATH.
`powershell -ExecutionPolicy Bypass` is needed on machines where script execution is restricted.

```powershell
powershell -ExecutionPolicy Bypass -File tools\agents\windows\pf-start.ps1  -Account agage-JG   # hidden watchers
powershell -ExecutionPolicy Bypass -File tools\agents\windows\pf-status.ps1 -Account agage-JG   # running? any wake line?
powershell -ExecutionPolicy Bypass -File tools\agents\windows\pf-stop.ps1   -Account agage-JG
```

- `pf-start.ps1` launches `pf-supervise.sh triage` and `pf-supervise.sh automerge` through Git Bash, hidden, with
  `PF_ACCOUNT` set, and records their pids in `%USERPROFILE%\.claude\pf\<account>\` (`tkneeland`: `%USERPROFILE%\.claude`).
  `-Only triage` or `-Only automerge` starts one. `pf-automerge.sh` really merges green PRs, so start it on purpose.
- The triage supervisor restarts `pf-triage-watch.sh` after every wake. The one wake line it printed goes to
  `triage-wake.txt` (latest, UTC-stamped) and `triage-wake.log`, and `triage-status.json` shows the state. Claude
  (or you) reads it with `pf-status.ps1`, which exits 10 while an unhandled wake line exists; `pf-status.ps1 -Ack`
  marks it handled. After a wake the supervisor waits 5 minutes before polling again.
- `pf-supervise.sh automerge` keeps `pf-automerge.sh` running and appends to `automerge.log`.
- `pf-supervise.sh beacon` runs `pf-beacon.sh` every 15 min to keep your #432 usage beacon current. The status
  line's own background beacon job can die with the status line process on Windows; failures go to `beacon.log`.
  The status line must still run, because it saves `usage-snapshot.json`, which the beacon reads.
- `pf-supervise.sh msg` keeps `pf-msg.sh listen` alive and runs `pf-msg.sh heartbeat` every 60 s (HELLO to the private channel, wake line when a peer goes silent). It needs `pf-msg.conf` in the state folder (`pf-msg.sh init`, then share the topic out of band). `-Only msg` starts just this one; macOS: `screen -dmS pf-msg bash tools/agents/windows/pf-supervise.sh msg`.
- `pf-stop.ps1` kills the supervisors and sweeps any leftover `pf-*.sh` watcher process on the machine.

## Start at logon (Task Scheduler), optional

Nothing here registers anything. To start the watchers whenever you sign in, run once in PowerShell:

```powershell
$a = New-ScheduledTaskAction -Execute "powershell.exe" -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Users\<you>\code\pickfight\tools\agents\windows\pf-start.ps1" -Account <handle>'
$t = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
Register-ScheduledTask -TaskName "Pickfight AT watchers" -Action $a -Trigger $t -Description "AT mode watchers (Git Bash)"
```

Remove it with `Unregister-ScheduledTask -TaskName "Pickfight AT watchers" -Confirm:$false`. Point the path at your
main checkout, not a worktree.

## Claude Code status line

In `%USERPROFILE%\.claude\settings.json` (the path is your main checkout):

```json
"statusLine": {
  "type": "command",
  "command": "\"C:/Program Files/Git/bin/bash.exe\" -c \"PF_ACCOUNT=agage-JG bash /c/Users/agage/code/pickfight/tools/agents/statusline-usage.sh\""
}
```

It starts Git Bash explicitly, so it works whether Claude Code runs the command through cmd, PowerShell or bash.
`PF_DRY_RUN=1` in the environment skips the background refresh and every GitHub write (for testing).

## What differs from macOS

- Git Bash ignores IANA timezone names (`TZ=America/New_York` silently means UTC), so `pf-env.sh` maps the common
  US zones in the account conf to POSIX rules. Another zone: set `TZ` in your conf to a POSIX string, for example
  `CET-1CEST,M3.5.0,M10.5.0/3`.
- Windows `jq.exe` ends lines with CRLF, which breaks `for`/`read` loops; `pf-env.sh` wraps it with `jq -b` when it detects that.
- `.sh` files and `accounts/*.conf` must stay LF (`.gitattributes` enforces it). A CRLF checkout breaks bash.
- No `bc` (`pf-rate.sh` uses awk), no `pgrep` (the install-script wait in `pf-automerge.sh` is skipped), no desktop
  notification banner (`pf_notify` is a no-op without `osascript`), and no `python3` in Git Bash, which
  `pf-scenario-merge.sh` needs: install Python or merge by hand.
