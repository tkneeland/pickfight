# Dot-sourced by the hive-*.ps1 scripts: finds Git Bash and asks hive-env.sh (via hive-supervise.sh state) for the
# account's state dir, %USERPROFILE%\.claude\hive\<repo>\<account> by default, so PowerShell and bash always agree.
function Find-GitBash {
  $cands = @()
  $git = Get-Command git.exe -ErrorAction SilentlyContinue
  if ($git) { $cands += (Join-Path (Split-Path (Split-Path $git.Source)) "bin\bash.exe") }
  $cands += "$env:ProgramFiles\Git\bin\bash.exe", "${env:ProgramFiles(x86)}\Git\bin\bash.exe", "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
  foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }
  throw "Git Bash (bash.exe) not found. Install Git for Windows."
}
function Get-HiveStateDir([string]$Bash, [string]$Here, [string]$Account) {
  $env:HIVE_ACCOUNT = $Account
  $sup = (Join-Path $Here "hive-supervise.sh").Replace("\", "/")
  $unix = (& $Bash --login $sup state 2>$null | Select-Object -Last 1)
  if (-not $unix) { throw "hive-env.sh could not load for $Account (is tools/agents/accounts/$Account.conf there, and hive.conf at the repo root?)" }
  $win = (& $Bash --login -c "cygpath -w '$unix'" 2>$null | Select-Object -Last 1)
  if (-not $win) { $win = $unix }
  New-Item -ItemType Directory -Force $win | Out-Null
  return $win
}
