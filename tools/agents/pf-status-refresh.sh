#!/bin/bash
# Background cache for the status line (lines 2+). Run by statusline-usage.sh at most every 60 s.
# Line 2: agents n/min · ready me N / <peer> N · PRs · last merge · tm <triagemaster>; then "  #N title" per running agent.
. "$(dirname "$0")/pf-env.sh" || exit 1
R=$ROOT; out=$PF_STATE/pf-status-cache.txt
bash "$PF_DIR/pf-succession.sh" --post >/dev/null 2>&1   # keeps $PF_STATE/pf-triagemaster current
iss=$(gh api "repos/$REPO/issues?state=open&per_page=100" 2>/dev/null) || exit 0
ready_for() { echo "$iss" | jq --arg h "$1" '[.[]|select(.pull_request==null)|select(any(.labels[];.name=="ready-for-agent"))|select(any(.assignees[];.login==$h))]|length'; }
rd="ready me $(ready_for "$PF_ACCOUNT")"
for h in $(pf_handles); do [ "$h" = "$PF_ACCOUNT" ] || rd+=" / $h $(ready_for "$h")"; done
prs=$(echo "$iss" | jq '[.[]|select(.pull_request!=null)]|length')
lm=$(gh pr list -R $REPO -s merged -L 1 --json number,mergedAt -q '.[0]|"\(.number) \(.mergedAt)"' 2>/dev/null)
ago=""; if [ -n "$lm" ]; then t=$(pf_iso_to_epoch "${lm#* }"); m=$(( ($(date +%s)-t)/60 )); [ $m -ge 60 ] && ago="$((m/60))h ago" || ago="${m}m ago"; fi
tm=$(pf_triagemaster)
if [ "$(pf_daynight)" = day ]; then min=$DAY_MIN_AGENTS; else min=$NIGHT_PREFERRED_AGENTS; fi
# running agents = worktrees on an issue branch
agents=""; n=0
for b in $(git -C $R worktree list --porcelain | awk '/^branch /{sub("refs/heads/","",$2);print $2}' | grep -E "issue-[0-9]+"); do
  i=$(echo "$b" | sed -E 's/.*issue-([0-9]+).*/\1/')
  t=$(echo "$iss" | jq -r ".[]|select(.number==$i and .pull_request==null)|.title")
  [ -z "$t" ] && continue   # issue closed: stale worktree, not a running agent
  n=$((n+1)); agents+=$'\n'"  #$i $t"
done
printf 'agents %d/%s · %s · PRs %s · last merge #%s %s · tm %s%s\n' "$n" "$min" "$rd" "$prs" "${lm%% *}" "$ago" "$tm" "$agents" > $out.tmp && mv $out.tmp $out
