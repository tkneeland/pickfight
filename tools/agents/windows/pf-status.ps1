<#
.SYNOPSIS
  Shows whether the AT watchers are running and what the triage watcher last woke for.
  Exit code 10 while the triage watcher has a wake line that has not been acknowledged.
.PARAMETER Ack
  Mark the current triage wake line as handled.
#>
param([string]$Account = "agage-JG", [switch]$Ack)
$stateDir = if ($Account -eq "tkneeland") { Join-Path $env:USERPROFILE ".claude" } else { Join-Path $env:USERPROFILE ".claude\pf\$Account" }
foreach ($kind in @("triage", "automerge", "beacon")) {
  $pidFile = Join-Path $stateDir "$kind.pid"
  $state = "stopped"
  if (Test-Path $pidFile) {
    $proc = Get-Process -Id ([int](Get-Content $pidFile)) -ErrorAction SilentlyContinue
    if ($proc -and $proc.ProcessName -eq "bash") { $state = "running (pid $($proc.Id))" } else { $state = "dead (stale pid file)" }
  }
  Write-Host ("{0,-10} {1}" -f $kind, $state)
  $sf = Join-Path $stateDir "$kind-status.json"
  if (Test-Path $sf) { $s = Get-Content $sf -Raw | ConvertFrom-Json; Write-Host ("           last: {0} {1} at {2}" -f $s.state, $s.line, $s.at) }
}
$wake = Join-Path $stateDir "triage-wake.txt"
$ackf = Join-Path $stateDir "triage-wake.acked"
$rc = 0
if (Test-Path $wake) {
  $w = (Get-Content $wake -Raw).Trim()
  $acked = if (Test-Path $ackf) { (Get-Content $ackf -Raw).Trim() } else { "" }
  if ($w -ne $acked) { Write-Host "WAKE (needs Claude): $w"; $rc = 10 } else { Write-Host "wake line already handled: $w" }
  if ($Ack) { Set-Content -Path $ackf -Value $w; $rc = 0 }
} else { Write-Host "no triage wake line yet" }
Write-Host "logs: $stateDir (automerge.log, triage-wake.log, triage-watch.err)"
exit $rc
