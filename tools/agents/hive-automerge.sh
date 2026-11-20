#!/bin/bash
# Zero-token auto-integrator: merges any open PR that is MERGEABLE with every CI check passed, then runs INSTALL_CMD
# (if set). Conflicting PRs get one comment asking to rebase. Covers every checkout in REPO_PATHS. Leaves alone:
#   - PRs labelled conflict-risk, unless this account is the current triagemaster
#   - review-blocked PRs (the reviewer found a confirmed correctness or spec issue; rule 12)
#   - REQUIRE_REVIEW_PASS=1 (default): PRs without the review-passed marker (no merge before a reviewer pass; rule 12)
#   - PRs that edit hive files (tools/agents/ outside accounts/, docs/agents/hive*.md, discord.md) without the
#     hive-install label: hive changes are made in claude-hive and installed (install.sh), never edited in a game
# Never moves a human's checkout: it fast-forwards and installs only when the checkout is already on MAIN_BRANCH.
# PRIVATE=1: only PRs this account opened, never comments (a desktop notice instead), review-blocked is a local marker.
# REQUIRE_CI=0: a PR with no checks counts as green.
. "$(dirname "$0")/hive-env.sh" || exit 1
LOCK=$HIVE_STATE/automerge.lock
if [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK")" 2>/dev/null; then echo "ALREADY RUNNING"; exit 0; fi
echo $$ > "$LOCK"; trap 'rm -f "$LOCK"' EXIT
MF=$(hive_merge_flag)
# "PR conflicts" markers hold the PR head they were raised for: a new push re-arms the notice, and the marker goes once
# the PR stops conflicting or is no longer open.
STUCK_DIR=$HIVE_STATE/stuck; mkdir -p "$STUCK_DIR"
# true when a PR edits hive-owned files and isn't an install (label hive-install)
HIVE_EDIT_JQ='([.labels[].name] | index("hive-install")) == null and ([.files[].path | select((startswith("tools/agents/") and (startswith("tools/agents/accounts/") | not)) or test("^docs/agents/(hive|hive-debrief|discord)\\.md$"))] | length > 0)'
while true; do
  for rp in $REPO_PATHS; do
    slug=$(hive_slug_of "$rp"); [ -n "$slug" ] || slug=$REPO; merged=0; sk=${slug//\//__}
    open=$(gh pr list --repo "$slug" --state open --base "$MAIN_BRANCH" $(hive_pr_author_flag) --json number,isDraft --jq '.[]|select(.isDraft|not)|.number' 2>/dev/null) && listed=1 || listed=0
    if [ "$listed" = 1 ]; then
      for mark in "$STUCK_DIR/$sk"-*; do
        [ -e "$mark" ] || continue
        echo "$open" | grep -qx "${mark##*-}" || rm -f "$mark"
      done
    fi
    for P in $open; do
      info=$(gh pr view "$P" --repo "$slug" --json mergeable,headRefOid --jq '.mergeable + " " + .headRefOid' 2>/dev/null)
      m=${info%% *}; sha=${info#* }
      if [ "$m" = "CONFLICTING" ]; then
        [ "$(cat "$STUCK_DIR/$sk-$P" 2>/dev/null)" = "$sha" ] || { echo "$sha" > "$STUCK_DIR/$sk-$P"; echo "$(date '+%F %T') STUCK $slug#$P conflicts with $MAIN_BRANCH"; hive_desktop_notify "AT mode" "PR $slug#$P conflicts with $MAIN_BRANCH"; }
        if [ "$PRIVATE" != 1 ]; then
          gh pr view "$P" --repo "$slug" --json comments --jq '.comments[].body' | grep -q "\[INTEGRATOR\]" || \
            gh pr comment "$P" --repo "$slug" --body "[INTEGRATOR] Conflicts with $MAIN_BRANCH. Author: please rebase onto origin/$MAIN_BRANCH and push; it merges automatically once CI is green." >/dev/null
        fi
        continue
      fi
      [ "$m" = "MERGEABLE" ] && rm -f "$STUCK_DIR/$sk-$P"   # no longer conflicting
      [ "$m" = "MERGEABLE" ] || continue
      hive_review_blocked "$slug" "$P" && continue   # rule 12: confirmed reviewer finding
      hive_review_passed "$slug" "$P" || continue    # rule 12: no merge before a reviewer pass
      hive_merge_gated "$slug" "$P" && continue   # rule 6: conflict-risk (PR or its ticket) is the triagemaster's
      if [ "$PRIVATE" != 1 ] && [ "$(gh pr view "$P" --repo "$slug" --json files,labels --jq "$HIVE_EDIT_JQ" 2>/dev/null)" = true ]; then
        [ -e "$HIVE_STATE/held/$sk-$P" ] || { mkdir -p "$HIVE_STATE/held"; : > "$HIVE_STATE/held/$sk-$P"; echo "$(date '+%F %T') HELD $slug#$P edits hive files (make the change in claude-hive and re-install)"; }
        continue
      fi
      states=$(gh pr checks "$P" --repo "$slug" --json state --jq '.[].state' 2>/dev/null)
      if [ -z "$states" ]; then [ "${REQUIRE_CI:-1}" = 0 ] || continue
      else echo "$states" | grep -qv "SUCCESS\|SKIPPED\|NEUTRAL" && continue; fi
      gh pr merge "$P" --repo "$slug" $MF --delete-branch >/dev/null 2>&1 && { echo "$(date '+%F %T') MERGED $slug#$P"; merged=1; rm -f "$STUCK_DIR/$sk-$P"; }
    done
    if [ $merged -eq 1 ]; then
      if [ "$(git -C "$rp" branch --show-current 2>/dev/null)" = "$MAIN_BRANCH" ]; then
        { git -C "$rp" fetch -q && git -C "$rp" merge -q --ff-only "origin/$MAIN_BRANCH"; } 2>/dev/null || echo "$(date '+%F %T') WARN: $rp not fast-forwarded"
        ( cd "$rp" && hive_run_install )
      else
        echo "$(date '+%F %T') $rp is not on $MAIN_BRANCH: not updated, no install"
      fi
    fi
  done
  sleep 180
done
