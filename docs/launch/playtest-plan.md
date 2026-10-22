# Steam Playtest run sheet (DRAFT)

DRAFT for the owner and Austin (#760). The owner decided (Oct 18) to run a Steam Playtest during the Couch Co-Op Fest in Feb 2027 and to register by about Dec 28 2026 ([owner-decisions.md](owner-decisions.md)). How Playtest works in general is in [playbook.md](playbook.md), sections "Demos and Steam Playtest" and "Steam Playtest and closed betas: how to run them". This file is the run sheet for our own playtest. Anything not decided yet is marked TODO.

The owner's rule (Oct 20): no scheduled sessions. The owner and Austin run playtests informally when they can. So this plan has deadlines for setup and a release, not a fixed schedule of nights.

## Dates

| Date | What | Source |
| --- | --- | --- |
| Nov 2026 | Steamworks signup. Decide the signup entity with Austin first (#685, #540). | owner-decisions.md |
| Early Dec 2026 | Public Discord server open; domain and one-page site with mailing-list signup. | owner-decisions.md |
| Mid-Dec 2026 | "Coming Soon" store page live (#540). | owner-decisions.md |
| About Dec 28 2026 | Register the Playtest. | owner-decisions.md |
| Before Feb 2027 | Steam friend invites (#298) and Steam names (#538) built and tested against Valve's test app 480. | owner-decisions.md |
| Feb 8 to 15 2027 | Couch Co-Op Fest. The playbook gives these dates; the owner decision says only "Feb 2027". TODO: confirm on Steam's event page. | playbook.md, owner-decisions.md |
| Feb to Mar 2027 | Pitch publishers with the Playtest build. | owner-decisions.md |
| Jun 14 to 21 2027 | Next Fest (demo). Playtest runs first so the one-time demo launch is not spent early. | owner-decisions.md, playbook.md |
| Thu Jul 22 2027 | Launch, 1.0. | owner-decisions.md |

## 1. Steamworks setup

Do in order. Tick each when done.

- [ ] Settle the signup entity with Austin (#685) and sign up in Nov 2026. (owner and Austin)
- [ ] Create the main app and note the app ID and depot IDs, one depot per OS (Windows, macOS, Linux). See `docs/steam-upload.md` and #540.
- [ ] Coming Soon page live mid-Dec 2026. Draft text: [store-page.md](store-page.md).
- [ ] Create the Playtest as a separate free app linked to the main game. Its sign-up button sits on the main store page, and Steam's review checks only its images (playbook). Playtest app ID: TODO.
- [ ] Choose sign-up mode. The playbook suggests Limited (admit in batches) with Friend Invites (experimental, 1 to 3 invites per tester) because it is a party game. Decision: TODO, owner and Austin.
- [ ] Register by about Dec 28 2026. Review lead time on Valve's side: TODO, check in Steamworks.
- [ ] Remember: a Playtest is public with no NDA by default (playbook). Do not put anything on it you would not show the public.
- [ ] Remember: a new app can't request keys for its first 3 weeks (playbook). Do not plan on keys for the first batch.
- [ ] Mention the AI-assisted translations in Steam's AI disclosure (owner decision Oct 18).
- [ ] Set the `pickfight/steam_app_id` project setting to the real ID for the shipped build. It defaults to 480 (Spacewar). See `docs/steam-readiness.md`. Whether the Playtest uses its own app ID or the main one: TODO, check Valve's docs.

## 2. Which build ships

Proposed: the full game build, not the demo build (the demo build limits content for Next Fest in June). Owner to confirm: TODO.

Export commands (from `tools/export.sh`; needs Godot 4.6.2 and its export templates):

```
tools/export.sh macos     # build/macos/Pickfight.app
tools/export.sh windows   # build/windows/Pickfight.exe
tools/export.sh linux     # build/linux/pickfight.x86_64
tools/export.sh all       # macos, windows and linux (the default)
tools/export.sh demo      # Next Fest demo, all three OSes: build/demo/macos/Pickfight Demo.app, build/demo/windows/Pickfight Demo.exe, build/demo/linux/pickfight-demo.x86_64
```

- The proposed Playtest build above is the full game: `macos`, `windows` and `linux` (or `all`). `demo` is the limited Next Fest build, not the Playtest build.
- Steam upload: a pushed `v*` tag uploads to the Steam `beta` branch through the `steam` job, and a human promotes it in Steamworks (`docs/steam-upload.md`). It needs the one-time setup in that file first.
- Before the tag, run the fresh-clone script check from `CLAUDE.md` (no `class_name` references) on the release commit (`docs/steam-readiness.md`, item 9.1).
- Crash reports need the Sentry SDK (`tools/fetch_sentry.sh`) and a DSN in the `pickfight/sentry_dsn` project setting in the release build. The owner pastes the DSN (owner-decisions.md; `docs/crash-reporting.md`). Check with `--crash-test` before tagging.
- Telemetry needs the relay's Fly volume (`PICKFIGHT_STATS_PATH`, `relay/fly.toml`) or the records do not persist (FEATURES.md).

## 3. Questions the playtest should answer

Each question maps to something the game already records.

| Question | Where the answer comes from |
| --- | --- |
| Do people finish matches, or quit early? | Anonymous match telemetry (#372, #643): `completed` and `rounds_played`. `tools/summarise_stats.py` prints completed and abandoned counts. |
| Are weapons balanced? | Telemetry per-weapon damage, hits, KOs and win rate by weapon (`tools/summarise_stats.py`). Online playtests also feed the balance report (#405). |
| Which modes and stages get played? | Telemetry: mode popularity and the stages played. |
| How long is a match? | Telemetry: match length and average match length. |
| Does it crash, and where? | Opt-out crash reports (#681) to Sentry, tagged with build, platform, mode and stage. |
| What do players dislike or find confusing? | The in-game Feedback button (#262) files a `needs-triage` and `feedback` GitHub issue with build, OS and stage; the survey below; Discord. |
| Do Online rooms fill and can friends join? | Steam friend invites (#298) and room codes. TODO: telemetry does not record room fill or join failures. See the "Not recorded" list below. |

Not recorded today (FEATURES.md lists no telemetry for these): time from scan to join, join failures and their reasons, the "one more round" rate, per-player idle time, wishlist clicks. If we want any of them, it needs a new ticket before the playtest. TODO: owner to decide which, if any.

Telemetry and crash reports stay on by default for testers, with the first-launch notice (FEATURES.md). Testers can turn them off in Settings > More options. Telemetry is never sent from scenario or `--bots` runs.

## 4. Feedback survey (7 questions)

Put the form link in `[FEEDBACK_FORM_URL]` (placeholder from [discord-server.md](discord-server.md)). Form tool: TODO.

1. How many people were in your game, and was it Online (room code or Steam invite) or in one room?
2. What happened in the last round you played? (open answer)
3. Did you start another round without being asked? Why or why not?
4. Was there a moment you could not tell what had hit you, or an attack that felt unfair? (open answer)
5. Which weapon or stage was the most fun, and which was the least?
6. Did anything stop you joining or playing (join, lag, crash)? What happened?
7. Would you wishlist the game, and would you tell a friend about it? Why?

Ask open questions first, and compare the answers with what the telemetry shows (playbook, "Playtesting and analytics"). Sign-ups are not wishlists, so ask for the wishlist separately (playbook).

## 5. How testers reach us

The plan is in [discord-server.md](discord-server.md). It is a DRAFT; the server opens early Dec 2026.

- `#playtest-signup`: pinned `[PLAYTEST_SIGNUP_URL]`; the developers post when slots open.
- `#bug-reports` (forum): ask for build, mode (Local or Online) and steps. The pinned note says the in-game Feedback button already files GitHub issues.
- `#balance-and-ideas` (forum): weapon, stage, balance and idea tags.
- `#announcements`: builds and playtest news. A Scheduled Event goes up only when a playtest session is real (the playtests are informal).
- The invite link, Steam page link and form link: the placeholders in discord-server.md. TODO: fill them in.
- The Playtester role gets pinged only for playtest news (playbook, Discord section).

## 6. Go/no-go: turning feedback into tickets

Triage follows the repo's labels (`docs/agents/triage-labels.md`). Feedback from the Feedback button already arrives as a `needs-triage` issue.

Fix before the Feb 2027 playtest opens (go or no-go for release of the build):

- [ ] A fresh install starts and a match finishes on Windows and macOS.
- [ ] Crash reports reach Sentry from a release build (`--crash-test`), and telemetry reaches the relay.
- [ ] An Online room can be joined by room code and by Steam friend invite.
- [ ] The Discord server, the signup link and the survey form are live.

Signals while it runs. The thresholds are not set; TODO: the owner and Austin to choose numbers after the first batch, not before:

| Signal | Turns into |
| --- | --- |
| Any crash seen in Sentry | A bug ticket (p1 if repeated), tagged with the mode and stage. |
| Several testers report the same problem, or the same unfair-feeling attack | A ticket; the playbook warns first playtests surface fairness complaints. |
| A weapon far ahead or behind in win rate (the summary script) | A balance ticket, after checking it against the balance report (#405). |
| Many matches abandoned early (`completed` false) | A "why did they leave" ticket; read the open survey answers first. |
| A single mention of an idea | Log it in `#balance-and-ideas`; no ticket until it repeats. |

After each batch: post what changed in `#devlog`, and say which feedback caused it. Feedback is never a promise.
