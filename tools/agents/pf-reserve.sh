#!/bin/bash
# Reserve-account supervisor (autotriage.md rule 5), one pass; launchd runs it every 10 min (see --install).
# Zero tokens unless it starts Claude. While every non-reserve dev can work normally, it hands this account's unstarted
# ready-for-agent tickets back with a [TRIAGE] comment. It starts a headless AT session (screen pf-at-<handle>) when this
# account has in-flight tickets (a remote issue branch exists) or is needed and has ready tickets. Log: $PF_STATE/reserve.log
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
screen -ls 2>/dev/null | grep -q "\.$SESSION[[:space:]]" && exit 0   # a session is already working
git -C "$ROOT" pull -q --ff-only 2>/dev/null
# the automerger is cheap and should outlive reboots too
screen -ls 2>/dev/null | grep -q "\.pf-automerge-$PF_ACCOUNT[[:space:]]" ||
  screen -dmS "pf-automerge-$PF_ACCOUNT" bash -c "PF_ACCOUNT=$PF_ACCOUNT bash $ROOT/tools/agents/pf-automerge.sh >> $PF_STATE/automerge.log 2>&1"
fi

now=$(date +%s)
beacons=$(gh api "repos/$REPO/issues/432/comments?per_page=100" --paginate \
  --jq '.[] | select(.body|test("^\\S+ usage @")) | .body | capture("^(?<h>\\S+) usage @ (?<at>\\S+)\\n5h: (?<p5>[0-9?]+)% \\(resets (?<r5>\\S+)\\)\\n7d: (?<p7>[0-9?]+)%") | "\(.h) \(.at) \(.p5) \(.r5) \(.p7)"' 2>/dev/null) ||
  { log "beacon read failed"; exit 0; }
# able <handle>: fresh beacon (<6h), under the weekly handoff %, and not 5h-capped with >1h to reset
able() {
  local l at p5 r5 p7; l=$(echo "$beacons" | awk -v h="$1" '$1==h' | tail -n 1); [ -n "$l" ] || return 1
  read -r _ at p5 r5 p7 <<< "$l"; at=$(pf_iso_to_epoch "$at") || return 1; [ $((now - at)) -lt 21600 ] || return 1
  [ "$p7" = "?" ] && p7=0; [ "$p7" -lt "$HANDOFF_WEEKLY_USED" ] || return 1
  [ "$p5" = "?" ] && p5=0; [ "$p5" -lt 100 ] && return 0
  r5=$(pf_iso_to_epoch "$r5") || return 1; [ $((r5 - now)) -le 3600 ]
}
devs=(); for h in $(pf_handles); do grep -q '^RESERVE=1' "$PF_DIR/accounts/$h.conf" || devs+=("$h"); done
needed=0; best=""; bestp=101
for h in "${devs[@]}"; do
  if able "$h"; then p=$(echo "$beacons" | awk -v h="$h" '$1==h{print $5}' | tail -n 1); [ "$p" = "?" ] && p=0
    [ "$p" -lt "$bestp" ] && { best=$h; bestp=$p; }
  else needed=1; fi
done
[ $((100 - $(pf_weekly_used))) -le "$MIN_WEEKLY_REMAINING_FOR_TICKETS" ] && needed=0
pf_budget_ok || needed=0

branches=$(git -C "$ROOT" ls-remote --heads origin 2>/dev/null | sed 's#.*refs/heads/##')
inflight=(); ready=()
for n in $(gh issue list --repo "$REPO" --assignee "$PF_ACCOUNT" --label ready-for-agent --state open --json number -q '.[].number'); do
  if echo "$branches" | grep -q "issue-$n-"; then inflight+=("$n"); else ready+=("$n"); fi
done
if [ "$DRY" = 1 ]; then echo "devs: ${devs[*]} | needed=$needed best=$best | inflight: ${inflight[*]} | ready: ${ready[*]}"; echo "$beacons"; exit 0; fi
if [ "$needed" = 0 ] && [ -n "$best" ]; then
  for n in "${ready[@]}"; do
    gh issue edit "$n" --repo "$REPO" --remove-assignee "$PF_ACCOUNT" --add-assignee "$best" >/dev/null &&
      gh issue comment "$n" --repo "$REPO" --body "[TRIAGE] $PF_ACCOUNT reassigned $PF_ACCOUNT -> $best: $PF_ACCOUNT is a reserve account (autotriage.md rule 5) and every regular dev can work normally; $best has the most weekly headroom." >/dev/null &&
      log "handed #$n back to $best"
  done
  ready=()
fi
work=("${inflight[@]}" "${ready[@]}"); [ ${#work[@]} -gt 0 ] || exit 0
# don't relaunch in a tight loop if a session keeps ending without progress
last=$(cat "$PF_STATE/reserve-last-launch" 2>/dev/null || echo 0); [ $((now - last)) -lt 1800 ] && exit 0
echo "$now" > "$PF_STATE/reserve-last-launch"
prompt=$(sed -e "s/{{ACCOUNT}}/$PF_ACCOUNT/g" -e "s/{{TICKETS}}/${work[*]}/g" "$PF_DIR/pf-reserve-prompt.md")
log "starting $SESSION for #${work[*]} (needed=$needed)"
printf -v q '%q' "$prompt"
screen -dmS "$SESSION" bash -lc "export PF_ACCOUNT=$PF_ACCOUNT; cd $(printf '%q' "$ROOT") && claude -p $q --dangerously-skip-permissions >> $(printf '%q' "$PF_STATE/at-session.log") 2>&1"
