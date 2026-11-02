#!/bin/bash
# Offline test for pf-triage-watch.sh's in-progress check (#1147): pf_pr_tickets reads canned
# `gh pr list --json number,body,title,headRefName` output, pf_ticket_in_progress adds the branch-name match.
# A scratch git repo stands in for ROOT. No network. macOS, Linux and Git Bash.   bash tools/agents/tests/triage-watch-in-progress.sh
AG=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/pf-triage-test.XXXXXX") || exit 1; trap 'rm -rf "$T"' EXIT
. "$AG/pf-triage-watch.sh" --functions || exit 1
ROOT=$T/repo; git init -q "$ROOT"
git -C "$ROOT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$ROOT" branch feat/issue-700-slug; git -C "$ROOT" branch fix/800-slug
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
busy() { pf_ticket_in_progress "$1" "$2" && echo yes || echo no; }
PRS='[
 {"number":1,"title":"feat: three tickets in one","headRefName":"feat/issue-1133-multi","body":"Closes #1134, closes #1135.\nFIXES: #42\nRefs #115"},
 {"number":2,"title":"Fixes #9 and resolved #10","headRefName":"chore/no-number","body":null},
 {"number":3,"title":"docs","headRefName":"fix/900-typo","body":"prefix #77, see #78, issue #79"}
]'
refs=$(pf_pr_tickets "$PRS")
check "pr tickets" "$refs" "10 1133 1134 1135 115 42 9 900"
# a PR body or title makes the ticket in progress with no branch for it
check "closes in body" "$(busy 1135 "$refs")" yes
check "keyword case" "$(busy 42 "$refs")" yes
check "refs in body" "$(busy 115 "$refs")" yes
check "fixes in title" "$(busy 9 "$refs")" yes
check "null body" "$(busy 10 "$refs")" yes
check "pr head branch" "$(busy 1133 "$refs")" yes
check "pr head fix/N-" "$(busy 900 "$refs")" yes
# exact number: #115 is not #11 (nor #1, #15); a bare #N or another word ending in fix is no reference
check "#11 vs #115" "$(busy 11 "$refs")" no
check "#1 vs #115" "$(busy 1 "$refs")" no
check "#15 vs #115" "$(busy 15 "$refs")" no
check "prefix #77" "$(busy 77 "$refs")" no
check "see #78" "$(busy 78 "$refs")" no
# branch-name behaviour unchanged: local branches match with or without any PR
check "issue-N branch" "$(busy 700 "$refs")" yes
check "fix/N- branch" "$(busy 800 "")" yes
check "issue-70 vs issue-700" "$(busy 70 "$refs")" no
check "no branch, no pr" "$(busy 1147 "$refs")" no
# gh failure or no open PRs: only branches count
check "empty pr list" "$(pf_pr_tickets "")" ""
check "no prs" "$(pf_pr_tickets "[]")" ""
check "no prs, branch" "$(busy 700 "")" yes
echo "triage-watch-in-progress: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
