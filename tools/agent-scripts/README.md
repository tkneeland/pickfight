# Agent helper scripts (reference copies)

These are copies of the helper scripts that tkneeland's Claude Code session runs from `~/.claude/` on the owner's Mac. They save tokens by doing deterministic steps (ship a PR, close out an Atlas work package, resolve scenario-runner conflicts) in one command.

They are **reference copies**: the paths are hard-coded to the owner's Mac (`/Users/tkneeland/...`, `/private/tmp/claude-502`, `~/.claude/usage-snapshot.json`), and the scripts use macOS `sed -i ''`. To use one on another machine, copy it to your own `~/.claude/` and change the paths. The originals in `~/.claude/` are the live versions; refresh these copies when they change.

| Script | What it does |
| --- | --- |
| `pf-ship.sh <issue> "<title>" "<body>"` | Merges main into `.claude/worktrees/<issue>/pickfight`, auto-resolves the known conflict files, pushes, opens the PR with a Resource Usage section, waits for CI, merges, installs the Mac build. |
| `pf-atlas.sh accept\|closeout\|tests\|run` | Atlas bookkeeping: state-file updates, the `[AI CODE REVIEW]`+`[CLOSEOUT]` comment and label move, and running scenarios matching a regex. |
| `pf-fix-runner.sh` | Resolves `tools/scenario_runner.gd` merge conflicts (the file is append-only: keep both sides). |
| `pf-runner-union.py <base> <branch> <main>` | Rebuilds the scenario runner as main plus the branch's appended scenario names, dispatch arms and functions. |
| `pf-rate.sh` | Sets `PF_RATE`/`PF_WEEK` (usage pace) for the PR Resource Usage section. Needs a statusline that writes `usage-snapshot.json`. |
| `pickfight-install-mac.sh` | Exports origin/main headlessly and installs `/Applications/Pickfight.app`. |
| `pickfight-automerge.sh` | Zero-token loop that merged green PRs during a budget week (retired). |
| `pickfight-watch-austin.sh` | Zero-token watcher on agage-JG's GitHub activity that wakes the integrating session. |

Not copied: the Discord relay and keepalive scripts. They run the owner's private Discord bridge and hold local state.

`dev-agent-prompt.txt` is the setup prompt the owner gave tommykneeland's autonomous dev agent (Oct 3). It covers git identity, plugin installs, the ticket lane, verification and PR rules. Austin's agent can use it as a template: swap in `agage-JG` and Austin's lane. The Atlas plugin source is left out because the repo is public; ask the owner for it.
