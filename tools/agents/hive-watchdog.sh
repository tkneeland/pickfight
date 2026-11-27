#!/bin/bash
# Usage: hive-watchdog.sh [--once]
# The per-machine watchdog (claude-hive #121), zero tokens: every minute it reads the studio's project stack (hive-stack.sh
# list: STUDIO_REPO's hive/projects.conf, cached, plus this install's own REPO) and starts, in detached screens, whatever
# daemon is missing. A repo added to the stack gets its daemons on the next tick; nothing is hand-edited. Nothing here calls
# claude except by starting the headless session (hive-at-headless.sh), which is the one always-on session of this machine.
#   always-on session   hive-at-<repo>-<account>  one headless AT/TM pass loop (hive-at-headless.sh), unless a keepalive
#                       session (hive-<repo>-<account>) already runs. One session covers the whole studio, not one per game.
#   msg, voice          hive-msg-/hive-voice-<repo>-<account>  hive-supervise.sh msg|voice of this install (they exit on their own
#                       where there is no channel or hub, so a restart attempt each minute is harmless)
#   automerger          hive-automerge-<repo>-<account>  one per stacked repo, only while this account holds the triagemaster
#                       role (hive.md rule 7): started when it takes the role, stopped within a minute when the role moves.
#                       A repo with a hive install of its own checked out beside this one (hive.conf, tools/agents and this
#                       account's conf) runs that hive's hive-automerge.sh; any other stacked repo (the hive's own, the
#                       studio's) runs hive-automerge-stack.sh, the same gate with gh alone.
#   legacy              the hand-written stopgap screen hive-automerge-extra-<account> is quit on sight (its job is now the above);
#                       also remove ~/.claude/hive/hive-automerge-extra.sh. Windows: windows/hive-watchdog.ps1, same rules.
#   caffeinate (macOS)  hive-caffeinate-<account>  keeps the machine awake while the hive runs (the display may sleep)
# --once: one tick, then exit (tests; also a manual "start whatever is missing"). Log: ~/.claude/hive/watchdog.log
# Generated wrapper: install.sh runs hive-install-watchdog.sh, which writes ~/.claude/hive/hive-watchdog-<repo>-<account>.sh
# and a login starter for this machine; this file is vendored and refreshed by install.sh like every other script.
export PATH="$PATH:$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
. "$(dirname "$0")/hive-env.sh" || exit 1
WLOG=${HIVE_WATCHDOG_LOG:-$HOME/.claude/hive/watchdog.log}; mkdir -p "${WLOG%/*}"
NAME=${HIVE_SLUG#*__}
log() { echo "$(date '+%m-%d %I:%M %p') $*" >> "$WLOG"; }
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
up() { screen -ls 2>/dev/null | grep -Eq "[0-9]\.($1)[[:space:]]"; }
start() {  # start <screen name> <why> <command...>
  local n=$1 w=$2; shift 2
  screen -dmS "$n" "$@" && log "started $w ($n)"
}
stop() { screen -S "$1" -X quit >/dev/null 2>&1 && log "stopped $2 ($1)"; }
# a hive install of its own, checked out beside this one, that this account can run
own_hive() {  # <owner/repo> -> prints its checkout dir
  local d
  if [ "$(lc "$1")" = "$(lc "${REPO:-}")" ]; then d=$ROOT; else d=$HIVE_CHECKOUT_DIR/${1#*/}; fi
  [ -f "$d/hive.conf" ] && [ -f "$d/tools/agents/windows/hive-supervise.sh" ] && [ -f "$d/tools/agents/accounts/$HIVE_ACCOUNT.conf" ] || return 1
  echo "$d"
}

tick() {
  local tm=0 repo d n
  hive_is_triagemaster && tm=1
  # the hand-written stopgap merger of claude-hive #121 (hive-automerge-extra.sh): replaced by the per-repo ones below
  up "hive-automerge-extra-$HIVE_ACCOUNT" && stop "hive-automerge-extra-$HIVE_ACCOUNT" "the legacy stopgap automerger"
  local stacked=" " recorded=$HIVE_STATE/watchdog-automergers
  if [ "$HIVE_OS" = Darwin ] && command -v caffeinate >/dev/null 2>&1; then
    up "hive-caffeinate-$HIVE_ACCOUNT" || start "hive-caffeinate-$HIVE_ACCOUNT" caffeinate caffeinate -is
  fi
  up "hive-at-$NAME-$HIVE_ACCOUNT|hive-at-$HIVE_ACCOUNT|hive-$NAME-$HIVE_ACCOUNT" \
    || start "hive-at-$NAME-$HIVE_ACCOUNT" "always-on session" bash "$HIVE_DIR/hive-at-headless.sh"
  for n in msg voice; do
    up "$(hive_screen $n)" || start "$(hive_screen $n)" "$n supervisor" bash -c "cd $(printf %q "$ROOT") && exec bash tools/agents/windows/hive-supervise.sh $n"
  done
  while read -r repo; do
    [ -n "$repo" ] || continue
    stacked+="${repo#*/} "
    n=hive-automerge-${repo#*/}-$HIVE_ACCOUNT
    if [ $tm = 0 ]; then up "$n" && stop "$n" "automerger of $repo (not the triagemaster)"; continue; fi
    up "$n" && continue
    grep -qxF "${repo#*/}" "$recorded" 2>/dev/null || echo "${repo#*/}" >> "$recorded"
    if d=$(own_hive "$repo"); then
      start "$n" "automerger of $repo" bash -c "cd $(printf %q "$d") && exec bash tools/agents/windows/hive-supervise.sh automerge"
    else
      start "$n" "gh-only automerger of $repo" bash "$HIVE_DIR/hive-automerge-stack.sh" "$repo"
    fi
  done < <(bash "$HIVE_DIR/hive-stack.sh" list 2>/dev/null)
  # a repo that left the stack: stop the automerger this watchdog started for it (only when the stack was read at all)
  if [ "$stacked" != " " ] && [ -f "$recorded" ]; then
    local keep=""
    while read -r n; do
      [ -n "$n" ] || continue
      case "$stacked" in *" $n "*) keep+="$n"$'\n'; continue;; esac
      stop "hive-automerge-$n-$HIVE_ACCOUNT" "automerger of $n (no longer in the stack)"
    done < "$recorded"
    printf '%s' "$keep" > "$recorded"
  fi
}

[ "${1:-}" = --once ] && { tick; exit 0; }
while true; do tick; sleep 60; done
