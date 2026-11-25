#!/bin/bash
# Offline test for the project priority stack (hive.md rule 28, hive-stack.sh): the studio's hive/projects.conf cached in
# HIVE_STUDIO_CACHE; `next` walks the repos ranked above this game (a hive game: only tickets assigned to this account; a
# repo with no hive.conf, the hive's own: unassigned and unclaimed ones too; p1 before p2 before unlabelled, then oldest);
# `claim` refuses a ticket someone else has; `triage` runs only on the top game's triagemaster. Stub gh, no network.
#   bash tools/agents/tests/stack.sh
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/hive-stack-test.XXXXXX") || exit 1
hive_test_guard
hive_fixture "$T" "STUDIO_REPO=example/studio" || exit 1
mkdir -p "$T/bin" "$T/state" "$T/studio" "$T/gh"
cat > "$T/bin/gh" <<'STUB'
#!/bin/bash
# a tiny gh: issues per repo in $GHD/<owner__repo>.json, comments in $GHD/<owner__repo>.<n>.comments.json; writes logged
repo=""; q="."; label=""; args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case ${args[i]} in -R) repo=${args[i+1]};; -q) q=${args[i+1]};; -l) label=${args[i+1]};; esac
done
slug() { echo "${1/\//__}"; }
case "$1 $2" in
  "api repos/"*)
    path=${2#repos/}; r=${path%%/contents/*}; r=${r%%/issues/*}
    case $path in
      */contents/hive.conf) [ -f "$GHD/$(slug "$r").hive" ] && exit 0; echo '{"message":"Not Found"} (HTTP 404)' >&2; exit 1;;
      */issues/*/comments*) n=${path#*/issues/}; n=${n%%/*}; f="$GHD/$(slug "$r").$n.comments.json"
        [ -f "$f" ] || echo '[]' > "$f"; jq -r "$q" "$f";;
      *) exit 1;;
    esac;;
  "issue list") f="$GHD/$(slug "$repo").json"; [ -f "$f" ] || echo '[]' > "$f"
    if [ -n "$label" ]; then jq --arg l "$label" '[.[] | select([.labels[].name] | index($l))]' "$f" | jq -r "$q"; else jq -r "$q" "$f"; fi;;
  "pr list") f="$GHD/$(slug "$repo").prs.json"; [ -f "$f" ] || echo '[]' > "$f"; jq -r "$q" "$f";;
  "issue view") jq --argjson n "$3" '.[] | select(.number == $n)' "$GHD/$(slug "$repo").json" | jq -r "$q";;
  "issue edit"|"issue comment") echo "$*" >> "$GHD/writes.log";;
  *) exit 1;;
esac
STUB
chmod +x "$T/bin/gh"; hive_stub_jq "$T/bin"
git init -q "$T/root"; git -C "$T/root" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
export PATH="$T/bin:$PATH" HIVE_STATE_DIR=$T/state HIVE_STUDIO_CACHE=$T/studio REPO_PATH=$T/root GHD=$T/gh
hive_require_stub "$T/bin" gh
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
stk() { HIVE_ACCOUNT=${ACCT:-alice} bash "$AG/hive-stack.sh" "$@" 2>/dev/null; }
touch "$T/studio/.synced-at"   # the cache is fresh: no sync
iss() {   # iss <n> <labels csv> <assignee or -> <title>
  local l a; l=$(jq -cn --arg s "$2" '$s | split(",") | map(select(length > 0) | {name: .})'); [ "$3" = - ] && a='[]' || a="[{\"login\":\"$3\"}]"
  printf '{"number":%s,"title":"%s","labels":%s,"assignees":%s}' "$1" "$4" "$l" "$a"
}
touch "$T/gh/example__project.hive" "$T/gh/example__game2.hive"   # hive games; example/hive has no hive.conf

# --- no stack: nothing ranks above this game
check "no stack: next" "$(stk next; echo "exit $?")" "exit 1"
check "no stack: list is this game" "$(stk list)" "example/project"

printf '# header\nexample/hive\r\n example/game2 # comment\nexample/project\nexample/hive\n' > "$T/studio/projects.conf"
check "list: order, comments, CRLF, repeats" "$(stk list | tr '\n' ' ')" "example/hive example/game2 example/project "

# --- next: the hive's own repo first; unassigned counts there, p1 before p2, then oldest
echo "[$(iss 7 ready-for-agent,p2 - "old p2"),$(iss 9 ready-for-agent,p1 - "newer p1"),$(iss 3 needs-triage - "untriaged"),$(iss 4 ready-for-agent,p1 bob "bob's")]" > "$T/gh/example__hive.json"
echo "[$(iss 20 ready-for-agent,p1 - "game2 unassigned"),$(iss 21 ready-for-agent,p2 alice "game2 mine")]" > "$T/gh/example__game2.json"
check "next: hive repo, p1 first, others' skipped" "$(stk next)" "example/hive 9 newer p1"
echo '[{"body":"[CLAIM] carol","user":{"login":"carol"},"created_at":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}]' > "$T/gh/example__hive.9.comments.json"
check "next: a fresh claim by someone else is skipped" "$(stk next)" "example/hive 7 old p2"
echo '[{"body":"[CLAIM] carol","user":{"login":"carol"},"created_at":"2020-01-01T00:00:00Z"}]' > "$T/gh/example__hive.9.comments.json"
check "next: a stale claim is not" "$(stk next)" "example/hive 9 newer p1"
echo '[]' > "$T/gh/example__hive.json"
check "next: a hive game counts only tickets assigned to me" "$(stk next)" "example/game2 21 game2 mine"
echo '[]' > "$T/gh/example__game2.json"
check "next: nothing above: exit 1" "$(stk next; echo "exit $?")" "exit 1"
echo "[$(iss 30 ready-for-agent - "below me")]" > "$T/gh/example__other.json"
printf 'example/project\nexample/other\n' > "$T/studio/projects.conf"
check "next: never looks below this game" "$(stk next; echo "exit $?")" "exit 1"

# --- claim
echo "[$(iss 9 ready-for-agent,p1 - "free"),$(iss 4 ready-for-agent bob "taken")]" > "$T/gh/example__hive.json"
echo '[]' > "$T/gh/example__hive.9.comments.json"
check "claim: free" "$(stk claim example/hive 9)" "claimed example/hive#9"
check "claim: assigns and comments" "$(grep -c -e 'issue edit 9 -R example/hive --add-assignee alice' -e 'issue comment 9 -R example/hive --body \[CLAIM\] alice' "$T/gh/writes.log")" 2
check "claim: someone else's: exit 1" "$(stk claim example/hive 4; echo "exit $?")" "exit 1"
check "claim: bad args: exit 2" "$(stk claim hive x; echo "exit $?")" "exit 2"

# --- triage: only the top hive game's triagemaster, only untriaged issues in the self-serve repos above it
printf 'example/hive\nexample/project\nexample/game2\n' > "$T/studio/projects.conf"
echo "[$(iss 3 needs-triage - "triage me"),$(iss 5 "" - "unlabelled"),$(iss 9 ready-for-agent - "done"),$(iss 6 wontfix - "no")]" > "$T/gh/example__hive.json"
echo alice > "$T/state/triagemaster"
check "triage: top game's triagemaster" "$(stk triage | tr '\n' '|')" "example/hive 3 triage me|example/hive 5 unlabelled|"
check "triage: anyone else: exit 1" "$(ACCT=bob stk triage; echo "exit $?")" "exit 1"
printf 'example/hive\nexample/game2\nexample/project\n' > "$T/studio/projects.conf"
check "triage: not the top game: exit 1" "$(stk triage; echo "exit $?")" "exit 1"

# --- review: the same machine lists the self-serve repos' PRs waiting for review
printf 'example/hive\nexample/project\n' > "$T/studio/projects.conf"
echo '[{"number":40,"title":"waiting","isDraft":false,"labels":[]},{"number":41,"title":"draft","isDraft":true,"labels":[]},{"number":42,"title":"passed","isDraft":false,"labels":[{"name":"review-passed"}]},{"number":43,"title":"blocked","isDraft":false,"labels":[{"name":"review-blocked"}]}]' > "$T/gh/example__hive.prs.json"
check "review: top game's triagemaster" "$(stk review | tr '\n' '|')" "example/hive 40 waiting|"
check "review: anyone else: exit 1" "$(ACCT=bob stk review; echo "exit $?")" "exit 1"

echo "stack: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
