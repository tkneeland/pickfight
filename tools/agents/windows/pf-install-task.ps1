<#
.SYNOPSIS
  Registers (or replaces) the "Pickfight AT watchers" scheduled task: runs pf-start.ps1 at logon and every 5 minutes,
  so a dead watcher (above all the private-channel listener, `msg`) is back within 5 minutes. Owner rule, 2026-11-04:
  the three machines must always be able to talk to each other.
.PARAMETER Account
  GitHub handle (PF_ACCOUNT), e.g. agage-JG or schans2.
.NOTES
  pf-start.ps1 leaves running watchers alone, so the repeat is safe. Also keeps the PC from sleeping while plugged in.
  The task runs with no window at all (conhost --headless). Re-run this script to update a task registered before that.
  Run once: powershell -ExecutionPolicy Bypass -File tools\agents\windows\pf-install-task.ps1 -Account <handle>
  Check:    Get-ScheduledTask -TaskName "Pickfight AT watchers" | Get-ScheduledTaskInfo
#>
param([Parameter(Mandatory = $true)][string]$Account)
$ErrorActionPreference = "Stop"
$start = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "pf-start.ps1"
# conhost --headless: PowerShell's own -WindowStyle Hidden only hides the console after it has opened, so the task
# flashed a window every 5 minutes. A headless console host never shows one (Windows 10 1809+ and 11).
$a = New-ScheduledTaskAction -Execute "conhost.exe" `
  -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$start`" -Account $Account"
$logon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$every5 = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
  -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
Register-ScheduledTask -TaskName "Pickfight AT watchers" -Action $a -Trigger @($logon, $every5) -Settings $s `
  -Description "AT watchers incl. the private channel listener; restarts any that died (every 5 min)" -Force | Out-Null
powercfg /change standby-timeout-ac 0
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $start -Account $Account
Write-Host "Registered 'Pickfight AT watchers' for $Account (logon + every 5 min); AC sleep off."
