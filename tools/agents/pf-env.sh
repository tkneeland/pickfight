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
# prints "day" or "night" (ignores MT mode)
pf_daynight() {
  h=$(date +%H); h=$((10#$h)); u=$(cat "$PF_STATE/pf-day-until" 2>/dev/null || echo 0)
  if [ "$(date +%s)" -lt "$u" ] || { [ "$h" -ge "$NIGHT_END" ] && [ "$h" -lt "$NIGHT_START" ]; }; then echo day; else echo night; fi
}
# pf_beacon <handle> <#432 comments JSON>: sets b_age (s, 999999 if none) b_p5 b_r5 b_used b_reset (7d) from the handle's own
# latest beacon comment. Percent values are floored; empty when the beacon shows "?". Resets are ISO strings.
pf_beacon() {
  local body ts e; body=$(echo "$2" | jq -r --arg h "$1" '[.[]|select(.user.login==$h and (.body|startswith("\($h) usage @")))]|last|.body // empty')
  ts=$(echo "$body" | sed -n 's/.*usage @ \([0-9TZ:-]*\).*/\1/p' | head -1)
  b_age=999999; [ -n "$ts" ] && e=$(pf_iso_to_epoch "$ts") && b_age=$(( $(date +%s) - e ))
  b_p5=$(echo "$body" | sed -n 's/^5h: \([0-9.]*\)%.*/\1/p' | head -1); b_p5=${b_p5%.*}
  b_r5=$(echo "$body" | sed -n 's/^5h:.*resets \([0-9TZ:-]*\)).*/\1/p' | head -1)
  b_used=$(echo "$body" | sed -n 's/^7d: \([0-9.]*\)%.*/\1/p' | head -1); b_used=${b_used%.*}
  b_reset=$(echo "$body" | sed -n 's/^7d:.*resets \([0-9TZ:-]*\)).*/\1/p' | head -1)
}
