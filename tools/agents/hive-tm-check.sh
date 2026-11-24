#!/bin/bash
# Triagemaster self-check (docs/agents/hive.md rule 19). One pass, zero tokens: prints one PASS / WARN / FAIL / INFO line per
# duty, each FAIL with the fix, and exits 1 when anything FAILs. Run it at AT session start, on taking the role
# (succession), and when the watcher wakes with TM_CHECK_FAIL (it runs this every 6h, and wakes within the hour when
# Discord stops answering).
#   hive-tm-check.sh            all checks
#   hive-tm-check.sh --quiet    print only WARN / FAIL lines (the watcher uses this)
# Watchers count as running from their own heartbeat in this account's $HIVE_STATE (portable, per account): the triage
# watcher touches .triage-watch-alive every tick, the msg supervisor rewrites msg-status.json every minute.
# HIVE_TM_CHECK_SKIP_PROCS=1 skips the watcher checks (tests).
. "$(dirname "$0")/hive-env.sh" || exit 1
QUIET=0; [ "${1:-}" = --quiet ] && QUIET=1
fails=0
say() { local lvl=$1; shift; [ "$lvl" = FAIL ] && fails=$((fails+1))
  [ "$QUIET" = 1 ] && [ "$lvl" != FAIL ] && [ "$lvl" != WARN ] && return 0; echo "$lvl $*"; }
age() { local m; m=$(hive_mtime "$1" 2>/dev/null); [ -n "$m" ] && echo $(( $(date +%s) - m )) || echo 999999; }
case $(uname -s) in MINGW*|MSYS*|CYGWIN*) HIVE_WIN=1;; *) HIVE_WIN=0;; esac
start_cmd() {  # how to (re)start one supervised watcher on this platform
  if [ "$HIVE_WIN" = 1 ]; then echo "run tools/agents/windows/hive-start.ps1"
  else echo "screen -dmS $(hive_screen "$1") bash -c 'HIVE_ACCOUNT=$HIVE_ACCOUNT bash tools/agents/windows/hive-supervise.sh $1'"; fi; }

# 1. Role (rule 7). Every other check still runs, so a stand-in can verify itself before taking over.
tm=$(hive_triagemaster)
if hive_is_triagemaster; then say PASS "triagemaster is $HIVE_ACCOUNT"
else say INFO "triagemaster is $tm, not $HIVE_ACCOUNT (checks below are for whoever holds the role)"; fi

# 2. AT mode (rule 1), ticket-maker mode (rule 11), worker target (rule 2).
mode=$(bash "$HIVE_DIR/hive-at-mode.sh" 2>/dev/null)
case $mode in AT*) say PASS "mode $mode";;
  *) if hive_studio_on; then say WARN "mode is ${mode:-unknown}: this account is switched out in the hub, so it does no autonomous work and cannot hold the role (switch it back in on the hub's members tab)"
     else say WARN "mode is ${mode:-unknown}: in MT the triagemaster does nothing on its own (owner turns AT back on)"; fi;;
esac
hive_tm_mode
say INFO "ticket-maker $tm_mode, worker target $(hive_worker_target 2>/dev/null), live agents $(hive_live_agents 2>/dev/null | grep -c .)"

# 3. GitHub access (filing, labels, merges).
if login=$(gh api user -q .login 2>/dev/null) && [ -n "$login" ]; then say PASS "gh signed in as $login"
else say FAIL "gh is not signed in: run gh auth login"; fi

# 4. Watchers alive. The triage watcher is the only thing that wakes the session for untriaged tickets, peer
#    messages and Discord reports; after handling a wake line it must be restarted at once.
if [ "${HIVE_TM_CHECK_SKIP_PROCS:-0}" != 1 ]; then
  a=$(age "$HIVE_STATE/.triage-watch-alive")
  if [ "$a" -lt 900 ]; then say PASS "triage watcher alive (heartbeat ${a}s ago)"
  else say FAIL "triage watcher not running (no heartbeat for 15 min+): restart it, bash tools/agents/hive-triage-watch.sh in the background, or $(start_cmd triage)"; fi
  a=$(age "$HIVE_STATE/msg-status.json")
  if [ "$SINGLE_ACCOUNT" = 1 ]; then :
  elif [ "$a" -lt 300 ]; then say PASS "private channel listener alive (supervisor ${a}s ago)"
  else say FAIL "private channel listener not supervised (msg-status.json stale): $(start_cmd msg) (rule 17: never stays down)"; fi
  if LC_ALL=C pgrep -f "HIVE_ACCOUNT=$HIVE_ACCOUNT.*hive-automerge" >/dev/null 2>&1 || [ "$(age "$HIVE_STATE/automerge-status.json")" -lt 86400 ]; then say PASS "automerge supervised"
  else say WARN "automerge not seen: green review-passed PRs wait ($(start_cmd automerge))"; fi
fi
if [ "$SINGLE_ACCOUNT" = 1 ]; then say INFO "single-account mode: no private channel or peers"
elif hive_channel_fresh 2>/dev/null; then say PASS "peer beacons fresh on the private channel"
else say WARN "no peer USAGE beacon under ${BEACON_FRESH_HOURS}h old: peers may be offline, or this listener is deaf (check msg.conf)"; fi

# 5. Discord bug channel (rule 18): token, channel, history, message text, permissions. Only with DISCORD=1.
if [ "$DISCORD" != 1 ]; then say INFO "Discord off (DISCORD=0): reports come from GitHub only"
elif [ ! -f "$HIVE_STATE/discord.conf" ]; then
  say FAIL "no $HIVE_STATE/discord.conf: Discord #$DISCORD_BUGS_NAME is NOT being watched. Write HIVE_DISCORD_TOKEN=<bot token> there (ask the owner out of band; never commit it)"
else
  out=$(bash "$HIVE_DIR/hive-discord-bugs.sh" status 2>&1); rc=$?
  while read -r lvl rest; do [ -n "$lvl" ] && say "$lvl" "$rest"; done <<EOT
$out
EOT
  [ "$rc" = 0 ] || say FAIL "Discord #$DISCORD_BUGS_NAME is NOT being watched: fix the line above (bot removed: the owner adds it to the server again)"
  case $out in *"unread reports: "[1-9]*) say WARN "Discord reports waiting: run hive-discord-bugs.sh read and triage them now";; esac
fi

# 6-8 read GitHub; a local tracker or private install has none of these duties.
if [ "$TRACKER" != github ] || [ "$PRIVATE" = 1 ]; then
  [ "$fails" = 0 ] && { say INFO "tm-check: all duties covered"; exit 0; }; say INFO "tm-check: $fails FAIL(s)"; exit 1
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
    [ -z "$n" ] && continue; c=$(hive_iso_to_epoch "$created"); up=$(hive_iso_to_epoch "$updated")
    case ",$labels," in
      *,review-blocked,*) [ -n "$up" ] && [ $((now - up)) -ge 7200 ] && stale="$stale #$n";;
      *,review-passed,*) ;;
      *) [ "$draft" = false ] && [ -n "$c" ] && [ $((now - c)) -ge 7200 ] && unrev="$unrev #$n";;
    esac
  done <<EOT
$(echo "$prs" | jq -r '.[] | "\(.number)|\(.createdAt)|\(.updatedAt)|\([.labels[].name] | join(","))|\(.isDraft)"')
EOT
  if [ "$REQUIRE_REVIEW_PASS" != 1 ]; then :
  elif [ -n "$unrev" ]; then say WARN "PR(s) open 2h+ with no reviewer pass:$unrev (rule 12)"; else say PASS "every PR 2h+ old has a review label"; fi
  [ -n "$stale" ] && say WARN "review-blocked PR(s) idle 2h+:$stale (rule 12 stale re-check)" || say PASS "no stale review-blocked PRs"
else say WARN "could not list open PRs"; fi

# 8. Main green (rule 9: main red 30 min+ is a fire): the latest finished run of each workflow on MAIN_BRANCH.
red=$(gh run list --repo "$REPO" --branch "$MAIN_BRANCH" -L 30 --json conclusion,status,createdAt,workflowName 2>/dev/null |
  jq -r '[.[] | select(.status == "completed")] | group_by(.workflowName) | map(max_by(.createdAt)) |
    .[] | select(.conclusion == "failure" or .conclusion == "timed_out") | "\(.createdAt)|\(.workflowName)"' 2>/dev/null)
if [ -z "$red" ]; then say PASS "$MAIN_BRANCH green (latest run of every workflow)"
else
  while IFS='|' read -r rt rw; do
    t=$(hive_iso_to_epoch "$rt")
    if [ -n "$t" ] && [ $(( $(date +%s) - t )) -ge 1800 ]; then say FAIL "$MAIN_BRANCH is red for 30 min+ ($rw): fire (rule 9), fix or revert"
    else say WARN "$MAIN_BRANCH just went red ($rw): watch it"; fi
  done <<EOT
$red
EOT
fi

[ "$fails" = 0 ] && { say INFO "tm-check: all duties covered"; exit 0; }
say INFO "tm-check: $fails FAIL(s)"; exit 1
