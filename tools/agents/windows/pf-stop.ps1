<#
.SYNOPSIS
  Stops the watchers started by pf-start.ps1 (the supervisor and everything it spawned).
#>
param([string]$Account = "agage-JG")
$stateDir = if ($Account -eq "tkneeland") { Join-Path $env:USERPROFILE ".claude" } else { Join-Path $env:USERPROFILE ".claude\pf\$Account" }
foreach ($kind in @("triage", "automerge")) {
  $pidFile = Join-Path $stateDir "$kind.pid"
  if (-not (Test-Path $pidFile)) { Write-Host "$kind : no pid file"; continue }
  $id = [int](Get-Content $pidFile)
  $proc = Get-Process -Id $id -ErrorAction SilentlyContinue
  if ($proc -and $proc.ProcessName -eq "bash") {
    & taskkill.exe /PID $id /T /F | Out-Null   # /T kills the child bash/gh/sleep processes too
    Write-Host "$kind : stopped (pid $id)"
  } else { Write-Host "$kind : not running" }
  Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}
# a killed pf-automerge.sh leaves its lock file behind; the next run sees the dead pid and ignores it
# msys forks are not always children in the Windows process tree, so taskkill /T can miss a running watcher:
# sweep any leftover AT watcher or supervisor started from this checkout's scripts (all accounts on this machine).
Get-CimInstance Win32_Process -Filter "Name='bash.exe'" |
  Where-Object { $_.CommandLine -match 'pf-(supervise|triage-watch|automerge)\.sh' } |
  ForEach-Object { & taskkill.exe /PID $_.ProcessId /T /F | Out-Null; Write-Host "swept leftover watcher (pid $($_.ProcessId))" }
