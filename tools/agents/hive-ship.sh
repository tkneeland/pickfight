#!/bin/bash
# Usage: hive-ship.sh <issue|local-id> "<title>" "<summary body>" [repo-name] [--refs]
# Merges the main branch into the ticket's worktree branch (WORKTREE_ROOT/<ticket>/<repo-name>, "/" in a local id becomes
# "-"), runs TEST_CMD and the fresh-clone boot check (BOOT_CHECK_CMD) if configured, pushes, opens the PR against
# MAIN_BRANCH (or reuses the branch's open PR on a re-run, refreshing its body), waits for CI, merges (MERGE_METHOD) and
# runs INSTALL_CMD. repo-name defaults to REPO's name, or the only REPO_PATHS entry. Agent worktrees work too: when the
# ticket worktree is missing it falls back to the current checkout if its branch names the issue.
#   --refs: the PR only partly fixes the ticket. The body says "Refs #N." instead of "Closes #N.", so the ticket stays open
#     after merge. On a re-run that cannot refresh an old "Closes" body, it aborts and turns the PR into a draft.
# Opens but does not merge a conflict-risk PR unless this account is the current triagemaster. REQUIRE_REVIEW_PASS=1
# (default): CI green but no review-passed marker -> "AWAITING REVIEW", hive-automerge.sh merges it after the review.
# Optional CONFLICT_RESOLVER_CMD (conf) is run in the worktree on a merge conflict; if unmerged files remain afterwards the
# script stops with exit 2 and a human or agent resolves them. REQUIRE_CI=0: a PR with no checks counts as green.
# Game hooks (conf), each run in the worktree with bash -c; whatever they leave changed is committed by this script:
#   PRE_PUSH_CMD  after the merge of main, before the tests (e.g. regenerate assets). Non-zero exit aborts the ship.
#   POST_PR_CMD   once the PR exists, with its number in $HIVE_PR (e.g. stamp the version). Non-zero exit aborts.
# PRIVATE=1: the PR body is just the summary (no "Closes #", no Resource Usage), and no labels are read or written.
. "$(dirname "$0")/hive-env.sh" || exit 1
. "$(dirname "$0")/hive-rate.sh" 2>/dev/null
kw=Closes; args=()
for a in "$@"; do case $a in --refs) kw=Refs;; --*) echo "ABORT: unknown option '$a'"; sed -n '2p' "$0"; exit 2;; *) args+=("$a");; esac; done
set -- ${args[@]+"${args[@]}"}
[ $# -ge 3 ] || { sed -n '2p' "$0"; exit 2; }
i=$1; t=$2; b=$3
name=${4:-}; [ -z "$name" ] && { if [ -n "${REPO:-}" ]; then name=${REPO#*/}; else set -- $REPO_PATHS; [ $# -eq 1 ] && name=$(basename "$1"); fi; }
[ -n "$name" ] || { echo "hive-ship: several REPO_PATHS; pass the repo name as the 4th argument"; exit 2; }
id=${i//\//-}
W=${WORKTREE_ROOT:-$ROOT/.claude/worktrees}/$id/$name
[ -d "$W" ] || { c=$(git rev-parse --show-toplevel 2>/dev/null) && git -C "$c" branch --show-current | grep -qE "issue-$id-|/$id-" && W=$c; }
cd "$W" || { echo "no worktree at $W"; exit 1; }
slug=$(hive_slug_of "$W"); [ -n "$slug" ] || slug=$REPO
checkout=""; for rp in $REPO_PATHS; do [ "$(basename "$rp")" = "$name" ] && checkout=$rp; done; checkout=${checkout:-$ROOT}
git fetch -q
if ! git merge -q "origin/$MAIN_BRANCH" >/dev/null 2>&1; then
  [ -n "${CONFLICT_RESOLVER_CMD:-}" ] && bash -c "$CONFLICT_RESOLVER_CMD" >/dev/null 2>&1
  u=$(git diff --name-only --diff-filter=U)
  if [ -n "$u" ]; then echo "CONFLICT $i: needs a human or agent merge: $(echo $u | tr '\n' ' ')"; exit 2; fi
  git add -A && git commit -qm "merge: $MAIN_BRANCH into $i" || exit 2
fi
# hive_hook <conf var> <commit message>: runs a game hook, commits what it changed. 1 = the hook failed.
hive_hook() {
  local cmd=${!1:-}; [ -n "$cmd" ] || return 0
  bash -c "$cmd" || { echo "ABORT $i: $1 failed"; return 1; }
  [ -z "$(git status --porcelain)" ] && return 0
  git add -A && git commit -qm "$2" || { echo "ABORT $i: could not commit what $1 changed"; return 1; }
}
hive_hook PRE_PUSH_CMD "chore: pre-push hook (PRE_PUSH_CMD)" || exit 1
if ! hive_run_tests; then echo "TESTS FAILED $i (TEST_CMD)"; exit 1; fi
if ! hive_fresh_clone_check; then echo "BOOT CHECK FAILED $i (BOOT_CHECK_CMD in a fresh clone)"; exit 1; fi
bash "$HIVE_DIR/hive-msg-leakcheck.sh" "$PWD" || { echo "ABORT $i: a channel secret would be pushed"; exit 1; }
# hive files are installed copies of claude-hive, never edited in a game (exit 2 = installed before manifests: allowed)
if [ "$PRIVATE" != 1 ]; then bash "$HIVE_DIR/hive-drift.sh" "$PWD" >/dev/null; [ $? = 1 ] && { bash "$HIVE_DIR/hive-drift.sh" "$PWD" | sed 's/^/  /'; echo "ABORT $i: edits hive files; make the change in claude-hive and re-install"; exit 1; }; fi
git push -qu origin HEAD 2>&1 | grep -v remote; [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "ABORT $i: git push failed"; exit 1; }
if [ "$PRIVATE" = 1 ]; then
  body="$b

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
else
  S=$HIVE_STATE/usage-snapshot.json
  p5=$(jq -r '.rate_limits.five_hour.used_percentage // "?"' "$S" 2>/dev/null); p7=$(jq -r '.rate_limits.seven_day.used_percentage // "?"' "$S" 2>/dev/null)
  r5=$(hive_fmt "$(jq -r '.rate_limits.five_hour.resets_at // 0' "$S" 2>/dev/null)" "+%a %b %-d, %-I:%M %p $TZ_LABEL")
  r7=$(hive_fmt "$(jq -r '.rate_limits.seven_day.resets_at // 0' "$S" 2>/dev/null)" "+%a %b %-d, %-I:%M %p $TZ_LABEL")
  rate=${HIVE_RATE:-unknown}; week=${HIVE_WEEK:-unknown}
  body="$kw #$i.

$b

## Resource Usage
- *5-hour rate:* $rate
- *Weekly projection:* $week
- *5-hour window resets:* $r5 (${p5}% used)
- *Weekly window resets:* $r7 (${p7}% used)

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
fi
# Re-run after a CI fix: reuse the branch's open PR (refreshing its body) instead of failing on create. A closed PR does not count.
n=$(gh pr list -R "$slug" --head "$(git branch --show-current)" --state open --json number -q '.[0].number' 2>/dev/null); case $n in ''|*[!0-9]*) n=;; esac
if [ -n "$n" ]; then
  echo "reusing PR $n"
  if ! e=$(gh pr edit "$n" -R "$slug" --body "$body" 2>&1); then
    # --refs must never merge a stale body: a PR first opened without --refs still says "Closes #N."
    if [ "$kw" = Refs ] && [ "$PRIVATE" != 1 ] && [ "$(gh pr view "$n" -R "$slug" --json body -q .body 2>/dev/null | head -1)" != "Refs #$i." ]; then
      # stopping here is not enough: the pushed PR stays open, so make it a draft, which no merger can merge
      gh pr ready "$n" -R "$slug" --undo >/dev/null 2>&1 && d="marked it draft; re-run with --refs to refresh it and mark it ready" || d="could NOT mark it draft: fix its body by hand or close it"
      echo "ABORT $i: could not refresh PR $n body to 'Refs #$i' (${e##*$'\n'}); its old body would close the ticket, so $d."; exit 1
    fi
    echo "WARN $i: could not refresh PR $n body (${e##*$'\n'})"
  elif [ "$(gh pr view "$n" -R "$slug" --json isDraft -q .isDraft 2>/dev/null)" = true ]; then
    gh pr ready "$n" -R "$slug" >/dev/null 2>&1 && echo "PR $n was a draft (as an earlier --refs abort leaves it); body refreshed, marked ready"
  fi
  pr=$(gh pr view "$n" -R "$slug" --json url -q .url 2>/dev/null); pr=${pr:-$n}
else
  pr=$(set -o pipefail; gh pr create -R "$slug" --base "$MAIN_BRANCH" --title "$t" --body "$body" | tail -1) || { echo "ABORT $i: gh pr create failed: $pr"; exit 1; }
  n=${pr##*/}; case $n in ''|*[!0-9]*) echo "ABORT $i: no PR number in '$pr'"; exit 1;; esac
fi
echo "PR $pr"
if [ -n "${POST_PR_CMD:-}" ] && [ -n "${n:-}" ]; then
  h=$(git rev-parse HEAD); HIVE_PR=$n; export HIVE_PR
  hive_hook POST_PR_CMD "chore: post-PR hook for #$n (POST_PR_CMD)" || exit 1
  if [ "$(git rev-parse HEAD)" != "$h" ]; then
    git push -q origin HEAD 2>&1 | grep -v remote; [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "ABORT $i: push after POST_PR_CMD failed"; exit 1; }
  fi
fi
[ "$kw" = Refs ] && [ "$PRIVATE" != 1 ] && echo "REFS: PR $n says 'Refs #$i'; ticket #$i stays open after merge (no close or transition step runs)."
if hive_merge_gated "$slug" "$n" "$i"; then echo "CONFLICT-RISK PR $n opened; only the triagemaster ($(hive_triagemaster)) merges it. Not merging."; exit 0; fi
sleep "${HIVE_SHIP_WAIT:-20}"; k=0
until s=$(gh pr checks "$n" -R "$slug" 2>&1); ! echo "$s" | grep -qE "pending|no checks"; do
  [ "${REQUIRE_CI:-1}" = 0 ] && echo "$s" | grep -q "no checks" && break
  k=$((k+1)); [ $k -gt 60 ] && { echo "CI TIMEOUT $n (conflict?)"; exit 1; }; sleep 30
done
if echo "$s" | grep -qE "[[:space:]]fail[[:space:]]"; then echo "CI FAILED $n"; echo "$s" | grep -E "[[:space:]]fail[[:space:]]"; exit 1; fi
echo "$s" | grep -v pass
if hive_review_blocked "$slug" "$n"; then echo "REVIEW-BLOCKED $n: a confirmed reviewer finding must be fixed first. Not merging."; exit 1; fi
if ! hive_review_passed "$slug" "$n"; then echo "AWAITING REVIEW $n: CI green; hive-automerge.sh merges it once the reviewer marks it review-passed."; exit 0; fi
gh pr merge "$n" -R "$slug" "$(hive_merge_flag)" --delete-branch 2>&1 | tail -1; st=$(gh pr view "$n" -R "$slug" --json state -q .state); echo "$n $st"; [ "$st" = MERGED ] || { echo "MERGE FAILED $n"; exit 1; }
# Never move a human's checkout: fast-forward and install only when it is already on MAIN_BRANCH.
if [ "$(git -C "$checkout" branch --show-current 2>/dev/null)" = "$MAIN_BRANCH" ]; then
  { git -C "$checkout" fetch -q origin && git -C "$checkout" merge -q --ff-only "origin/$MAIN_BRANCH"; } || echo "WARN: $checkout not fast-forwarded"
  ( cd "$checkout" && hive_run_install 2>&1 | tail -1 )
else echo "NOTE: $checkout is not on $MAIN_BRANCH: not updated, no install"; fi
exit 0
