<!-- atlas-v3:operators-guide:start -->
# How Atlas works here

Atlas is a set of Claude Code plugins. It gives coding agents one route through
planned, checked work. This guide says what Atlas does in this repository, and
what it does in your issue tracker.

This guide is for the people who run the work. `CLAUDE.md` and the documents
under `docs/agents/` hold the same rules, written for the agents. Read those
when you need the exact wording.

Setup wrote files in this repository. Setup wrote nothing in your issue
tracker. The upstream Matt Pocock setup also wrote only files. Part two says
what Atlas will write on a ticket later, while it does the work.

## Part one: what Atlas does in this repository

### This workspace

| Item | Value |
|---|---|
| Workspace name | pickfight |
| What this repository is for | A local-multiplayer platform fighter combining Stick Fight's scrappy physics combat with Getting Over It's pole/hammer movement scheme. Early prototype: one arena, two test players, proving out pole-swing movement and knockback-on-collision combat before further features (art, levels, weapons, win conditions) get built. |
| Folder for proof of work | `test-results` |

Atlas may change the repositories below, and nothing else.

| Repository | Path | Base branch |
|---|---|---|
| `pickfight` | `.` | `main` |

A *base branch* is the line of work that new work starts from. Atlas starts
each new branch from it. Atlas opens one pull request for each repository it
changes. A *pull request* is a request to merge a branch, which a person
reviews.

### The checks that prove a change

Atlas runs these commands to prove that a change works.

| Check | Command | What it covers | When it runs | Status |
|---|---|---|---|---|
| boot-check | `godot --headless --quit` | Catches GDScript parse errors and broken scene/resource references at project boot | Before opening a PR | verified |

`verified` means setup ran the command here and it worked. `inferred` means the
repository names the command, but setup did not run it. `unavailable` means the
check does not exist yet.

Atlas saves the proof of each run in the folder named above. It clears that
folder when a new piece of work starts, so the folder holds proof of the
current work only. Atlas commits the proof with the change, then links to it
from the pull request.

### The documents Atlas generated

Atlas wrote one document for each policy below. The agents read them before
they act. Your team owns these files now: edit one, and Atlas keeps the edit.

| Document | What it holds |
|---|---|
| `docs/agents/issue-tracker.md` | How Atlas reads your tracker, and what it may change there |
| `docs/agents/planning.md` | What Atlas must settle before it plans a piece of work |
| `docs/agents/testing.md` | Which checks prove a change, and what counts as proof |
| `docs/agents/tooling.md` | Which extra tools this repository may use, and when |

Two more documents come from another setup. Atlas can point at them, but Atlas
does not write them.

| Document | What it holds | Comes from |
|---|---|---|
| `docs/agents/domain.md` | The words this project uses, and what each one means | `/setup-matt-pocock-skills` |
| `docs/agents/triage-labels.md` | The labels that sort and rank new tickets | `/setup-matt-pocock-skills` |

### How work reaches Atlas

Use the lightest route that fits the work.

- A small, clear change: run `/implement`, then check the result.
- A normal feature: run `/grill-with-docs`, then `/to-spec`, then `/to-tickets`, then `/atlas-implement`.
- A large or unclear effort: run `/wayfinder` first, then follow the feature route.
- A ticket, an epic, or a settled spec: run `/atlas-plan` for a written plan first, then `/atlas-implement`.

An *epic* is a parent ticket with child tickets. A *spec* is a written
statement of the work, kept in this repository.

## Part two: what Atlas does in your issue tracker

Atlas writes on a ticket only while it works on that ticket. It changes nothing
else on your board.

### The order work moves through

Work moves through your own states in the order below. A *state* is the status
on your board.

| Step | State | What it means | Who moves work into it |
|---|---|---|---|
| 1 | `needs-triage` | New issue, not yet groomed or planned | Atlas |
| 2 | `atlas:planning` | Atlas is actively drafting an implementation plan for this ticket | Atlas |
| 3 | `atlas:plan-review` | Plan drafted in the repo; awaiting human approval before implementation starts | Atlas |
| 4 | `ready-for-agent` | Fully specified and approved; an agent is implementing it and running AI review | Atlas |
| 5 | `ready-for-human` | Requires human implementation or human review before it can proceed | A person only |
| 6 | `closed` | Work is done and merged | A person only |
| 7 | `needs-info` | Blocked on more information from the reporter or an open decision | Atlas |
| 8 | `wontfix` | Will not be actioned | Atlas |

A state marked *A person only* is one Atlas never moves work into. A person
makes that move.

### Where plans go

| Question | Answer |
|---|---|
| Where Atlas keeps a plan | In this repository, as a file |
| A plan arrives as a draft for approval | yes |

If a plan arrives as a draft, a person approves it before Atlas builds from it.
Atlas shows you the exact words it will post before it posts them.

### What Atlas writes on a ticket

Atlas adds a record to the ticket as the work moves. It never rewrites what the
ticket asks for.

| Record | What it says |
|---|---|
| `[EXECUTION PLAN]` | The steps Atlas plans to take |
| `[PROGRESS]` | What is finished so far |
| `[SCOPE CHANGE]` | An agreed change to the work, and the reason for it |
| `[BLOCKED]` | Why the work stopped, and what it needs to start again |
| `[AI CODE REVIEW]` | The full review of the finished change |
| `[CLOSEOUT]` | The result, the proof, and every deviation |

Atlas also writes the pull-request link on the ticket.

### What Atlas never does

- Atlas never merges a pull request. A person merges it.
- Atlas never marks work as done. A person does that, after they review the pull request.
- Atlas never removes or rewrites what a ticket asks for.
<!-- atlas-v3:operators-guide:end -->
