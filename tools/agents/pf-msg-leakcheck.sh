#!/bin/bash
# Fails (exit 1) when the private channel topic appears in tracked files or the staged diff of a checkout.
# Usage: pf-msg-leakcheck.sh [repo-dir]   (default: the main checkout). pf-ship.sh runs it before every push.
. "$(dirname "$0")/pf-env.sh" || exit 1
topic=$(sed -n 's/^PF_MSG_TOPIC=//p' "$PF_STATE/pf-msg.conf" 2>/dev/null | head -n 1)
[ -n "$topic" ] || { echo "no topic configured; skipped"; exit 0; }
dir=${1:-$ROOT}
hits=$(git -C "$dir" grep -I -F -l -- "$topic" 2>/dev/null | tr '\n' ' ')
if git -C "$dir" diff --cached | grep -F -q -- "$topic"; then hits="$hits(staged diff) "; fi
# commits not yet on main: a topic added then removed would still be pushed in history
if git -C "$dir" log -p origin/main..HEAD 2>/dev/null | grep -F -q -- "$topic"; then hits="$hits(unpushed commits) "; fi
if [ -n "$hits" ]; then echo "TOPIC LEAK: $hits"; exit 1; fi
echo ok
