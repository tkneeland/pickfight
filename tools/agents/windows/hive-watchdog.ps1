<#
.SYNOPSIS
  One watchdog tick for Windows (claude-hive #121), zero tokens: the twin of hive-watchdog.sh. hive-install-task.ps1 runs it every minute.
  It reads the studio's project stack through Git Bash (hive-stack.sh list: STUDIO_REPO's hive/projects.conf plus this install's
  own repo) and starts what is missing, as hidden background processes:
  - msg and voice supervisors of this install (hive-start.ps1 -Only msg / voice; both exit on their own where they do not apply);
  - one automerger per stacked repo, only while this account is the triagemaster (hive.md rule 7): started when it takes the
    role, stopped within a minute when the role moves or the repo leaves the stack. A repo with its own hive beside this
    checkout (hive.conf, tools/agents, this account's conf) runs that hive's hive-supervise.sh automerge; any other stacked
    repo runs hive-automerge-stack.sh <owner/repo> (gh only).
  The always-on session is the separate "hive AT session" task (hive-keepalive.ps1); keep-awake is set by hive-install-task.ps1.
  Pid files wd-automerge-<repo>.pid in the account's state dir record what this started. HIVE_NO_START=1 starts and stops nothing.
.PARAMETER Account
  GitHub handle (HIVE_ACCOUNT); tools\agents\accounts\<Account>.conf must exist.
#>
param([Parameter(Mandatory = $true)][string]$Account)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "hive-common.ps1")
$bash = Find-GitBash
$root = (Resolve-Path (Join-Path $here "..\..\..")).Path
$agents = (Split-Path -Parent $here).Replace("\", "/")
$env:HIVE_ACCOUNT = $Account
$stateDir = Get-HiveStateDir $bash $here $Account
$checkouts = if ($env:HIVE_CHECKOUT_DIR) { $env:HIVE_CHECKOUT_DIR } else { Split-Path -Parent $root }
function Invoke-Bash([string]$cmd) { & $bash --login -c $cmd 2>$null }
function Test-Pid([string]$file) {
  if (-not (Test-Path $file)) { return $false }
  $p = Get-Process -Id ([int](Get-Content $file)) -ErrorAction SilentlyContinue
  return [bool]($p -and $p.ProcessName -eq "bash")
}
function Stop-Pid([string]$file) {
  if (Test-Path $file) {
    & taskkill.exe /PID ([int](Get-Content $file)) /T /F 2>$null | Out-Null
    Remove-Item $file -Force -ErrorAction SilentlyContinue
  }
}

$repos = @(Invoke-Bash "bash '$agents/hive-stack.sh' list" | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match "/" })
$rootU = $root.Replace("\", "/")
$tm = (Invoke-Bash "cd '$rootU' && . tools/agents/hive-env.sh >/dev/null 2>&1; hive_is_triagemaster && echo 1" | Select-Object -Last 1) -eq "1"
if ($env:HIVE_NO_START) { Write-Host "HIVE_NO_START set: nothing started"; exit 0 }

foreach ($kind in @("msg", "voice")) { & (Join-Path $here "hive-start.ps1") -Account $Account -Only $kind | Out-Null }

$names = @($repos | ForEach-Object { ($_ -split "/")[-1] })
# a repo that left the stack: stop its merger
Get-ChildItem -Path $stateDir -Filter "wd-automerge-*.pid" -ErrorAction SilentlyContinue | ForEach-Object {
  $n = $_.BaseName.Substring("wd-automerge-".Length)
  if ($names -notcontains $n) { Stop-Pid $_.FullName; Write-Host "stopped the automerger of $n (no longer in the stack)" }
}
foreach ($repo in $repos) {
  $n = ($repo -split "/")[-1]
  $pidFile = Join-Path $stateDir "wd-automerge-$n.pid"
  if (-not $tm) { if (Test-Path $pidFile) { Stop-Pid $pidFile; Write-Host "stopped the automerger of $repo (not the triagemaster)" }; continue }
  if (Test-Pid $pidFile) { continue }
  $own = Join-Path $checkouts $n
  $hasHive = (Test-Path (Join-Path $own "hive.conf")) -and (Test-Path (Join-Path $own "tools\agents\windows\hive-supervise.sh")) -and
    (Test-Path (Join-Path $own "tools\agents\accounts\$Account.conf"))
  if (-not $hasHive -and $root -ne $own) {
    # the install's own repo is always run from this checkout
    $self = (Invoke-Bash "cd '$rootU' && . tools/agents/hive-env.sh >/dev/null 2>&1; echo `$REPO" | Select-Object -Last 1)
    if ($repo -ieq "$self") { $own = $root; $hasHive = $true }
  }
  $argv = if ($hasHive) { @("--login", (Join-Path $own "tools\agents\windows\hive-supervise.sh").Replace("\", "/"), "automerge") }
          else { @("--login", "$agents/hive-automerge-stack.sh", $repo) }
  $p = Start-Process -FilePath $bash -ArgumentList $argv -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $stateDir "wd-automerge-$n.out") -RedirectStandardError (Join-Path $stateDir "wd-automerge-$n.err")
  Set-Content -Path $pidFile -Value $p.Id
  Write-Host "automerger of $repo started (pid $($p.Id))"
}
