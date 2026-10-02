# Steam release readiness (#258)

Ordered checklist to ship Pickfight on Steam. Itch stays the private-friends channel.

**Legend.** Who: `owner` = needs the owner's identity, money or a decision; `agent` = an agent can do it in the repo. Status is read from the repo as of 2026-10-01: `done`, `todo`, `partial`.

**Verification caveat.** This was written without web access. Every external number (fees, waiting periods, image sizes) is from memory and marked **verify**; check it against the Steamworks docs (partner.steamgames.com/doc) before spending money or producing art.

## Owner decisions already made (from #258 comments)

| Decision | Value |
|---|---|
| Price | $4.99 |
| Name | "Pickfight" (one word); open to change. 2026-10-01 search found no Steam title named Pickfight or Pick Fight; nearest is "Pickup n' Fight" on itch (free, small). Re-check at name lock. |
| Language | English only at launch; keep user-facing strings in one place for later translation (#258 grill) |
| Playing without a phone | Gamepad (right stick = arm, relative vector) plus the host-PC mouse seat; no shared keyboard |
| Online | Keep Fly relay and room codes for itch; Steam builds add Steam lobbies and friend invites over the same relay (#298) |
| macOS signing | At Steam launch; friends use right-click, Open until then |
| Achievements | Low priority |

## Still-open owner decisions (placeholders)

| Item | Placeholder | Who |
|---|---|---|
| Release date | Decided 2026-10-01: store page public by about December 2026; a demo in **Steam Next Fest, Feb 22 - Mar 1 2027 (registration by Jan 10 2027)**; Early Access launch about March 2027. Demo is a slice: about 6 stages, 5 weapons, Classic plus one mode, 8 players. Early Access bar: everything ticketed as of October 2026. Steam wants the store page public ahead of release (**verify**: about 2 weeks minimum "Coming soon") and a wait after paperwork/fee (**verify**: about 30 days). Work backwards from these. | owner |
| Launch price per region | Decided 2026-10-01: **$7.99 USD** in Early Access, rising to **$9.99** at 1.0 (only the host buys; phones join free), 10-15% launch discount; Steam suggests regional prices (**verify**); launch discount (**verify** typical 10-20%) | owner |
| Final name / trademark check | "Pickfight" | owner |
| Early Access vs 1.0 | Decided 2026-10-01: **Early Access** | owner |
| Publisher entity (individual vs company) | Decided 2026-10-01: the owner as an individual, with a revenue split agreed privately with Austin; drives tax/bank forms and macOS/Windows signing identity | owner |

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
| 2.1 | Short description, long description, tags, feature list. Draft from `docs/FEATURES.md` | agent drafts, owner approves | name | todo |
| 2.2 | Capsule and library art (sizes below, all **verify**) | owner or commissioned artist; agent can lay out from `docs/art/` | name, logo | todo |
| 2.3 | At least 5 screenshots, 1920x1080 (**verify** minimum). Capture with the existing screenshot tools (`tools/`) and playtest footage | agent | none | partial (tools exist, no curated set) |
| 2.4 | Trailer: cut from playtest footage; the game has an F9 instant replay that saves ~10 s PNG sequences to `user://clips/` (#329, ADR-0020, 256x144, too small for a trailer). Record the trailer with a screen recorder (OBS) at 1080p or higher during playtests instead; use F9 clips only as a reference for moments worth re-capturing | owner (records) | playtest session | todo |
| 2.5 | System requirements, supported languages (English only), controller support flag (partial/full, see section 6) | agent | 6.x | todo |
| 2.6 | Legal links: privacy policy URL (the game talks to our relay and files feedback issues, so say so), support contact | owner | none | todo |
| 2.7 | Submit store page for Valve review, then set "Coming soon" public | owner | 2.1-2.6, 1.3 | todo |

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

Art in the repo today is placeholder (`icon.svg`, `docs/art/`); none of the above exists. Status: todo.

### 3. Ratings and compliance
| # | Item | Who | Blocked on | Status |
|---|---|---|---|---|
| 3.1 | Steam content survey (mature content questionnaire) and the IARC-based age rating questionnaire for the store (**verify** current form names). Cartoon violence only (ragdoll-ish melee, no blood, no gambling, no in-app purchases, no user-generated content shared beyond the feedback text box) | owner (agent supplies answers) | 1.1 | todo |
| 3.2 | Declare the online features and data the game sends (relay, feedback button #262) in the privacy policy | owner | 2.6 | todo |
| 3.3 | Tax/export compliance questions in the app wizard | owner | 1.2 | todo |

### 4. Legal and credits
| # | Item | Who | Blocked on | Status |
|---|---|---|---|---|
| 4.1 | Sound effects are Kenney packs, CC0 1.0, credited in `CREDITS.md`; CC0 allows commercial use with no attribution | agent | none | done |
| 4.2 | Re-audit every asset type before release: `assets/music/` (confirm licence and source is in `CREDITS.md`), the synthesised announcer lines, fonts (Godot default), any art. Anything not CC0/own must have a licence that allows commercial sale | agent | none | partial (SFX documented; confirm music and anything added since) |
| 4.3 | Godot's MIT licence text and third-party notices must ship with the game (Godot: Project, Export includes them via Help, Copyright info; add a `THIRD-PARTY.md` or in-game credits screen). If GodotSteam is added, include its MIT notice and the Steamworks SDK terms | agent | 5.x | todo |
| 4.4 | Trademark/name check, and EULA/terms if wanted | owner | name | todo |

### 5. Builds, depots and SteamPipe

Today: `.github/workflows/release.yml` runs on `v*` tags (or manual dispatch), installs Godot 4.6.2 plus templates, exports `Windows`, `macOS`, `Linux` presets (`export_presets.cfg`), zips them to `dist/`, uploads a workflow artifact and pushes to itch via butler (secret `BUTLER_API_KEY`, variable `ITCH_TARGET`; skipped if unset). Builds are unsigned. macOS preset has `codesign/codesign=1` but empty identity and notarization off; Windows signing is off. Status of that pipeline: `done`.

Add a Steam step:

| # | Item | Who | Blocked on | Status |
|---|---|---|---|---|
| 5.1 | Define three depots in Steamworks (Windows, macOS, Linux) and a `default` then `beta` branch plan | owner | 1.3 | todo |
| 5.2 | Add `steam/app_build.vdf` and `steam/depot_*.vdf` to the repo (AppID and depot IDs from GitHub variables, `contentroot` pointing at the unzipped per-OS build dirs). Export dirs, not zips: SteamPipe wants files | agent | 1.4 | todo |
| 5.3 | Add a `steam` job to `release.yml` after `export`, gated like the itch step (skip with a message when secrets/vars are unset, so forks and early tags still pass). Use a steamcmd action (for example `game-ci/steam-deploy`, **verify** maintenance and pin by SHA) or download steamcmd directly. Set the build's branch to `beta` and promote to `default` by hand in Steamworks | agent | 5.1, 5.2 | todo |
| 5.4 | Create a dedicated Steam builder account with only "Edit App Metadata"/"Publish App Changes" and "Upload builds" rights | owner | 1.1 | todo |
| 5.5 | Steam Guard on the builder account: CI cannot answer a prompt. Use the config.vdf / ssfn approach the chosen action documents (**verify**) | owner | 5.4 | todo |
| 5.6 | Export-preset tweaks for Steam: Windows `application/*` metadata (company, product, version), macOS bundle id and min OS, Linux x86_64 only | agent | none | todo |
| 5.7 | Windows code signing (optional, reduces SmartScreen friction; Steam does not require it). Owner decides on a certificate | owner | cost decision | todo |
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
| 6.1 | Add GodotSteam GDExtension; add `steam_appid.txt` to dev checkouts only (git-ignored); initialise Steam behind a single `SteamPlatform` wrapper so itch/non-Steam builds run when the client or library is absent. Preload by path, never by `class_name` (repo rule) | agent | 1.4 for real AppID; Spacewar 480 for dev | todo |
| 6.2 | Remote Play Together: the owner wants this tested first. Needs no new code beyond Steam running and the game launched through Steam; mark "Remote Play Together" in the store page features (**verify** the checkbox name). Test: host launches through Steam, invites a friend via the Steam overlay, friend plays with phone or gamepad stream. Known risk: the phone controller flow needs the LAN web server (ADR-0002); the remote friend has no LAN, so they use Remote Play input (gamepad/mouse) or the relay | owner tests, agent fixes issues | 1.3 (non-Steam shortcut or Spacewar can work for a first test, **verify**), 6.1 | todo |
| 6.3 | Steam lobbies and friend invites carrying the room code; game traffic stays on our relay, no Steam P2P | agent (agage-JG) | #298, #241, 6.1 | todo (tracked in #298, ready-for-agent) |
| 6.4 | Steam overlay compatibility check with the Compatibility renderer | owner tests | 6.1 | todo |
| 6.5 | Achievements: low priority. When it's time, `docs` list in #258: weapon mastery (9 weapons), silly feats, social. Define in Steamworks, wire through `SteamPlatform` | agent | 6.1 | todo (deferred) |
| 6.6 | Steam Cloud: not needed (settings are small, `user://audio.cfg`) | none | none | skip |

Existing online work this builds on: relay with room codes (#238, ADR-0019), host going online and remote seats (#239), snapshots (#251), PC client join by code (#241, agage-JG). Itch and non-Steam builds keep plain room codes.

### 7. Steam Deck
| # | Item | Who | Blocked on | Status |
|---|---|---|---|---|
| 7.1 | Gamepad seats: right stick drives the arm, no phone needed | agent | none | done (#261) |
| 7.2 | Confirm full-controller navigation of menus and lobby (no mouse or keyboard needed to start a match), on-screen glyphs, and a Deck-readable UI at 1280x800 | agent | none | todo |
| 7.3 | Linux build runs under Proton-free native Linux or Proton; test on a real Deck or `Steam Deck` desktop-mode simulation (**verify** Valve's Deck Verified checklist) | owner (hardware) | 5.3 | todo |
| 7.4 | The phone web controller still works on Deck as host if the Deck is on a LAN; document it | agent | none | todo |
| 7.5 | Deck Verified submission | owner | 7.2, 7.3, store page live | todo |

### 8. Localization
English only at launch (owner decision). Keep user-facing strings together so translation is possible later; no work now beyond not scattering new strings. Status: `done` for the decision, `todo` for an audit of where strings live (agent-doable, low priority).

### 9. Release gates (owner)
| # | Item | Who | Status |
|---|---|---|---|
| 9.1 | Playtest-ready build passes the fresh-clone script check from `CLAUDE.md` (no `class_name` references) | agent | todo (re-run on the release tag) |
| 9.2 | Final build uploaded, Valve review passed | owner | todo |
| 9.3 | Set price ($4.99 placeholder), release date, press "Release" | owner | todo |
| 9.4 | Post-launch: monitor the in-game Feedback button (#262) and Steam discussions | owner | todo |

## Top owner actions, in order
1. Decide publisher entity, then create the Steamworks account and finish tax/bank forms (1.1, 1.2).
2. Pay the $100 app fee (1.3) and send the AppID/depot IDs.
3. Test Remote Play Together first (6.2) with Spacewar or a non-Steam shortcut.
4. Produce store art and the trailer (2.2, 2.4); lock the name.
5. Set a release date working back from Steam's store-page and review lead times (verify them).
6. Create the builder account and add secrets (5.4, 5.5); later Apple membership for notarization (5.8).

## Out of scope
Nintendo Switch is #268, after Steam. Keep the input layer seat-based and avoid platform-specific code outside the seat and export layers.
