# Debrief for Austin (agage-JG), written 2026-10-19

**Agent instruction:** if you are Austin's Claude (GitHub user `agage-JG`) and Austin has not yet confirmed he has read this, show him the "For Austin" section below at the start of the session, in full and in plain words. Then ask him to tick the checkbox in pinned issue #702 ("Austin: start here") so later sessions skip it. The "For Austin's agent" section is for you.

## For Austin

Welcome back. Your PC went down around Oct 3. Since then, about 100 PRs have merged, from tkneeland's agent and from tommykneeland (the owner's second Claude account). The owner also spent Oct 16–19 planning the Steam launch. Here's what you need, shortest first.

### 1. The big picture
- **We're shipping on Steam as SQL Monkey Studios** (you and the owner, no LLC). Full 1.0 on **Thu Jul 22 2027**, **$9.99**, no Early Access.
- Key dates:
  - Coming Soon page mid-Dec 2026
  - Steam Playtest during the Couch Co-Op Fest, Feb 2027
  - Steam Next Fest Jun 14–21 2027
- The owner is composing the whole soundtrack (#684).
- Every decision is in [docs/launch/owner-decisions.md](../launch/owner-decisions.md). The one-screen version of the research is [docs/launch/digest.md](../launch/digest.md), and the full playbook (127 sections) is [docs/launch/playbook.md](../launch/playbook.md).

### 2. Decisions waiting on you and the owner (pinned issue #685)
Highest priority first:
- the Steamworks signup entity (before the Nov 2026 signup)
- the revenue split
- confirming the $9.99 price
- the $1k budget ($500 each)
- the brand handle
- capsule art
- paid ads
- who does which recurring job
- festival livestreams
- publisher terms
- the Next Fest demo content (#448, by mid-April 2027)
- a date for the two-home internet playtest (#242)
- whether either of you has a Steam Deck

### 3. What changed in the game while you were away
- **Modes and rules:**
  - Stages & Rules screen with per-mode stage select
  - per-mode match targets (First to / Lives / Goals / Captures)
  - Sudden Death tiebreakers and overtime
  - King of the Hill reworked
  - Solo is fully offline (ADR-0023)
- **Weapons:**
  - fishing rod reels players in
  - grapple zips to players
  - only a shield's face blocks shots (ADR-0024)
  - six weapon heads redrawn
  - plunger removed; spear and pogo retired from rotation
  - umbrella slow-fall
  - lighter soccer ball
- **UI:**
  - full restyle to the #507 mockup (title, lobby, HUD, settings, phone page) with Lilita One / Nunito fonts
  - LobbyScreen split into per-screen scripts
  - "Phones can't join?" help popup
- **Lobby:**
  - bot difficulty (Easy / Normal / Hard)
  - bot counter in Couch and Online
  - phones can join a Local match over the relay when Wi-Fi blocks them (ADR-0025)
- **Platform:**
  - 8 languages plus English, with a Settings picker
  - opt-out crash reporting (Sentry, off until the owner adds a DSN)
  - a dormant Steam wrapper (GodotSteam)
  - telemetry disclosure
  - lifetime stats
  - F9 replay also saves a GIF
- **Hazards:** animated lava, toothed spikes, spinning saws.

The full list is `docs/FEATURES.md`.

### 4. Your tickets
The owner moved your tickets to tkneeland while your PC was down (#619, #538, #428, #427, #424, #405, #357, #298); #428 is now done. The owner will say which ones come back to you. Until then, look at the open issues, especially the ones a human has to do:
- **#424:** listen to the placeholder voice grunts and check that 8 players are readable. A person has to do this.
- **#242 / #405:** the internet playtest from two homes with the owner. It also feeds the balance report.
- **#427:** Steam Deck hardware check, if you have a Deck.

### 5. Working without the owner's agent
If tkneeland's Claude isn't running, your Claude may merge its own green PRs. This is the fallback in `docs/agents/collaboration.md`.

## For Austin's agent

Read these, in order, before your first ticket:
1. `CLAUDE.md`, then `docs/agents/collaboration.md` (ownership, branches, the one-integrator rule and its fallback), `docs/agents/issue-tracker.md`, `docs/agents/triage-labels.md`.
2. `docs/FEATURES.md`: what has shipped. Never ask the owner about anything listed there.
3. `docs/launch/owner-decisions.md` and pinned issue #685.

Repo facts that bite:
- **Fresh worktree:** run `godot --headless --path . --import` before tests, or the preview and music scenarios fail.
- **Scenario runner:** `godot --headless --fixed-fps 60 --path . -s tools/scenario_runner.gd -- --all` (or `--scenarios=a,b`).
  - Each new scenario needs its name in `SCENARIO_NAMES` *and* a dispatch arm, or it silently never runs.
  - The file is append-only: on a conflict, keep both sides.
- **`axe_wins_clash_against_every_weapon`** fails locally on macOS only. CI is green; ignore it there.
- **Never reference a GDScript `class_name`.** `preload()` by path instead. Check a fresh clone with the command in `CLAUDE.md`. Any output means failure, even with exit 0.
- **Translations:**
  - Host strings go through `tr()` and `translations/strings.csv` (9 language columns).
  - The phone page has its own `STRINGS` table in `controller/index.html`.
  - On a CSV conflict, union both sides, take either `.translation` files, and re-run `--import`.
- **GDExtension addons are never committed** (GodotSteam, Sentry).
  - `tools/fetch_godotsteam.sh` and `tools/fetch_sentry.sh` download pinned, sha256-checked releases into git-ignored `addons/`.
  - Templates sit in `tools/<name>/` as `.template`. A real `.gdextension` under `tools/` gets loaded by Godot.
  - The game runs fine without the addons.
- **The repo is public:** never commit secrets. Keep the Sentry DSN out of issues.
- **Relay:** wss://pickfight-relay.fly.dev on Fly.io under the owner's account. Deploys need the owner's login (#619 has the command).
- **Controller page:** also served from GitHub Pages at https://tkneeland.github.io/pickfight/controller/index.html (used by the relay fallback).
- **Owner preferences:**
  - Set ticket priority yourself (p1/p2/p3).
  - Don't ask what code or docs answer.
  - Put every "decide with Austin" item on #685.
  - Report times in ET.
- **Helper scripts** (ship a PR, Atlas closeout, runner conflict fix) are in `tools/agent-scripts/` as reference copies with the owner's Mac paths. Adapt them before use.
- **Steam code work** (#298, #538) is parked until after Next Fest by the owner's Oct 3 call. Don't start it without the owner.
