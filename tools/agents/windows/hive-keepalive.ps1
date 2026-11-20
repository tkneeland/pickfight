<#
.SYNOPSIS
  Keeps one always-on headless Claude session running the AT prompt (the Windows stand-in for hive-keepalive.sh, which
  needs `screen`). Nobody has to keep a terminal open: when the session ends, hits a usage limit or crashes, the next one
  starts after a short pause.
.PARAMETER Account
  GitHub handle (HIVE_ACCOUNT); tools\agents\accounts\<Account>.conf must exist.
.PARAMETER SkipPermissions
  Opt in to `--dangerously-skip-permissions` for the headless session. Without it the session runs under your own Claude
  settings (an unattended `claude -p` cannot answer permission prompts, so the allow rules must cover git, gh, bash and
  the hive scripts). It is off by default on purpose: turn it on only on a machine you trust with unattended AT work.
.PARAMETER ClaudeArgs
  Extra arguments for claude.exe, for example --permission-mode acceptEdits or --model sonnet. Per-machine args can also go
  one per line in keepalive-args.txt in the state folder (lines starting with # are ignored).
.PARAMETER PauseSec
  Seconds to wait after a session ends before starting the next one (default 60). A session that ends in under
  ShortRunSec (a usage limit, a crash loop) waits BackoffSec instead (default 600) so it never spins.
.PARAMETER ClaudePath
  Path of the claude executable (default: found on PATH or in ~.localbin); for tests.
.PARAMETER Once
  Run a single session and exit (for testing).
.NOTES
  Safe to start twice: a second copy sees the first one's pid file and exits. The prompt is the same one the screen
  keepalive uses (hive-keepalive.sh --print-prompt), rebuilt for every session so edits to hive-session-prompt.md and
  the account conf apply at once. The session is stateless by design: AT mode reads its state from GitHub, the private
  channel and the repo, so a fresh session picks up where the last one stopped.
  State and logs: keepalive.pid, keepalive-status.json, keepalive.log, keepalive-session.out/.err in HIVE_STATE.
  Run with: powershell -ExecutionPolicy Bypass -File hive-keepalive.ps1 -Account <handle>
#>
param(
  [Parameter(Mandatory = $true)][string]$Account,
  [switch]$SkipPermissions,
  [string[]]$ClaudeArgs = @(),
  [int]$PauseSec = 60,
  [int]$ShortRunSec = 120,
  [int]$BackoffSec = 600,
  [string]$ClaudePath = "",
  [switch]$Once
)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "hive-common.ps1")
$bash = Find-GitBash
$stateDir = Get-HiveStateDir $bash $here $Account
$env:HIVE_ACCOUNT = $Account
$env:HIVE_SESSION = "always-on"
$repoRoot = (Resolve-Path (Join-Path $here "..\..\..")).Path
$log = Join-Path $stateDir "keepalive.log"
$pidFile = Join-Path $stateDir "keepalive.pid"
$statusFile = Join-Path $stateDir "keepalive-status.json"

function Write-Log([string]$m) { Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $m) }
function Set-Status([string]$state, [string]$extra = "") {
  @{ state = $state; line = $extra; at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") } | ConvertTo-Json | Set-Content -Path $statusFile
}
function Find-Claude {
  $c = Get-Command claude.exe -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  foreach ($p in @("$env:USERPROFILE\.local\bin\claude.exe", "$env:APPDATA\npm\claude.cmd", "$env:LOCALAPPDATA\Programs\claude\claude.exe")) {
    if (Test-Path $p) { return $p }
  }
  throw "claude.exe not found (looked on PATH, ~\.local\bin, %APPDATA%\npm)."
}

# one keepalive per account per machine. The pid file is "<pid> <start time ticks>": a live process with another start
# time is a recycled pid, not a running keepalive.
if (Test-Path $pidFile) {
  $parts = ((Get-Content $pidFile) | Select-Object -First 1) -split ' '
  $old = Get-Process -Id ([int]$parts[0]) -ErrorAction SilentlyContinue
  if ($old -and $old.Id -ne $PID -and $old.ProcessName -like "powershell*" -and $parts.Count -gt 1 -and [string]$old.StartTime.ToUniversalTime().Ticks -eq $parts[1]) { Write-Host "keepalive already running (pid $($old.Id))"; exit 0 }
}
Set-Content -Path $pidFile -Value "$PID $((Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks)"
$claude = if ($ClaudePath) { $ClaudePath } else { Find-Claude }
$keep = (Join-Path $here "..\hive-keepalive.sh").Replace("\", "/")
$promptFile = Join-Path $stateDir "keepalive-prompt.txt"
Write-Log "keepalive started for $Account (pid $PID, claude $claude)"
Set-Status "running" "starting"

while ($true) {
  try {
    # the same prompt the screen keepalive builds (placeholders filled from hive.conf and the account conf)
    $prompt = (& $bash --login $keep --print-prompt 2>$null) -join "`n"
    if ([string]::IsNullOrWhiteSpace($prompt)) { throw "hive-keepalive.sh --print-prompt gave no prompt" }
    # This is a headless one-shot run on Windows, not an interactive session: the watcher supervisors (triage, automerge,
    # beacon, msg) already run as background processes, and a background Bash command needs approval nobody can give.
    $prompt += "`n`nHEADLESS RUN (Windows keepalive): you are a one-shot claude -p session; the keepalive starts the next one after you exit. Do NOT start hive-triage-watch.sh or hive-watch-peers.sh: the supervisors already run them. Read the wake line with: bash tools/agents/hive-wake.sh (exit 10 = a WAKE to handle); after handling it run: bash tools/agents/hive-wake.sh --ack. Run hive-pace.sh, do the AT work that is ready now with short foreground commands only, then exit with a one-line summary. NO PERMISSION PROMPTS CAN BE ANSWERED in this run, so: use the Bash tool only (never the PowerShell tool, never powershell.exe from Bash: a nested PowerShell is always refused); HIVE_ACCOUNT=$Account is already in your environment, so run every script bare (bash tools/agents/<script>.sh), never with a VAR=value prefix; one command per Bash call, with no pipes, ; or && chains (each part needs its own allow rule); put these same rules in every subagent's prompt."
    [System.IO.File]::WriteAllText($promptFile, $prompt, (New-Object System.Text.UTF8Encoding($false)))
    $argList = @("-p") + $ClaudeArgs
    # per-machine extra args, one per line, in keepalive-args.txt in the state folder (never committed): the permission
    # allowlist for the unattended session, for example --permission-mode / acceptEdits / --allowedTools / Bash(git:*)
    $argFile = Join-Path $stateDir "keepalive-args.txt"
    if (Test-Path $argFile) { $argList += @(Get-Content $argFile | Where-Object { $_.Trim() -ne "" -and -not $_.TrimStart().StartsWith("#") } | ForEach-Object { $_.Trim() }) }
    # Start-Process joins the array with spaces and no quoting: quote an argument that contains whitespace
    $argList = @($argList | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } })
    if ($SkipPermissions) { $argList += "--dangerously-skip-permissions" }
    $started = Get-Date
    Write-Log "session starting"
    Set-Status "session" ("started " + $started.ToUniversalTime().ToString("HH:mm:ss") + "Z")
    # the prompt goes in on stdin (no quoting limits); the session runs hidden in the repo root
    $p = Start-Process -FilePath $claude -ArgumentList $argList -WorkingDirectory $repoRoot -WindowStyle Hidden -PassThru `
      -RedirectStandardInput $promptFile `
      -RedirectStandardOutput (Join-Path $stateDir "keepalive-session.out") -RedirectStandardError (Join-Path $stateDir "keepalive-session.err")
    Set-Content -Path (Join-Path $stateDir "keepalive-claude.pid") -Value $p.Id
    $p.WaitForExit()
    $ran = [int]((Get-Date) - $started).TotalSeconds
    Write-Log "session ended after ${ran}s (exit $($p.ExitCode))"
    $wait = if ($ran -lt $ShortRunSec) { $BackoffSec } else { $PauseSec }
  } catch {
    Write-Log "error: $($_.Exception.Message)"
    $wait = $BackoffSec
  }
  if ($Once) { break }
  Set-Status "waiting" "next session in ${wait}s"
  Start-Sleep -Seconds $wait
}
Remove-Item $pidFile -ErrorAction SilentlyContinue
Set-Status "stopped"
