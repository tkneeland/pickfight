# Collaboration: two devs working at the same time

Two developers (each with their own Claude + Atlas) work in parallel on this
repo. This file is the working agreement both agents follow. It sits alongside
`issue-tracker.md`, which still owns claim/label/transition mechanics.

## Ownership comes from the tracker

- **One active owner per issue**: the assignee. Atlas claims with
  `gh issue edit <n> --add-assignee @me`.
- **Never start, edit, or comment-as-owner on an issue assigned to someone
  else.** If there's no unassigned work in your lane, stop and tell your human.
- Every issue body has a **Touches** section listing the files it expects to
  change. When you're planning, fill it in accurately. It is how the other
  dev's agent sees collisions coming.

## Before editing a file

1. `git fetch origin` and rebase your branch onto `origin/main`.
2. If the file is in the **Touches** list of an open issue *assigned to the
   other dev*, it is a **shared file**. Treat it as follows:
   - keep the edit minimal and local (add, don't restructure or reformat);
   - never move, rename, or reorder existing code or nodes in it;
   - post a one-line comment on your issue: `Touching <file>: <what>`.
3. `.tscn` scene files merge badly. Don't both change the same scene in
   parallel. Where you can, add new scenes instead of editing shared ones.

Current hot shared files: `scripts/RoundManager.gd`, `scenes/Main.tscn`,
`tools/scenario_runner.gd` (append new scenarios at the end of the list and
the dispatcher; don't reorder), `CONTEXT.md`.

## Branches, commits, PRs

- One issue = one branch (`<type>/issue-<n>-<slug>`) = one PR against `main`.
- Commit and push to your branch often, at least every accepted deliverable,
  so work is never stranded on one laptop.
- Rebase onto `origin/main` right before opening the PR and again before
  merge. Re-run `godot --headless --path . -s tools/scenario_runner.gd -- --all`
  after every rebase that pulled in the other dev's changes.
- **Never push to or force-push `main`**, and never push to the other dev's
  branch. Force-push only your own branch, after a rebase.
- **Agents merge their own PRs; there's no pause for human review** (owner's
  decision, 2026-09-24). Once the full suite is green on a branch rebased onto
  the current `origin/main`, poll `gh pr view <n> --json mergeable` until it is
  not `UNKNOWN`, then `gh pr merge <n> --merge --delete-branch`. Either dev's
  Claude may merge any green PR. If main moved since your last suite run,
  rebase and re-run before merging.

## Shared decisions

- New ADRs: take the next free number when you open the PR. If the other dev
  took it first, renumber yours during rebase.
- Anything both agents must know goes in the repo (CLAUDE.md, ADRs,
  `docs/agents/*`), through a PR, never only in one person's Claude memory.
- Don't reopen settled decisions (ADRs, CLAUDE.md "settled" items) in your
  own branch. Raise them as an issue.

## After the other dev merges

Rebase your branch onto `origin/main`, re-run the full scenario suite, and
fix any conflict in *your* branch. Don't ask the other dev to change theirs.
