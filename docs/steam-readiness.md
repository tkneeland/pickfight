# Steam release readiness (#258)

Ordered checklist to ship Pickfight on Steam. Itch stays the private-friends channel.

**Legend.** Who: `owner` = needs the owner's identity, money or a decision; `agent` = an agent can do it in the repo. Status is read from the repo as of 2026-10-22: `done`, `todo`, `partial`, `skip` (not needed for launch).

**Verification caveat.** This was written without web access. Every external number (fees, waiting periods, image sizes) is from memory and marked **verify**; check it against the Steamworks docs (partner.steamgames.com/doc) before spending money or producing art.

## Owner decisions already made (from #258 comments)

| Decision | Value |
|---|---|
| Price | $9.99 (owner, 2026-10-18) |
| Name | Title text "PickFight" (owner, 2026-10-18; all-caps logo, `docs/launch/owner-decisions.md`); the 2026-10-01 note said "Pickfight", the rest of this repo still writes "Pickfight" (a spelling cleanup, not an open decision). 2026-10-01 search found no Steam title named Pickfight or Pick Fight; nearest is "Pickup n' Fight" on itch (free, small). Re-check at name lock. |
| Language | **Superseded 2026-10-18:** English plus 8 languages (zh-Hans, ru, es-419, pt-BR, de, fr, ja, ko), shipped in #688; Claude translates, volunteers proofread, no paid agency (`docs/launch/owner-decisions.md`). The 2026-10-01 "English only" answer is void. |
| Playing without a phone | Gamepad (right stick = arm, relative vector) in either match kind; in an Online or Solo match the host-PC mouse seat is claimed by itself (#435: no "Play on this PC" toggle); no shared keyboard |
| Online | Keep Fly relay and room codes for itch; Steam builds add Steam lobbies and friend invites over the same relay (#298) |
| macOS signing | At Steam launch; friends use right-click, Open until then |
| Achievements | **Superseded 2026-10-20:** the 18-item list on #689 is approved and shipped (`scripts/Achievements.gd`, #689). Steam definitions still need the real app (see 6.5). |

## Still-open owner decisions (placeholders)

| Item | Placeholder | Who |
|---|---|---|
| Release date | **Superseded 2026-10-18:** full **1.0 on Thu Jul 22 2027** (no Early Access). Store page "Coming Soon" mid-December 2026; Steam Playtest during Couch Co-Op Fest (Feb 2027); demo in **Steam Next Fest, June 2027** (demo content still to decide with Austin, #448). Old 2026-10-01 plan (Feb Next Fest, March EA) is void. | owner |
| Launch price per region | **Superseded 2026-10-18:** **$9.99 USD** at 1.0, **20% launch-week discount**, Steam recommended regional prices as-is. Soundtrack DLC $4.99 on launch day; no other paid DLC. | owner |
| Final name / trademark check | "PickFight"; trademark: run a clearance search only, do not file (owner, 2026-10-18) | owner |
| Early Access vs 1.0 | **Superseded 2026-10-18:** full **1.0**, no Early Access | owner |
| Publisher entity (individual vs company) | **Reopened 2026-10-18:** to decide with Austin (individual, Austin, or an LLC) before the Nov 2026 signup, with the revenue split (#685). The 10-01 answer was the owner as an individual; drives tax/bank forms and macOS/Windows signing identity | owner |

## Demo contents (#361)

The Next Fest demo is the same game with a content slice, chosen by one flag: the "demo" feature tag (the `Demo macOS`, `Demo Windows` and `Demo Linux` export presets, `tools/export.sh demo`) or `--demo-build` on the command line. The slice lives in `scripts/DemoBuild.gd`. It limits the stage rotation, the pickup weapon pool and the host phone's mode picker; the Settings panel lists only slice items and can't switch on anything outside it. Up to 8 players, no time cap. After a match's victory screen the demo shows an end card with the logo: "Thanks for playing the Pickfight demo! Wishlist the full game on Steam".

| Part | Picks | Why |
|---|---|---|
| Stages (6) | Flatlands, Highrise, Pillars, Islands, Bowl, Springboard | Plant-and-swing reads best on stages with something to plant on. Flatlands opens every match and teaches the controls on flat ground; Highrise is vertical, Pillars and Islands make gaps to cross with the pole, Bowl suits King of the Hill, Springboard adds bounce pads. None is a large-view stage (those need 5+ players, and a demo table often has two), and none has heavy hazards, so the hook is the fighting. |
| Weapons (5) | Pickaxe (everyone starts with it), sword, boomstick, grapple, flail | Four very different feels for a first match: a plain melee swing, a ranged shot, a pull-yourself-around tool that is the closest thing to Getting Over It, and a physics chain. Axe, dagger and the rest are held back for the full game. |
| Modes (2) | Classic, King of the Hill | Classic is the core loop; King of the Hill gives a reason to stay in one spot and fight over it. Hot Potato, Sudden Death and Stock stay in the full game. |

`--demo` on its own is the older showcase mode (random weapons, 120 Hz physics), not this; `--demo-build` is the demo.

## Checklist (in order)

### 1. Steamworks account and app
| # | Item | Who | Blocked on | Status |
|---|---|---|---|---|
| 1.1 | Create Steamworks partner account (partner.steamgames.com); choose individual or company | owner | publisher entity decision | todo |
| 1.2 | Complete identity, tax (W-9 / W-8) and bank forms | owner | 1.1 | todo |
| 1.3 | Pay Steam Direct app fee, $100 per app (**verify**; recoupable after $1,000 gross revenue, **verify**) | owner | 1.2 | todo |
| 1.4 | Record the AppID and the depot IDs (one per OS) in the repo as GitHub variables (not secrets) | owner then agent | 1.3 | todo |
| 1.5 | Do not use the Spacewar test AppID (480) for anything shipped; fine for local GodotSteam tests | agent | none | todo |

### 2. Store page
| # | Item | Who | Blocked on | Status |
|---|---|---|---|---|
| 2.1 | Short description, long description, tags, feature list. Draft from `docs/FEATURES.md` | agent drafts, owner approves | name | partial (draft in `docs/launch/store-page.md`, needs owner approval, #712) |
| 2.2 | Capsule and library art (sizes below, all **verify**) | owner or commissioned artist; agent can lay out from `docs/art/` | art budget (#685) | partial (logo and six capsule exports in `art/logo/capsules/`; page background and icons missing) |
| 2.3 | At least 5 screenshots, 1920x1080 (**verify** minimum). Capture with the existing screenshot tools (`tools/`) and playtest footage | agent | none | done (9 shots in `docs/launch/screenshots/`, regenerate with `tools/capture_store_screenshots.gd`, #723) |
| 2.4 | Trailer: cut from playtest footage; the game has an F9 instant replay that saves ~10 s PNG sequences to `user://clips/` (#329, ADR-0020, 256x144, too small for a trailer). Record the trailer with a screen recorder (OBS) at 1080p or higher during playtests instead; use F9 clips only as a reference for moments worth re-capturing | owner (edits) | none | todo (owner edits it from Claude's shot list, `docs/launch/trailer-shot-list.md`, #728; Next Fest trailer due May 3 2027) |
| 2.5 | System requirements, supported languages (English plus 8, #688), controller support flag (partial/full, see section 6) | agent | 6.x | partial (draft in `docs/launch/store-page.md`, needs owner approval, #712) |
| 2.6 | Legal links: privacy policy URL (the game talks to our relay and files feedback issues, so say so), support contact | owner | none | partial (draft in `docs/launch/privacy-policy.md`, needs owner approval, #712) |
| 2.7 | Submit store page for Valve review, then set "Coming soon" public | owner | 2.1-2.6, 1.3 | todo |

**Telemetry (for the privacy policy, 2.6; #372).** On by default, with an opt-out toggle in Settings ("Send anonymous match stats") and a one-time first-launch notice on the host screen (#617: nothing is sent until it has been dismissed with "Got it" or "Turn off"). At the end of each match the host sends one record to our relay: per-weapon damage, hits and KOs by human players (bots and the lobby sandbox excluded), the game mode, the stage names, the format (free-for-all or teams), the match length, and the winning weapon. It contains no nickname, player colour, device or Steam identifier, or any other player ID. The relay does not store or log the sender's IP address; it keeps only a salted hash in memory to rate-limit, which is lost on restart, and rounds the stored timestamp to the hour. The data is used only to balance weapons, modes and stages. If anything ever needs an identifier, switch to opt-in. The policy text should say all of this and mention the toggle.

Capsule sizes to **verify** against the current Steamworks "Store graphical assets" page:

| Asset | Size |
|---|---|
| Header capsule | 460 x 215 |
| Small capsule | 231 x 87 |
| Main capsule | 616 x 353 |
| Vertical capsule | 374 x 448 |
| Page background | 1438 x 810 |
| Library capsule | 600 x 900 |
| Library header | 920 x 430 |
| Library hero | 3840 x 1240 |
| Library logo | up to 1280 x 720, transparent PNG |
| Client icon / community icon | 256 x 256 / 184 x 184 (**verify**) |

Art in the repo today: the logo (`art/logo/logo.svg`, and `art/logo/logo_1024.png`, 1024x256 with transparency, which fits the library logo bound; **verify** before using it as one) and six capsule exports in `art/logo/capsules/` (header 920x430, small 462x174, main 1232x706, vertical 748x896, library 600x900, library hero 3840x1240; the first four are 2x the sizes above). Not yet in the repo: page background, client and community icons. The owner's budget decision on capsule art and logo is still open with Austin (#685), so item 2.2 stays `partial`. Status: partial.

### 3. Ratings and compliance
| # | Item | Who | Blocked on | Status |
|---|---|---|---|---|
| 3.1 | Steam content survey (mature content questionnaire) and the IARC-based age rating questionnaire for the store (**verify** current form names). Cartoon violence only (ragdoll-ish melee, no blood, no gambling, no in-app purchases, no user-generated content shared beyond the feedback text box) | owner (agent supplies answers) | 1.1 | partial (draft in `docs/launch/content-survey.md`, needs owner approval, #712) |
| 3.2 | Declare the online features and data the game sends (relay, feedback button #262, opt-out crash reports #681) in the privacy policy | owner | 2.6 | partial (draft in `docs/launch/privacy-policy.md`, needs owner approval, #712) |
| 3.3 | Tax/export compliance questions in the app wizard | owner | 1.2 | todo |

### 4. Legal and credits
| # | Item | Who | Blocked on | Status |
|---|---|---|---|---|
| 4.1 | Sound effects are Kenney packs, CC0 1.0, credited in `CREDITS.md`; CC0 allows commercial use with no attribution | agent | none | done |
| 4.2 | Re-audit every asset type before release: `assets/music/` (confirm licence and source is in `CREDITS.md`), the synthesised announcer lines, fonts, any art. Anything not CC0/own must have a licence that allows commercial sale | agent | none | **done** (#721: every file under `assets/` audited: Kenney SFX, nine OpenGameArt CC0 tracks, own synthesised announcer and grunts, OFL fonts (Lilita One and Nunito in `art/fonts/`), own logo art; `CREDITS.md` now has an Art section) |
| 4.3 | Godot's MIT licence text and third-party notices must ship with the game (Godot: Project, Export includes them via Help, Copyright info; add a `THIRD-PARTY.md` or in-game credits screen). If GodotSteam is added, include its MIT notice and the Steamworks SDK terms | agent | 5.x | **done** (#721: `THIRD-PARTY.md`, shown on the in-game Credits screen and included in exports) |
| 4.4 | Trademark/name check, and EULA/terms if wanted | owner | name | todo |

### 5. Builds, depots and SteamPipe

Today: `.github/workflows/release.yml` runs on `v*` tags (or manual dispatch), installs Godot 4.6.2 plus templates, exports `Windows`, `macOS`, `Linux` presets (`export_presets.cfg`), zips them to `dist/`, uploads a workflow artifact and pushes to itch via butler (secret `BUTLER_API_KEY`, variable `ITCH_TARGET`; skipped if unset). Builds are unsigned. macOS preset has `codesign/codesign=1` but empty identity and notarization off; Windows signing is off. Status of that pipeline: `done`.

Add a Steam step:

| # | Item | Who | Blocked on | Status |
|---|---|---|---|---|
| 5.1 | Define three depots in Steamworks (Windows, macOS, Linux) and a `default` then `beta` branch plan | owner | 1.3 | todo |
| 5.2 | Add `steam/app_build.vdf` and `steam/depot_*.vdf` to the repo (AppID and depot IDs from GitHub variables, `contentroot` pointing at the unzipped per-OS build dirs). Export dirs, not zips: SteamPipe wants files | agent | 1.4 | done (#722; owner adds secrets/vars, see `docs/steam-upload.md`) |
| 5.3 | Add a `steam` job to `release.yml` after `export`, gated like the itch step (skip with a message when secrets/vars are unset, so forks and early tags still pass). Use a steamcmd action (for example `game-ci/steam-deploy`, **verify** maintenance and pin by SHA) or download steamcmd directly. Set the build's branch to `beta` and promote to `default` by hand in Steamworks | agent | 5.1, 5.2 | done (#722; owner adds secrets/vars, see `docs/steam-upload.md`) |
| 5.4 | Create a dedicated Steam builder account with only "Edit App Metadata"/"Publish App Changes" and "Upload builds" rights | owner | 1.1 | todo |
| 5.5 | Steam Guard on the builder account: CI cannot answer a prompt. Use the config.vdf / ssfn approach the chosen action documents (**verify**) | owner | 5.4 | todo |
| 5.6 | Export-preset tweaks for Steam: Windows `application/*` metadata (company, product, version), macOS bundle id and min OS, Linux x86_64 only | agent | none | done (#722; version stays on the project setting, not the preset) |
| 5.7 | Windows code signing (optional, reduces SmartScreen friction; Steam does not require it). Owner decision 2026-10-18: skip unless it would really bite | owner | cost decision | skip (owner, 2026-10-18) |
| 5.8 | macOS signing and notarization: owner decided "at Steam launch". Needs an Apple Developer Program membership (**verify** $99/yr), a Developer ID certificate, notarytool credentials; fill `codesign/identity`, `codesign/apple_team_id` and `notarization/*` in `export_presets.cfg`, and run on a macOS runner (signing from ubuntu is not practical, **verify**) | owner (accounts) then agent (workflow) | Apple membership | todo |
| 5.9 | Steam review of the build (Valve checks the build before release, **verify** duration, usually a few days): submit well before the target date | owner | 5.3 | todo |

Secrets and variables the Steam step needs (names are suggestions; do not commit values, owner adds them in repo settings):

| Name | Kind | Purpose |
|---|---|---|
| `STEAM_USERNAME` | secret | Steam builder account login |
| `STEAM_CONFIG_VDF` (or password plus guard-code mechanism) | secret | Steam Guard session for the builder account |
| `STEAM_APP_ID` | variable | AppID |
| `STEAM_DEPOT_WINDOWS`, `STEAM_DEPOT_MACOS`, `STEAM_DEPOT_LINUX` | variables | Depot IDs |
| `APPLE_*` (cert p12, password, team id, notary API key) | secrets | Only for 5.8 |

### 6. GodotSteam integration

Choices for Godot 4.6 (**verify** the current GodotSteam release supports 4.6.x before committing):

| Option | Notes | Recommendation |
|---|---|---|
| GodotSteam GDExtension | Drop-in addon in `addons/`, no engine rebuild, works with the stock export templates the workflow already downloads. Needs the Steamworks SDK redistributables shipped per platform | **Choose this** |
| GodotSteam engine module / precompiled editor | Requires custom engine and custom export templates built in CI; slower, more to maintain | Only if the GDExtension lacks a needed feature |
| Own thin wrapper over the C SDK | Maximum control, maximum work | No |

Plan:
| # | Item | Who | Blocked on | Status |
|---|---|---|---|---|
| 6.1 | (GodotSteam binaries are not committed: run `bash tools/fetch_godotsteam.sh`, pinned to 4.23.1 + sha256; the release workflow runs it before export.)  Add GodotSteam GDExtension; add `steam_appid.txt` to dev checkouts only (git-ignored); initialise Steam behind a single `SteamPlatform` wrapper so itch/non-Steam builds run when the client or library is absent. Preload by path, never by `class_name` (repo rule) | agent | 1.4 for real AppID; Spacewar 480 for dev | **done** (#428, GodotSteam GDExtension 4.23.1, see 6.1 notes below) |
| 6.2 | Remote Play Together: **off at launch** (owner, 2026-10-18; supersedes the earlier "test first" plan). Do not tick the store-page feature; no test needed for launch. If it is revisited, the old notes apply: host launches through Steam, friend plays with gamepad or mouse (phones do not play online, ADR-0021) | owner | none | skip (off at launch, owner, 2026-10-18) |
| 6.3 | Steam lobbies and friend invites carrying the room code; game traffic stays on our relay, no Steam P2P | agent (agage-JG) | #298, #241, 6.1 | done (#298) |
| 6.4 | Steam overlay compatibility check with the Compatibility renderer | owner tests | 6.1 | todo |
| 6.5 | Achievements: the 18-item list on #689 (owner-approved 2026-10-20), wired through `SteamPlatform`. Defining them in Steamworks needs the real app; enter them from `docs/steam-achievements.md` | agent (code), owner (Steamworks) | 6.1, 1.3 | partial (code done, #689, `scripts/Achievements.gd`; Steamworks definitions todo) |
| 6.6 | Steam Cloud: not needed (settings are small, `user://audio.cfg`) | none | none | skip |

Existing online work this builds on: relay with room codes (#238, ADR-0019), host going online and remote seats (#239), snapshots (#251), PC client join by code (#241, agage-JG). Itch and non-Steam builds keep plain room codes.

#### 6.1 notes (done, #428)

- **Version:** GodotSteam GDExtension **4.23.1** (Steamworks 1.65; release notes: "works on any Godot version 4.4 and up", `compatibility_minimum = "4.4"`; verified loading on Godot 4.6.2). The upstream project moved to Codeberg (`codeberg.org/godotsteam/godotsteam`, release `v4.23.1`, asset `godotsteam-4.23.1-gdextension-plugin-4.4.zip.tar.xz`); the GitHub repo is archived and its releases only hold overflow files.
- **What is checked in** (`addons/godotsteam/`, about 30 MB): the `.gdextension` (trimmed to macOS universal, Windows x86_64, Linux x86_64), debug and release libraries for those three (the editor and headless runs load the debug ones), the Steam API redistributables and `license.md`. Dropped: Android, 32-bit, Linux arm64, per-arch macOS dylibs and the editor updater plugin. To update, replace the folder from a newer release and re-trim the `.gdextension`.
- **Wrapper:** `scripts/SteamPlatform.gd`, autoload `SteamPlatform`. Reaches Steam only through `Engine.has_singleton("Steam")`, so no `class_name` and no hard dependency. It initialises (`steamInitEx`) only when the singleton exists and the game is not under the scenario runner or `--headless`; any failure logs one line and leaves `available = false`. API: `available`, `app_id`, `persona_name()`, `steam_id()`, `set_achievement(api_name)`, `store_stats()` (the last two are the hooks for #689 and #538, no-ops until Steam is up).
- **App ID:** project setting `pickfight/steam_app_id` (default 480, Spacewar). Shipping builds must change it (item 1.5).
- **Testing locally with Spacewar 480:** start the Steam client, then run `echo 480 > steam_appid.txt` in the repo root (git-ignored, never commit it) and launch the game (`godot --path .`). The log shows `SteamPlatform: Steam ready (app 480)`. Without the file or client the log shows `Steam init failed` and the game runs normally.
- **Exports:** `export_presets.cfg` has no Steam-specific preset, and the GDExtension libraries are packed into every macOS, Windows and Linux export, including the itch builds. That is fine: without the Steam client the init fails with one log line and the game runs. A separate Steam preset is only needed later if we want to keep the Steam libraries out of the itch download, or to ship a different app ID; at that point exclude `addons/godotsteam/*` from the non-Steam presets and add `steam_appid.txt` handling to the Steam one.

### 7. Steam Deck
| # | Item | Who | Blocked on | Status |
|---|---|---|---|---|
| 7.1 | Gamepad seats: right stick drives the arm, no phone needed | agent | none | done (#261) |
| 7.2 | Confirm full-controller navigation of menus and lobby (no mouse or keyboard needed to start a match), on-screen glyphs, and a Deck-readable UI at 1280x800 | agent | none | done in code (#368: Y host menu, View settings, 16 px text floor, scenarios `deck_*`); the on-device check stays with 7.3. Gap list: `docs/steam-deck-readiness.md` |
| 7.3 | Linux build runs under Proton-free native Linux or Proton; test on a real Deck. Valve's criteria are recorded in `docs/steam-deck-readiness.md` (checked 2026-10-02) | owner (hardware) | 5.3 | todo |
| 7.4 | The phone web controller still works on Deck as host if the Deck is on a LAN; document it | agent | none | documented in `docs/steam-deck-readiness.md`; needs a real Deck to confirm |
| 7.5 | Deck Verified submission | owner | 7.2, 7.3, store page live | todo |

### 8. Localization
All in-game text is translatable (#367) and ships in English plus the 8 languages in the decisions table (#688). The translations are machine-made and not yet proofread: volunteer proofreaders get credited in-game, and every language in the `CREDITS.md` Translations table is still open. Store page text in all 8 languages is drafted in `docs/launch/store-page-l10n.md` (#740), needing owner approval and proofreading. AI disclosure on Steam: the AI-assisted translations only (owner, `docs/launch/owner-decisions.md`). Status: partial.

### 9. Release gates (owner)
| # | Item | Who | Status |
|---|---|---|---|
| 9.1 | Playtest-ready build passes the fresh-clone script check from `CLAUDE.md` (no `class_name` references) | agent | automated: `release.yml` deletes the class cache and fails the release before export on any `SCRIPT ERROR`/`Failed to load script` boot output (#1113); first tag run will confirm |
| 9.2 | Final build uploaded, Valve review passed | owner | todo |
| 9.3 | Set price ($9.99), release date, press "Release" | owner | todo |
| 9.4 | Post-launch: monitor the in-game Feedback button (#262) and Steam discussions | owner | todo |

## Top owner actions, in order
1. Decide publisher entity, then create the Steamworks account and finish tax/bank forms (1.1, 1.2).
2. Pay the $100 app fee (1.3) and send the AppID/depot IDs.
3. Submit the store page for review (2.7) so the Coming Soon page is live by mid-December 2026, and register the Steam Playtest by about Dec 28 2026 (`docs/launch/owner-decisions.md`).
4. Finish store art (page background, icons; budget with Austin, #685), run the trademark clearance search (4.4) and lock the name. Remote Play Together is off at launch (6.2).
5. Edit the trailer from the shot list by May 3 2027 (2.4), and test Steam overlay compatibility (6.4).
6. Create the builder account and add secrets (5.4, 5.5); later Apple membership for notarization (5.8).

## Needs owner confirmation
- **Publisher entity.** `docs/launch/owner-decisions.md` describes the studio as SQL Monkey Studios (the owner and Austin, no LLC) but also says the Steamworks signup entity is reopened with Austin (#685); the table above still lists an LLC as an option. Confirm with Austin before the Nov 2026 signup.

## Out of scope
Nintendo Switch is #268, after Steam. Keep the input layer seat-based and avoid platform-specific code outside the seat and export layers.
