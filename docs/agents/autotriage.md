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
- **Usage beacon.** Each account's comment on issue #432 with its 5-hour and 7-day usage and reset times, refreshed by `statusline-usage.sh` every 15 minutes.

## Rules

1. **On by default.** AT is on until the owner turns it off. In MT, act only when asked.
2. **Agents.** Day: keep at least `DAY_MIN_AGENTS` (3) workers running. Night: up to 3 are allowed, but prefer `NIGHT_PREFERRED_AGENTS` (1-2) when that is cheaper for the same result. The ticket-maker and merger agents do not count.
3. **Budget.** Do not dispatch when weekly use is at or above `HANDOFF_WEEKLY_USED` (85%), except in the `RESET_GRACE_HOURS` (24h) before that account's weekly reset, when you spend the remaining budget. `pf_budget_ok` in `pf-env.sh` encodes this.
4. **Filing.** Only the triagemaster auto-files tickets, and every filing runs `tools/agents/pf-dupe-check.sh "<keywords>"` first (exit 1 = review the hits, do not file a duplicate). Other accounts request tickets manually unless their conf sets `AUTO_FILE=1`.
5. **Assignment.** Assign by weekly headroom (the #432 rules in `collaboration.md`). Never assign to an account whose remaining weekly (100 minus 7d%) is at or below its `MIN_WEEKLY_REMAINING_FOR_TICKETS`.
6. **Conflict-risk tickets.** Label `conflict-risk` when the ticket edits (not just appends to) a hot shared file (`scripts/RoundManager.gd`, `scenes/Main.tscn`, `scripts/Player.gd`, `scripts/ControllerServer.gd`, `CONTEXT.md`, any `.tscn`), or a file another open ticket lists under Touches. Appending to `tools/scenario_runner.gd` does not count. Only the triagemaster files, assigns and orders them, with one in flight across all devs, and only the triagemaster merges them (`pf-automerge.sh` and `pf-ship.sh` enforce the merge half).
7. **Succession.** When the triagemaster has used 85% of its weekly (outside the 24h before its reset), the role passes to the next `SUCCESSION_RANK` with a fresh beacon (under 6h old) and under 85% used. The new holder posts `[TRIAGEMASTER] <handle> until <reset ISO>` on #432 (`pf-succession.sh --post` does this). The role returns automatically at the original holder's reset. The stand-in has full powers.
8. **Session shape.** AT runs in a separate background Claude session (in `screen`); the main terminal is a control panel. On request, or when the owner returns after 2h+ away, give a status: tickets created and completed since the last status, with time estimates from the median claim-to-merge time by priority. The 9 AM digest of owner decisions goes to the terminal and Discord; the owner may reply on either.
9. **Fires** (immediate, terminal plus Discord): main red for 30 minutes or more; every dev's agent blocked; a secret or security issue; weekly at or above 85% with more than 24h until reset; the AT session crashed. Everything else waits for the digest.
10. **Status line.** Line 1: `<model> · 5h N% (r <time>) · 7d N% (r <day time>) · AT·night`. Line 2: agents / ready / PRs / last merge / triagemaster. Then one line per running agent: `#N title`.
11. **Script it.** Repeatable, deterministic steps belong in `tools/agents/`, not in model turns.

## Per-account settings (`tools/agents/accounts/<handle>.conf`)

`ROLE`, `AUTO_FILE`, `TZ`, `NIGHT_START`, `NIGHT_END`, `MIN_WEEKLY_REMAINING_FOR_TICKETS`, `SUCCESSION_RANK`; optional
`REPO_PATH`, `INSTALL_SCRIPT`, `WATCH_PEERS`, `TZ_LABEL`. Shared thresholds are in `accounts/_shared.conf`.
