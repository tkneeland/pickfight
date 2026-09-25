# Pickfight

A local-multiplayer platform fighter that combines **Stick Fight**'s scrappy
physics-based combat with **Getting Over It with Bennett Foddy**'s
pole/hammer movement scheme.

Instead of walking and jumping, each player holds a single weapon — a
pole with a heavy head — that plants against the world and pushes, pulls,
or swings their body around. It is also the only way to hurt anyone, and
the only way to block. Swapping it for a heavier one changes how you move
as much as how you fight.

Built with Godot 4.6.

## Status

Early prototype, ready for playtesting. `scenes/Main.tscn` runs the endless
round loop for up to four phone-controlled players across 11 rotating
stages, some built around moving platforms, crumbling ledges and hazard
walls. Five
weapons exist (pickaxe, staff, sword, axe, dagger); everything but the
pickaxe is found as a pickup on the stage. Art is still flat placeholder
shapes.

## How it plays

A session is an endless run of rounds on rotating stages. A round ends
when one player is left alive; that player scores; the tally keeps running
until everyone stops playing. No health bars — you die by taking enough
damage, or by being knocked into a hazard or off the stage.

Everyone starts a round with a pickaxe, except whoever won the last one:
they keep what they were holding. Other weapons lie on the stage as
**pickups**: one is there when the round starts, another arrives every 10
seconds (two at most), and walking into one with your body swaps your weapon
for it. Your weapon's head can't grab them, so you have to get there.

## Controls

Everyone plays from their **phone**. One host machine runs the game and
renders the shared screen, and serves a controller web page over the local
network — players join by opening a URL, no install.

Input is a **drag vector**: direction sets the weapon's angle, distance sets
how far it reaches. See [ADR-0003](docs/adr/0003-relative-vector-input.md).

## Running it

1. **Start the host.** Open the project in the Godot 4.6 editor and press
   play, or run it from the repo root. `godot` below stands for your Godot
   binary: it's `Godot_v4.6.2-stable_win64.exe` on Windows (use the
   `_console.exe` build to see the log) and
   `Godot.app/Contents/MacOS/Godot` on macOS, unless you've put it on your
   PATH as `godot`.

   ```
   godot --path .
   ```

   The host also starts a small HTTP server on `:8080` and a WebSocket input
   server on `:8081`.
2. **Let it through the firewall.** The first launch triggers Windows
   Defender Firewall, or macOS's "accept incoming connections?" prompt if its
   firewall is on. Allow it, and on Windows tick the network type you're
   actually on. Wi-Fi is often set to *Public*, and allowing only *Private*
   silently blocks every phone.
3. **Read the join URL.** It's shown in the top-left of the game window,
   e.g. `http://192.168.1.42:8080/`, and as a QR code at the top right if
   [`qrencode`](https://fukuchi.org/works/qrencode/) is on your PATH. If you
   type it in instead, every address is printed to the console; the one shown
   on screen is the best guess for your Wi-Fi.
4. **Open it on a phone** on the same network. Prefer a 5 GHz band or the
   host machine's own hotspot — congested 2.4 GHz is the biggest threat to
   input feel ([ADR-0002](docs/adr/0002-phone-browser-controllers.md)).
   The page shows `P1` to `P4` once it is bound to a player; two are
   needed to start a round, and a fifth phone is turned away.
5. **Drag anywhere on the phone screen to swing.** The drag is relative to
   wherever your thumb lands, so you never need to look at the phone. One
   finger drives: a second finger touching down is ignored until the first
   lifts.

### Starting with random weapons

Optional, for playtesting weapons without chasing pickups: launch with
`--random-weapons` and everyone except the last round's winner starts each
round holding a random weapon from the roster. The winner still keeps what
they had, and pickups still spawn.

```
godot --path . -- --random-weapons
```

### Demo mode

For a short showcase slot: `--demo` turns on random weapons, and plays the
stages with the most parts first, in a fixed order (Springboard, Rockfall,
Gale, Bulwark, Carousel, Sinkhole, then the rest). It also brings the lava
in sooner: it holds for 20 s, then rises over 40 s.

```
godot --path . -- --demo
```

A new phone takes the first free player slot and enters play at the start of
the next round. A phone that drops mid-round keeps its slot until that round
ends, and reconnecting gets the same player back
([ADR-0007](docs/adr/0007-roster-survives-a-mid-round-disconnect.md)). A
round nobody still in it can finish, because every survivor's phone is gone,
ends with no winner after 10 seconds.

### Debugging

Run the host with `--log-input` to print every decoded input packet and
every controller bind/unbind:

```
godot --path . -- --log-input
```

`tools/ws_probe_client.gd` is a headless controller stand-in that replays a
fixed input sequence over the real WebSocket transport, useful for checking
the host without a phone in hand:

```
godot --headless --path . -s tools/ws_probe_client.gd -- --sequence=direction
```

Sequences are `direction`, `reach`, `release`, `hold` and `stall`. Two
probes run at once bind two separate players, which is enough to start a
round with no phones at all.

### Known limitation

The controller page is served over plain HTTP, and the Screen Wake Lock API
is restricted to secure contexts — so the phone screen can still dim or lock
mid-session. Raise your phone's auto-lock timeout while playing. Adding HTTPS
is deliberately deferred.

## Exported builds

`tools/export.sh` builds a standalone macOS `.app` and Windows `.exe` into
`build/` (gitignored), so the host machine doesn't need Godot installed:

```
tools/export.sh            # both; or: tools/export.sh macos | windows
```

It needs Godot 4.6.2 on your PATH (or `GODOT=/path/to/godot`) and the 4.6.2
export templates (in the editor: *Editor > Manage Export Templates*). The
presets live in `export_presets.cfg`. The controller page is plain HTML, not a
Godot resource, so the presets list `controller/*` as an extra include; drop
that and the exported build serves a 500 instead of the page.

- **macOS** (`build/macos/Pickfight.app`, universal): ad-hoc signed only, not
  notarized, so Gatekeeper blocks a double-click with "cannot be opened".
  Right-click the app, choose **Open**, then **Open** again. You only have to
  do it once. On recent macOS, if there's no Open button, allow it under
  *System Settings > Privacy & Security* ("Open Anyway").
- **Windows** (`build/windows/Pickfight.exe`, x86_64, PCK embedded): unsigned,
  so SmartScreen may warn. Choose *More info > Run anyway*. The firewall
  prompt from step 2 above still applies.

## Decisions

See [`CONTEXT.md`](./CONTEXT.md) for the glossary and shape of the game,
and [`docs/adr/`](./docs/adr/) for the architecture decisions — notably
that this is same-room, host-rendered play rather than networked
multiplayer ([ADR-0001](docs/adr/0001-same-room-host-rendered-multiplayer.md)),
that the session never ends
([ADR-0004](docs/adr/0004-endless-session-replaces-the-match.md)), and that
the weapon and the arm are one object
([ADR-0005](docs/adr/0005-the-weapon-is-the-arm.md)).
The earlier open question about gamepad-vs-keyboard local input is
resolved and no longer applies.

## Project layout

```
scenes/      .tscn scene files (Main, Player; Arena is the scenario
             suite's physics fixture)
scenes/stages/  the 11 rotating stages, one .tscn each (ADR-0008)
scenes/parts/   reusable stage parts: MovingPlatform, CrumblingLedge, Hazard
scripts/     GDScript sources (Player, WeaponHead, WeaponStats,
             ControllerServer, RoundManager, Stage, KillZone,
             MovingPlatform, CrumblingLedge, Pickup, PickupWeapons)
resources/   weapon stat resources (pickaxe, staff, sword, axe, dagger)
controller/  the single-file controller web page served to phones
tools/       headless test fixtures (scenario_runner, ws_probe_client,
             capture_damage_screenshots)
```

<!-- atlas-v3:readme:start -->
## Atlas

This repo uses Atlas, a Claude Code plugin that acts as a shared path for AI-assisted development — generated, customizable policies, guidelines, and guardrails that keep agent-driven work safe and consistent without locking teams into one rigid workflow. Read [`docs/atlas-operators-guide.md`](./docs/atlas-operators-guide.md) for how to work in this repo, in plain language, and the **Atlas** section in [`CLAUDE.md`](./CLAUDE.md) for the policy the agents follow.

Everything Atlas generated here — hooks, the `CLAUDE.md` section, `docs/agents/` — is a **base recommendation**, not fixed policy. Adapt it to this project's actual needs and processes.
<!-- atlas-v3:readme:end -->
