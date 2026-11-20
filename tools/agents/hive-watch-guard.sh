#!/bin/bash
# Claude Code Stop hook: in AT mode the session may not go idle while the triage watcher isn't running.
# The watcher exits on every event (that exit is what wakes the session), so it must be relaunched after
# each one; forgetting left AT deaf for hours (2026-11-05). This turns "forgot" into a blocked stop.
# Opt-in per machine (the session that runs AT, not a control-panel terminal):
# Install: .claude/settings.local.json → hooks.Stop → command "HIVE_ACCOUNT=<handle> bash <repo>/tools/agents/hive-watch-guard.sh"
in=$(cat)
[ "$(printf '%s' "$in" | jq -r '.stop_hook_active // false' 2>/dev/null)" = true ] && exit 0   # never loop
. "$(dirname "$0")/hive-env.sh" >/dev/null 2>&1 || exit 0
[ "$(cat "$HIVE_STATE/at-mode" 2>/dev/null || echo AT)" = AT ] || exit 0
command -v pgrep >/dev/null 2>&1 || exit 0   # no pgrep (Git Bash): cannot tell, never block
LC_ALL=C pgrep -f "$HIVE_DIR/hive-triage-watch.sh" >/dev/null && exit 0
jq -cn --arg cmd "HIVE_ACCOUNT=$HIVE_ACCOUNT bash $HIVE_DIR/hive-triage-watch.sh" \
  '{decision:"block", reason:("AT mode is on but the triage watcher is not running. Relaunch it with Bash run_in_background: " + $cmd + " (then act on each line it exits with).")}'
