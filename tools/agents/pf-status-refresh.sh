#!/bin/bash
# Background cache for the status line (lines 2+). Run by statusline-usage.sh at most every 60 s.
# Line 2: agents n/min · ready me N / <peer> N · PRs · last merge · tm <triagemaster>
# Line 3: peers' usage from their newest USAGE message on the private channel (msg-inbox.log; no GitHub call)
# Then "  #N title" per running agent.
. "$(dirname "$0")/pf-env.sh" || exit 1
R=$ROOT; out=$PF_STATE/pf-status-cache.txt
bash "$PF_DIR/pf-succession.sh" --post >/dev/null 2>&1   # keeps $PF_STATE/pf-triagemaster current
iss=$(set -o pipefail; gh api --paginate "repos/$REPO/issues?state=open&per_page=100" 2>/dev/null | jq -s 'add // []') || exit 0   # every page, one array
ready_for() { echo "$iss" | jq --arg h "$1" '[.[]|select(.pull_request==null)|select(any(.labels[];.name=="ready-for-agent"))|select(any(.assignees[];.login==$h))]|length'; }
rd="ready me $(ready_for "$PF_ACCOUNT")"
for h in $(pf_handles); do [ "$h" = "$PF_ACCOUNT" ] || rd+=" / $h $(ready_for "$h")"; done
prs=$(echo "$iss" | jq '[.[]|select(.pull_request!=null)]|length')
lm=$(gh pr list -R $REPO -s merged -L 1 --json number,mergedAt -q '.[0]|"\(.number) \(.mergedAt)"' 2>/dev/null)
ago=""; if [ -n "$lm" ]; then t=$(pf_iso_to_epoch "${lm#* }"); m=$(( ($(date +%s)-t)/60 )); [ $m -ge 60 ] && ago="$((m/60))h ago" || ago="${m}m ago"; fi
tm=$(pf_triagemaster)
min=$(pf_worker_target)
# running agents = live worktrees on an issue branch, one row per open issue
agents=""; n=0
for i in $(pf_live_agents); do
  t=$(echo "$iss" | jq -r ".[]|select(.number==$i and .pull_request==null)|.title")
  [ -z "$t" ] && continue   # issue closed: not a running agent
  n=$((n+1)); agents+=$'\n'"  #$i $t"
done
# peers' usage, "<handle> 5h N% 7d N%" with the beacon's age once it is an hour old ("?" = no beacon or unknown)
pu=""
for h in $(pf_handles); do
  [ "$h" = "$PF_ACCOUNT" ] && continue
  pf_beacon "$h"
  if [ "$b_age" -ge 999999 ]; then pu+=" · $h ?"; continue; fi
  pu+=" · $h 5h ${b_p5:-?}% 7d ${b_used:-?}%"; [ "$b_age" -ge 3600 ] && pu+=" ($((b_age / 3600))h old)"
done
agents=$'\n'"peers${pu# ·}$agents"
printf 'agents %d/%s · %s · PRs %s · last merge #%s %s · tm %s%s\n' "$n" "$min" "$rd" "$prs" "${lm%% *}" "$ago" "$tm" "$agents" > $out.tmp && mv $out.tmp $out
