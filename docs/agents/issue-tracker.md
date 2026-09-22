# Issue tracker: GitHub

Issues and specs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

Infer the repo from `git remote -v`; `gh` does this automatically when run inside a clone.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues, using the `gh pr` equivalents:

- **Read a PR**: `gh pr view <number> --comments` and `gh pr diff <number>` for the diff.
- **List external PRs for triage**: `gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments` then keep only `authorAssociation` of `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`, or `NONE` (drop `OWNER`/`MEMBER`/`COLLABORATOR`).
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, `gh pr close`.

GitHub shares one number space across issues and PRs, so a bare `#42` may be either: resolve with `gh pr view 42` and fall back to `gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body. `gh issue create --label wayfinder:map`.
- **Child ticket**: an issue linked to the map as a GitHub sub-issue (`gh api` on the sub-issues endpoint). Where sub-issues aren't enabled, add the child to a task list in the map body and put `Part of #<map>` at the top of the child body. Labels: `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed, the ticket is assigned to the driving dev.
- **Blocking**: GitHub's **native issue dependencies**, the canonical, UI-visible representation. Add an edge with `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`, where `<blocker-db-id>` is the blocker's numeric **database id** (`gh api repos/<owner>/<repo>/issues/<n> --jq .id`, _not_ the `#number` or `node_id`). GitHub reports `issue_dependencies_summary.blocked_by` (open blockers only, the live gate). Where dependencies aren't available, fall back to a `Blocked by: #<n>, #<n>` line at the top of the child body. A ticket is unblocked when every blocker is closed.
- **Frontier query**: list the map's open children (`gh issue list --state open`, scoped to the map's sub-issues / task list), drop any with an open blocker (`issue_dependencies_summary.blocked_by > 0`, or an open issue in the `Blocked by` line) or an assignee; first in map order wins.
- **Claim**: `gh issue edit <n> --add-assignee @me`, the session's first write.
- **Resolve**: `gh issue comment <n> --body "<answer>"`, then `gh issue close <n>`, then append a context pointer (gist + link) to the map's Decisions-so-far.

<!-- atlas-v3:tracker:start -->
# Issue tracker

Tracker type: **github**.

This document is the authoritative repository policy for tracker reads, writes,
readiness, availability, claims, ownership, transitions, human-only actions,
and planning-artifact publication.

## States

| State | Meaning |
|---|---|
| `needs-triage` | New issue, not yet groomed or planned |
| `atlas:planning` | Atlas is actively drafting an implementation plan for this ticket |
| `atlas:plan-review` | Plan drafted in the repo; awaiting human approval before implementation starts |
| `ready-for-agent` | Fully specified and approved; an agent is implementing it and running AI review |
| `ready-for-human` | Requires human implementation or human review before it can proceed |
| `closed` | Work is done and merged |
| `needs-info` | Blocked on more information from the reporter or an open decision |
| `wontfix` | Will not be actioned |

Human-only states: `ready-for-human`, `closed`.

Recommended lifecycle: `needs-triage` → `atlas:planning` → `atlas:plan-review` → `ready-for-agent` → `ready-for-human` → `closed` → `needs-info` → `wontfix`.

## Read and write rules

- Read the complete ticket and comments before planning or implementation.
- Check for available work before claiming. Available work is ready to
  implement, unclaimed, in an eligible state, has no active impediment or
  blocking decision, and every `blocked by` ticket is in
  `closed`. A dependency that is not a `blocked by` edge does
  not make work unavailable.
- Claim before starting work and use one active owner. Enter
  `needs-triage` only when starting any work.
- Enter `atlas:planning` only when planning starts and
  `atlas:plan-review` only when the plan is ready for review.
- Enter `ready-for-agent` only when implementation starts.
- Enter `ready-for-agent` only when aggregate AI code review starts.
- Record blocks, approved scope changes, proof of work, and the PR URL.
- Enter `ready-for-human` only after verification and PR creation.
- Compare the next Atlas phase with the last-known tracker state from the
  initial ticket read or most recent successful transition. Do not fetch the
  ticket solely for this comparison. When both map to the same state, record
  the phase in its configured phase record or comment without requesting a
  same-status transition.
- Never enter `closed`; a human does that after reviewing the PR.
- When blocked, preserve work, record the exact reason and resume instructions,
  and follow the configured blocked-state behavior. On resume, reread the ticket
  and avoid duplicating claims, transitions, workers, commits, or comments.
- Planning artifact storage: **repository**.
- Drafts before approval: **true**.
- Preview exact plan writes and transitions before publishing them. If drafts
  are not permitted, return the draft without presenting it as tracker state.
- Preserve stable ticket/spec requirements. Record evolving execution in
  `[EXECUTION PLAN]`, `[PROGRESS]`, `[SCOPE CHANGE]`, `[BLOCKED]`,
  `[AI CODE REVIEW]`, and `[CLOSEOUT]` records rather than silently rewriting
  the contract. Write the complete AI Code Review output to the ticket before
  entering `ready-for-human`.

Before creating, classifying, prioritizing, or decomposing tickets, also read
and follow `docs/agents/triage-labels.md`. Do not infer labels or priority from
this document.

## Readiness

Ready to plan: Issue has a clear problem/outcome and is not labeled needs-triage or needs-info

Ready to implement: Issue labeled ready-for-agent with no assignee

Available to claim: Issue has no assignee

## Sources and pull requests

| Repository | Path | Source host | Base branch | PR creation command |
|---|---|---|---|---|
| `pickfight` | `.` | github | `main` | `gh pr create --base main --head <feature-branch>` |

Open one PR per affected repository.

The tracker and source host may differ. Never infer tracker operations from the
source host.

## Atlas closeout record

Record every repository delivery, deliverable and worker/model, each DoD
outcome and evidence, deviations, verified run command, deployed smoke when
applicable, every PR URL, and the AI Code Review output.
<!-- atlas-v3:tracker:end -->
