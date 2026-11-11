#!/bin/bash
# Triagemaster self-check (autotriage.md rule 19). One pass, zero tokens: prints one PASS / WARN / FAIL / INFO line per
# duty, each FAIL with the fix, and exits 1 when anything FAILs. Run it at AT session start, on taking the role
# (succession), and when the watcher wakes with TM_CHECK_FAIL (it runs this every 6h, and wakes within the hour when
# Discord stops answering).
#   pf-tm-check.sh            all checks
#   pf-tm-check.sh --quiet    print only WARN / FAIL lines (the watcher uses this)
# Watchers count as running from their own heartbeat in this account's $PF_STATE (portable, per account): the triage
# watcher touches .triage-watch-alive every tick, the msg supervisor rewrites msg-status.json every minute.
# PF_TM_CHECK_SKIP_PROCS=1 skips the watcher checks (tests).
. "$(dirname "$0")/pf-env.sh" || exit 1
QUIET=0; [ "${1:-}" = --quiet ] && QUIET=1
fails=0
say() { local lvl=$1; shift; [ "$lvl" = FAIL ] && fails=$((fails+1))
  [ "$QUIET" = 1 ] && [ "$lvl" != FAIL ] && [ "$lvl" != WARN ] && return 0; echo "$lvl $*"; }
age() { local m; m=$(pf_mtime "$1" 2>/dev/null); [ -n "$m" ] && echo $(( $(date +%s) - m )) || echo 999999; }
case $(uname -s) in MINGW*|MSYS*|CYGWIN*) PF_WIN=1;; *) PF_WIN=0;; esac
start_cmd() {  # how to (re)start one supervised watcher on this platform
  if [ "$PF_WIN" = 1 ]; then echo "run tools/agents/windows/pf-start.ps1"
  else echo "screen -dmS pf-$1-$PF_ACCOUNT bash -c 'PF_ACCOUNT=$PF_ACCOUNT bash tools/agents/windows/pf-supervise.sh $1'"; fi; }

# 1. Role (rule 7). Every other check still runs, so a stand-in can verify itself before taking over.
tm=$(pf_triagemaster)
if pf_is_triagemaster; then say PASS "triagemaster is $PF_ACCOUNT"
else say INFO "triagemaster is $tm, not $PF_ACCOUNT (checks below are for whoever holds the role)"; fi

# 2. AT mode (rule 1), ticket-maker switch (rule 11), worker target (rule 2).
mode=$(bash "$PF_DIR/pf-at-mode.sh" 2>/dev/null)
case $mode in AT*) say PASS "mode $mode";; *) say WARN "mode is ${mode:-unknown}: in MT the triagemaster does nothing on its own (owner turns AT back on)";; esac
say INFO "ticket-maker $(bash "$PF_DIR/pf-ticketmaker.sh" 2>/dev/null), worker target $(pf_worker_target 2>/dev/null), live agents $(pf_live_agents 2>/dev/null | grep -c .)"

# 3. GitHub access (filing, labels, merges).
if login=$(gh api user -q .login 2>/dev/null) && [ -n "$login" ]; then say PASS "gh signed in as $login"
else say FAIL "gh is not signed in: run gh auth login"; fi

# 4. Watchers alive. The triage watcher is the only thing that wakes the session for untriaged tickets, peer
#    messages and Discord reports; after handling a wake line it must be restarted at once.
if [ "${PF_TM_CHECK_SKIP_PROCS:-0}" != 1 ]; then
  a=$(age "$PF_STATE/.triage-watch-alive")
  if [ "$a" -lt 900 ]; then say PASS "triage watcher alive (heartbeat ${a}s ago)"
  else say FAIL "triage watcher not running (no heartbeat for 15 min+): restart it, bash tools/agents/pf-triage-watch.sh in the background, or $(start_cmd triage)"; fi
  a=$(age "$PF_STATE/msg-status.json")
  if [ "$a" -lt 300 ]; then say PASS "private channel listener alive (supervisor ${a}s ago)"
  else say FAIL "private channel listener not supervised (msg-status.json stale): $(start_cmd msg) (rule 17: never stays down)"; fi
  if pgrep -f "PF_ACCOUNT=$PF_ACCOUNT.*pf-automerge" >/dev/null 2>&1 || [ "$(age "$PF_STATE/automerge-status.json")" -lt 86400 ]; then say PASS "automerge supervised"
  else say WARN "automerge not seen: green review-passed PRs wait ($(start_cmd automerge))"; fi
fi
if pf_channel_fresh 2>/dev/null; then say PASS "peer beacons fresh on the private channel"
else say WARN "no peer USAGE beacon under 6h old: peers may be offline, or this listener is deaf (check pf-msg.conf)"; fi

# 5. Discord #bug-reports (rule 18): token, channel, history, message text, permissions.
if [ ! -f "$PF_STATE/pf-discord.conf" ]; then
  say FAIL "no $PF_STATE/pf-discord.conf: Discord #bug-reports is NOT being watched. Write PF_DISCORD_TOKEN=<bot token> there (ask the owner via pf-msg.sh send ASK; never commit it)"
else
  out=$(bash "$PF_DIR/pf-discord-bugs.sh" status 2>&1); rc=$?
  while read -r lvl rest; do [ -n "$lvl" ] && say "$lvl" "$rest"; done <<EOT
$out
EOT
  [ "$rc" = 0 ] || say FAIL "Discord #bug-reports is NOT being watched: fix the line above (bot removed: the owner adds it to the server again)"
  case $out in *"unread reports: "[1-9]*) say WARN "Discord reports waiting: run pf-discord-bugs.sh read and triage them now";; esac
fi

# 6. Untriaged backlog (the UNTRIAGED wake should keep this at zero).
u=$(gh api --paginate "repos/$REPO/issues?state=open&per_page=100" 2>/dev/null | jq -s 'add // [] | [.[] | select(.pull_request==null) | select(((.labels|map(.name)|map(test("^p[123]$"))|any)|not) or ((.assignees|length)==0))] | length' 2>/dev/null)
if [ -z "$u" ]; then say WARN "could not count untriaged issues"
elif [ "$u" = 0 ]; then say PASS "no untriaged issues"
else say WARN "$u open issue(s) missing a p1/p2/p3 label or an assignee: triage them"; fi

# 7. Review gate (rule 12): open PRs 2h+ old with no review label; review-blocked PRs idle 2h+ (stale re-check).
if prs=$(gh pr list --repo "$REPO" --state open -L 200 --json number,updatedAt,createdAt,isDraft,labels 2>/dev/null) && [ -n "$prs" ]; then
  now=$(date +%s); unrev=""; stale=""
  while IFS='|' read -r n created updated labels draft; do
    [ -z "$n" ] && continue; c=$(pf_iso_to_epoch "$created"); up=$(pf_iso_to_epoch "$updated")
    case ",$labels," in
      *,review-blocked,*) [ -n "$up" ] && [ $((now - up)) -ge 7200 ] && stale="$stale #$n";;
      *,review-passed,*) ;;
      *) [ "$draft" = false ] && [ -n "$c" ] && [ $((now - c)) -ge 7200 ] && unrev="$unrev #$n";;
    esac
  done <<EOT
$(echo "$prs" | jq -r '.[] | "\(.number)|\(.createdAt)|\(.updatedAt)|\([.labels[].name] | join(","))|\(.isDraft)"')
EOT
  [ -n "$unrev" ] && say WARN "PR(s) open 2h+ with no reviewer pass:$unrev (rule 12)" || say PASS "every PR 2h+ old has a review label"
  [ -n "$stale" ] && say WARN "review-blocked PR(s) idle 2h+:$stale (rule 12 stale re-check)" || say PASS "no stale review-blocked PRs"
else say WARN "could not list open PRs"; fi

# 8. Main green (rule 9: main red 30 min+ is a fire): the latest finished run of each workflow on main.
red=$(gh run list --repo "$REPO" --branch main -L 30 --json conclusion,status,createdAt,workflowName 2>/dev/null |
  jq -r '[.[] | select(.status == "completed")] | group_by(.workflowName) | map(max_by(.createdAt)) |
    .[] | select(.conclusion == "failure" or .conclusion == "timed_out") | "\(.createdAt)|\(.workflowName)"' 2>/dev/null)
if [ -z "$red" ]; then say PASS "main green (latest run of every workflow)"
else
  while IFS='|' read -r rt rw; do
    t=$(pf_iso_to_epoch "$rt")
    if [ -n "$t" ] && [ $(( $(date +%s) - t )) -ge 1800 ]; then say FAIL "main is red for 30 min+ ($rw): fire (rule 9), fix or revert"
    else say WARN "main just went red ($rw): watch it"; fi
  done <<EOT
$red
EOT
fi

[ "$fails" = 0 ] && { say INFO "tm-check: all duties covered"; exit 0; }
say INFO "tm-check: $fails FAIL(s)"; exit 1
