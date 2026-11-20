<#
.SYNOPSIS
  Registers (or replaces) two scheduled tasks for the account:
  - "hive AT watchers (<repo>, <Account>)": runs hive-start.ps1 at logon and every 5 minutes, so a dead watcher (above all the
    private-channel listener, `msg`) is back within 5 minutes and the machines in the hive can always reach each other.
  - "hive AT session (<repo>, <Account>)": runs hive-keepalive.ps1 at logon and every 5 minutes, which keeps ONE always-on headless
    Claude session running the AT prompt. Nobody needs a terminal open (skip it with -NoSession).
.PARAMETER Account
  GitHub handle (HIVE_ACCOUNT).
.PARAMETER NoSession
  Register only the watcher task (the old behaviour).
.PARAMETER SkipPermissions
  Passed to hive-keepalive.ps1: run the headless session with --dangerously-skip-permissions. Off by default; without it
  the session uses your own Claude settings, whose allow rules must cover git, gh, bash and the hive scripts.
.NOTES
  hive-start.ps1 and hive-keepalive.ps1 leave a running copy alone, so the repeat is safe. Also keeps the PC from
  sleeping while plugged in. Both tasks run with no window at all (conhost --headless).
  Run once: powershell -ExecutionPolicy Bypass -File tools\agents\windows\hive-install-task.ps1 -Account <handle>
  Check:    Get-ScheduledTask -TaskName "hive AT watchers (<repo>, <handle>)" | Get-ScheduledTaskInfo
            powershell -ExecutionPolicy Bypass -File tools\agents\windows\hive-status.ps1 -Account <handle>
#>
param([Parameter(Mandatory = $true)][string]$Account, [switch]$NoSession, [switch]$SkipPermissions)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$start = Join-Path $here "hive-start.ps1"
$keepalive = Join-Path $here "hive-keepalive.ps1"
$repo = Split-Path -Leaf (Resolve-Path (Join-Path $here "..\..\..")).Path   # one task pair per game on a machine
$name = "hive AT watchers ($repo, $Account)"
# conhost --headless: PowerShell's own -WindowStyle Hidden only hides the console after it has opened, so the task
# flashed a window every 5 minutes. A headless console host never shows one (Windows 10 1809+ and 11).
$a = New-ScheduledTaskAction -Execute "conhost.exe" `
  -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$start`" -Account $Account"
$logon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$every5 = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
  -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
Register-ScheduledTask -TaskName $name -Action $a -Trigger @($logon, $every5) -Settings $s `
  -Description "AT watchers incl. the private channel listener; restarts any that died (every 5 min)" -Force | Out-Null
powercfg /change standby-timeout-ac 0
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $start -Account $Account
Write-Host "Registered '$name' (logon + every 5 min); AC sleep off."

if (-not $NoSession) {
  $sname = "hive AT session ($repo, $Account)"
  $extra = if ($SkipPermissions) { " -SkipPermissions" } else { "" }
  $sa = New-ScheduledTaskAction -Execute "conhost.exe" `
    -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$keepalive`" -Account $Account$extra"
  # the keepalive loops forever: no execution time limit; a second copy exits at once (pid file), so the repeat only revives a dead one
  $ss = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)
  Register-ScheduledTask -TaskName $sname -Action $sa -Trigger @($logon, $every5) -Settings $ss `
    -Description "Always-on headless Claude AT session (hive-keepalive.ps1); restarts it if it died" -Force | Out-Null
  Start-ScheduledTask -TaskName $sname
  Write-Host "Registered '$sname' (logon + every 5 min); the AT session now runs with no terminal open."
  if (-not $SkipPermissions) { Write-Host "Note: the session uses your Claude permission rules; add -SkipPermissions to run it unattended with all prompts bypassed." }
}
