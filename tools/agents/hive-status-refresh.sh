#!/bin/bash
# Background cache for the status line (lines 2+). Run by statusline.sh at most every 60 s.
# Line 2: agents n/min · ready me N / <peer> N · PRs · last merge · tm <triagemaster>
# Line 3 (several accounts): peers' usage from their newest USAGE message on the private channel (msg-inbox.log; no GitHub call)
# Then "  #N title" per running agent, mine first, then "  #N title (peer)" for each peer agent (an issue branch a peer
# pushed to in the last PEER_ACTIVE_HOURS).
. "$(dirname "$0")/hive-env.sh" || exit 1
R=$ROOT; out=$HIVE_STATE/status-cache.txt
if [ "$TRACKER" = local ]; then
  # Line 2: agents n/min · triage N · ready N · doing N · review N · PRs N; then one line per active Atlas work package
  c() { hive_tickets "$1" | wc -l | tr -d ' '; }
  min=$(hive_worker_target)
  prs=0; for rp in $REPO_PATHS; do k=$(cd "$rp" 2>/dev/null && gh pr list --author @me --json number -q length 2>/dev/null); prs=$((prs+${k:-0})); done
  agents=""; for f in "$R"/.claude/atlas-state/*.json; do [ -e "$f" ] || continue; agents+=$'\n'"  $(basename "$f" .json)"; done
  extra=""; [ -n "${STATUS_HOOK:-}" ] && extra=" · $(cd "$HIVE_ROOT" && bash -c "$STATUS_HOOK" 2>/dev/null | head -1)"
  printf 'agents %s/%s · triage %s · ready %s · doing %s · review %s · PRs %s%s%s\n' "$(hive_active_packages)" "$min" "$(c needs-triage)" "$(c ready-for-agent)" \
    "$(c 'planning|plan-review|in-progress|ai-review')" "$(c 'human-review|ready-for-human')" "$prs" "$extra" "$agents" > "$out.tmp.$$" && mv "$out.tmp.$$" "$out"
  exit 0
fi
bash "$HIVE_DIR/hive-succession.sh" --post >/dev/null 2>&1   # keeps $HIVE_STATE/triagemaster current
iss=$(set -o pipefail; gh api --paginate "repos/$REPO/issues?state=open&per_page=100" 2>/dev/null | jq -s 'add // []') || exit 0   # every page, one array
ready_for() { echo "$iss" | jq --arg h "$1" '[.[]|select(.pull_request==null)|select(any(.labels[];.name=="ready-for-agent"))|select(any(.assignees[];.login==$h))]|length'; }
rd="ready me $(ready_for "$HIVE_ACCOUNT")"
for h in $(hive_handles); do [ "$h" = "$HIVE_ACCOUNT" ] || rd+=" / $h $(ready_for "$h")"; done
prs=$(echo "$iss" | jq '[.[]|select(.pull_request!=null)]|length')
lm=$(gh pr list -R "$REPO" -s merged -L 1 --json number,mergedAt -q '.[0]|"\(.number) \(.mergedAt)"' 2>/dev/null)
ago=""; if [ -n "$lm" ]; then t=$(hive_iso2epoch "${lm#* }"); m=$(( ($(date +%s)-t)/60 )); [ $m -ge 60 ] && ago="$((m/60))h ago" || ago="${m}m ago"; fi
tm=$(hive_triagemaster)
min=$(hive_worker_target)
# running agents = live worktrees on an issue branch, one row per open issue
agents=""; n=0
for i in $(hive_live_agents); do
  t=$(echo "$iss" | jq -r ".[]|select(.number==$i and .pull_request==null)|.title" | cut -c1-60)
  [ -z "$t" ] && continue   # issue closed: not a running agent
  n=$((n+1)); agents+=$'\n'"  #$i $t"
done
# peer agents run on other machines: an issue branch a peer pushed to recently, issue still open
peers=$(hive_peers | jq -R . | jq -sc .)
peer=$(gh api graphql -f query="{repository(owner:\"${REPO%/*}\",name:\"${REPO#*/}\"){refs(refPrefix:\"refs/heads/\",first:100,query:\"issue-\"){nodes{name target{... on Commit{committedDate author{user{login}}}}}}}}" \
  --jq ".data.repository.refs.nodes[]|select(.target.author.user.login|IN($peers[]))|select((.target.committedDate|fromdate) > (now-${PEER_ACTIVE_HOURS:-3}*3600))|\"\\(.name) \\(.target.author.user.login)\"" 2>/dev/null)
while read -r b who; do
  [ -z "$b" ] && continue
  i=$(echo "$b" | sed -E 's/.*issue-([0-9]+).*/\1/')
  t=$(echo "$iss" | jq -r ".[]|select(.number==$i and .pull_request==null)|.title" | cut -c1-55)
  [ -z "$t" ] && continue
  agents+=$'\n'"  #$i $t ($who)"
done <<< "$peer"
# peers' usage, "<handle> 5h N% 7d N%" with the beacon's age once it is an hour old ("?" = no beacon or unknown)
if [ "$SINGLE_ACCOUNT" != 1 ]; then
  hive_usage_backfill; pu=""
  for h in $(hive_handles); do
    [ "$h" = "$HIVE_ACCOUNT" ] && continue
    hive_beacon "$h"
    if [ "$b_age" -ge 999999 ]; then pu+=" · $h ?"; continue; fi
    pu+=" · $h 5h ${b_p5:-?}%${b_pace:+ $b_pace} 7d ${b_used:-?}%"; [ "$b_age" -ge 3600 ] && pu+=" ($((b_age / 3600))h old)"
  done
  [ -n "$pu" ] && agents=$'\n'"peers${pu# ·}$agents"
fi
printf 'agents %d/%s · %s · PRs %s · last merge #%s %s · tm %s%s\n' "$n" "$min" "$rd" "$prs" "${lm%% *}" "$ago" "$tm" "$agents" > "$out.tmp.$$" && mv "$out.tmp.$$" "$out"
