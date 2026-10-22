# Autonomous triage (AT mode)

Team-owned and authoritative for AT mode, the triagemaster role and per-account settings. Scripts live in
`tools/agents/` (one line each in its README); per-account settings in `tools/agents/accounts/<handle>.conf`
(chosen by env `PF_ACCOUNT`, else `gh api user -q .login`). Ticket-assignment mechanics stay in `collaboration.md`
and `issue-tracker.md`.

## Glossary

- **AT mode / MT mode.** AT: the agent triages, files, assigns, dispatches and merges on its own. MT: it acts only when its human asks. Stored in `$PF_STATE/pf-at-mode`; `pf-at-mode.sh` prints it.
- **Day / night mode.** Day is `NIGHT_END` to `NIGHT_START` o'clock in the account's `TZ`; night is the rest. **Day override:** when the owner asks for speed at night, `$PF_STATE/pf-day-until` holds an epoch and the account runs as day until then.
- **Triagemaster.** The one account whose agent auto-files tickets, orders conflict-risk tickets and merges them. `tkneeland` (rank 1) unless succession has passed it on.
- **Conflict-risk ticket.** A ticket labelled `conflict-risk`; see the rule below.
- **Fire.** An event that interrupts the owner immediately (terminal and Discord). Everything else waits for the digest.
- **Morning digest.** The 9 AM message of owner decisions, sent to the terminal and to Discord.
- **Ticket-maker / merger / reviewer.** Helper agents run by the AT session that do not count toward the worker target. The ticket-maker files tickets, the merger ships green PRs, and the reviewer reviews every PR before merge.
- **Dry.** The ticket-maker found nothing that clears the filing bar this run.
- **Usage beacon.** Each account's comment on issue #432 with its 5-hour and 7-day usage and reset times, refreshed by `statusline-usage.sh` every 15 minutes.

## Rules

1. **On by default.** AT is on until the owner turns it off. In MT, act only when asked.
2. **Agents.** Day: keep at least `DAY_MIN_AGENTS` (3) workers running. Drop to 2, or rarely 1, only when the ticket-maker is dry and no ticket is ready. Never trade productivity for this, and note idle time in the digest. Night: up to 3 are allowed, but prefer `NIGHT_PREFERRED_AGENTS` (1-2) when that is cheaper for the same result. The ticket-maker and merger agents do not count.
3. **Budget.** Do not dispatch when weekly use is at or above `HANDOFF_WEEKLY_USED` (85%), except in the `RESET_GRACE_HOURS` (24h) before that account's weekly reset, when you spend the remaining budget. `pf_budget_ok` in `pf-env.sh` encodes this.
4. **Filing.** Only the triagemaster auto-files tickets, and every filing runs `tools/agents/pf-dupe-check.sh "<keywords>"` first (exit 1 = review the hits, do not file a duplicate). Other accounts request tickets manually unless their conf sets `AUTO_FILE=1`.
5. **Assignment.** Assign by weekly headroom (the #432 rules in `collaboration.md`). Never assign to an account whose remaining weekly (100 minus 7d%) is at or below its `MIN_WEEKLY_REMAINING_FOR_TICKETS`. **Reserve accounts** (`RESERVE=1`, tommykneeland) reject tickets while every non-reserve dev (tkneeland, agage-JG) can work normally. They take tickets when at least one of those devs cannot, meaning it has no beacon under 6h old, or it is at or above `HANDOFF_WEEKLY_USED`, or its 5-hour window is full with more than 1h until reset. A reserve account hands its unstarted tickets back once every non-reserve dev can work again, and it finishes in-flight work. `tools/agents/pf-reserve.sh` does this check and the hand-back. (Owner, 2026-10-22.)
6. **Conflict-risk tickets.** Label `conflict-risk` when the ticket edits (not just appends to) a hot shared file (`scripts/RoundManager.gd`, `scenes/Main.tscn`, `scripts/Player.gd`, `scripts/ControllerServer.gd`, `CONTEXT.md`, any `.tscn`), or a file another open ticket lists under Touches. Appending to `tools/scenario_runner.gd` does not count. Only the triagemaster files, assigns and orders them, with one in flight across all devs, and only the triagemaster merges them (`pf-automerge.sh` and `pf-ship.sh` enforce the merge half).
7. **Succession.** When the triagemaster has used 85% of its weekly (outside the 24h before its reset), the role passes to the next `SUCCESSION_RANK` with a fresh beacon (under 6h old) and under 85% used. The new holder posts `[TRIAGEMASTER] <handle> until <reset ISO>` on #432 (`pf-succession.sh --post` does this). The role returns automatically at the original holder's reset. The stand-in has full powers. **Hard limit:** at or above `HANDOFF_HARD_WEEKLY_USED` (95%) the role passes on at any time, even inside the 24h reset window, because an account that close to its limit cannot run the triagemaster work. (Austin, 2026-10-22.)
8. **Session shape.** AT runs in a separate background Claude session (in `screen`); the main terminal is a control panel. On request, or when the owner returns after 2h+ away, give a status: tickets created and completed since the last status, with time estimates from the median claim-to-merge time by priority. The 9 AM digest of owner decisions goes to the terminal and Discord; the owner may reply on either.
9. **Fires** (immediate, terminal plus Discord): main red for 30 minutes or more; every dev's agent blocked; a secret or security issue; weekly at or above 85% with more than 24h until reset; the AT session crashed. Everything else waits for the digest.
10. **Status line.** Line 1: `<model> · 5h N% (r <time>) · 7d N% (r <day time>) · AT·night`. Line 2: agents / ready / PRs / last merge / triagemaster. Then one line per running agent: `#N title`.
11. **Filing bar and dry.** Every auto-filed ticket names its source: a launch-doc gap (`docs/launch/`), owner or playtest feedback, a bug with evidence (CI, logs, telemetry, a reviewer finding), or a clear extension of a `docs/FEATURES.md` entry. It also passes `pf-dupe-check.sh`. File only what clears that bar; zero is fine. When nothing does, report `dry: <reason>` and don't re-run the ticket-maker until something changes (a merge, new feedback, a launch-doc edit) or 24h pass. **Stay productive:** if the ticket-maker is dry on most days in a week, the bar is too strict. Loosen it (smaller polish, test-coverage and tooling tickets count) rather than going idle.
12. **Reviewer.** Every PR from every account gets a reviewer pass before merge: `mattpocock-skills:code-review` (standards and spec against the ticket) plus `/code-review high` (correctness). Findings go on the PR as comments. **Confirmed correctness or spec findings block the merge** (the reviewer labels the PR `review-blocked`; `pf-automerge.sh` and `pf-ship.sh` skip it; remove the label after the re-check passes) until the author's agent fixes them and the reviewer re-checks. Style and cleanup findings are advisory. This is an automated gate, so "no pause for human review" still holds.
13. **Review findings become tickets.** A confirmed bug the reviewer finds outside the PR's scope is not fixed in that PR. It is posted as `[REVIEW-BUG] <file:line> <one line>` on the PR, and the ticket-maker turns every unfiled `[REVIEW-BUG]` into a ticket on each run (source: that PR), after the dupe check.
14. **Atlas everywhere.** Every worker ticket goes through `/atlas-implement`, with no hand-written worker packets, so Atlas review and verification always run. Run `/atlas-plan` first, day or night, for any ticket that is `conflict-risk`, p1, or has more than one deliverable; p1 plans also go through `/atlas-red-team`. Small single-area tickets skip `/atlas-plan`. The ticket-maker follows `docs/agents/planning.md` and `triage-labels.md`. The main terminal uses the Atlas routes in `CLAUDE.md` for anything the owner asks for. **Night:** still Atlas, but with the cheapest capable worker model and one ticket at a time.
15. **Script it.** Repeatable, deterministic steps belong in `tools/agents/`, not in model turns.

## Per-account settings (`tools/agents/accounts/<handle>.conf`)

`ROLE`, `RESERVE`, `AUTO_FILE`, `TZ`, `NIGHT_START`, `NIGHT_END`, `MIN_WEEKLY_REMAINING_FOR_TICKETS`, `SUCCESSION_RANK`; optional
`REPO_PATH`, `INSTALL_SCRIPT`, `WATCH_PEERS`, `TZ_LABEL`. Shared thresholds are in `accounts/_shared.conf`.
