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
- Shield: a wide (50 px, was 36) heater-shaped plate with a matching polygon hitbox (#465); blocks hits landing on its face; a bash does little damage but big knockback (#275)
- Umbrella: held overhead it slows your fall, catches wind zones and turns hits on its canopy; a short poker otherwise (#269)
- Pogo stick: auto-bounce, charge-and-release launch, damage only from stomps (#271)
- Boomstick: fires bullets on a 3 s interval, heavy knockback (#55, #92, ADR-0014)
- Grappling hook (#150)
- Flail: chain physics, boosted climb (#150, #228)
- Boomerang (#150; #481: also thrown along the aim by an action press -- PC Space tap, gamepad bumper press or stick click -- instead of toggling release; the flick throw stays)
- Weapons spawn as on-stage pickups; body touch swaps (#14, ADR-0009); pickups scale with player count (#152); never spawn on a spot a living player is standing on, another free spot is used instead (#333)
- Plunger: sticks to players (drag them) and surfaces (hang and swing, never reels you in); a hard yank pops it free (#270)
- Per-stage weapon themes: pickup odds are weighted by the parts on the stage (wind zones favour the umbrella, tall layouts the grapple, bounce pads or flat floors the pogo); weighted not exclusive, every enabled weapon can still appear, pickaxe never; optional `weapon_weight_overrides` on a stage; seeded (#310)

## Stages and stage parts
- 43 rotating stages (#8, #17, #19, #51, #54, #143, #315, #373, #376, #377, #402, #403); #403 added two Capture the Flag halls, Bastion and Stronghold (closed, left-right symmetric, a base per team declared with `Base0` / `Base1` areas and `Flag0` / `Flag1` markers, weighted 4x for the mode and 0.3 elsewhere); #402 added three Soccer pitches, Pitch, Cage and Dunes (closed, left-right symmetric, a goal at each end declared with `Goal0` / `Goal1` areas and a `BallSpawn` marker, eight spawns), weighted 4x for Soccer and 0.3 in other modes; #377 added four King of the Hill stages, Summit and Mesa (fixed hill) and Relay and Roundabout (the hill hops between stage-defined spots every ~30 s, with a ~3 s warning ring on the next one), declared with `HillSpot` markers and `Stage.hill_moves`, weighted 4x for King of the Hill and 0.3 in other modes; a stage with no hill spots keeps the hill at the spawns' centre; #373 added three large Hot Potato chase-loop stages, Racetrack (oval of decks, ramps, bridge and bounce pads), Switchyard (two yards, a shuttle over the gap and a high bridge) and Orbit (two platforms circling a void), each with no dead ends and eight spawns; #315 added Footbridge (crumbling ledges, moving platform, spikes), Gantry (moving platform, saw, spikes) and Vent (fan, gust, spikes), and sprinkled spikes, a saw and a crumbling ledge into Gauntlet, Islands and Flatlands; shuffled bag rotation (#20, ADR-0011)
- Per-stage rotation weights by game mode (`mode_weights`): the three #373 stages are dealt about four times as often in Hot Potato and rare in every other mode (dealt into a bag 30% of the time); a weight under 1 is a probability of being in the bag (#373)
- #315 added Footbridge (crumbling ledges, moving platform, spikes), Gantry (moving platform, saw, spikes) and Vent (fan, gust, spikes), and sprinkled spikes, a saw and a crumbling ledge into Gauntlet, Islands and Flatlands; shuffled bag rotation (#20, ADR-0011); #376 added four no-frills competitive stages (flagged `competitive`, symmetrical, no hazards or moving parts): Final Destination (flat), Battlefield (3 platforms), Pocket (small) and Colosseum (large, 5+ players)
- Wide maps with 8 spawn points each (#137, #138)
- Large stages with a per-stage camera view, used at 5+ players (#144)
- Parts: lava/hazard zones, moving platforms, crumbling ledges (#18, #279, #280)
- Parts: bounce pad, wind zone, rotating platform (#52)
- Parts: fan (air column along its facing; can travel, spin or sweep; Carousel) and stage-wide gust (periodic, one direction, 1.5 s warning with tint, streaks and wind sound; Pillars) (#281)
- Parts: falling rocks, collapsing floor, breakable walls (#53)
- Parts: spikes and saw (travels a path) deal big damage plus knockback with a per-player hit cooldown (#282)
- Per-stage gradient sky and parallax silhouettes (#117); stage title card (#120)

## Match flow and scoring
- Endless round loop over the live roster (ADR-0004, ADR-0007)
- Matches: first to N rounds, host picks N; victory podium (#120); each phone taps Continue and the room returns to the lobby once every human has (bots excluded), after 30 s, or on a host keypress (#337)
- Teams mode: Red vs Blue, no friendly damage, team rings, auto-balance (#236, ADR-0018)
- Game modes (#352): the host phone's menu picks Classic, King of the Hill, Hot Potato or Sudden Death for the whole match, saved with the other host settings (`user://audio.cfg`). Combines with Free-for-all or Teams (the Format); Hot Potato is Free-for-all only (greyed out with Teams on, and switching Teams on drops it to Classic); Soccer (#402) is the mirror, Teams only (greyed out in Free-for-all, and switching Teams off drops it to Classic). King of the Hill in Teams: teammates hold the hill together, a mixed hill is contested and frozen, hold time banks per team. The Rise runs in Classic, is off in King of the Hill and Hot Potato, and in Sudden Death starts after half the grace period at 1.5x speed. Each mode bans modifiers: Sudden Death double damage, Hot Potato weapon roulette, King of the Hill meteor shower. The stage title card shows the mode name and a one-line rule; the how-to-play panel has one card per mode. All of it is one table, `GameModes.TABLE`
- Soccer mode (#402, Teams only): one physics ball on a closed pitch with a goal at each end (Red defends the left, Blue the right); players bat it with weapon heads and bodies. A ball in a goal scores for the other team, with a "GOAL!" banner and a 1.5 s pause, then the ball goes back to the centre and everyone to their own half. First team to 3 goals wins the round (the other team is eliminated, so the normal last-team-standing scoring applies); the score shows top centre. A knocked-out player respawns after about 1.5 s with spawn protection through the same respawn Stock uses (`Respawn.gd`), so nobody sits out (a player the host kicks while waiting stays out). Played only on the three pitches, even when the host switched them off: no other stage has goals. No rising lava; meteor shower banned. Bots chase the ball, get behind it and drive it at the enemy goal. Mode award "Top Scorer" (the goal is credited to the last player of the scoring team to touch the ball)
- Capture the Flag mode (#403, Teams only, greyed out in Free-for-all like Soccer): each team has a base with a flag on a symmetric hall (Red left, Blue right). Touching the enemy flag picks it up; the carrier keeps their weapon and can fight, but any hit (or a KO) makes them drop it. A dropped flag lies where it fell and returns home after 10 s, or at once when a player of its own team touches it; the player who dropped it cannot re-grab it for 1.5 s. Bringing the enemy flag into your own base is a capture (the flag goes home); first team to 2 captures wins the round (the other team is eliminated, so the normal last-team-standing scoring applies); the score shows top centre. KOs respawn after about 1.5 s with spawn protection through the shared `Respawn.gd`. Played only on Bastion and Stronghold, even when the host switched them off: no other stage has bases. No rising lava; meteor shower banned. Bots: the lowest-slot bot on a team defends its flag, the others attack the enemy flag, everyone chases an enemy carrier, a carrier runs home, a dropped flag is run down. Mode award "Flag Runner" (most captures). Announcer lines "Capture the Flag!", "Flag taken!" and "Captured!" use stand-in UI sounds until voice clips are recorded.
- Round modifiers, about 1 round in 3 (#50, ADR-0015, #147): low gravity, heavy weapons, big heads, fast lava, slippery floor, tiny weapons, weapon roulette, meteor shower, bouncy, double damage, gale (#312: a stage-wide gust over the whole view, one direction per round, calm then 1.5 s warning then gust; pushes players, the umbrella catches it)
- Stock mode (#354): 1-10 lives per round (default 3) and a 2 / 5 / 8 / 15 min or no time limit (default 8), both set on the host phone and remembered. A lost life respawns after about 1.5 s at the spawn farthest from the others, with spawn protection, the pickaxe and zero damage; out of lives means out, with the KO ghost. No rising lava. Lives show as pips under the name tag and as "♥ N" on the phone. Timeout: most lives wins (a team's total in Teams); a tie plays a one-hit overtime among the tied. In Teams an eliminated player can "Steal a life" from the team-mate with most (2+ lives). Countdown top centre, pulsing in the last 10 s. One stage per match (#375): the host phone shows a Smash-style stage grid under the Stock controls (every enabled stage, competitive-flagged ones first, plus a Random tile), the pick holds for every round and is remembered in `user://audio.cfg`; Random draws an enabled stage once per match. Stock rolls no round modifiers (`no_modifiers` in `GameModes.TABLE`). Classic and the other modes keep the rotation and the per-stage on/off list
- Kill feed, KO credit, match awards (#148), including Longest airtime, the longest stretch with no body contact (#337); a hazard (spikes, saws, lava) or ring-out death credits whoever last hit the victim within 3 s of game time, else a self-KO; teammates never earn it (#311)
- The match-winning KO plays about 1 s of slow motion with the camera punched in on the hit and a brief flash, then goes to the victory panel; no zoom with screen shake off, no flash with reduce flashes on (#328)
- Night stages (#332): about 1 round in 5 plays its stage as a night variant, applied by data (`Stage.night`, rolled per round by `RoundManager.night_chance`, from its own RNG; off with the modifier-roll seam, `forced_night` overrides). Darker Night palette with stars, lamps over the spawns, and a soft glow on players, weapon heads, pickups and hazards. Visual only. Lighting is `CanvasModulate` plus shadowless `PointLight2D` (works with the Compatibility renderer); lamps hold steady with Reduce flashes on
- Victory screen stats (#325): a per-player table under the awards (KOs, damage dealt and taken, self-KOs, weapon pickups, favourite weapon) and a "Magpie" award for the most weapon pickups
- Mode awards (#355): the victory screen adds one award for the mode played, only in that mode: "Longest Hold" (most seconds alone on the hill, King of the Hill; individual holds only, so none in Teams), "Hot Hands" (most tags passed on, Hot Potato), "Survivor" (most lives left, summed over the match's rounds, Stock), "Top Scorer" (most goals, Soccer). Classic and Sudden Death add none. Each mode node hands its round numbers to `MatchStats` through `report_stats()` when the round ends
- Scoreboard shown at round end (#5)
- KO'd players drive a floaty translucent ghost from their phone that shows only while they touch their controls (fades ~1.5 s after); it cannot hurt anyone, only weakly nudges pickups, never appears for bots and is cleared at round end (#324)
- A reconnecting phone keeps its seat and score (#164); a new phone or bot taking a freed slot starts at 0 (#161); an Online late joiner starts at 0 and waits for the next round (#446); roster survives a mid-round disconnect (#12, ADR-0007)

## Players, cosmetics and identity
- Up to 8 players (#36, #138)
- Player picks own nickname on first join; rename in lobby (#139, #121, #194)
- Always-on name tags (#151)
- Six eye styles (round, sleepy, angry, wide, dot, visor) picked in the same phone picker as hats and colour; pupils still track the weapon; kept per seat through reconnects (#297)
- Hats (crown, top hat, cap, beanie, viking, party, halo, propeller) and colour picker on the phone (#151)
- In-game cosmetics picker for players without a phone (#441), one shared model (`CosmeticsPicker.gd`) with the phone's catalog and rules, lobby only (lobby and countdown). Local: a gamepad seat's lobby card carries a compact picker (preview plus hat / colour / eyes slots; D-pad up/down picks the slot, LB/RB cycle it, A still readies), shown only while a gamepad holds the seat, so a phone-only lobby shows none; a pad's pick lasts the session (kept through a replug, #442). Online: the PC client's lobby shows a mouse panel beside the player list (big preview, clickable hat, colour and eyes grids) until the player readies; the pick is saved in the client's own settings and sent on join. A colour another player wears is refused first come first served on every input: a pad skips it, the panel greys it out, a phone is refused. Teams mode keeps its team tint. The host's own seat in an Online lobby gets the same panel once #435 lands (`OnlineCosmeticsPanel.bind_server`)
- Squares have eyes that track the weapon head, blink and squint; arm drawn in front/behind body (#254, #91)
- One cohesive colour palette (#255); the eight default slot colours are checked to stay distinguishable under protanopia, deuteranopia and tritanopia (#330)

## Controllers and input
- Phone browser controller page over LAN, served by the host (#1, ADR-0002)
- Multi-touch, drag smoothing against Wi-Fi jitter (#29, #113)
- Phone buzz feedback, e.g. on round win (#34, ADR-0013)
- Phone damage bar: a thin strip showing how close you are to KO, turning red near the end; phone only, resets each round (#331)
- Laptop browser as a controller with pointer-lock mouse (#244)
- Explicit release input (#463, ADR-0022): grapple retract, plunger let-go, flail release timing and gridlock head-unsticking need a release, which a mouse never sends. On PC (Online client and the host PC seat) a tap of Space toggles released on and off, as a finger lifting and touching again; on a gamepad holding LB or RB releases while held and clicking either stick (L3/R3) toggles it. With the boomerang held, that same press throws it instead (#481). Phones are unchanged (finger lift). Starts not released and resets each round and respawn
- Gamepad seats: right stick drives the arm, no phone needed (#261); parity with phone seats (#442): A on the podium continues and counts toward "every human continued" (an all-pad room returns to the lobby), a KO'd pad's right stick drives its ghost, buzzes play as controller rumble, a one-time "Right stick swings, a bumper lets go" tip shows on a new pad's lobby card until it swings, an unplugged pad that replugs (even on another port) reclaims its seat and cosmetics (keyed by device GUID, slot index as fallback), and pads get no damage bar
- Gamepad host menus for Steam Deck (#368): Y in the lobby opens the host controls (Match kind, Mode, First to, Start, Join someone else's game; Play on this PC and its P key are gone since #435), View opens the Settings panel (or focuses the first-launch notice), D-pad moves, A presses, B closes; A and B stop joining and readying while a menu is open. Captions drop the "(Enter)" keyboard glyph once a gamepad is the active input. The audit and open gaps are in `docs/steam-deck-readiness.md`
- Gamepad host menus for Steam Deck (#368): Y in the lobby opens the host controls (Go online, Play on this PC, Mode, First to, Start, Join someone else's game), View opens the Settings panel, D-pad moves, A presses, B closes; A and B stop joining and readying while a menu is open. Captions drop the "(Enter)" keyboard glyph once a gamepad is the active input. The audit and open gaps are in `docs/steam-deck-readiness.md`
- Host phone controls: pause, end, kick, settings (#149, #216, #231)
- Host gamepad pause (#430): Start on the host's controller (joypad 0: the Steam Deck's built-in controls, or a PC host's first pad) pauses and resumes a match like the host phone's Pause; any other pad's Start does nothing mid-round and still joins and readies in the lobby
- Phone reconnect, message validation, refused-phone state (#164, #193, #194)

## Bots and solo practice
- Bots via `--bots=N` flag and Solo practice button (#152)
- Bots read stage hazards; bots yield to phones (#176, #193)
- Bots steer clear of spikes and saws (a moving saw by its current position) and move upwind of a stage gust warning once a gust part exists (#313)
- Bots hunt deliberately: they pick the rival cheapest to reach (a rival high up on a ledge is the last chosen) and stick with it, never a teammate, and a bot hooked on a ledge by its own pickaxe sweeps the head off it instead of hanging there (#302)
- Bots no longer stall rounds (#409): a bot held at an edge for 3 s tries a wider gap (up to 150 px) so two bots either side of a pit meet; it drops a pickup it has chased for 10 s without reaching (for 90 s) and goes back to fighting; and King of the Hill's default hill (no stage hill spot) sits on the floor under the spawns' centre, not in mid-air where nobody on the ground is inside it; Reactor now has its own hill spots out on each wing of the floor, clear of the molten core (#416), so its King of the Hill rounds end by hold time
- Bots get past what used to stall them (#409): after 3 s held at an edge they also step onto moving ground (see-saws, turning sails, a crane) and keep riding it, and after 12 s waiting in one place they leap over the edge and walk through spikes and saws; one stuck against a breakable wall (Reactor's shields) backs off and chops it down; a duel where neither can reach the other (one on a ledge) is dropped for 12 s so the bot goes to its rival; and holding off a rival at an edge gives up after 6 s. 4-bot King of the Hill and Stock rounds now end on Carousel, Springboard, Gantry, Mill, Updraft, Reactor, Vent and Summit
- Bots keep their own swing from throwing them over a rival and off the stage: no closing on a rival with a drop right past it, a gentler chop near an edge, a brake when carried towards one, and no swinging while thrown into the air; and they press harder as opponents dwindle (shorter hesitation, closer fighting, further engagement, a faster vault) up to full pace with one rival left (#302)
- Bots play each mode's objective: in King of the Hill they head into the hill and fight whoever holds it; in Hot Potato the bot that is "it" chases a rival and every other bot keeps away from "it"; in Soccer they get behind the ball and drive it at the enemy goal (#402); in Capture the Flag they defend, attack, escort and chase the carrier (#403); Sudden Death (and any mode without an objective) plays as Classic (#353)

## Lobby and onboarding
- Lobby with ready-up (#120)
- Title screen (#435, ADR-0021): at launch the host picks Couch, Online or Solo (click, the keys C / O / S, or D-pad and A on a gamepad; A there never seats the pad). A match is Couch (Local: phones by QR and URL, the browser controller page, gamepads; the relay is never contacted, a remote seat is refused, the host's mouse takes no seat) or Online (the host goes online and shows the room code, still hidden by streamer mode; the host's mouse seat is claimed and ready by itself; no QR or LAN URL, phones are refused with "online match: join from the game on a computer"; gamepads still join), never mixed. Solo is an Online match with the room closed (no code, no joins) and three bots seated. The lobby's "Match (O): Couch / Online / Solo" control (key O, the gamepad host menu's first entry) switches Couch and Online in the lobby; the switch drops the other kind's seats with a short notice ("Online match: 2 phone players left the lobby"). It replaces Go online and Play on this PC, and the host phone's Go online button hides in a Couch match
- Join URL plus in-game generated QR code (#29, #214, #230), shown on the lobby, countdown and victory screens only: nothing join-related is on screen during a round (#430)
- Lobby mode cards sit in a fixed 2 x 4 grid under the QR, so the QR stays 340 px with eight players and up to eight modes (a ninth card opens a third column rather than shrinking the QR); the host controls are tighter, with Start beside First to (#425)
- Joining someone else's online game from the host screen: "Join someone else's game (J)" heads the lobby's host controls and opens the PC client's room-code entry. It works while the only seat taken is the host's own (the Online host-PC seat) or bots, and in an Online match (the open room is closed on the way out); once anyone else is seated it is off, with the caption "Off while players are in your lobby". The online room code now sits beside the match control (formerly Go online) at 26 px instead of under the URL at 64 px, so the whole lobby fits 1600 x 900, 1080p and the Steam Deck with online on, the PC seat on and eight players seated (#425 playtest)
- How-to-play explainer with animated demos (#149, #219)
- First-join tip on the phone: looping drag-to-swing animation, shown once per device (#291)
- Live lobby sandbox: seated players move, swing and fight on a stage under the lobby; nothing scores, KOs respawn, the match starts clean (#291)

## Settings
- Music and settings menu: volume, fullscreen (#118, ADR-0017, #167)
- Window size option for windowed mode (#294)
- Stage on/off list: the rotation skips switched-off stages (#294)
- Pickup weapon on/off list: switched-off weapons never spawn as pickups (#294)
- Rules section in the host settings panel (#378): pick a mode (Classic, King of the Hill, Sudden Death, Hot Potato, Stock, Soccer) and untick the round modifiers that may not roll in it; saved per mode in `user://audio.cfg`, default all on. A mode's own bans (and all of Stock's) show locked off and cannot be re-enabled; with every modifier off, none rolls. Host screen only, not mirrored on the phone
- Comfort options in the Settings panel's "More options": screen shake on/off (#256), reduce flashes (elimination burst, bounce pad, breaking wall), and name tag size 1x / 1.5x / 2x; all persist (#317)
- "Share anonymous match stats" toggle, the last row of "More options", on by default and persisted; no first-launch notice or prompt (#372, #461)
- Text on the host screen is never below 16 design px (12.8 px on a 1280x800 Steam Deck screen), checked by a scenario; the lobby mode cards went from 12 to 16 (#368)
- Streamer mode: a "Hide room code" toggle in the Settings panel's "More options" (off by default, persists) replaces the shared screen's online room code, join URL and join QR with "Code hidden: see host phone"; the host phone's menu still shows the code (#369)
- The last enabled stage and weapon cannot be switched off; choices persist in `user://audio.cfg` (#294)
- All text is translatable (English only for now): host-screen strings go through `tr()` and `translations/strings.csv`, the phone page through its `STRINGS` table (#367)

## Audio
- Sound effects for combat, round and UI (#75, ADR-0016) and stage parts (#76); mix tuned (#93)
- Distinct, fitting hit sounds for every weapon; no placeholder copies (#288)
- Music: lobby and fight tracks (#118); six more CC0 fight tracks join the rotation, eight in all, each loop-trimmed so it repeats without a gap (#289)
- Narrator/announcer, one consistent voice (#152, #211)
- Subtle voice grunts: each of the eight player slots has its own voice, a short grunt when hit (at most one per half second) and a longer one when knocked out; mixed about 15 dB under weapon sounds, on the SFX bus so Mute and the SFX slider govern them; placeholder synthesised sounds (#290)
- Mode callouts (#370): the announcer says "King of the Hill!", "Hot Potato!", "Sudden Death!" and "Stock!" and "Soccer!" as those rounds start, "Goal!" on every Soccer goal, "Hill taken!" when a different player or team takes the hill, "Last life!" in Stock at one life, "Stolen!" on a stolen life and "Overtime!" at a Stock tie.

## Visual look and juice
- Landing dust, head motion trails, clash sparks (#116, #196)
- Death burst, hit feedback (#33, #168)
- Flat parallax stage dressing: clouds or stars plus far and mid silhouettes, mood-coloured, per-stage layouts, no collision (#257, `scripts/StageBackground.gd`)

- PICKFIGHT logo (flat letters in the player palette, the first I a pickaxe) in `art/logo/`, with 1024 px and Steam capsule PNG exports; shown on the lobby/title screen and the victory screen, whose podium blocks are flat ink-outlined panels (#359, `tools/gen_logo_art.py`, `tools/export_logo_pngs.gd`)
- Character polish (#360, on top of the #254 eyes/outline and #256 squash): every weapon head gets a dark ink outline that follows the stage ink, a sudden upward launch stretches the body tall and thin (within the 15% squash cap), and a hit flashes the body white for 0.1 s (off with Reduce flashes). Visual only; evidence in `test-results/character-polish/` (`tools/capture_character_polish.gd`)

## Online
- Room-code relay server (#238, ADR-0019)
- Host goes online; remote seats send relative input (#239). Online only in an Online match since #435: a Couch match refuses remote seats (the PC client reads "That host is playing a Couch match, not Online.") and a Solo room is closed ("That room is closed.")
- PC client takes a gamepad: the first pad's right stick drives the arm (same deadzone as a host gamepad seat), and the mouse takes over again once the stick centres (#435)
- Online edges (#446): when the host's room closes (it quits or goes offline) every remote client lands on the join screen reading "Host left.", with no host migration. A remote seat that joins mid-match watches until the next round starts, then plays, taking a freed slot at 0 points exactly as a late phone does (#161). The host pings each remote seat about once a second over the seat channel; the round trip shows beside the player in the lobby (host screen and PC client) and on the scoreboard, in a warning colour above 150 ms, and a slow ping never kicks anyone
- Online host controls on the PC (#458): with Go online on, the host needs no phone. Every lobby row but the host PC's own seat has a Kick button, and mid-match the Esc menu (the Settings panel; Esc on the captured mouse frees it and opens the menu in one press) leads with Pause/Resume, End match and the player list, each row with a Kick. A kicked remote client lands on its join screen reading "The host removed you from the match." and is refused if it joins again; the host PC can kick any seat but its own, even the earliest-joined remote seat. These send the same commands as the host phone's menu, so pause, end and kick behave identically
- Host streams world snapshots to remote seats (#251)
- Host survives a relay blip without losing the room (#249)
- Dropped remote seat held for 30 s (#459): a remote player whose connection drops mid-match goes limp, keeps their roster entry for 30 s of game time (through round boundaries; a pause does not count down) and rejoins the same seat with the same score, name and looks. The PC client retries on its own every 1.5 s for that window. After 30 s the seat frees, even mid-round (the body leaves the round as a kicked one does, with no ban), and a later rejoin is a fresh seat at 0 points. Nothing is held in the lobby, as for phones (ADR-0007)
- Online in the demo build, demo and full kept apart (#447): the demo build offers Online over room codes. A remote seat's hello says which build it is, and the host refuses the other one: a demo player joining a full game's room lands on the join screen reading "Get the full game to join this room", and a full-game player joining a demo room reads "This room is running the demo. Join it from the demo." Demo joins demo and full joins full as before
- Remote client shows the full match (#436): scoreboard, round result line, mode HUD line (King of the Hill holds, flag and goal scores, potato fuse, stock lives and clock), announcer banner, countdown, match podium with a Leave button. The host streams a small `hud` text frame (`scripts/RemoteHud.gd`, only on change, at most ~7 Hz) beside the snapshots. A removed body, projectile or pickup, or a new round or stage, goes out as a full snapshot at once so no ghost outlives one snapshot (#429)

## Builds and distribution
- Exported macOS .app and Windows .exe (#119, `tools/export.sh`)
- Release workflow builds Windows, macOS, Linux and pushes to itch.io (`.github/workflows/release.yml`)
- Steam Next Fest demo build: the "demo" feature tag (Demo macOS/Windows/Linux export presets, `tools/export.sh demo`) or `--demo-build` limits the game to 6 stages, the pickaxe plus 4 pickup weapons and Classic plus King of the Hill, hides the rest from Settings, and ends each match on a "Wishlist the full game on Steam" card with the logo (#361, `scripts/DemoBuild.gd`)
- Relay deployable on Fly.io (`relay/fly.toml`, `relay/Dockerfile`)
- In-game Feedback button in the host Settings panel: sends text (plus build, OS, stage) to the relay, which files a `needs-triage` + `feedback` GitHub issue using the relay-only `GITHUB_FEEDBACK_TOKEN`; 5 per IP per hour, 2000 chars, offline (503) until the token is set (#262)
- Anonymous match telemetry (#372): at match end the host sends one record (per-weapon damage, hits and KOs by real players, mode, stages, format, length, winner weapon; no names, colours, devices or IDs) to the relay, which appends it to a JSONL file with the time rounded to the hour and never stores or logs the IP; 30 per IP per hour, 8 KB cap. Never sent from scenario or `--bots` runs or with the toggle off (#461: "Share anonymous match stats", last in Settings > More options, on by default). `tools/summarise_stats.py` prints damage per hit, win rate by weapon, mode popularity and average match length. Needs a Fly volume (`PICKFIGHT_STATS_PATH`, see `relay/fly.toml`) to persist

## Dev tooling
- Headless scenario runner and suite (`tools/scenario_runner.gd`, `tools/list_scenarios.sh`) with shared-state resets and parallel-safe ports (#73, #179)
- CI runs the scenario suite on every PR, `--fixed-fps 60` (#186, #195)
- Screenshot capture tools for stages and damage numbers
- Instant replay: F9 saves the last ~10 s (12 fps, 256x144, ~13 MB ring) as a PNG sequence in `user://clips/` with a toast showing the path (#329, ADR-0020)
- Local balance log: at each match end the host appends one JSON line to `user://balance_stats.jsonl` (Godot's user data folder) with damage and hits per weapon by real players; bots and the lobby sandbox excluded, never networked (#316)

## In flight / planned
Not shipped; do not treat as existing.
- #242 Deploy relay, ship PC builds (tkneeland)
- #268 Switch release (tkneeland)
- #298 Steam lobbies and invites over relay (agage-JG)
