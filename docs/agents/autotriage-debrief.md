# Debrief: autonomous triage (AT mode) for Austin and tommykneeland

**Agent instruction:** if you are the Claude for `agage-JG` or `tommykneeland` and your human has not yet confirmed they read this, show them the "For your human" section at the start of the session, in plain words. Then do the "Adopt it" checklist. Full rules: [autotriage.md](autotriage.md).

## For your human

**What changed.** The owner's autonomous triage setup now lives in the repo (`tools/agents/`), so every account can use it. In AT mode your Claude watches GitHub, keeps a few worker agents busy on your tickets, and merges your green PRs on its own. Daytime means at least 3 workers; at night it prefers 1 or 2 when that costs less for the same result. It stops dispatching at 85% of your weekly limit, except in the last 24 hours before the weekly reset, when it spends what is left.

**Your settings** live in `tools/agents/accounts/<your-handle>.conf`. Edit it and commit it like any file:
- `TZ`: your timezone (Austin: change `America/New_York` to yours). Day/night and every printed time follow it.
- `NIGHT_START` / `NIGHT_END`: night hours (default 20 to 9).
- `AUTO_FILE`: `0` = your Claude asks for tickets instead of filing them. Set `1` only if the owner agrees.
- `MIN_WEEKLY_REMAINING_FOR_TICKETS`: your account gets no new tickets when its remaining weekly percent is at or below this (tommykneeland: 50).
- `SUCCESSION_RANK`: who stands in as triagemaster when `tkneeland` runs low (Austin 2, tommykneeland 3).

**What your Claude does on its own:** starts workers on tickets assigned to you, ships and merges your PRs, keeps your usage beacon on issue #432 current, and shows the status line. **What it won't do:** file tickets itself (unless `AUTO_FILE=1`), or merge a `conflict-risk` PR. Those are for the triagemaster, which is `tkneeland` or, when that account is low on weekly budget, the next account in rank (it posts `[TRIAGEMASTER] ...` on #432).

**Quality gates.** Every ticket is built through Atlas (`/atlas-implement`, with `/atlas-plan` first for risky or p1 tickets). Before any PR merges, including yours, a reviewer agent checks it against repo standards, the ticket, and for correctness bugs. A confirmed bug or spec miss blocks the merge until your Claude fixes it. Style notes are advisory. Bugs it spots elsewhere become new tickets automatically.

**Requesting tickets.** Ask the owner or the triagemaster, or comment on #432 with what you need. Before asking, your Claude runs `tools/agents/pf-dupe-check.sh "<keywords>"` so you do not request something that exists.

**Switching modes.** Tell your Claude "MT mode" to make it act only when asked, or "AT mode" to switch back (it writes `AT` or `MT` to `~/.claude/pf/<handle>/pf-at-mode`). "Day mode for 3 hours" overrides night.

**The status line.**
```
Sonnet 5.5 · 5h 42% (r 3:10p) · 7d 61% (r Tue 9a) · AT·night
agents 2/1-2 · ready me 3 / tkneeland 4 · PRs 2 · last merge #781 12m ago · tm tkneeland
  #779 Edge arrows for fighters knocked off screen
```
Line 1 is the model, 5-hour and 7-day usage with reset times, and the mode. Line 2 is running agents versus the target, ready tickets per account, open PRs, last merge, and the triagemaster. Each further line is a running agent.

## Adopt it (for your Claude)

1. `git pull` main so `tools/agents/` and your `accounts/<handle>.conf` exist. Ask your human to confirm the `TZ` and `AUTO_FILE` values and commit any change.
2. Set your handle and point the status line at the script, in your Claude settings (`statusLine` command): `PF_ACCOUNT=<handle> bash <repo>/tools/agents/statusline-usage.sh`. It also writes your #432 beacon.
3. Check it: `PF_ACCOUNT=<handle> bash tools/agents/pf-at-mode.sh` prints `AT·day` or `AT·night`.
4. Start the watchers in `screen`, each with `PF_ACCOUNT=<handle>`: `pf-triage-watch.sh` (exits with one line when you must act; restart after each wake) and `pf-automerge.sh` (merges green PRs, leaves `conflict-risk` ones alone).
5. Use `pf-ship.sh <issue> "<title>" "<body>"` to ship and `pf-dupe-check.sh` before any ticket request.
6. If you share a Mac with another account, always set `PF_ACCOUNT` explicitly; state is kept per handle under `~/.claude/pf/<handle>/`.
7. Tell your human it is on, and how to say "MT mode".

### On Windows (Git Bash)

Same steps, with these swaps (details: `tools/agents/windows/README.md`):

- Step 2, the `statusLine` setting in `%USERPROFILE%\.claude\settings.json` (the path is your main checkout):
  ```json
  "statusLine": {
    "type": "command",
    "command": "\"C:/Program Files/Git/bin/bash.exe\" -c \"PF_ACCOUNT=<handle> bash /c/Users/<you>/code/pickfight/tools/agents/statusline-usage.sh\""
  }
  ```
- Step 4, no `screen`: `powershell -ExecutionPolicy Bypass -File tools\agents\windows\pf-start.ps1 -Account <handle>` starts both watchers as hidden processes. `pf-status.ps1` shows whether they run and the last wake line (exit code 10 means a wake line needs you; `-Ack` clears it), and `pf-stop.ps1` stops them. `windows/README.md` has the optional Task Scheduler entry.
- Git Bash ignores IANA `TZ` names; `pf-env.sh` maps the common US zones itself (other zones: a POSIX string in your conf).
