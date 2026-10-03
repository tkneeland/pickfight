# Collaboration: two devs working at the same time

Several agents work in parallel on this repo, one per GitHub account:
`tkneeland` (the integrator), `tommykneeland` (the owner's second agent) and
`agage-JG` (Austin). This file is the working agreement every agent follows. It sits alongside
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
  merge. Re-run `godot --headless --fixed-fps 60 --path . -s tools/scenario_runner.gd -- --all`
  after every rebase that pulled in the other dev's changes. (`--fixed-fps 60`
  runs the suite on game time, faster than real time, #182.)
- **CI check (#186):** `.github/workflows/scenarios.yml` runs on every PR and
  push to `main`: import, boot check, runner parse check, then the full suite
  in 4 `--fixed-fps 60` shards (`tools/list_scenarios.sh <i> 4`). Each shard's
  output is uploaded as an artifact. Don't merge a PR whose `scenarios` check
  is red. CI deletes `.godot/global_script_class_cache.cfg` after the import,
  so a `class_name` dependency turns the boot check red, as on a fresh clone.
- **Test isolation (#195):** a `-s` run (the runner, `perf_probe.gd`,
  `ringout_probe.gd`) never reads or writes the owner's `user://audio.cfg`.
  Sfx and Music start from defaults with saving off, on a temp file. Godot
  still writes its own log under the user data folder unless you pass
  `--log-file <path>` before `-s`. CI does, and locally that's
  `godot --headless --fixed-fps 60 --log-file /tmp/pickfight-run.log --path . -s tools/scenario_runner.gd -- --all`.
  `-- --scenarios=a,b,c` runs a list in order (empty entries are dropped).
  An unknown argument exits 2.
- **Never push to or force-push `main`**, and never push to the other dev's
  branch. Force-push only your own branch, after a rebase.
- **No pause for human review** (owner's decision, 2026-09-24), and **one
  integrator merges**: tkneeland's Claude. Everyone else, tommykneeland's and
  Austin's Claude and any subagents included, pushes the branch, opens the PR with the suite
  green, comments on the issue with the PR URL, and **stops**. The integrator
  merges PRs one at a time. For each, it rebases onto the current
  `origin/main`, resolves conflicts, re-runs the full suite, then runs
  `gh pr merge <n> --merge --delete-branch` once `mergeable` is not
  `UNKNOWN`. One merger means nobody rebases against a main that is moving
  under them.
- **Fallback:** if the integrator is unavailable (for example, out of
  usage), tommykneeland's or Austin's Claude may merge its own green PRs by
  the same steps.
- **Owner's call, 2026-10-03:** while Austin's machine is down, tommykneeland's
  Claude merges its own green PRs by the same steps, without waiting for the
  integrator. Tickets reassigned to tommykneeland belong to it: other agents
  drop any unpushed work on them.

## Shared decisions

- New ADRs: take the next free number when you open the PR. If the other dev
  took it first, renumber yours during rebase.
- Every PR that changes a player-facing feature updates `docs/FEATURES.md`; the integrator checks it before merging.
- Anything both agents must know goes in the repo (CLAUDE.md, ADRs,
  `docs/agents/*`), through a PR, never only in one person's Claude memory.
- Don't reopen settled decisions (ADRs, CLAUDE.md "settled" items) in your
  own branch. Raise them as an issue.

## After the other dev merges

Rebase your branch onto `origin/main`, re-run the full scenario suite, and
fix any conflict in *your* branch. Don't ask the other dev to change theirs.

## Throughput: run agents in parallel (owner request, 2026-10-01)

Both owners want maximum throughput. Every agent working this repo should:

- **Run one background worker per ready ticket you own, at the same time.** Each
  worker gets its own worktree (`.claude/worktrees/<issue>/pickfight`, branch
  `feat/issue-<n>-<slug>` from `origin/main`). Don't work tickets one at a time
  in the main checkout.
- **Use the cheapest model that can do the ticket** (Sonnet for most features,
  Haiku for mechanical swaps). Keep the orchestrator for merging and review.
- **Give each worker a self-contained packet:** the issue number, its worktree,
  the append-only runner rules below, and the exact verify commands. Have it
  commit but not push. The orchestrator merges `origin/main`, opens the PR and
  merges it after CI.
- **Ship serially, build in parallel.** Main moves fast, so merge `origin/main`
  into each finished branch right before its PR, and re-run the suite.
- **`tools/scenario_runner.gd` is append-only.** Add names at the end of
  `SCENARIO_NAMES`, cases at the end of the dispatcher (just before the single
  `_:` arm) and functions at the end of the file. In a conflict, keep both
  sides. Then check that there is still exactly one `_:` arm
  (`grep -c "^		_:$"` → 1), that no comma was lost at the end of the name
  list, and that the last function still ends in `return failures`.
- **When idle, take the next ready ticket.** Every open ticket should be owned
  and moving. If yours are all in flight, ask your owner to grill for more, or
  pick up an unowned `ready-for-agent` one and assign yourself.

## Usage beacon and triage by headroom

- **Keep your beacon current.** Each agent's status-line hook edits that account's
  own comment on issue #432 at most every 15 minutes. The comment carries the
  5-hour and 7-day used percentages and their reset times, in UTC. Never edit
  another agent's comment.
- **Any agent that files or reassigns tickets reads every beacon first:**
  `gh issue view 432 -R tkneeland/pickfight --json comments -q '.comments[]|.body'`.
- **Assign by weekly headroom, not by ticket count.** Headroom is 100 minus the
  7-day %. Split new tickets in proportion to headroom across every agent with a
  fresh beacon. For example, at 85% and 51% headroom, about 60/40 to the
  first. Recompute on every triage.
- **The 5-hour window only decides timing, not ownership.** At 90% or more,
  that dev's agent still gets the ticket, but starts it after the 5-hour reset.
  Don't hand it to the other dev just for that.
- **When a beacon is missing or more than 6 hours stale,** leave that agent
  out of the split (if none is fresh, split evenly by open-ticket count), and
  mention the stale beacon in the triage report.
- **Tickets that need a human,** such as owner decisions, secrets or store
  submissions, go to the dev the owner names, whatever the headroom.
