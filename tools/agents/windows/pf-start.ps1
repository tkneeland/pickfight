<#
.SYNOPSIS
  Starts the AT-mode watchers as hidden background processes via Git Bash (the Windows stand-in for `screen`).
.PARAMETER Account
  GitHub handle (PF_ACCOUNT). Default: agage-JG.
.PARAMETER Only
  triage, automerge, beacon, msg, or both (default: all four).
.NOTES
  State, pid files and logs live in %USERPROFILE%\.claude\pf\<Account> (tkneeland: %USERPROFILE%\.claude), the same
  folder pf-env.sh calls PF_STATE. Safe to re-run: a watcher that is already running is left alone.
  Run with: powershell -ExecutionPolicy Bypass -File pf-start.ps1
#>
param(
  [string]$Account = "agage-JG",
  [ValidateSet("both", "triage", "automerge", "beacon", "msg")][string]$Only = "both"
)
$ErrorActionPreference = "Stop"

function Find-GitBash {
  $cands = @()
  $git = Get-Command git.exe -ErrorAction SilentlyContinue
  if ($git) { $cands += (Join-Path (Split-Path (Split-Path $git.Source)) "bin\bash.exe") }
  $cands += "$env:ProgramFiles\Git\bin\bash.exe", "${env:ProgramFiles(x86)}\Git\bin\bash.exe", "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
  foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }
  throw "Git Bash (bash.exe) not found. Install Git for Windows."
}

$bash = Find-GitBash
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sup = (Join-Path $here "pf-supervise.sh").Replace("\", "/")
$stateDir = if ($Account -eq "tkneeland") { Join-Path $env:USERPROFILE ".claude" } else { Join-Path $env:USERPROFILE ".claude\pf\$Account" }
New-Item -ItemType Directory -Force $stateDir | Out-Null
$env:PF_ACCOUNT = $Account

foreach ($kind in @("triage", "automerge", "beacon", "msg")) {
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
