<#
.SYNOPSIS
  Stops the watchers started by hive-start.ps1 (the supervisor and everything it spawned).
#>
param([Parameter(Mandatory = $true)][string]$Account)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "hive-common.ps1")
$stateDir = Get-HiveStateDir (Find-GitBash) $here $Account
foreach ($kind in @("triage", "automerge", "beacon", "msg", "voice")) {
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
# a killed hive-automerge.sh leaves its lock file behind; the next run sees the dead pid and ignores it
# msys forks are not always children in the Windows process tree, so taskkill /T can miss a running watcher: sweep any
# leftover watcher or supervisor started from THIS repo's scripts (another game's hive on this machine keeps running).
$repo = Split-Path -Leaf (Resolve-Path (Join-Path $here "..\..\..")).Path
$rx = "[\\/]" + [regex]::Escape($repo) + "[\\/]tools[\\/]agents[\\/]"
$procs = @(Get-CimInstance Win32_Process)
$ours = @($procs | Where-Object { $_.Name -eq "bash.exe" -and $_.CommandLine -match ($rx + '(windows[\\/])?hive-(supervise|triage-watch|automerge|beacon|msg)\.sh') })
$ourIds = @($ours | ForEach-Object { $_.ProcessId })
# the channel listener's curl.exe is a native process outside the msys process group, and its URL comes in on stdin
# (curl -K -), so it is found by its parent: one of this repo's watcher shells
$procs | Where-Object { $_.Name -eq "curl.exe" -and $ourIds -contains $_.ParentProcessId } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; Write-Host "swept channel listener curl (pid $($_.ProcessId))" }
$ours | ForEach-Object { & taskkill.exe /PID $_.ProcessId /T /F 2>$null | Out-Null; Write-Host "swept leftover watcher (pid $($_.ProcessId))" }
# the hub voice runner is a native node.exe, also outside the msys process group
$procs | Where-Object { $_.Name -eq "node.exe" -and $_.CommandLine -match ($rx + 'hive-voice\.mjs') } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; Write-Host "swept voice runner (pid $($_.ProcessId))" }
# the always-on AT session (hive-keepalive.ps1) and the claude it spawned. The "hive AT session (<repo>, <handle>)" task restarts
# the keepalive within 5 minutes; to stop it for good, unregister that task (see README).
foreach ($k in @("keepalive.pid", "keepalive-claude.pid")) {
  $f = Join-Path $stateDir $k
  if (-not (Test-Path $f)) { continue }
  $id = [int](((Get-Content $f) | Select-Object -First 1) -split ' ')[0]
  $proc = Get-Process -Id $id -ErrorAction SilentlyContinue
  if ($proc) { & taskkill.exe /PID $id /T /F | Out-Null; Write-Host "$k : stopped (pid $id)" }
  Remove-Item $f -Force -ErrorAction SilentlyContinue
}
