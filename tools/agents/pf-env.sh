# Source me (bash). Resolves the account and loads tools/agents/accounts/<handle>.conf.
# Account: env PF_ACCOUNT, else `gh api user -q .login` (cached 1 h). Exports PF_ACCOUNT, PF_DIR,
# PF_STATE (per-account local state dir), REPO, ROOT (main checkout), TZ and the conf settings.
PF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
# Portable time/file helpers: GNU (Linux, Git Bash on Windows) and BSD (macOS) forms. Defined first, used below.
if date --version >/dev/null 2>&1; then PF_GNU=1; else PF_GNU=0; fi
pf_mtime() { if [ "$PF_GNU" = 1 ]; then stat -c %Y "$1" 2>/dev/null; else stat -f %m "$1" 2>/dev/null; fi; }   # file mtime, epoch s
pf_iso_to_epoch() { if [ "$PF_GNU" = 1 ]; then date -u -d "$1" +%s 2>/dev/null; else date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null; fi; }   # 2026-10-22T15:00:42Z -> epoch (fails on bad input)
pf_epoch_fmt() { local e=${1%.*}; if [ "$PF_GNU" = 1 ]; then date -d "@$e" "$2"; else date -r "$e" "$2"; fi; }   # pf_epoch_fmt <epoch> <+format>
pf_notify() { command -v osascript >/dev/null 2>&1 && osascript -e "display notification \"$1\" with title \"Pickfight\"" 2>/dev/null; return 0; }   # macOS banner; no-op elsewhere
# Windows jq.exe ends lines with CRLF, which survives $(...) and breaks every comparison; --binary turns that off. Only wrapped when needed.
case "$(command jq -n -r '"x","y"' 2>/dev/null)" in *$'\r'*) jq() { command jq -b "$@"; };; esac
if [ -z "${PF_ACCOUNT:-}" ]; then
  _c=$HOME/.claude/.pf-account-cache
  if [ -f "$_c" ] && [ $(( $(date +%s) - $(pf_mtime "$_c") )) -lt 3600 ]; then PF_ACCOUNT=$(cat "$_c")
  else PF_ACCOUNT=$(gh api user -q .login 2>/dev/null); [ -n "$PF_ACCOUNT" ] && { mkdir -p "$HOME/.claude"; echo "$PF_ACCOUNT" > "$_c"; }; fi
fi
if [ ! -f "$PF_DIR/accounts/${PF_ACCOUNT:-none}.conf" ]; then
  echo "pf-env: no tools/agents/accounts/${PF_ACCOUNT:-<unknown>}.conf (set PF_ACCOUNT or add the conf)" >&2; return 1 2>/dev/null || exit 1
fi
export PF_ACCOUNT PF_DIR
. "$PF_DIR/accounts/_shared.conf"
. "$PF_DIR/accounts/$PF_ACCOUNT.conf"
# Git Bash (MSYS) does not know IANA zone names and silently falls back to UTC: translate the common US ones to POSIX rules.
if [ "$PF_GNU" = 1 ] && [ "$(TZ=$TZ date +%Z)" = GMT ]; then
  case $TZ in
    America/New_York|America/Detroit|US/Eastern) TZ=EST5EDT,M3.2.0,M11.1.0;;
    America/Chicago|US/Central) TZ=CST6CDT,M3.2.0,M11.1.0;;
    America/Denver|US/Mountain) TZ=MST7MDT,M3.2.0,M11.1.0;;
    America/Los_Angeles|US/Pacific) TZ=PST8PDT,M3.2.0,M11.1.0;;
    America/Phoenix) TZ=MST7;;
  esac
fi
export TZ REPO
: "${TZ_LABEL:=$(date +%Z)}"
if [ -z "${REPO_PATH:-}" ]; then REPO_PATH=$(dirname "$(git -C "$PF_DIR" rev-parse --path-format=absolute --git-common-dir)"); fi
ROOT=$REPO_PATH
# per-account local state: tkneeland keeps ~/.claude; others get their own subdir so accounts sharing a Mac do not collide
# PF_STATE_DIR in the environment (tests, fixtures) wins over the computed dir. A distinct name, because
# PF_STATE itself is exported and would otherwise leak from one account's script into another's.
if [ -n "${PF_STATE_DIR:-}" ]; then PF_STATE=$PF_STATE_DIR
elif [ "$PF_ACCOUNT" = tkneeland ]; then PF_STATE=$HOME/.claude; else PF_STATE=$HOME/.claude/pf/$PF_ACCOUNT; fi
mkdir -p "$PF_STATE"; export PF_STATE ROOT

pf_handles() { for f in "$PF_DIR"/accounts/*.conf; do b=$(basename "$f" .conf); case $b in _*) ;; *) echo "$b";; esac; done; }
pf_rank1() { for h in $(pf_handles); do grep -q '^SUCCESSION_RANK=1\b' "$PF_DIR/accounts/$h.conf" && echo "$h"; done | head -1; }
pf_triagemaster() { cat "$PF_STATE/pf-triagemaster" 2>/dev/null || pf_rank1; }
pf_is_triagemaster() { [ "$(pf_triagemaster)" = "$PF_ACCOUNT" ]; }
pf_weekly_used() { jq -r '.rate_limits.seven_day.used_percentage // 0 | floor' "$PF_STATE/usage-snapshot.json" 2>/dev/null || echo 0; }
pf_weekly_reset() { jq -r '.rate_limits.seven_day.resets_at // 0 | floor' "$PF_STATE/usage-snapshot.json" 2>/dev/null || echo 0; }
# 0 when dispatching is allowed: under HANDOFF_WEEKLY_USED, or inside the last RESET_GRACE_HOURS before the weekly reset
pf_budget_ok() {
  [ "$(pf_weekly_used)" -lt "$HANDOFF_WEEKLY_USED" ] && return 0
  r=$(pf_weekly_reset); [ "$r" -gt 0 ] && [ $(( r - $(date +%s) )) -le $(( RESET_GRACE_HOURS * 3600 )) ]
}
# pf_live_agents: issue numbers (one per line, deduped) of this checkout's worktrees on an issue branch (issue-N or
# <type>/N-) whose issue is still open and that something wrote to in the last 30 min. Idle leftovers from finished
# or stalled runs don't count.
pf_live_agents() {
  local open; open=" $(gh issue list -R "$REPO" --state open -L 300 --json number -q '.[].number' 2>/dev/null | tr '\n' ' ') "
  git -C "$ROOT" worktree list --porcelain | awk '/^worktree /{w=$2} /^branch /{sub("refs/heads/","",$2); print w, $2}' |
  while read -r wt b; do
    i=$(echo "$b" | sed -nE 's/.*issue-([0-9]+).*/\1/p; s#^[a-z]+/([0-9]+)-.*#\1#p' | head -1); [ -n "$i" ] || continue
    case "$open" in *" $i "*) ;; *) continue;; esac
    gd=$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null)
    { [ -n "$(find "$gd/index" "$gd/HEAD" -mmin -30 2>/dev/null)" ] ||
      [ -n "$(find "$wt" -path "$wt/.godot" -prune -o -path "$wt/.git" -prune -o -type f -mmin -30 -print 2>/dev/null | head -1)" ]; } && echo "$i"
  done | sort -un
}
pf_five_h_used() { jq -r '.rate_limits.five_hour.used_percentage // 0 | floor' "$PF_STATE/usage-snapshot.json" 2>/dev/null || echo 0; }
# worker target right now: the mode's DAY_AGENTS / NIGHT_AGENTS, 1 once the 5h window reaches FIVE_H_SLOW_USED,
# 0 at FIVE_H_STOP_USED or when the weekly budget says stop. Start workers only while running < target; never above it.
pf_worker_target() {
  pf_budget_ok || { echo 0; return; }
  local f; f=$(pf_five_h_used)
  if [ "$f" -ge "$FIVE_H_STOP_USED" ]; then echo 0; elif [ "$f" -ge "$FIVE_H_SLOW_USED" ]; then echo 1
  elif [ "$(pf_daynight)" = day ]; then echo "$DAY_AGENTS"; else echo "$NIGHT_AGENTS"; fi
}
# prints "day" or "night" (ignores MT mode)
pf_daynight() {
  h=$(date +%H); h=$((10#$h)); u=$(cat "$PF_STATE/pf-day-until" 2>/dev/null || echo 0)
  if [ "$(date +%s)" -lt "$u" ] || { [ "$h" -ge "$NIGHT_END" ] && [ "$h" -lt "$NIGHT_START" ]; }; then echo day; else echo night; fi
}
# pf_beacon <handle>: sets b_age (s, 999999 if none) b_p5 b_r5 b_used b_reset (7d) b_at (ISO stamp) from the handle's
# newest USAGE message in $PF_STATE/msg-inbox.log ("<5h>% <7d>% <7d reset ISO> r5=<5h reset ISO> agents=<n> [at=<ISO>]",
# filled by pf-msg.sh listen/backfill), or from this account's own usage-snapshot.json. Percent values are floored and
# empty when unknown ("?", or a 1970 reset). The age is from at= (when the snapshot was taken) when present.
# Run pf_usage_backfill first so a machine that was off does not decide on an empty or stale inbox.
pf_beacon() {
  local line rest ts e w p7 r7; b_age=999999; b_p5=""; b_r5=""; b_used=""; b_reset=""; b_at=""
  if [ "$1" = "$PF_ACCOUNT" ]; then
    local snap=$PF_STATE/usage-snapshot.json; [ -s "$snap" ] || return 0
    e=$(pf_mtime "$snap") || return 0
    rest=$(jq -r '"\(.rate_limits.five_hour.used_percentage // "?"|if type=="number" then floor else . end)% \(.rate_limits.seven_day.used_percentage // "?"|if type=="number" then floor else . end)% \(.rate_limits.seven_day.resets_at // 0|floor|todate) r5=\(.rate_limits.five_hour.resets_at // 0|floor|todate)"' "$snap" 2>/dev/null) || return 0
  else
    line=$(awk -F'|' -v h="$1" '$2==h && $3=="USAGE" && $1+0>=m {m=$1+0; l=$0} END {print l}' "$PF_STATE/msg-inbox.log" 2>/dev/null)
    [ -n "$line" ] || return 0
    e=${line%%|*}; e=${e%.*}; rest=${line#*|*|*|}
    ts=$(echo "$rest" | sed -n 's/.* at=\([0-9TZ:-]*\).*/\1/p'); [ -n "$ts" ] && { w=$(pf_iso_to_epoch "$ts") && e=$w; }
  fi
  b_age=$(( $(date +%s) - e )); b_at=$(TZ=UTC pf_epoch_fmt "$e" +%Y-%m-%dT%H:%M:%SZ)
  read -r b_p5 p7 r7 _ <<EOT
$rest
EOT
  b_p5=${b_p5%\%}; b_p5=${b_p5%.*}; p7=${p7%\%}; p7=${p7%.*}
  b_r5=$(echo "$rest" | sed -n 's/.*r5=\([0-9TZ:-]*\).*/\1/p')
  case $b_p5 in ''|*[!0-9]*) b_p5="";; esac
  case $b_r5 in 1970-01-01*) b_p5=""; b_r5="";; esac
  case $p7 in ''|*[!0-9]*) p7="";; esac
  case $r7 in 1970-01-01*|'') p7=""; r7="";; esac
  b_used=$p7; b_reset=$r7
}
# pf_usage_backfill: when the inbox's newest USAGE line is missing or 30+ min old (listener down, machine was off; a
# live listener gets one every 15 min per account), fills it from the channel's cache (pf-msg.sh backfill: ntfy poll of
# the last 12h) before anyone reads beacons. At most one poll per 15 min (stamp file), so a failing poll is not retried
# every tick and a backfill that found nothing is retried soon, not after 6h.
pf_usage_backfill() {
  local n m s; n=$(date +%s)
  m=$(awk -F'|' '$3=="USAGE" && $1+0>m {m=$1+0} END {print m+0}' "$PF_STATE/msg-inbox.log" 2>/dev/null); m=${m:-0}
  [ $(( n - ${m%.*} )) -lt 1800 ] && return 0
  s=$(pf_mtime "$PF_STATE/.msg-backfill-last" || true); s=${s:-0}
  [ $(( n - s )) -lt 900 ] && return 0
  touch "$PF_STATE/.msg-backfill-last"
  bash "$PF_DIR/pf-msg.sh" backfill >/dev/null 2>&1 || true
}
# pf_channel_fresh: 0 when the inbox holds at least one other account's USAGE line under 6h old. With none (no channel
# configured, listener down and backfill failed) there is no beacon evidence: callers make no decision.
pf_channel_fresh() {
  awk -F'|' -v me="$PF_ACCOUNT" -v now="$(date +%s)" '$3=="USAGE" && $2!=me && now-$1<21600 {f=1} END {exit !f}' "$PF_STATE/msg-inbox.log" 2>/dev/null
}
