#!/bin/bash
# Offline test for pf_pr_conflict_risk (#1287): a PR is conflict-risk when the PR, an issue it closes, or the issue its
# head branch names carries the label (rule 6 labels the ticket), and an unreadable GitHub counts as conflict-risk.
# Stub gh first on PATH. No network. macOS, Linux and Git Bash.   bash tools/agents/tests/conflict-risk.sh
AG=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/pf-conflictrisk-test.XXXXXX"); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/state"
# The stub answers the GraphQL call with $T/pr.json (passed through --jq by real jq) and `issue view` with $T/issue.txt.
cat > "$T/bin/gh" <<'STUB'
#!/bin/bash
echo "gh $*" >> "$PF_TEST_LOG"
case "$1 $2" in
  "api graphql")
    [ -f "$PF_TEST_DIR/fail" ] && exit 1
    jqf=; prev=; for a in "$@"; do [ "$prev" = --jq ] && jqf=$a; prev=$a; done
    jq -r "$jqf" "$PF_TEST_DIR/pr.json" | tr -d '';;   # gh's own --jq never writes CR (Windows jq does)
  "issue view") cat "$PF_TEST_DIR/issue.txt" 2>/dev/null;;
  *) exit 1;;
esac
STUB
chmod +x "$T/bin/gh"
git init -q "$T/repo"; git -C "$T/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
export PATH="$T/bin:$PATH" PF_STATE_DIR=$T/state REPO_PATH=$T/repo PF_TEST_LOG=$T/calls.log PF_TEST_DIR=$T PF_ACCOUNT=schans2
. "$AG/pf-env.sh" || exit 1
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
pr() { # pr <branch> <pr labels csv> <closing issue labels csv>
  local pl il
  pl=$(jq -cn --arg s "$2" '$s | split(",") | map(select(length > 0) | {name: .})')
  il=$(jq -cn --arg s "$3" '$s | split(",") | map(select(length > 0) | {name: .})')
  printf '{"data":{"repository":{"pullRequest":{"headRefName":"%s","labels":{"nodes":%s},"closingIssuesReferences":{"nodes":[{"labels":{"nodes":%s}}]}}}}}' "$1" "$pl" "$il" > "$T/pr.json"
}
rc() { pf_pr_conflict_risk 42; echo $?; }

pr "fix/issue-7-x" "review-passed,conflict-risk" ""; : > "$T/issue.txt"
check "T1 label on the PR" "$(rc)" 0
pr "feat/issue-1266-unplug-pits" "review-passed" "enhancement,conflict-risk"
check "T2 label on the closed issue only (#1285)" "$(rc)" 0
pr "feat/issue-9-y" "review-passed" ""; printf 'bug\nconflict-risk\n' > "$T/issue.txt"
check "T3 label on the branch's issue only (no Closes line)" "$(rc)" 0
grep -q "issue view 9 " "$T/calls.log"; check "T3 reads issue 9 from the branch name" "$?" 0
pr "feat/issue-9-y" "review-passed" "bug"; printf 'bug\np2\n' > "$T/issue.txt"
check "T4 no label anywhere" "$(rc)" 1
pr "hotfix-no-issue" "review-passed" ""; printf 'conflict-risk\n' > "$T/issue.txt"; : > "$T/calls.log"
check "T5 branch names no issue: not conflict-risk" "$(rc)" 1
grep -q "issue view" "$T/calls.log"; check "T5 no issue read without an issue number" "$?" 1
touch "$T/fail"
check "T6 GitHub unreadable counts as conflict-risk" "$(rc)" 0
rm -f "$T/fail"
# Both callers use the helper, not a PR-only label check.
for s in pf-automerge.sh pf-ship.sh; do
  grep -q "pf_pr_conflict_risk" "$AG/$s"; check "T7 $s uses pf_pr_conflict_risk" "$?" 0
  grep -qE "labels.*grep -qx conflict-risk" "$AG/$s"; check "T7 $s has no PR-only conflict-risk check" "$?" 1
done

echo "conflict-risk: $pass passed, $fail failed"
[ $fail -eq 0 ]
