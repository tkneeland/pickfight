# Pickfight: what already exists

Shipped-feature inventory (evidence: closed issue numbers). Read it before proposing work; frame questions as extensions of what is here.

**Maintenance rule: Every PR that adds, removes or changes a player-facing feature updates this file in the same PR.**

## Core movement and combat
- Weapon is the arm: force-driven jointed weapon, relative-vector drag aim (#1, #2, ADR-0003/0005/0006)
- Damage, blocking, knockback, ring-out deaths (#2)
- Weapon heads bite into surfaces for traction; weapons and traversal made more responsive (#110, #136, #180, #181)
- Weapon turn guard and anti-tunnelling vs terrain and other heads (#23, #82, #103, #109)
- Trapped weapon head phases home after a delay (#115)
- Spawn protection: about 1 s invulnerable, blinking (#114)
- Round winner keeps their weapon; everyone else respawns with the pickaxe (#6, ADR-0005)
- Rising lava kill zone ends stalling (#22, #45, ADR-0012)
- Hitmarkers and debug damage numbers (#33)
- Smooth physics interpolation, game-time clock, seeded match RNG (#108, #182, #187)

## Weapons
- Pickaxe: everyone's starting weapon (#2, #135, #181)
- Staff, sword, dagger (#13)
- Axe: heavy, sluggish, double-sided head, 90 damage (#49, #90)
- Spear: long reach, weak up close (#272)
- Boomstick: fires bullets on a 3 s interval, heavy knockback (#55, #92, ADR-0014)
- Grappling hook (#150)
- Flail: chain physics, boosted climb (#150, #228)
- Boomerang (#150)
- Weapons spawn as on-stage pickups; body touch swaps (#14, ADR-0009); pickups scale with player count (#152)

## Stages and stage parts
- 24 rotating stages (#8, #17, #19, #51, #54, #143); shuffled bag rotation (#20, ADR-0011)
- Wide maps with 8 spawn points each (#137, #138)
- Large stages with a per-stage camera view, used at 5+ players (#144)
- Parts: lava/hazard zones, moving platforms, crumbling ledges (#18, #279, #280)
- Parts: bounce pad, wind zone, rotating platform (#52)
- Parts: falling rocks, collapsing floor, breakable walls (#53)
- Per-stage gradient sky and parallax silhouettes (#117); stage title card (#120)

## Match flow and scoring
- Endless round loop over the live roster (ADR-0004, ADR-0007)
- Matches: first to N rounds, host picks N; victory podium (#120)
- Teams mode: Red vs Blue, no friendly damage, team rings, auto-balance (#236, ADR-0018)
- Round modifiers, about 1 round in 3 (#50, ADR-0015, #147): low gravity, heavy weapons, big heads, fast lava, slippery floor, tiny weapons, weapon roulette, meteor shower, bouncy, double damage
- Kill feed, KO credit, match awards (#148)
- Scoreboard shown at round end (#5)
- Mid-match joiner inherits freed slot's score (#161); roster survives a mid-round disconnect (#12, ADR-0007)

## Players, cosmetics and identity
- Up to 8 players (#36, #138)
- Player picks own nickname on first join; rename in lobby (#139, #121, #194)
- Always-on name tags (#151)
- Hats (crown, top hat, cap, beanie, viking, party, halo, propeller) and colour picker on the phone (#151)
- Squares have eyes that track the weapon head, blink and squint; arm drawn in front/behind body (#254, #91)
- One cohesive colour palette (#255)

## Controllers and input
- Phone browser controller page over LAN, served by the host (#1, ADR-0002)
- Multi-touch, drag smoothing against Wi-Fi jitter (#29, #113)
- Phone buzz feedback, e.g. on round win (#34, ADR-0013)
- Laptop browser as a controller with pointer-lock mouse (#244)
- Gamepad seats: right stick drives the arm, no phone needed (#261)
- Host phone controls: pause, end, kick, settings (#149, #216, #231)
- Phone reconnect, message validation, refused-phone state (#164, #193, #194)

## Bots and solo practice
- Bots via `--bots=N` flag and Solo practice button (#152)
- Bots read stage hazards; bots yield to phones (#176, #193)

## Lobby and onboarding
- Lobby with ready-up (#120)
- Join URL plus in-game generated QR code (#29, #214, #230)
- How-to-play explainer with animated demos (#149, #219)

## Settings
- Music and settings menu: volume, fullscreen (#118, ADR-0017, #167)
- Window size option for windowed mode (#294)
- Stage on/off list: the rotation skips switched-off stages (#294)
- Pickup weapon on/off list: switched-off weapons never spawn as pickups (#294)
- The last enabled stage and weapon cannot be switched off; choices persist in `user://audio.cfg` (#294)

## Audio
- Sound effects for combat, round and UI (#75, ADR-0016) and stage parts (#76); mix tuned (#93)
- Music: lobby and fight tracks (#118)
- Narrator/announcer, one consistent voice (#152, #211)

## Visual look and juice
- Landing dust, head motion trails, clash sparks (#116, #196)
- Death burst, hit feedback (#33, #168)

## Online
- Room-code relay server (#238, ADR-0019)
- Host goes online; remote seats send relative input (#239)
- Host streams world snapshots to remote seats (#251)
- Host survives a relay blip without losing the room (#249)

## Builds and distribution
- Exported macOS .app and Windows .exe (#119, `tools/export.sh`)
- Release workflow builds Windows, macOS, Linux and pushes to itch.io (`.github/workflows/release.yml`)
- Relay deployable on Fly.io (`relay/fly.toml`, `relay/Dockerfile`)

## Dev tooling
- Headless scenario runner and suite (`tools/scenario_runner.gd`, `tools/list_scenarios.sh`) with shared-state resets and parallel-safe ports (#73, #179)
- CI runs the scenario suite on every PR, `--fixed-fps 60` (#186, #195)
- Screenshot capture tools for stages and damage numbers

## In flight / planned
Not shipped; do not treat as existing. Mode scripts for Sudden Death, King of the Hill and Hot Potato exist in `scripts/` but are not wired in.
- #297 Cosmetics: eye styles (tkneeland)
- #291 Onboarding: first-join tip on phone, live lobby sandbox (tkneeland)
- #288 Real per-weapon hit sounds (tkneeland)
- #282 Hazard: spikes and saws (tkneeland); #281 wind / fans (tkneeland)
- #271 Pogo stick, #270 Plunger, #269 Umbrella (tkneeland)
- #275 Shield, #274 Magnet, #273 Fishing rod (agage-JG)
- #278 Tag / hot potato, #277 Sudden death, #276 King of the hill (agage-JG)
- #290 Per-player voice grunts, #289 More music tracks (agage-JG)
- #256 Juice pass (agage-JG); #257 Richer stage dressing (tkneeland)
- #262 In-game send-feedback button (tkneeland); #263 Content roadmap (tkneeland)
- #240 Snapshot encode/decode, #241 PC client: join by code, mouse arm (agage-JG); #242 Deploy relay, ship PC builds (tkneeland); #212 PC/online idea (tkneeland, parked)
- #258 Steam readiness plan, #268 Switch release (tkneeland); #296, #298 Steam lobbies and invites over relay (agage-JG)
