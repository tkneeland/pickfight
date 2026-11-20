#!/bin/bash
# Fails (exit 1) when a hive secret appears in tracked files, the staged diff or commits not yet on the main branch: the
# private channel topic or its ntfy access token ($HIVE_STATE/msg.conf HIVE_MSG_TOPIC, HIVE_MSG_TOKEN) or the Discord bot
# token ($HIVE_STATE/discord.conf).
# Usage: hive-msg-leakcheck.sh [repo-dir]   (default: the main checkout). hive-ship.sh runs it before every push.
. "$(dirname "$0")/hive-env.sh" || exit 1
val() { sed -n "s/^$2=//p" "$HIVE_STATE/$1" 2>/dev/null | tr -d '\r"'"'"' ' | head -n 1; }
dir=${1:-$ROOT}; hits=""; n=0
for secret in "$(val msg.conf HIVE_MSG_TOPIC)" "$(val msg.conf HIVE_MSG_TOKEN)" "$(val discord.conf HIVE_DISCORD_TOKEN)"; do
  [ -n "$secret" ] || continue; n=$((n+1))
  h=$(git -C "$dir" grep -I -F -l -- "$secret" 2>/dev/null | tr '\n' ' ')
  if git -C "$dir" diff --cached | grep -F -q -- "$secret"; then h="$h(staged diff) "; fi
  # commits not yet on the main branch: a secret added then removed would still be pushed in history
  if git -C "$dir" log -p "origin/$MAIN_BRANCH..HEAD" 2>/dev/null | grep -F -q -- "$secret"; then h="$h(unpushed commits) "; fi
  hits="$hits$h"
done
[ "$n" -gt 0 ] || { echo "no topic or token configured; skipped"; exit 0; }
if [ -n "$hits" ]; then echo "SECRET LEAK (channel topic or token, or Discord token): $hits"; exit 1; fi
echo ok
