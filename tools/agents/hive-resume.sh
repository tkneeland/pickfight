#!/bin/bash
# Restarts AT work that stopped on a usage limit, for sessions NOT run by hive-keepalive.sh (e.g. an interactive
# terminal). Run it every 10 min (launchd/hive-resume.plist.template). Zero tokens unless hive_limit_stalled is true; then it
# starts one headless Claude run in ROOT that resumes the in-flight work. If the limit has not reset yet that run fails
# fast and the next tick retries. Sessions under hive-keepalive.sh are nudged in place instead, so skip those.
export PATH="$HOME/.local/bin:$HOME/.bun/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
. "$(dirname "$0")/hive-env.sh" || exit 1
screen -ls 2>/dev/null | grep -q "\.hive-${HIVE_SLUG#*__}-$HIVE_ACCOUNT[[:space:]]" && exit 0   # keepalive owns this one
hive_limit_stalled || exit 0
mkdir "$HIVE_STATE/resume.lock" 2>/dev/null || exit 0
trap 'rmdir "$HIVE_STATE/resume.lock"' EXIT
LOG=$HIVE_STATE/resume.log
echo "$(date '+%F %T %Z') stalled on a usage limit; starting a resume run" >> "$LOG"
prompt="AT resume (headless, started by tools/agents/hive-resume.sh): Claude work in this repo stopped on a usage limit and nothing has run for ${STALL_MINUTES}+ min. Continue the in-flight AT work autonomously under CLAUDE.md and docs/agents/hive.md: resume each open work package from its saved state (verify branches, worktrees and commits first; never duplicate a worker, commit or PR), then keep working ready tickets. Use simple one-line Bash commands. End with a 3-line plain-English summary."
[ "$PRIVATE" = 1 ] && prompt+=" PRIVATE MODE: never mention AT, these tools or usage in any repo, commit, PR or client-facing text."
out=$(cd "$ROOT" && HIVE_SESSION=always-on claude -p "$prompt" </dev/null 2>>"$LOG"); rc=$?
echo "$(date '+%F %T %Z') resume run exit $rc: ${out:0:300}" >> "$LOG"
[ ${#out} -lt 400 ] && echo "$out" | grep -qiE 'limit|rate_limit|429' && exit 0   # still limited: next tick retries
hive_outbox DONE "Resumed AT work after a usage limit: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-400)"
