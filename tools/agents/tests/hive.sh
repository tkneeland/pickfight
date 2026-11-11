#!/bin/bash
# Offline test for pf-hive.sh status (#1208): a canned msg-inbox.log, a stub gh (one canned issues answer) and a stub
# Discord check, a scratch repo with one issue worktree. Checks each line of the full and --short forms, the cache
# (--cached), GitHub unreachable, and the 15 s budget. No network. macOS, Linux and Git Bash.   bash tools/agents/tests/hive.sh
AG=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/pf-hive-status-test.XXXXXX") && [ -d "$T" ] || { echo "hive: cannot make a scratch dir" >&2; exit 1; }
T=$(cd "$T" && pwd) && case $T in */pf-hive-status-test.*) ;; *) echo "hive: odd scratch dir '$T'" >&2; exit 1;; esac
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/state"
cat > "$T/bin/gh" <<'STUB'
#!/bin/bash
echo "gh $*" >> "$PF_TEST_LOG"
[ -n "$PF_TEST_GH_SLEEP" ] && sleep "$PF_TEST_GH_SLEEP"
[ -n "$PF_TEST_GH_DOWN" ] && exit 1
case "$*" in
  "api --paginate repos/"*"/issues?state=open"*) cat "$PF_TEST_ISSUES";;
  "issue list"*) echo 901; echo 902; echo 903; echo 904; echo 905; echo 685;;   # pf_live_agents' open issues
  *) exit 1;;
esac
STUB
cat > "$T/bin/discord" <<'STUB'
#!/bin/bash
case "$*" in "--dev check") exit 1;; check) echo 3; exit 0;; esac; exit 2
STUB
chmod +x "$T/bin/gh" "$T/bin/discord"
[ "$(command -v gh)" != "$T/bin/gh" ] && PATH="$T/bin:$PATH"
[ "$(command -v gh)" = "$T/bin/gh" ] || { echo "hive: stub gh not first on PATH; refusing to touch the network" >&2; exit 1; }
git init -q "$T/repo"; git -C "$T/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$T/repo" worktree add -q -b feat/issue-901-thing "$T/repo/wt901" 2>/dev/null
export PATH PF_STATE_DIR=$T/state REPO_PATH=$T/repo PF_TEST_LOG=$T/calls.log PF_TEST_ISSUES=$T/issues.json \
  PF_HIVE_DISCORD=$T/bin/discord PF_ACCOUNT=schans2
. "$AG/pf-env.sh" || exit 1
now=$(date +%s); iso() { TZ=UTC pf_epoch_fmt "$1" +%Y-%m-%dT%H:%M:%SZ; }
S=$T/state; INBOX=$S/msg-inbox.log
echo tkneeland > "$S/pf-triagemaster"
echo '{}' > "$S/msg-status.json"                 # this machine's channel supervisor is up
touch "$S/.discord-bugs-last"                     # #change-requests triaged here before; #hive never
# own usage: 5h 7% resetting 2026-11-12 03:00 ET, 7d 30% resetting Thu 2026-11-12 12:00 ET (EST, UTC-5)
echo '{"rate_limits":{"five_hour":{"used_percentage":7.4,"resets_at":1794470400},"seven_day":{"used_percentage":30,"resets_at":1794502800}}}' > "$S/usage-snapshot.json"
{ echo "$((now - 30 * 3600))|agage-JG|FIRE|old fire"
  echo "$((now - 3 * 3600))|agage-JG|HELLO|agage-JG"
  echo "$((now - 3 * 3600))|agage-JG|USAGE|50% 80% 2026-11-14T15:00:00Z r5=2026-11-12T18:30:00Z agents=0 at=$(iso $((now - 3 * 3600)))"
  echo "$((now - 3600))|agage-JG|FIRE|build broken on main"
  echo "$((now - 900))|tkneeland|CLAIM|902"
  echo "$((now - 900))|tkneeland|CLAIM|903"
  echo "$((now - 600))|tkneeland|RELEASE|903"
  echo "$((now - 600))|tkneeland|CLAIM|950"
  echo "$((now - 300))|tkneeland|USAGE|12% 40% 2026-11-12T17:00:00Z r5=2026-11-11T21:00:00Z agents=2 at=$(iso $((now - 300)))"
  echo "$((now - 300))|tkneeland|HELLO|tkneeland"; } > "$INBOX"
# label <name>, assignee <login>
cat > "$T/issues.json" <<'JSON'
[{"number":901,"title":"a","labels":[{"name":"ready-for-agent"}],"assignees":[{"login":"schans2"}],"user":{"login":"tkneeland"},"body":""},
 {"number":902,"title":"b","labels":[{"name":"ready-for-agent"}],"assignees":[{"login":"tkneeland"}],"user":{"login":"tkneeland"},"body":""},
 {"number":903,"title":"c","labels":[{"name":"ready-for-agent"}],"assignees":[{"login":"tkneeland"}],"user":{"login":"tkneeland"},"body":""},
 {"number":904,"title":"d","labels":[{"name":"needs-triage"}],"assignees":[],"user":{"login":"tkneeland"},"body":""},
 {"number":905,"title":"e","labels":[{"name":"ready-for-human"}],"assignees":[{"login":"tkneeland"}],"user":{"login":"tkneeland"},"body":""},
 {"number":685,"title":"Austin list","labels":[],"assignees":[],"user":{"login":"tkneeland"},
  "body":"Intro\n- [ ] not under a heading\n## Open\n### Business\n- [ ] one\n- [x] done\n  - [ ] two\n## Decided\n- [ ] closed one"},
 {"number":910,"title":"p","labels":[{"name":"review-passed"}],"assignees":[],"user":{"login":"schans2"},"pull_request":{}},
 {"number":911,"title":"q","labels":[{"name":"review-blocked"}],"assignees":[],"user":{"login":"schans2"},"pull_request":{}},
 {"number":912,"title":"r","labels":[],"assignees":[],"user":{"login":"tkneeland"},"pull_request":{}}]
JSON
pass=0; fail=0
has() { case $2 in *"$3"*) pass=$((pass+1));; *) fail=$((fail+1)); echo "FAIL $1: no '$3' in:"; echo "$2" | sed 's/^/    /';; esac; }
line() { printf '%s\n' "$1" | grep -A1 "^$2 " | head -n "${3:-1}" | tail -n 1; }   # line <out> <handle> [1|2]

t0=$(date +%s)
out=$(bash "$AG/pf-hive.sh" status); rc=$?
el=$(( $(date +%s) - t0 ))
[ "$rc" = 0 ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL full: exit $rc"; }
[ "$el" -lt 15 ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL full: took ${el}s (budget 15)"; }
has "one gh call" "$(grep -c 'api --paginate' "$T/calls.log")" 1
has "no other gh call (live agents reuse it)" "$(grep -c . "$T/calls.log")" 1
has "header" "$(printf '%s\n' "$out" | head -n 1)" "schans2's view · tm tkneeland"
has "header in ET" "$(printf '%s\n' "$out" | head -n 1)" "$(TZ=$PF_ET_TZ pf_epoch_fmt "$t0" '+%a') "
l=$(line "$out" tkneeland); l2=$(line "$out" tkneeland 2)
has "tk online" "$l" "online 5m"; has "tk role" "$l" "triagemaster"
has "tk 5h ET" "$l" "5h 12% (r 4p)"; has "tk 7d ET" "$l" "7d 40% (r Thu 12p)"; has "tk agents" "$l" "agents 2"
has "tk claimed (released and closed dropped)" "$l2" "claimed #902 ·"; has "tk ready" "$l2" "ready 2"; has "tk PRs" "$l2" "PRs #912 waiting"
l=$(line "$out" agage-JG); l2=$(line "$out" agage-JG 2)
has "aj offline" "$l" "offline 3h"; has "aj role" "$l" "· dev ·"; has "aj stale usage" "$l" "(3h old)"
has "aj 5h ET" "$l" "5h 50% (r 1:30p)"; has "aj 7d ET" "$l" "7d 80% (r Sat 10a)"; has "aj agents" "$l" "agents 0"
has "aj none" "$l2" "claimed none · ready 0 · PRs none"
l=$(line "$out" schans2); l2=$(line "$out" schans2 2)
has "me online" "$l" "online (this machine)"; has "me usage" "$l" "5h 7% (r 3a) · 7d 30% (r Thu 12p)"; has "me agents" "$l" "agents 1"
has "me claimed" "$l2" "claimed #901"; has "me ready" "$l2" "ready 1"; has "me PRs" "$l2" "PRs #910 passed, #911 blocked"
l=$(line "$out" tommykneeland)
has "reserve" "$l" "offline (never heard) · reserve · usage ? · agents ?"
team=$(printf '%s\n' "$out" | grep '^team')
has "fires (24h only, latest)" "$team" "fires 24h 1 (latest: agage-JG: build broken on main)"
has "change-requests" "$team" "#change-requests 3 unhandled"
has "hive never triaged here" "$team" "#hive n/a (not triaged on this machine)"
has "needs-triage" "$team" "needs-triage 1 waiting for ✅"
has "tommy" "$team" "Tommy: 2 open on #685, 1 ready-for-human"

# --short: one line per account plus the team line, also saved as the cache
s=$(bash "$AG/pf-hive.sh" status --short)
has "short tk" "$s" "tkneeland: on 5m · TM · 5h12% 7d40% · agents 2 · claimed #902 · ready 2 · PRs 0 passed/0 blocked/1 waiting"
has "short me" "$s" "schans2: on · dev · 5h7% 7d30% · agents 1 · claimed #901 · ready 1 · PRs 1 passed/1 blocked/0 waiting"
has "short aj" "$s" "agage-JG: off 3h · dev · 5h50% 7d80%(3h old) · agents 0 · claimed none · ready 0 · PRs none"
has "short team" "$s" "team: fires 24h 1"
has "short lines" "$(printf '%s\n' "$s" | wc -l | tr -d ' ')" 6
has "cache saved" "$(cat "$S/hive-status-short.txt")" "$s"

# --cached prints the cache with no gh call (PF_DRY_RUN: no background refresh); nothing cached is exit 3
: > "$T/calls.log"
c=$(PF_DRY_RUN=1 bash "$AG/pf-hive.sh" status --short --cached)
has "cached" "$c" "$s"; has "cached: no gh" "$(grep -c . "$T/calls.log")" 0
# a stale cache refreshes in the background, and a captured call never waits for it (the refresh's gh takes 6 s here)
touch -t 202001010000 "$S/hive-status-short.txt"; t0=$(date +%s)
c=$(PF_TEST_GH_SLEEP=6 bash "$AG/pf-hive.sh" status --short --cached); el=$(( $(date +%s) - t0 ))
[ "$el" -le 2 ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL cached: a captured call waited ${el}s for the refresh"; }
has "cached: stale one still printed" "$c" "$s"
i=0; while [ -d "$S/.hive-refresh.lock" ] && [ "$i" -lt 150 ]; do sleep 0.2; i=$((i+1)); done   # let the refresh finish
has "cached: the refresh ran" "$(grep -c 'api --paginate' "$T/calls.log")" 1
rm -f "$S/hive-status-short.txt"; PF_DRY_RUN=1 bash "$AG/pf-hive.sh" status --short --cached >/dev/null
has "nothing cached: exit 3" "$?" 3

# GitHub unreachable: the inbox half still shows, GitHub numbers are "?"
bash "$AG/pf-hive.sh" status --short >/dev/null; good=$(cat "$S/hive-status-short.txt")
g=$(PF_TEST_GH_DOWN=1 bash "$AG/pf-hive.sh" status --short)
has "gh down: last good cache kept" "$(cat "$S/hive-status-short.txt")" "$good"
has "gh down: note" "$g" "(GitHub unreachable"; has "gh down: usage still" "$g" "tkneeland: on 5m · TM · 5h12%"
has "gh down: ready ?" "$g" "ready ? · PRs ?"; has "gh down: team ?" "$g" "needs-triage ? waiting"

echo "hive: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
