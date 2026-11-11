#!/bin/bash
# One screen of the whole hive, on any machine (#1208). Modelled on the status line (statusline-usage.sh,
# pf-status-refresh.sh): peers from the private channel's inbox (msg-inbox.log), GitHub from one batched call.
#   pf-hive.sh status            per account: online/offline (last HELLO/USAGE, with its age), role, 5h and 7d usage
#                                with resets in ET, running agents, claimed tickets, ready queue, open PRs by review
#                                state; then the team: fires, unhandled #change-requests and #hive, needs-triage
#                                waiting for a ✅, decisions waiting on Tommy (#685, ready-for-human on tkneeland)
#   pf-hive.sh status --short    the compact form for posting (rule 21: "status" in #hive replies with it)
#   pf-hive.sh status --short --cached
#                                prints the last --short result at once and refreshes it in the background (the
#                                SessionStart hook, which has 4 s); exit 3 with nothing cached yet. PF_DRY_RUN=1: no refresh
# Every run saves its --short form to $PF_STATE/hive-status-short.txt.
# Sources: claimed = a peer's CLAIMs on the channel (24 h, not RELEASEd) / this machine's issue worktrees, both on
# open issues; agents = a peer's USAGE agents= / this machine's live worktrees (pf_live_agents). #change-requests and
# #hive counts come from `pf-discord-bugs.sh [--dev] check` on a machine that has triaged them (its marker exists),
# else "n/a". Env: PF_HIVE_DISCORD (tests: the Discord check command), PF_DISCORD_TIMEOUT (default here 6 s).
AG=$(cd "$(dirname "$0")" && pwd)
. "$AG/pf-env.sh" || exit 1
INBOX=$PF_STATE/msg-inbox.log
CACHE=$PF_STATE/hive-status-short.txt
[ "${1:-}" = status ] || { sed -n '2,17p' "$0"; exit 2; }
shift; short=""; cached=""
for a in "$@"; do case $a in --short) short=1;; --cached) cached=1;; *) echo "pf-hive: unknown option $a" >&2; exit 2;; esac; done
if [ -n "$cached" ]; then   # never waits on the network: prints the cache (exit 0) or nothing (exit 3), then refreshes
  [ -z "${PF_DRY_RUN:-}" ] && (bash "$0" status --short >/dev/null 2>&1 &)
  [ -s "$CACHE" ] || exit 3
  m=$(( ($(date +%s) - $(pf_mtime "$CACHE")) / 60 ))
  cat "$CACHE"; [ "$m" -ge 2 ] && echo "(as of ${m} min ago)"
  exit 0
fi

now=$(date +%s)
et() { TZ=$PF_ET_TZ pf_epoch_fmt "$1" "$2" | sed 's/AM$/a/;s/PM$/p/;s/:00\([ap]\)$/\1/'; }   # et <epoch> <+fmt>
iso_et() { local e; [ -n "$1" ] && e=$(pf_iso_to_epoch "$1") && et "$e" "$2"; }
ago() { local s=$1; if [ "$s" -lt 3600 ]; then echo "$((s / 60))m"; elif [ "$s" -lt 172800 ]; then echo "$((s / 3600))h"; else echo "$((s / 86400))d"; fi; }

# Discord counts in the background while GitHub answers (each is a network call)
D=$(mktemp -d "${TMPDIR:-/tmp}/pf-hive.XXXXXX") || exit 1; trap 'rm -rf "$D"' EXIT
discord() {  # discord <bugs|dev>: the unhandled count, or n/a
  local k=$1 cmd=${PF_HIVE_DISCORD:-bash $AG/pf-discord-bugs.sh} n rc
  if [ ! -f "$PF_STATE/pf-discord.conf" ] && [ -z "${PF_HIVE_DISCORD:-}" ]; then echo "n/a"; return; fi
  [ -f "$PF_STATE/.discord-$k-last" ] || { echo "n/a"; return; }   # never triaged here: a first check would count old history
  if [ "$k" = dev ]; then n=$(PF_DISCORD_TIMEOUT=${PF_DISCORD_TIMEOUT:-6} $cmd --dev check 2>/dev/null); rc=$?
  else n=$(PF_DISCORD_TIMEOUT=${PF_DISCORD_TIMEOUT:-6} $cmd check 2>/dev/null); rc=$?; fi
  case $rc in 0) echo "${n:-?}";; 1) echo 0;; *) echo "?";; esac
}
discord bugs > "$D/bugs" & discord dev > "$D/dev" &
# this machine's live agents scan its worktrees (slow on Windows): also in the background
{ pf_live_agents > "$D/live"; touch "$D/live.done"; } &

# GitHub: every open issue and PR, labels, assignees, authors and bodies, in one paginated call
iss=$(set -o pipefail; gh api --paginate "repos/$REPO/issues?state=open&per_page=100" 2>/dev/null | jq -s 'add // []') || iss=""
gh_ok=1; [ -n "$iss" ] || { gh_ok=""; iss='[]'; }
open_issues=$(echo "$iss" | jq -r '[.[] | select(.pull_request == null) | .number] | join(" ")')
tm=$(pf_triagemaster)
# per account, one line: "<handle> <ready> <PRs passed> <blocked> <waiting> <#n_state,_...>" (one jq for all: forks are slow on Windows)
per_gh=$(echo "$iss" | jq -r --arg hs "$(pf_handles | tr '\n' ' ')" '. as $all | ($hs | split(" ") | map(select(. != "")))[] as $h |
  [$all[] | select(.pull_request == null) | select(any(.labels[]; .name == "ready-for-agent")) | select(any(.assignees[]; .login == $h))] as $r |
  [$all[] | select(.pull_request != null and .user.login == $h) |
    {n: .number, s: (if any(.labels[]; .name == "review-passed") then "passed" elif any(.labels[]; .name == "review-blocked") then "blocked" else "waiting" end)}] as $p |
  "\($h) \($r | length) \([$p[] | select(.s == "passed")] | length) \([$p[] | select(.s == "blocked")] | length) \([$p[] | select(.s == "waiting")] | length) \([$p[] | "#\(.n) \(.s)"] | join(", ") | gsub(" "; "_"))"')

fires=$(awk -F'|' -v t="$now" '$3 == "FIRE" && $1 + 86400 >= t' "$INBOX" 2>/dev/null)
nfires=$(printf '%s' "$fires" | grep -c . || true)

# row <handle>: its two full lines to $D/row.<handle>, its short line to $D/srow.<handle>. Rows run in parallel.
row() {
  local h=$1 role on son s last use suse agents claimed ready pr_pass pr_block pr_wait prs srole sprs
  role=dev; [ "$h" = "$tm" ] && role=triagemaster
  [ "$role" = dev ] && grep -q '^RESERVE=1' "$PF_DIR/accounts/$h.conf" 2>/dev/null && role=reserve
  # online: this machine by its channel supervisor (msg-status.json, rewritten every minute); a peer by its last HELLO/USAGE
  if [ "$h" = "$PF_ACCOUNT" ]; then
    s=$(pf_mtime "$PF_STATE/msg-status.json" || true)
    if [ -n "$s" ] && [ $((now - s)) -le 180 ]; then on="online (this machine)"; son="on"; else on="channel down (this machine)"; son="down"; fi
  else
    last=$(awk -F'|' -v p="$h" '$2 == p && ($3 == "HELLO" || $3 == "USAGE") && $1 + 0 > m { m = $1 + 0 } END { print int(m) }' "$INBOX" 2>/dev/null)
    if [ "${last:-0}" -le 0 ]; then on="offline (never heard)"; son="off"
    elif [ $((now - last)) -le 3600 ]; then on="online $(ago $((now - last)))"; son="on $(ago $((now - last)))"
    else on="offline $(ago $((now - last)))"; son="off $(ago $((now - last)))"; fi
  fi
  pf_beacon "$h"
  if [ "$b_age" -ge 999999 ]; then use="usage ?"; suse="?"
  else
    use="5h ${b_p5:-?}%"; [ -n "$b_r5" ] && use+=" (r $(iso_et "$b_r5" +%-I:%M%p))"
    use+=" · 7d ${b_used:-?}%"; [ -n "$b_reset" ] && use+=" (r $(iso_et "$b_reset" '+%a %-I:%M%p'))"
    suse="5h${b_p5:-?}% 7d${b_used:-?}%"
    [ "$b_age" -ge 3600 ] && { use+=" ($(ago "$b_age") old)"; suse+="($(ago "$b_age") old)"; }
  fi
  if [ "$h" = "$PF_ACCOUNT" ]; then
    while [ ! -f "$D/live.done" ]; do sleep 0.2; done
    agents=$(grep -c . "$D/live")
    claimed=$(git -C "$ROOT" worktree list --porcelain 2>/dev/null | sed -nE 's#^branch refs/heads/.*issue-([0-9]+).*#\1#p')
  else
    agents=$(awk -F'|' -v p="$h" '$2 == p && $3 == "USAGE" && $1 + 0 >= m { m = $1 + 0; l = $4 } END { print l }' "$INBOX" 2>/dev/null |
      sed -n 's/.*agents=\([0-9]*\).*/\1/p'); agents=${agents:-?}
    claimed=$(awk -F'|' -v p="$h" -v t="$now" '$2 == p { split($4, w, " ")
        if ($3 == "CLAIM" && $1 + 86400 >= t) c[w[1]] = 1; else if ($3 == "RELEASE") delete c[w[1]] }
      END { for (n in c) print n }' "$INBOX" 2>/dev/null)
  fi
  claimed=$(for n in $claimed; do case " $open_issues " in *" $n "*) echo "#$n";; esac; done | sort -u | tr '\n' ' ')
  claimed=${claimed% }
  # ready queue and PRs from the one GitHub answer (worked out for every account at once, above)
  read -r _ ready pr_pass pr_block pr_wait prs <<EOT
$(echo "$per_gh" | awk -v h="$h" '$1 == h')
EOT
  prs=${prs//_/ }
  [ -n "$gh_ok" ] || { ready="?"; prs="?"; }
  { printf '%-14s %s · %s · %s · agents %s\n' "$h" "$on" "$role" "$use" "$agents"
    printf '%-14s claimed %s · ready %s · PRs %s\n' "" "${claimed:-none}" "$ready" "${prs:-none}"; } > "$D/row.$h"
  srole=$role; case $role in triagemaster) srole=TM;; esac
  sprs="none"; [ -n "$gh_ok" ] || sprs="?"
  [ -n "$gh_ok" ] && [ $((pr_pass + pr_block + pr_wait)) -gt 0 ] && sprs="${pr_pass} passed/${pr_block} blocked/${pr_wait} waiting"
  echo "$h: $son · $srole · $suse · agents $agents · claimed ${claimed:-none} · ready $ready · PRs $sprs" > "$D/srow.$h"
}
for h in $(pf_handles); do row "$h" & done

# team counts, one jq: needs-triage; #685's unticked "- [ ]" items under its "## Open" heading; ready-for-human on tkneeland
if [ -n "$gh_ok" ]; then
  read -r triage tommy rfh <<EOT
$(echo "$iss" | jq -r '[.[] | select(.pull_request == null)] as $i |
  ([$i[] | select(any(.labels[]; .name == "needs-triage"))] | length) as $t |
  ([$i[] | select(.number == 685)][0].body // "" | split("\n") |
    reduce .[] as $x ({o: false, n: 0}; if ($x | test("^## ")) then .o = ($x | test("^## Open"))
      elif .o and ($x | test("^\\s*- \\[ \\]")) then .n += 1 else . end) | .n) as $o |
  ([$i[] | select(any(.labels[]; .name == "ready-for-human")) | select(any(.assignees[]; .login == "tkneeland"))] | length) as $r |
  "\($t) \($o) \($r)"')
EOT
else triage="?"; tommy="?"; rfh="?"; fi
wait
bugs=$(cat "$D/bugs"); dev=$(cat "$D/dev")
rows=""; srows=""
for h in $(pf_handles); do rows+=$(cat "$D/row.$h")$'\n'; srows+=$(cat "$D/srow.$h")$'\n'; done
lastfire=""; [ "$nfires" -gt 0 ] && lastfire=" (latest: $(printf '%s\n' "$fires" | tail -n 1 | awk -F'|' '{ r = $4; for (i = 5; i <= NF; i++) r = r "|" $i; print $2 ": " r }' | cut -c1-120))"
unh() { case $1 in ''|*[!0-9]*) echo "$1 (not triaged on this machine)";; *) echo "$1 unhandled";; esac; }
[ "$bugs" = "?" ] || bugs=$(unh "$bugs"); [ "$dev" = "?" ] || dev=$(unh "$dev")
team="fires 24h $nfires$lastfire · #change-requests $bugs · #hive $dev · needs-triage $triage waiting for ✅ · Tommy: $tommy open on #685, $rfh ready-for-human"
stamp="$(et "$now" '+%a %-I:%M%p') ET"

sout="hive $stamp ($PF_ACCOUNT's view)"$'\n'"$srows""team: $team"
[ -n "$gh_ok" ] || sout+=$'\n'"(GitHub unreachable: ready, PRs and triage counts unknown)"
printf '%s\n' "$sout" > "$CACHE.tmp" && mv "$CACHE.tmp" "$CACHE"
if [ -n "$short" ]; then printf '%s\n' "$sout"; exit 0; fi
echo "hive · $stamp · $PF_ACCOUNT's view · tm $tm"
printf '%s' "$rows"
echo "team           $team"
[ -n "$gh_ok" ] || echo "(GitHub unreachable: ready, PRs and triage counts unknown)"
exit 0
