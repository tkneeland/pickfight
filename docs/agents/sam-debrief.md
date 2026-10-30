# Onboarding for Sam Schantz (schans2)

**Agent instruction:** if you are Sam's Claude (GitHub user `schans2`) and Sam has not yet confirmed he has read this, show him the "For Sam" section at the start of the session, in plain words, then do the "Set up" checklist.

## For Sam

Welcome to SQL Monkey Studios. Pickfight is a same-room platform fighter built in Godot 4.6; three other agents already work in this repo (`tkneeland`, `agage-JG` and `tommykneeland`), and yours joins them as a regular dev. Your agent can start workers on tickets assigned to you, ship and merge your green PRs, and keeps a usage beacon (a `USAGE` message on the private channel) current. It never files tickets unless `AUTO_FILE=1` in your account file, and it never merges a `conflict-risk` PR (the triagemaster does that).

What you need from the owners, outside the repo:
- push access to `tkneeland/pickfight` (a collaborator invite to `schans2`),
- the private message-channel topic (given to you directly, never committed, posted or pasted anywhere public),
- the itch.io page password if you want to download builds (`pookman4/pickfight`; builds come from the release workflow, so there is no need to export zips locally).

Your account settings are `tools/agents/accounts/schans2.conf` (timezone, night hours, `AUTO_FILE`, succession rank 3: below `tkneeland` and `agage-JG`). Change them and commit like any file.

## Set up (for your Claude)

1. Install Godot 4.6.2, Git (Git Bash on Windows), `gh` (logged in as `schans2`) and `jq`. Clone the repo and `git pull` main.
2. Read `CLAUDE.md`, [collaboration.md](collaboration.md) and [autotriage-debrief.md](autotriage-debrief.md) once, and `docs/FEATURES.md` before proposing or filing anything.
3. Put the channel topic in `~/.claude/pf/schans2/pf-msg.conf` as `PF_MSG_TOPIC=...`. Never commit, post or echo it.
4. Start the watchers: `powershell -ExecutionPolicy Bypass -File tools\agents\windows\pf-start.ps1 -Account schans2` (macOS/Linux: see `tools/agents/README.md`). Point the Claude status line at `tools/agents/statusline-usage.sh` with `PF_ACCOUNT=schans2`; it also keeps your `USAGE` beacon on the private channel current.
5. Check it: `PF_ACCOUNT=schans2 bash tools/agents/pf-at-mode.sh` prints `AT·day` or `AT·night`.
6. Send a hello on the channel (`pf-msg.sh send HELLO schans2-online`) and tell Sam it is on, and how to say "MT mode".
7. Boot-check habit for every PR: clone the committed branch fresh and run `godot --headless --path <clone> --quit`; any `SCRIPT ERROR` or `Failed to load script` line is a failure (see `CLAUDE.md`).
