# Debrief: the hive (AT mode)

**Agent instruction:** if you are a developer's Claude (not the triagemaster's) and your human has not yet confirmed they read this, show them the "For your human" section at the start of the session, in plain words. Then do the "Adopt it" checklist. Full rules: [hive.md](hive.md); the team's own preferences: [team-memory.md](team-memory.md).

## For your human

**What changed.** The team's autonomous triage setup (the hive) now lives in the repo (`tools/agents/`), so every account can use it. In AT mode your Claude watches GitHub, keeps a few worker agents busy on your tickets, and merges your green, reviewed PRs on its own. It runs up to the max workers (your `max_workers` in the hive hub, 3 by default), never more, and starts none while the pace governor says it is ahead of pace. At your 5h stop it starts none until the window resets, and at your weekly stop it starts nothing at all, except in the last `reset_spend_hours` (24) before the weekly reset, when it spends what is left. You set both stops in the hive hub.

**Your settings** live in `tools/agents/accounts/<your-handle>.conf`. Edit it and commit it like any file:
- `TZ`: your timezone. Quiet hours and every printed time follow it.
- `QUIET_START` / `QUIET_END`: your quiet hours (default 20 to 9), when the hive pings you only about p1. They never slow the work.
- `AUTO_FILE`: `0` = your Claude asks for tickets instead of filing them. Set `1` only if the team agrees.
- `MIN_WEEKLY_REMAINING_FOR_TICKETS`: your account takes no new tickets and starts no work when its remaining weekly percent is at or below this (use 50 for a reserve account), except in the last 24h before your weekly reset (100% always stops). Set it, and your 5-hour stop, in the hive hub; the hub's values win over the conf.
- `SUCCESSION_RANK`: who stands in as triagemaster when the current one runs low (2 is next, then 3). With a studio, the hive hub's members list sets this order instead.
- `DISPLAY_NAME`: your name as the hive writes it (optional).
- `RESERVE=1`: only for a spare account that should work only while the regular devs cannot (`accounts/example-reserve.conf`).

**What your Claude does on its own:** starts workers on tickets assigned to you, ships and merges your PRs once they pass review, keeps your usage beacon (a `USAGE` message on the private channel) current, joins the hive whenever you open a session (the SessionStart hook prints the hive status), and shows the status line. **What it won't do:** file tickets itself (unless `AUTO_FILE=1`), or merge a `conflict-risk` PR. Those are for the triagemaster, which is the rank-1 account or, when that account is low on weekly budget, the next account in rank (it sends a `TM ...` message on the private channel).

**Quality gates.** Every ticket is built through Atlas (`/atlas-implement`, with `/atlas-plan` first for risky or p1 tickets). Before any PR merges, including yours, a reviewer agent checks it against repo standards, the ticket, and for correctness bugs. A confirmed bug or spec miss blocks the merge (label `review-blocked`) until your Claude fixes it; a clean pass adds `review-passed`, which merging needs. Style notes are advisory. Bugs it spots elsewhere become new tickets automatically.

**Requesting tickets.** Ask the triagemaster, send an `ASK` on the private channel (`hive-ask.sh <account> "<question>"` waits for the answer), or, when the team uses Discord, post in the dev channel. Before asking, your Claude runs `tools/agents/hive-dupe-check.sh "<keywords>"` so you do not request something that exists.

**Switching modes.** With a studio, switch your account out (MT: it acts only when asked) or in (AT) on the hive hub's members tab. Without one, tell your Claude "MT mode" or "AT mode" (`bash tools/agents/hive-at-mode.sh MT` or `AT`).

**The status line.**
```
Sonnet 5.5 · 5h 42% (r 3:10p) · 7d 61% (r Tue 9a) · AT·on pace
agents 2/1-2 · ready me 3 / alice 4 · PRs 2 · last merge #781 12m ago · tm alice
  #779 Edge arrows for fighters knocked off screen
```
Line 1 is the model, 5-hour and 7-day usage with reset times, and the mode. Line 2 is running agents versus the target, ready tickets per account, open PRs, last merge, and the triagemaster. Each further line is a running agent. `bash tools/agents/hive.sh status` shows the same for every account at once.

## Adopt it (for your Claude)

1. `git pull` the main branch so `tools/agents/` and your `accounts/<handle>.conf` exist (copy `accounts/example-dev.conf` to `accounts/<handle>.conf` if it does not). Ask your human to confirm the `TZ` and `AUTO_FILE` values and commit any change.
2. Join the private channel: the team's first account runs `HIVE_ACCOUNT=<handle> bash tools/agents/hive-msg.sh init`, which writes a random secret topic to `~/.claude/hive/<repo>/<handle>/msg.conf`; every other account puts that same `HIVE_MSG_TOPIC=...` line in its own `msg.conf` (get it from a teammate directly, never in a public place). If the team uses Discord and this account can become triagemaster, also put `HIVE_DISCORD_TOKEN=<bot token>` in `discord.conf` next to it. Never commit either file.
3. Point the status line at the script, in your Claude settings (`~/.claude/settings.json`, `statusLine` command): `HIVE_ACCOUNT=<handle> bash <repo>/tools/agents/statusline.sh`. It also sends your usage beacon.
4. Check it: `HIVE_ACCOUNT=<handle> bash tools/agents/hive-at-mode.sh` prints `AT·on pace` or `AT·ahead`, and `bash tools/agents/hive.sh status` lists your account as online.
5. Start the watchers in `screen`, each with `HIVE_ACCOUNT=<handle>`: `hive-triage-watch.sh` (exits with one line when you must act; restart after each wake), `hive-automerge.sh` (merges green, review-passed PRs, leaves `conflict-risk` and `review-blocked` ones alone), and `windows/hive-supervise.sh msg` (the channel listener and heartbeat; the SessionStart hook restarts it when it dies). To run the whole background session instead, use `hive-keepalive.sh` (see `tools/agents/README.md`).
6. Use `hive-ship.sh <issue> "<title>" "<body>"` to ship and `hive-dupe-check.sh` before any ticket request.
7. If you share a machine with another account, always set `HIVE_ACCOUNT` explicitly; state is kept per repo and handle under `~/.claude/hive/<repo>/<handle>/`.
8. Tell your human it is on, and how to say "MT mode".

### On Windows (Git Bash)

Same steps, with these swaps (details: `tools/agents/windows/README.md`):

- Step 3, the `statusLine` setting in `%USERPROFILE%\.claude\settings.json` (the path is your main checkout):
  ```json
  "statusLine": {
    "type": "command",
    "command": "\"C:/Program Files/Git/bin/bash.exe\" -c \"HIVE_ACCOUNT=<handle> bash /c/Users/<you>/code/<repo>/tools/agents/statusline.sh\""
  }
  ```
- Step 5, no `screen`: `powershell -ExecutionPolicy Bypass -File tools\agents\windows\hive-start.ps1 -Account <handle>` starts the watchers as hidden processes. `hive-status.ps1` shows whether they run and the last wake line (exit code 10 means a wake line needs you; `-Ack` clears it), and `hive-stop.ps1` stops them. Register `hive-install-task.ps1` once so they restart at logon and every 5 minutes.
- Git Bash ignores IANA `TZ` names; `hive-env.sh` maps the common US zones itself (other zones: a POSIX string in your conf).
