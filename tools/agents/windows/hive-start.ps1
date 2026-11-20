<#
.SYNOPSIS
  Starts the AT-mode watchers as hidden background processes via Git Bash (the Windows stand-in for `screen`).
.PARAMETER Account
  GitHub handle (HIVE_ACCOUNT); tools\agents\accounts\<Account>.conf must exist.
.PARAMETER Only
  triage, automerge, beacon, msg, voice, or both (default: all five; voice exits at once without hub.conf).
.NOTES
  State, pid files and logs live in the folder hive-env.sh calls HIVE_STATE (%USERPROFILE%\.claude\hive\<repo>\<Account>).
  Safe to re-run: a watcher that is already running is left alone. In SINGLE_ACCOUNT mode beacon and msg exit at once.
  HIVE_NO_START=1 in the environment starts nothing (for tests).
  Run with: powershell -ExecutionPolicy Bypass -File hive-start.ps1 -Account <handle>
#>
param(
  [Parameter(Mandatory = $true)][string]$Account,
  [ValidateSet("both", "triage", "automerge", "beacon", "msg", "voice")][string]$Only = "both"
)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "hive-common.ps1")
$bash = Find-GitBash
$sup = (Join-Path $here "hive-supervise.sh").Replace("\", "/")
if ($env:HIVE_NO_START) { Write-Host "HIVE_NO_START set: nothing started"; exit 0 }
$stateDir = Get-HiveStateDir $bash $here $Account
$env:HIVE_ACCOUNT = $Account

foreach ($kind in @("triage", "automerge", "beacon", "msg", "voice")) {
  if ($Only -ne "both" -and $Only -ne $kind) { continue }
  $pidFile = Join-Path $stateDir "$kind.pid"
  if (Test-Path $pidFile) {
    $old = Get-Process -Id ([int](Get-Content $pidFile)) -ErrorAction SilentlyContinue
    if ($old -and $old.ProcessName -eq "bash") { Write-Host "$kind already running (pid $($old.Id))"; continue }
  }
  $p = Start-Process -FilePath $bash -ArgumentList @("--login", $sup, $kind) -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $stateDir "$kind-supervisor.out") -RedirectStandardError (Join-Path $stateDir "$kind-supervisor.err")
  Set-Content -Path $pidFile -Value $p.Id
  Write-Host "$kind started (pid $($p.Id)) for $Account; state in $stateDir"
}
