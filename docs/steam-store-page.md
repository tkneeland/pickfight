# Steam store page copy (draft)

Draft for owner approval (#362). Store page target: public by about December 2026; demo in Steam Next Fest Feb 22 - Mar 1 2027; Early Access about March 2027 (see `docs/steam-readiness.md`). Source of truth for features is `docs/FEATURES.md`.

Honesty rules for this copy:

- Mention only shipped features, plus the four modes (King of the Hill, Hot Potato, Sudden Death, Stock) that are landing now. Re-check them against `docs/FEATURES.md` before the page goes public; cut any mode that has not shipped.
- Remote Play Together is **to be tested** (steam-readiness 6.2). It stays out of the copy and the checkbox until the test passes. Steam friend invites are **planned**, not shipped (#298); online play today is a room code.
- Art is placeholder today; the target look is polished flat shapes (CONTEXT.md Design intent). Do not capture final screenshots until that pass is done.
- Verify the $7.99 price and dates against `docs/steam-readiness.md` before publishing.

## 1. Short description

Limit is about 300 characters. This is 261.

```
Same-room party platform fighter. Your weapon is your arm: swing a pickaxe, hook onto walls and knock your friends off the stage. Up to 8 players. In a room, each plays on their own phone or a gamepad: scan a QR code, no app to install. Online, each plays on their own PC. Only the host buys the game.
```

## 2. Long description (Steam BBCode)

```
[h2]Your weapon is your arm.[/h2]
Pickfight is a same-room party platform fighter. Think Stick Fight's scrappy physics combat crossed with Getting Over It's pole-and-hammer movement. You drag your thumb, your arm swings, and you haul yourself around the stage with it. You fight with the same arm.

[h2]Only one person buys the game[/h2]
The host runs Pickfight on a PC or Mac and puts it on the big screen. Everyone else scans a QR code and plays from their own phone browser. No app install, no account, no extra controllers. Laptop browsers and gamepads work too. If your friends are not in the room, online play works through a room code, but online players need their own copy of the game and play with a mouse or gamepad. Phones work in the room only.

[h2]Up to 8 players[/h2]
Bring the whole couch. Eight players share one screen, with bots to fill empty seats or to practice solo.

[h2]Easy to learn, hard to master[/h2]
[list]
[*] Drag to swing. A first-join tip and a live lobby sandbox let new players practice before the match starts.
[*] Weapons bite into walls and floors, so your swing is also your climb.
[*] Block, knock people back, and ring them out.
[/list]

[h2]Weapons[/h2]
Everyone starts with the pickaxe. Everything else is picked up on the stage:
[list]
[*] Staff, sword, dagger, axe, spear
[*] Umbrella, pogo stick
[*] Boomstick, grappling hook, flail, boomerang
[/list]
Each weapon moves differently, not just hits differently. The stage decides which weapons turn up most often.

[h2]27 stages that fight back[/h2]
Moving and rotating platforms, crumbling ledges, bounce pads, wind zones and fans, falling rocks, breakable walls, spikes, saws, and rising lava that ends stalling. Every stage supports 8 players, and about one round in five plays at night.

[h2]Modes and mayhem[/h2]
[list]
[*] Classic: last one standing wins the round. First to N rounds wins the match.
[*] Teams: Red vs Blue, no friendly fire.
[*] King of the Hill, Hot Potato, Sudden Death and Stock modes.
[*] Round modifiers: low gravity, heavy weapons, big heads, slippery floors, meteor showers, weapon roulette and more.
[*] Kill feed, match awards and a victory podium to settle arguments.
[/list]

[h2]Make it yours[/h2]
Pick a nickname, a colour, a hat and a pair of eyes. Fallen players come back as a floaty ghost and can still nudge things from their phone or gamepad.

[h2]Built to be comfortable[/h2]
Screen shake and flashing can be turned off, name tags can be enlarged, and the default player colours are checked for the common kinds of colour blindness. Stages and weapons can be switched on or off in the host's settings.

[h2]Early Access[/h2]
Pickfight is in Early Access. It is playable now and growing quickly. See the Early Access FAQ below.
```

## 3. Early Access FAQ

```
[b]Why Early Access?[/b]
The core game is playable and fun, but a game built for a room full of friends gets better with real rooms full of friends. We want feedback from real parties on weapons, stages, modes and balance before calling it 1.0.

[b]Roughly how long will it be in Early Access?[/b]
We expect about 6 to 12 months. This is a goal, not a promise, and we will say so plainly if it changes.

[b]What is planned?[/b]
[list]
[*] More weapons
[*] More modes
[*] More stages
[*] Steam friend invites for online play
[*] A stage editor, later
[/list]
Plans can change based on what players tell us.

[b]What is the current state of the game?[/b]
Up to 8 players, 12 weapons, 27 stages, several modes, bots, and local and online play. Art and audio are still being polished toward a cleaner flat-shape look.

[b]Will the price change?[/b]
Early Access launches at $7.99. The price rises to $9.99 at 1.0, so buying now is the cheapest way in. We will announce any change ahead of time.

[b]Will the full version differ from Early Access?[/b]
It will have more content and more polish. Everyone who bought in Early Access gets the 1.0 game.

[b]How can I help shape the game?[/b]
Press the Feedback button in the host's Settings panel. It sends your message to us along with the build, OS and stage. You can also post in the Steam discussions. We read all of it.
```

## 4. Suggested tags (priority order)

1. Local Multiplayer
2. Party Game
3. Platformer
4. Fighting
5. Physics
6. Multiplayer
7. Local Party
8. Funny
9. Casual
10. Action
11. Competitive
12. 2D
13. 2D Fighter
14. Arcade
15. Difficult
16. Online Co-Op
17. Controller
18. Cartoony
19. Colorful
20. Indie

Notes: "Online Co-Op" is a Steam tag but the game is competitive; swap it for "PvP" or "Online PvP" if the tag picker offers one. Drop "Difficult" if it reads wrong against a party pitch. Verify tag names in Steamworks.

## 5. Feature checklist

Steamworks category checkboxes. Verify exact names in Steamworks (**verify**).

- [x] Single-player (solo practice against bots)
- [x] Multi-player
- [x] PvP
- [x] Online PvP (room code via relay)
- [x] Shared/Split Screen PvP (everyone on one screen)
- [x] Shared/Split Screen
- [x] Partial Controller Support (gamepad seats; phones and laptop browsers are the main controllers)
- [ ] Remote Play Together: tick only after the test passes (steam-readiness 6.2)
- [ ] Steam Cloud: not used
- [ ] Achievements, Trading Cards, Workshop: not planned for launch
- [ ] Family Sharing: only if left enabled; the host buys, so it is a natural fit

Other store settings: Early Access, $7.99 USD ($9.99 at 1.0). Languages: English interface and audio (narrator). Content survey: cartoon violence, no blood, no gambling, no in-app purchases.

## 6. Screenshot ideas

Capture at 1920x1080 on the polished flat-shape art. Steam wants at least five. Put the strongest first.

1. **Eight-player brawl.** A busy stage mid-fight with all eight squares, name tags and hats visible. Lead image.
2. **Phone in hand.** A real photo or mock beside the screen: the phone controller with its damage bar, with the match on the TV behind it. Shows the "no app" pitch.
3. **QR join lobby.** The lobby with the join URL and QR code, ready-up and the live sandbox running underneath.
4. **Weapon variety.** A collage or one scene that shows the umbrella catching wind, the pogo mid-launch and the grappling hook mid-swing.
5. **Hazard stage.** Rising lava, a swinging saw or spikes, with a player about to be knocked into it. Shows that stages fight back.
6. **Night stage.** The darker palette with stars and lamps over the spawns, glowing weapon heads.
7. **Victory podium.** The podium with awards and the stats table, and a confetti or slow-motion KO moment.
8. **Modes and Teams.** Red vs Blue team rings, or a King of the Hill hill with players fighting over it. Use whichever mode has shipped.

Trailer note: open with the arm swing and a ring-out in the first 3 seconds, then show the QR scan, then 8 players.
