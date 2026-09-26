## Agent skills

### Issue tracker

Issues live as GitHub Issues in `tkneeland/pickfight`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Collaboration

Two devs work in parallel, each with their own agent. Before claiming an issue,
starting work, or editing a file another open issue lists under **Touches**,
read and follow `docs/agents/collaboration.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

<!-- atlas-v3:guidance:start -->
## Workspace framing

Atlas workspace: **pickfight**. Confirmed repositories:

- `pickfight` at `.`; base `main`; source host `github`.

When isolation or parallel delivery benefits from worktrees, they live beneath
`.claude/worktrees/<work-package>/<repository-id>/`. The frontier
orchestrator chooses direct checkout, worker worktrees, and an optional
integration worktree from the dependency, concurrency, file-ownership, and
shared-state risks. Never place worktrees beneath `.atlas/`. Each affected
repository keeps its own base SHA, branch, verification result, and pull request.

## Repository framing

**pickfight** — A same-room multiplayer platform fighter combining Stick Fight's scrappy physics combat with Getting Over It's pole/hammer movement scheme. One host machine simulates and renders the shared screen; each player drives their arm from their own phone browser over the LAN. Early prototype at playtest stage: up to eight phone-controlled players, an endless round loop over 24 rotating stages built from reusable parts, and nine weapons (the pickaxe everyone starts with, plus eight handed out as on-stage pickups, ADR-0009); art is placeholder.

### Structure

- `scenes/` — .tscn scene files (Main, Player; Arena is the scenario suite's physics fixture); `scenes/stages/` holds the rotating stages (ADR-0008)
- `scripts/` includes `RoundManager.gd`, the endless round loop over `ControllerServer`'s roster (ADR-0004, ADR-0007)
- `scripts/` — GDScript sources
- `controller/` — the single-file controller web page served to phones
- `tools/` — headless test fixtures
- `docs/adr/` — Architecture decision records
- `docs/agents/` — Agent-facing tracker/domain/guardrail guidance

### Repository-specific rules

- Personal hackathon prototype, single repo, low risk - not a client engagement.
- GDScript has no standard lint/format tool; do not invent one without team approval.
- **Never reference a GDScript type by its `class_name`.** Godot resolves those
  through a global class cache that lives in the gitignored `.godot/` and is
  only built by an editor run, so on a fresh clone the reference fails to parse
  and the script does not load. Worse, `godot --headless --quit` still exits 0
  in that state, so the boot check passes over a broken build. Consumers
  `preload()` the script by path instead — see `WeaponStatsType` /
  `WeaponHeadType` in `scripts/Player.gd`. Check it in a throwaway clone of
  your committed branch, which never has a `.godot/`: Godot 4.6.2 headless
  does not create one, only an editor run does. So never touch the editor's
  own cache:
  `rm -rf /tmp/pf-fresh && git clone -q . /tmp/pf-fresh && godot --headless --path /tmp/pf-fresh --quit 2>&1 | grep -E "SCRIPT ERROR|Failed to load script"`.
  **Any output means the check failed**, whatever the exit code. The exit code
  is 0 either way (#21).
- Input scheme is **settled**: relative vector input from phone browsers, per [ADR-0003](docs/adr/0003-relative-vector-input.md). The former open question (gamepad-per-player vs keyboard-only) is void — it assumed a shared screen and shared input devices, and [ADR-0001](docs/adr/0001-same-room-host-rendered-multiplayer.md) removed both assumptions. Do not reopen it as though it were live.

## Atlas repository workflow

Use the lightest route that fits:

- Small, clear change: `/implement <description-or-spec>` then verify.
- Normal feature: `/grill-with-docs` → optional prototype → `/to-spec` → optional `/to-tickets` → `/atlas-red-team` when required → optional `/atlas-plan <ticket-epic-or-spec>` → `/atlas-implement`.
- Huge or unclear effort: `/wayfinder`, then rejoin at the spec route.
- Existing ticket, epic, or stable spec: optional `/atlas-plan <work-package>` → `/atlas-implement <work-package>`.

Run `/atlas-plan` and `/atlas-implement` using the most capable approved
frontier-grade model available. These commands reserve frontier capacity for
planning, orchestration, review, and final verification; implementation
delegates tightly specified or mechanical work to the least expensive capable
worker model.

Managed work uses `/atlas-implement <ticket-or-epic-or-spec>`. A frontier
orchestrator chooses the execution structure and delegates bounded deliverables
when useful. It uses the least expensive capable worker model per delegation;
tight, mechanical packets favor cheaper models, while final review and
verification judgment stay with the frontier orchestrator. Implementation
workers read and follow the supported Matt Pocock implementation skill source
while deferring its final review step. Size alone is never a reason to stop.

## Repository policy and contract model

`CLAUDE.md` is the agent entry point and cross-cutting policy router. Team-owned
documents under `docs/agents/` are authoritative for their named scope. Within
a document that classifies entries, the classification determines authority;
recommendations and repository facts do not silently become mandatory policy.
Tickets and specs remain stable work-package contracts. Planning resolves the
applicable repository policy and facts into technical plans and execution
packets. Generic skills provide reusable mechanics and do not override
repository policy.

Setup initializes `docs/agents/*`; the team owns those files afterward. A setup
rerun refreshes only the managed sections Atlas itself last wrote, preserves any
section the team has edited, and reports every preserved edit in `plan` and
`verify` output.

- Before any tracker read, write, comment, claim, or transition, read and follow
  `docs/agents/issue-tracker.md`.
- Before creating, classifying, prioritizing, or decomposing tickets, read and
  follow `docs/agents/triage-labels.md`.
- Before clarifying, researching, prototyping, specifying, decomposing,
  technically planning, or red-team reviewing proposed work, read and follow
  `docs/agents/planning.md`. This includes `/grill-with-docs`, Wayfinder,
  planning prototypes, `/to-spec`, `/to-tickets`, and `/atlas-plan`.
- During planning, read `docs/agents/domain.md` when the work introduces or
  changes domain concepts and resolve conflicting terminology in the plan.
- Before writing acceptance criteria, Definition of Done, fixtures, or
  verification steps, read `docs/agents/testing.md`.
- During planning, read `docs/agents/tooling.md` when work depends on a detected
  capability and resolve the applicable tool into the execution plan.

Execution workers receive resolved decisions, exact verification commands, and
the evidence location in their task packet. Do not make execution workers
reread planning, tracker, triage, domain, testing, or tooling guidance.

## Atlas planning contract

- Invoking `/atlas-implement` approves the fixed work-package contract and any
  existing technical plan. When the contract is content-complete but no plan
  exists, the frontier orchestrator derives the execution plan without inventing
  missing product or architectural decisions.
- `/atlas-plan` is optional. Read `docs/agents/issue-tracker.md` for the
  project's configured readiness, availability, claim, transition, and
  writeback policy; do not infer those rules here.
<!-- atlas-v3:guidance:end -->
