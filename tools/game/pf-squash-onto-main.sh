#!/bin/bash
# Finishes a `git merge origin/main` on a ticket branch as one squashed commit on top of main instead of a merge
# commit. The secret-scrub commit hook scans the whole staged merge, main's lines included, and main carries long
# identifiers it reads as secrets; a squash stages only this branch's own changes, so the hook sees just those.
#   pf-squash-onto-main.sh "<commit message>"   run inside the worktree once the merge is resolved and staged
# Leaves the branch at main + one commit; push it with --force-with-lease. Exits 1 with the merge untouched if no
# merge is in progress or anything is still unstaged or unmerged.
set -euo pipefail
msg=${1:?usage: pf-squash-onto-main.sh \"<commit message>\"}
main=$(git rev-parse -q --verify MERGE_HEAD) || { echo "no merge in progress"; exit 1; }
[ -z "$(git diff --name-only --diff-filter=U)" ] || { echo "unmerged files remain"; exit 1; }
git diff --quiet || { echo "unstaged changes remain: stage or drop them first"; exit 1; }
patch=$(mktemp)
trap 'rm -f "$patch"' EXIT
git diff --cached --binary "$main" > "$patch"
[ -s "$patch" ] || { echo "branch adds nothing on top of main"; exit 1; }
git merge --abort
git reset -q --hard "$main"
git apply --index "$patch"
git commit -q -m "$msg"
git log --oneline -1
