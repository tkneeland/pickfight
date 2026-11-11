#!/bin/bash
# Triagemaster self-check (autotriage.md rule 19). One pass, zero tokens: prints one PASS / WARN / FAIL / INFO line per
# duty, each FAIL with the fix, and exits 1 when anything FAILs. Run it at AT session start, on taking the role
# (succession), and when the watcher wakes with TM_CHECK_FAIL (every 6h it runs this for you).
#   pf-tm-check.sh            all checks
#   pf-tm-check.sh --quiet    print only WARN / FAIL lines (the watcher uses this)
# PF_TM_CHECK_SKIP_PROCS=1 skips the running-process checks (tests).
. "$(dirname "$0")/pf-env.sh" || exit 1
QUIET=0; [ "${1:-}" = --quiet ] && QUIET=1
fails=0
say() { case $1 in FAIL) fails=$((fails+1));; esac
  [ "$QUIET" = 1 ] && [ "$1" != FAIL ] && [ "$1" != WARN ] && return 0; echo "$*"; }
running() { pgrep -f "$1" >/dev/null 2>&1 || ps -ef 2>/dev/null | grep -v grep | grep -q -- "$1"; }

# 1. Role. Every other check still runs, so a stand-in can verify itself before taking over.
tm=$(pf_triagemaster)
if pf_is_triagemaster; then say PASS "triagemaster is $PF_ACCOUNT"
else say INFO "triagemaster is $tm, not $PF_ACCOUNT (checks below are for whoever holds the role)"; fi

# 2. AT mode on (rule 1).
mode=$(bash "$PF_DIR/pf-at-mode.sh" 2>/dev/null)
case $mode in AT*) say PASS "mode $mode";; *) say WARN "mode is ${mode:-unknown}: in MT the triagemaster does nothing on its own (owner turns AT back on)";; esac

# 3. GitHub access (filing, labels, merges).
if gh api user -q .login >/dev/null 2>&1; then say PASS "gh signed in as $(gh api user -q .login 2>/dev/null)"
else say FAIL "gh is not signed in: run gh auth login"; fi

# 4. Watchers alive. The triage watcher is the only thing that wakes the session for untriaged tickets, peer
#    messages and Discord reports; after handling a wake line it must be restarted at once.
if [ "${PF_TM_CHECK_SKIP_PROCS:-0}" != 1 ]; then
  if running pf-triage-watch.sh; then say PASS "triage watcher running"
  else say FAIL "triage watcher not running: restart it (bash tools/agents/pf-triage-watch.sh in the background, or screen -dmS pf-triage bash tools/agents/windows/pf-supervise.sh triage)"; fi
  if running "pf-msg.sh listen"; then say PASS "private channel listener running"
  else say FAIL "private channel listener not running: screen -dmS pf-msg bash tools/agents/windows/pf-supervise.sh msg (rule 17: never stays down)"; fi
  if running pf-automerge.sh; then say PASS "automerge running"
  else say WARN "automerge not running: green review-passed PRs wait (screen -dmS pf-automerge bash tools/agents/windows/pf-supervise.sh automerge)"; fi
fi
if pf_channel_fresh 2>/dev/null; then say PASS "peer beacons fresh on the private channel"
else say WARN "no peer USAGE beacon under 6h old: peers may be offline, or this listener is deaf (check pf-msg.conf)"; fi

# 5. Discord #bug-reports (rule 18).
if [ ! -f "$PF_STATE/pf-discord.conf" ]; then
  say FAIL "no $PF_STATE/pf-discord.conf: Discord #bug-reports is NOT being watched. Write PF_DISCORD_TOKEN=<bot token> there (ask the owner via pf-msg.sh send ASK; never commit it)"
else
  out=$(bash "$PF_DIR/pf-discord-bugs.sh" status 2>&1); rc=$?
  while IFS= read -r l; do [ -n "$l" ] && say $l; done <<< "$out"
  [ "$rc" = 0 ] || say FAIL "Discord #bug-reports is NOT being watched: fix the line above (owner adds the bot to the server: discord.com/oauth2/authorize?client_id=<bot app id>&scope=bot&permissions=8)"
  case $out in *"unread reports: "[1-9]*) say WARN "Discord reports waiting: run pf-discord-bugs.sh read and triage them now";; esac
fi

# 6. Untriaged backlog (the UNTRIAGED wake should keep this at zero).
u=$(gh api "repos/$REPO/issues?state=open&per_page=100" --jq '[.[] | select(.pull_request==null) | select(((.labels|map(.name)|map(test("^p[123]$"))|any)|not) or ((.assignees|length)==0))] | length' 2>/dev/null)
if [ -z "$u" ]; then say WARN "could not count untriaged issues"
elif [ "$u" = 0 ]; then say PASS "no untriaged issues"
else say WARN "$u open issue(s) missing a p1/p2/p3 label or an assignee: triage them"; fi

# 7. Review gate (rule 12): a review-blocked PR whose last push is 2h+ old needs the stale re-check.
stale=$(gh pr list --repo "$REPO" --label review-blocked --json number,updatedAt -q \
  "[.[] | select((now - (.updatedAt | fromdateiso8601)) > 7200) | .number] | map(tostring) | join(\" \")" 2>/dev/null)
[ -n "$stale" ] && say WARN "review-blocked PR(s) idle 2h+: #$stale. Re-check the findings (rule 12 stale re-check)" || say PASS "no stale review-blocked PRs"

[ "$fails" = 0 ] && { say INFO "tm-check: all duties covered"; exit 0; }
say INFO "tm-check: $fails FAIL(s)"; exit 1
