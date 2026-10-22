#!/bin/bash
# Reserve-account supervisor (autotriage.md rule 5), one pass; launchd runs it every 10 min (see --install).
# Zero tokens unless it starts Claude. While every non-reserve dev can work normally, it hands this account's unstarted
# ready-for-agent tickets back with a [TRIAGE] comment, and also when a regular dev is down but this account's own weekly
# is at or below MIN_WEEKLY_REMAINING_FOR_TICKETS. It starts a headless AT session (screen pf-at-<handle>) when this
# account has in-flight tickets that need work, or is needed and has ready tickets. Log: $PF_STATE/reserve.log
#   PF_ACCOUNT=<handle> bash tools/agents/pf-reserve.sh            one pass
#   PF_ACCOUNT=<handle> bash tools/agents/pf-reserve.sh --dry      print the decision, change nothing
#   PF_ACCOUNT=<handle> bash tools/agents/pf-reserve.sh --install  write and load the launchd job (macOS)
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
. "$(dirname "$0")/pf-env.sh" || exit 1
[ "${RESERVE:-0}" = 1 ] || { echo "pf-reserve: $PF_ACCOUNT is not RESERVE=1" >&2; exit 1; }
LABEL=com.pickfight.reserve.$PF_ACCOUNT
if [ "${1:-}" = --install ]; then
  p=$HOME/Library/LaunchAgents/$LABEL.plist
  cat > "$p" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$ROOT/tools/agents/pf-reserve.sh</string></array>
  <key>EnvironmentVariables</key><dict><key>PF_ACCOUNT</key><string>$PF_ACCOUNT</string><key>HOME</key><string>$HOME</string></dict>
  <key>StartInterval</key><integer>600</integer>
  <key>RunAtLoad</key><true/>
  <key>AbandonProcessGroup</key><true/>
  <key>StandardOutPath</key><string>$PF_STATE/reserve.log</string>
  <key>StandardErrorPath</key><string>$PF_STATE/reserve.log</string>
</dict></plist>
EOF
  launchctl unload "$p" 2>/dev/null; launchctl load "$p" && echo "loaded $LABEL"; exit
fi
DRY=0; [ "${1:-}" = --dry ] && DRY=1
log() { echo "$(date -u +%FT%TZ) $*" >> "$PF_STATE/reserve.log"; }
[ "$(cat "$PF_STATE/pf-at-mode" 2>/dev/null || echo AT)" = MT ] && exit 0
SESSION=pf-at-$PF_ACCOUNT
if [ "$DRY" = 0 ]; then
  # the automerger is cheap and should outlive reboots too
  screen -ls 2>/dev/null | grep -q "\.pf-automerge-$PF_ACCOUNT[[:space:]]" ||
    screen -dmS "pf-automerge-$PF_ACCOUNT" bash -c "PF_ACCOUNT=$PF_ACCOUNT bash $(printf '%q' "$ROOT/tools/agents/windows/pf-supervise.sh") automerge"
  screen -ls 2>/dev/null | grep -q "\.$SESSION[[:space:]]" && exit 0   # a session is already working
  git -C "$ROOT" pull -q --ff-only 2>/dev/null
fi
git -C "$ROOT" fetch -q origin 2>/dev/null

now=$(date +%s)
raw=$(gh api "repos/$REPO/issues/432/comments?per_page=100" --paginate 2>/dev/null) || { log "beacon read failed"; exit 0; }
comments=$(echo "$raw" | jq -s 'add') || { log "beacon parse failed"; exit 0; }
# able: fresh beacon (<6h); under the weekly handoff % or inside its reset grace window (rule 3); 5h not full with >1h to go.
# An unknown 7d ("?", e.g. just after a reset) counts as able but ranks last for hand-backs.
able() {
  [ "$b_age" -lt 21600 ] || return 1
  if [ -n "$b_used" ] && [ "$b_used" -ge "$HANDOFF_WEEKLY_USED" ]; then
    r=$(pf_iso_to_epoch "$b_reset") || return 1; [ $((r - now)) -le $((RESET_GRACE_HOURS * 3600)) ] || return 1
  fi
  [ -z "$b_p5" ] || [ "$b_p5" -lt 100 ] && return 0
  r=$(pf_iso_to_epoch "$b_r5") || return 1; [ $((r - now)) -le 3600 ]
}
needed=0; best=""; bestp=999; who=""
for h in $(pf_handles); do
  grep -q '^RESERVE=1' "$PF_DIR/accounts/$h.conf" && continue
  pf_beacon "$h" "$comments"
  if able; then p=${b_used:-100}; [ "$p" -lt "$bestp" ] && { best=$h; bestp=$p; }; who+="$h:able "
  else needed=1; who+="$h:unable "; fi
done
# own budget: no new tickets at or below MIN_WEEKLY_REMAINING_FOR_TICKETS; nothing at all once pf_budget_ok says stop
snap_age=$(( now - $(pf_mtime "$PF_STATE/usage-snapshot.json" || echo 0) ))
take_new=$needed; [ $((100 - $(pf_weekly_used))) -le "$MIN_WEEKLY_REMAINING_FOR_TICKETS" ] && take_new=0
run_any=1; pf_budget_ok || { run_any=0; take_new=0; }
[ "$snap_age" -gt 21600 ] && log "own usage snapshot is $((snap_age / 3600))h old (headless sessions don't refresh it)"

remote=$(git -C "$ROOT" ls-remote --heads origin) || { log "ls-remote failed"; exit 0; }
# "<branch> <sha>" lines, remote heads then local ones (local catches committed-but-unpushed work)
heads=$(echo "$remote" | awk '{sub("refs/heads/", "", $2); print $2, substr($1, 1, 12)}'
  git -C "$ROOT" for-each-ref --format='%(refname:short) %(objectname:short=12)' refs/heads)
issues=$(gh issue list --repo "$REPO" --assignee "$PF_ACCOUNT" --label ready-for-agent --state open -L 200 --json number,labels) || { log "issue list failed"; exit 0; }
prs=$(gh pr list --repo "$REPO" --state open -L 200 --json headRefName,labels,mergeable,isDraft,statusCheckRollup) || { log "pr list failed"; exit 0; }
week_ago=$((now - 7 * 86400))
inflight=(); ready=(); waiting=()
while read -r n cr; do
  [ -n "$n" ] || continue
  # live work: an issue-<n>- branch (anchored) with commits not on main, last committed within a week (older = abandoned)
  mine=""
  while read -r b sha; do
    [ -n "$b" ] || continue
    git -C "$ROOT" cat-file -e "$sha^{commit}" 2>/dev/null || { mine=1; break; }   # unknown object: assume live
    [ "$(git -C "$ROOT" rev-list --count "origin/main..$sha" 2>/dev/null || echo 1)" -gt 0 ] || continue
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
  echo "$who| needed=$needed take_new=$take_new run_any=$run_any best=$best | inflight: ${inflight[*]} | ready: ${ready[*]} | waiting: ${waiting[*]}"; exit 0
fi
if [ "$take_new" = 0 ] && [ -n "$best" ]; then
  for n in "${ready[@]}"; do
    gh issue edit "$n" --repo "$REPO" --remove-assignee "$PF_ACCOUNT" --add-assignee "$best" >/dev/null &&
      gh issue comment "$n" --repo "$REPO" --body "[TRIAGE] $PF_ACCOUNT reassigned $PF_ACCOUNT -> $best: $PF_ACCOUNT is a reserve account (autotriage.md rule 5) and is not taking new tickets now (regular devs: ${who% }); $best has the most weekly headroom." >/dev/null &&
      log "handed #$n back to $best"
  done
fi
[ "$take_new" = 1 ] || ready=()
[ "$run_any" = 1 ] || exit 0
work=("${inflight[@]}" "${ready[@]}"); [ ${#work[@]} -gt 0 ] || exit 0
# relaunch only when the ticket set changed since the last session, or 6h passed; a session that leaves the same
# tickets in flight (blocked, waiting on a human) is not restarted every pass
sig="${work[*]}"
last=$(cat "$PF_STATE/reserve-last-launch" 2>/dev/null); lt=${last%% *}; ls=${last#* }
[ "$ls" = "$sig" ] && [ $((now - ${lt:-0})) -lt 21600 ] && exit 0
[ $((now - ${lt:-0})) -lt 1800 ] && exit 0
echo "$now $sig" > "$PF_STATE/reserve-last-launch"
# the prompt goes in through a file on stdin: inlined into the bash -lc string, its backticks ran as commands
pf=$PF_STATE/at-session-prompt.txt
sed -e "s/{{ACCOUNT}}/$PF_ACCOUNT/g" -e "s/{{TICKETS}}/${work[*]}/g" "$PF_DIR/pf-reserve-prompt.md" > "$pf"
log "starting $SESSION for #${work[*]} (needed=$needed)"
# absolute claude path and plain bash -c: a login shell resets PATH and loses ~/.local/bin
cl=$(command -v claude) || { log "claude not on PATH"; exit 0; }
screen -dmS "$SESSION" bash -c "export PF_ACCOUNT=$PF_ACCOUNT PATH=$(printf '%q' "$PATH"); cd $(printf '%q' "$ROOT") && $(printf '%q' "$cl") -p --dangerously-skip-permissions < $(printf '%q' "$pf") >> $(printf '%q' "$PF_STATE/at-session.log") 2>&1"
