# Agent helper scripts (owner-only leftovers)

The live, account-agnostic helpers (ship a PR, Atlas closeout, usage pace, statusline, auto-merge, peer watcher,
scenario-runner conflict fix) are in [`tools/agents/`](../agents/README.md). Use those; this folder keeps only what
has no counterpart there.

| File | What it does |
| --- | --- |
| `pickfight-install-mac.sh` | Exports origin/main headlessly and installs `/Applications/Pickfight.app`. Reference copy with the owner's Mac paths (`/Users/tkneeland/...`); `tools/agents/accounts/tkneeland.conf` runs the live copy from `~/.claude/` as `INSTALL_SCRIPT`. |
| `dev-agent-prompt.txt` | The setup prompt the owner gave tommykneeland's autonomous dev agent (Oct 3): git identity, plugin installs, the ticket lane, verification and PR rules. Use it as a template: swap in your handle and lane. The Atlas plugin source is left out because the repo is public; ask the owner for it. |

Retired from this folder (#1134): `pf-atlas.sh`, `pf-rate.sh`, `pf-ship.sh` and `statusline-usage.sh` (stale copies of
the `tools/agents/` scripts of the same name), `pickfight-automerge.sh` (now `tools/agents/pf-automerge.sh`),
`pickfight-watch-austin.sh` (now `tools/agents/pf-watch-peers.sh`), and `pf-fix-runner.sh` + `pf-runner-union.py`
(now `tools/agents/pf-scenario-merge.sh`).

Not copied: the Discord relay and keepalive scripts. They run the owner's private Discord bridge and hold local state.
