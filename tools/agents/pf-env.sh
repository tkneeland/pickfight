# Source me (bash). Resolves the account and loads tools/agents/accounts/<handle>.conf.
# Account: env PF_ACCOUNT, else `gh api user -q .login` (cached 1 h). Exports PF_ACCOUNT, PF_DIR,
# PF_STATE (per-account local state dir), REPO, ROOT (main checkout), TZ and the conf settings.
PF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
if [ -z "${PF_ACCOUNT:-}" ]; then
  _c=$HOME/.claude/.pf-account-cache
  if [ -f "$_c" ] && [ $(( $(date +%s) - $(stat -f %m "$_c") )) -lt 3600 ]; then PF_ACCOUNT=$(cat "$_c")
  else PF_ACCOUNT=$(gh api user -q .login 2>/dev/null); [ -n "$PF_ACCOUNT" ] && { mkdir -p "$HOME/.claude"; echo "$PF_ACCOUNT" > "$_c"; }; fi
fi
if [ ! -f "$PF_DIR/accounts/${PF_ACCOUNT:-none}.conf" ]; then
  echo "pf-env: no tools/agents/accounts/${PF_ACCOUNT:-<unknown>}.conf (set PF_ACCOUNT or add the conf)" >&2; return 1 2>/dev/null || exit 1
fi
export PF_ACCOUNT PF_DIR
. "$PF_DIR/accounts/_shared.conf"
. "$PF_DIR/accounts/$PF_ACCOUNT.conf"
export TZ REPO
: "${TZ_LABEL:=$(date +%Z)}"
if [ -z "${REPO_PATH:-}" ]; then REPO_PATH=$(dirname "$(git -C "$PF_DIR" rev-parse --path-format=absolute --git-common-dir)"); fi
ROOT=$REPO_PATH
# per-account local state: tkneeland keeps ~/.claude; others get their own subdir so accounts sharing a Mac do not collide
if [ "$PF_ACCOUNT" = tkneeland ]; then PF_STATE=$HOME/.claude; else PF_STATE=$HOME/.claude/pf/$PF_ACCOUNT; fi
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
