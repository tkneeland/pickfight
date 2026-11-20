#!/bin/bash
# Reserve-account supervisor (docs/agents/hive.md rule 5), one pass; launchd (or cron) runs it every 10 min (see --install).
# For an account with RESERVE=1 in its accounts/<handle>.conf. Zero tokens unless it starts Claude.
# While every non-reserve dev can work normally, it hands this account's unstarted ready-for-agent tickets back with a
# [TRIAGE] comment, and also when a regular dev is down but this account's own weekly is at or below
# MIN_WEEKLY_REMAINING_FOR_TICKETS. It starts a headless AT session (screen hive-reserve-<handle>) when this account has
# in-flight tickets that need work, or is needed and has ready tickets. Log: $HIVE_STATE/reserve.log
# The headless session runs with every permission and reads ticket text, so only tickets whose author and last editor are
# in TRUSTED_TICKET_AUTHORS (hive.conf or _shared.conf; empty = none) go in.
#   HIVE_ACCOUNT=<handle> bash tools/agents/hive-reserve.sh            one pass
#   HIVE_ACCOUNT=<handle> bash tools/agents/hive-reserve.sh --dry      print the decision, change nothing
#   HIVE_ACCOUNT=<handle> bash tools/agents/hive-reserve.sh --install  macOS: write and load the launchd job; else print a cron line
# Needs the private channel (USAGE beacons) and GitHub issues: off in SINGLE_ACCOUNT/PRIVATE mode and with TRACKER=local.
export PATH="$PATH:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"   # appended: launchd/cron PATH is minimal, a caller's own PATH wins
. "$(dirname "$0")/hive-env.sh" || exit 1
[ "${RESERVE:-0}" = 1 ] || { echo "hive-reserve: $HIVE_ACCOUNT is not RESERVE=1" >&2; exit 1; }
[ "$SINGLE_ACCOUNT" = 1 ] && { echo "hive-reserve: single-account (or private) mode has no reserve accounts" >&2; exit 1; }
[ "$TRACKER" = local ] && { echo "hive-reserve: needs GitHub issues (TRACKER=local)" >&2; exit 1; }
LABEL=com.claude-hive.reserve.${HIVE_SLUG#*__}.$HIVE_ACCOUNT
if [ "${1:-}" = --install ]; then
  if [ "$HIVE_OS" != Darwin ]; then
    echo "Add this line to crontab -e:"
    echo "*/10 * * * * HIVE_ACCOUNT=$HIVE_ACCOUNT /bin/bash $(printf '%q' "$HIVE_DIR/hive-reserve.sh") >> $(printf '%q' "$HIVE_STATE/reserve.log") 2>&1"
    exit 0
  fi
  p=$HOME/Library/LaunchAgents/$LABEL.plist
  cat > "$p" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$HIVE_DIR/hive-reserve.sh</string></array>
  <key>EnvironmentVariables</key><dict><key>HIVE_ACCOUNT</key><string>$HIVE_ACCOUNT</string><key>HOME</key><string>$HOME</string></dict>
  <key>StartInterval</key><integer>600</integer>
  <key>RunAtLoad</key><true/>
  <key>AbandonProcessGroup</key><true/>
  <key>StandardOutPath</key><string>$HIVE_STATE/reserve.log</string>
  <key>StandardErrorPath</key><string>$HIVE_STATE/reserve.log</string>
</dict></plist>
EOF
  launchctl unload "$p" 2>/dev/null; launchctl load "$p" && echo "loaded $LABEL"; exit
fi
DRY=0; [ "${1:-}" = --dry ] && DRY=1
log() { echo "$(date -u +%FT%TZ) $*" >> "$HIVE_STATE/reserve.log"; }
[ "$(cat "$HIVE_STATE/at-mode" 2>/dev/null || echo AT)" = MT ] && exit 0
SESSION=hive-reserve-$HIVE_ACCOUNT
name=${REPO#*/}
if [ "$DRY" = 0 ]; then
  # no status line here or in the headless session: refresh the usage snapshot and USAGE beacon from the usage endpoint
  bash "$HIVE_DIR/hive-usage.sh" || log "usage refresh failed (see beacon.log)"
  # the automerger is cheap and should outlive reboots too
  screen -ls 2>/dev/null | grep -q "\.hive-automerge-$HIVE_ACCOUNT[[:space:]]" ||
    screen -dmS "hive-automerge-$HIVE_ACCOUNT" bash -c "HIVE_ACCOUNT=$HIVE_ACCOUNT bash $(printf '%q' "$HIVE_DIR/windows/hive-supervise.sh") automerge"
  screen -ls 2>/dev/null | grep -q "\.$SESSION[[:space:]]" && exit 0   # a session is already working
  [ "$(git -C "$ROOT" branch --show-current 2>/dev/null)" = "$MAIN_BRANCH" ] && git -C "$ROOT" pull -q --ff-only 2>/dev/null
fi
git -C "$ROOT" fetch -q origin 2>/dev/null

now=$(date +%s)
# beacons: each account's newest USAGE message in msg-inbox.log, backfilled from the channel when missing or stale
hive_usage_backfill
# no fresh beacon from any other account (no channel configured, listener down and backfill failed): no evidence that
# the devs cannot work, so make no decision rather than treat them all as unable
hive_channel_fresh || { [ "$DRY" = 1 ] && echo "no fresh channel data: no decision"; log "no fresh USAGE beacons on the channel (msg.conf missing or listener down?); no decision"; exit 0; }
# able: fresh beacon (< BEACON_FRESH_HOURS); under the weekly handoff % or inside its reset grace window (rule 3); 5h not
# full with >1h to go. An unknown 7d ("?", e.g. just after a reset) counts as able but ranks last for hand-backs.
# Hand-back target only (#226, rule 5): a peer at or under its own MIN_WEEKLY_REMAINING_FOR_TICKETS (account conf, else
# _shared.conf, else 0), or with unknown 7d while that cap is above 0, is never chosen as $best. This does not affect $needed.
peer_min() {   # peer_min <handle>: that dev's ticket floor, always a non-negative integer
  local m; m=$(hive_conf_of "$1" MIN_WEEKLY_REMAINING_FOR_TICKETS)
  case $m in ''|*[!0-9]*) m=$(sed -n 's/^MIN_WEEKLY_REMAINING_FOR_TICKETS=//p' "$HIVE_DIR/accounts/_shared.conf" 2>/dev/null | sed 's/[[:space:]]*#.*//; s/^"//; s/"$//' | head -n 1);; esac
  case $m in ''|*[!0-9]*) m=0;; esac
  echo "$m"
}
handback_ok() {   # handback_ok <handle>: may this able peer receive a hand-back? (uses b_used from hive_beacon)
  local m; m=$(peer_min "$1")
  if [ -z "$b_used" ]; then [ "$m" -eq 0 ]; return; fi
  [ $((100 - b_used)) -gt "$m" ]
}
able() {
  [ "$b_age" -lt $(( BEACON_FRESH_HOURS * 3600 )) ] || return 1
  if [ -n "$b_used" ] && [ "$b_used" -ge "$HANDOFF_WEEKLY_USED" ]; then
    r=$(hive_iso_to_epoch "$b_reset") || return 1; [ $((r - now)) -le $((RESET_GRACE_HOURS * 3600)) ] || return 1
  fi
  [ -z "$b_p5" ] || [ "$b_p5" -lt 100 ] && return 0
  r=$(hive_iso_to_epoch "$b_r5") || return 1; [ $((r - now)) -le 3600 ]
}
needed=0; best=""; bestp=999; who=""
for h in $(hive_handles); do
  hive_is_reserve "$h" && continue
  hive_beacon "$h"
  if able "$h"; then p=${b_used:-100}; handback_ok "$h" && [ "$p" -lt "$bestp" ] && { best=$h; bestp=$p; }; who+="$h:able "
  else needed=1; who+="$h:unable "; fi
done
# own budget: no new tickets at or below MIN_WEEKLY_REMAINING_FOR_TICKETS; nothing at all once hive_budget_ok says stop
snap_age=$(( now - $(hive_mtime "$HIVE_STATE/usage-snapshot.json" || echo 0) ))
take_new=$needed; [ $((100 - $(hive_weekly_used))) -le "$MIN_WEEKLY_REMAINING_FOR_TICKETS" ] && take_new=0
run_any=1; hive_budget_ok || { run_any=0; take_new=0; }
[ "$DRY" = 0 ] && [ "$snap_age" -gt 1800 ] && log "own usage snapshot is $((snap_age / 60)) min old (hive-usage.sh failing?)"

remote=$(git -C "$ROOT" ls-remote --heads origin) || { log "ls-remote failed"; exit 0; }
# "<branch> <sha>" lines, remote heads then local ones (local catches committed-but-unpushed work)
heads=$(echo "$remote" | awk '{sub("refs/heads/", "", $2); print $2, substr($1, 1, 12)}'
  git -C "$ROOT" for-each-ref --format='%(refname:short) %(objectname:short=12)' refs/heads)
issues=$(gh issue list --repo "$REPO" --assignee "$HIVE_ACCOUNT" --label ready-for-agent --state open -L 200 --json number,labels) || { log "issue list failed"; exit 0; }
prs=$(gh pr list --repo "$REPO" --state open -L 200 --json headRefName,labels,mergeable,isDraft,statusCheckRollup) || { log "pr list failed"; exit 0; }
week_ago=$((now - 7 * 86400))
inflight=(); ready=(); waiting=()
while read -r n cr; do
  [ -n "$n" ] || continue
  # live work: an issue-<n>- branch (anchored) with commits not on the main branch, last committed within a week (older = abandoned)
  mine=""
  while read -r b sha; do
    [ -n "$b" ] || continue
    git -C "$ROOT" cat-file -e "$sha^{commit}" 2>/dev/null || { mine=1; break; }   # unknown object: assume live
    [ "$(git -C "$ROOT" rev-list --count "origin/$MAIN_BRANCH..$sha" 2>/dev/null || echo 1)" -gt 0 ] || continue
    [ "$(git -C "$ROOT" log -1 --format=%ct "$sha" 2>/dev/null || echo "$now")" -ge "$week_ago" ] && { mine=1; break; }
  done < <(echo "$heads" | awk -v re="(^|/)issue-$n-" '$1 ~ re')
  if [ -n "$mine" ]; then
    # an open, non-draft PR (on any of the issue's branches) that is not conflicting, not review-blocked and not failing
    # CI is waiting on CI, the automerger or the triagemaster: no session for it
    pr=$(echo "$prs" | jq -r --arg re "(^|/)issue-$n-" '[.[] | select(.headRefName | test($re)) | select(.isDraft | not)
      | select(.mergeable != "CONFLICTING" and (any(.labels[]; .name == "review-blocked") | not)
        and (any(.statusCheckRollup[]?; (.conclusion // .state // "") | test("FAILURE|ERROR|CANCELLED|TIMED_OUT|ACTION_REQUIRED")) | not))] | length')
    [ "$pr" -gt 0 ] && { waiting+=("$n"); continue; }
    inflight+=("$n")
  elif [ "$cr" = true ] && [ "$take_new" = 0 ]; then waiting+=("$n")   # rule 6: only the triagemaster reassigns these
  else ready+=("$n"); fi
done < <(echo "$issues" | jq -r '.[] | "\(.number) \(any(.labels[]; .name == "conflict-risk"))"')
if [ "$DRY" = 1 ]; then
  echo "$who| needed=$needed take_new=$take_new run_any=$run_any best=$best | inflight: ${inflight[*]:-} | ready: ${ready[*]:-} | waiting: ${waiting[*]:-}"; exit 0
fi
if [ "$take_new" = 0 ] && [ -n "$best" ]; then
  for n in ${ready[@]+"${ready[@]}"}; do
    gh issue edit "$n" --repo "$REPO" --remove-assignee "$HIVE_ACCOUNT" --add-assignee "$best" >/dev/null &&
      gh issue comment "$n" --repo "$REPO" --body "[TRIAGE] $HIVE_ACCOUNT reassigned $HIVE_ACCOUNT -> $best: $HIVE_ACCOUNT is a reserve account (hive.md rule 5) and is not taking new tickets now (regular devs: ${who% }); $best has the most weekly headroom." >/dev/null &&
      log "handed #$n back to $best"
  done
fi
[ "$take_new" = 1 ] || ready=()
[ "$run_any" = 1 ] || exit 0
# The session runs unattended with every permission and reads the ticket text: only tickets whose author and last
# editor are in TRUSTED_TICKET_AUTHORS go in, so a stranger's edit cannot steer it (prompt injection).
trusted_login() { case " ${TRUSTED_TICKET_AUTHORS:-} " in *" $1 "*) [ -n "$1" ];; *) return 1;; esac; }
trusted_ticket() {   # trusted_ticket <n>: 0 when the author and the last editor (if any) are trusted
  local who a e
  who=$(gh api graphql -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){author{login} editor{login}}}}' \
    -f o="${REPO%%/*}" -f r="${REPO#*/}" -F n="$1" \
    --jq '.data.repository.issue | "\(.author.login // "-") \(.editor.login // "")"' 2>/dev/null) || return 1
  a=${who%% *}; e=${who#* }
  trusted_login "$a" || return 1
  [ -z "$e" ] || trusted_login "$e"
}
work=()
for n in ${inflight[@]+"${inflight[@]}"} ${ready[@]+"${ready[@]}"}; do
  if trusted_ticket "$n"; then work+=("$n"); else log "skipping #$n: its author or last editor is not in TRUSTED_TICKET_AUTHORS (or the check failed)"; fi
done
[ ${#work[@]} -gt 0 ] || exit 0
# relaunch only when the ticket set changed since the last session, or 6h passed; a session that leaves the same
# tickets in flight (blocked, waiting on a human) is not restarted every pass
sig="${work[*]}"
last=$(cat "$HIVE_STATE/reserve-last-launch" 2>/dev/null); lt=${last%% *}; ls=${last#* }
[ "$ls" = "$sig" ] && [ $((now - ${lt:-0})) -lt 21600 ] && exit 0
[ $((now - ${lt:-0})) -lt 1800 ] && exit 0
echo "$now $sig" > "$HIVE_STATE/reserve-last-launch"
# the prompt goes in through a file on stdin: inlined into the bash -c string, its backticks ran as commands
pf=$HIVE_STATE/reserve-session-prompt.txt
sed -e "s#{{ACCOUNT}}#$HIVE_ACCOUNT#g" -e "s#{{TICKETS}}#${work[*]}#g" -e "s#{{REPO}}#$REPO#g" -e "s#{{REPO_NAME}}#$name#g" \
  -e "s#{{MAIN_BRANCH}}#$MAIN_BRANCH#g" "$HIVE_DIR/hive-reserve-prompt.md" > "$pf"
log "starting $SESSION for #${work[*]} (needed=$needed)"
# absolute claude path and plain bash -c: a login shell resets PATH and loses ~/.local/bin
cl=$(command -v claude) || { log "claude not on PATH"; exit 0; }
screen -dmS "$SESSION" bash -c "export HIVE_ACCOUNT=$HIVE_ACCOUNT HIVE_SESSION=always-on PATH=$(printf '%q' "$PATH"); cd $(printf '%q' "$ROOT") && $(printf '%q' "$cl") -p --dangerously-skip-permissions < $(printf '%q' "$pf") >> $(printf '%q' "$HIVE_STATE/reserve-session.log") 2>&1"
