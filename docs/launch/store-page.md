# PickFight: Steam store page draft

**DRAFT — needs owner approval.** Nothing here is published. Facts come from `docs/FEATURES.md`, `docs/launch/owner-decisions.md`, `docs/launch/digest.md` and `project.godot`. Counts: 44 stages and 6 game modes are from FEATURES.md; 13 weapons in rotation = the pickaxe everyone starts with plus the 12 on-stage pickups (staff, sword, dagger, axe, shield, umbrella, boomstick, grappling hook, flail, boomerang, fishing rod, magnet). The spear and pogo stick stay in the code but are retired from rotation (#642, #655), so they are not counted. Recount from FEATURES.md before submitting.

| Field | Value |
| --- | --- |
| Title | PickFight |
| Developer | SQL Monkey Studios |
| Publisher | SQL Monkey Studios |
| Price | $9.99 USD, 20% launch-week discount (owner decision, Oct 18) |
| Release | Thu Jul 22 2027 (full 1.0, no Early Access) |
| Platforms | Windows, macOS, Linux (aiming for Steam Deck Verified) |

## Short description

PickFight is a same-room party brawler for up to 8 players. No controllers needed: everyone scans a QR code and fights with their phone, swinging a pickaxe, sword or grappling hook across 44 stages. Play on the couch, online by room code, or solo against bots.

(260 characters; Steam's limit is 300.)

## Long description

**8 players. No controllers. Just scan the QR.**

PickFight is a same-room platform fighter for up to eight players. One computer (or a Steam Deck) runs the shared screen. Everybody else joins by scanning a QR code with the phone already in their pocket. No app to install, no pads to hunt for, no account to make. Your thumb drags the weapon, and the weapon is your arm: swing it, plant it in a wall, haul yourself up a cliff, knock your friends into the lava.

Movement is physics, not buttons. Your weapon is a jointed arm that bites into the ground, so climbing, swinging and throwing yourself across gaps are all the same drag. It is scrappy, a bit clumsy on purpose, and funny to watch.

**A whole pack of stuff to fight over**
- 44 rotating stages built from hazards: lava, spikes, saws, moving platforms, crumbling ledges, bounce pads, wind zones, fans, falling rocks.
- 13 weapons: everyone starts with a pickaxe, and the rest drop onto the stage as pickups. Sword, axe, dagger, staff, shield, umbrella, boomstick, grappling hook, flail, boomerang, fishing rod, magnet.
- 6 game modes: Classic, King of the Hill, Sudden Death, Stock, Soccer and Capture the Flag, with Free-for-all or Red vs Blue teams.
- Round modifiers now and then: low gravity, double damage, meteor shower, slippery floors and more.

**Play your way**
- **Couch:** phones and gamepads in one room, joined by QR code.
- **Online:** every player on their own computer, joined by a room code. Invite Steam friends straight from the lobby.
- **Solo with bots:** practise or play alone against bots on Easy, Normal or Hard.

A match is Couch or Online, never mixed. If your Wi-Fi blocks phones from reaching the host, they can join over the internet relay instead.

## Feature bullets

- Up to 8 players on one screen, joined by QR code from any phone browser: no app, no controllers.
- Your weapon is your arm: drag to swing, climb and fling yourself around.
- 44 stages with lava, spikes, saws, moving platforms, bounce pads and wind.
- 13 weapons, from the pickaxe everyone starts with to the grappling hook, boomerang, fishing rod and magnet.
- 6 modes: Classic, King of the Hill, Sudden Death, Stock, Soccer, Capture the Flag.
- Couch, Online by room code, or Solo against bots (Easy, Normal, Hard).
- Gamepads work too, including Steam Deck as the host.
- Hats, eye styles and colours, picked on your phone.
- 18 Steam achievements and Steam Timeline markers for every KO and round win.
- Slow-motion final KO and a "play of the round" replay.
- Comfort options: screen shake off, reduce flashes, bigger name tags, colour-blind-safe player colours.
- Interface and subtitles in nine languages.

## Suggested Steam tags (20)

Check each against Steam's current tag list before entering them. Order is rough priority.

1. Local Multiplayer
2. Party Game
3. Local Co-Op
4. Multiplayer
5. Fighting
6. Physics
7. Funny
8. Casual
9. 2D
10. 2D Platformer
11. Arena Shooter
12. Online Co-Op
13. PvP
14. Competitive
15. Controller
16. Cartoony
17. Colorful
18. Short
19. Replay Value
20. Indie

## Supported languages

Interface and subtitles only; there is no voiced audio. The announcer is a synthesised voice and is not localised.

| Language | Interface | Full audio | Subtitles |
| --- | --- | --- | --- |
| English | yes | no | yes |
| Simplified Chinese (zh-Hans) | yes | no | yes |
| Russian (ru) | yes | no | yes |
| Spanish, Latin America (es-419) | yes | no | yes |
| Portuguese, Brazil (pt-BR) | yes | no | yes |
| German (de) | yes | no | yes |
| French (fr) | yes | no | yes |
| Japanese (ja) | yes | no | yes |
| Korean (ko) | yes | no | yes |

Translations are machine-made (Claude) with volunteer proofreading credited in-game (owner decision, Oct 18). The owner's AI-disclosure choice for Steam is recorded in `owner-decisions.md` (translations only).

## Controller support

**Partial.** Gamepads can drive a seat on the host machine (right stick moves the arm; the left stick works for a lone Joy-Con), and the lobby, settings and host menus work from a gamepad. Phones are the main controller and are not Steam-recognised controllers, and the PC join screen and feedback box need a keyboard. Steam Input's default layout for the Deck still needs setting and testing (`docs/steam-deck-readiness.md`, D15). Remote Play Together is off at launch.

## System requirements

**All numbers are estimates: verify on low-end hardware before publishing.** Derived from the engine and renderer, not from measurement. `project.godot` sets `renderer/rendering_method="gl_compatibility"` on Godot 4.6 (the OpenGL Compatibility renderer, 2D art and 2D physics), so no Vulkan card is needed. The Compatibility renderer needs OpenGL 3.3 on desktop. The Steam Deck target is 30 fps at 800p (`docs/steam-deck-readiness.md`, D17, not yet measured).

Phones need a modern browser and the same Wi-Fi as the host (Couch), or any internet connection (relay fallback and Online). The host needs a network that lets devices talk to each other; guest Wi-Fi often blocks this.

### Windows

| | Minimum | Recommended |
| --- | --- | --- |
| OS | Windows 10 64-bit | Windows 10 or 11 64-bit |
| Processor | Dual-core, about 2.0 GHz | Quad-core, about 3.0 GHz |
| Memory | 2 GB RAM | 4 GB RAM |
| Graphics | OpenGL 3.3 capable (Intel HD 4000 class) | Any dedicated or recent integrated GPU |
| Storage | 500 MB | 500 MB |
| Network | Wi-Fi or LAN for phones | Broadband for Online |

### macOS

| | Minimum | Recommended |
| --- | --- | --- |
| OS | macOS 10.13 or later (verify against the 4.6 export) | macOS 12 or later |
| Processor | Intel dual-core or Apple Silicon | Apple Silicon or Intel quad-core |
| Memory | 2 GB RAM | 4 GB RAM |
| Graphics | OpenGL 3.3 capable (Intel HD 4000 class) | Apple Silicon integrated |
| Storage | 500 MB | 500 MB |

The build is a universal app; notarization is planned for Steam launch.

### Linux

| | Minimum | Recommended |
| --- | --- | --- |
| OS | 64-bit (x86_64) distribution with glibc, SteamOS 3 / Steam Deck | Same |
| Processor | Dual-core, about 2.0 GHz | Quad-core, about 3.0 GHz |
| Memory | 2 GB RAM | 4 GB RAM |
| Graphics | OpenGL 3.3 capable (Mesa or proprietary) | Any recent GPU |
| Storage | 500 MB | 500 MB |

Storage is a guess (the GodotSteam libraries alone add about 30 MB to each export); replace it with the real depot size.
