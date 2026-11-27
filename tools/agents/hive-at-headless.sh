#!/bin/bash
# Headless always-on AT/TM session for this machine (a detached screen never gets the interactive TUI): each run is one
# `claude -p` pass of the AT prompt (hive-keepalive.sh --print-prompt); when it exits the next one starts. Started by
# hive-watchdog.sh. Create ~/.claude/hive/at-headless.pause to hold it between passes. Log: ~/.claude/hive/at-headless.log
export PATH="$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH" HIVE_SESSION=always-on
for v in $(env | grep -o '^CLAUDE[A-Z_]*'); do unset "$v"; done
. "$(dirname "$0")/hive-env.sh" || exit 1
cd "$ROOT" || exit 1
L=$HOME/.claude/hive/at-headless.log; mkdir -p "${L%/*}"
while true; do
  [ -f "$HOME/.claude/hive/at-headless.pause" ] && { sleep 60; continue; }
  git pull -q --ff-only 2>/dev/null
  echo "$(date '+%m-%d %I:%M %p') start" >> "$L"
  claude -p "$(bash tools/agents/hive-keepalive.sh --print-prompt)" --dangerously-skip-permissions </dev/null >> "$L" 2>&1
  echo "$(date '+%m-%d %I:%M %p') exit $?" >> "$L"
  sleep 30
done
