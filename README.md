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

Early prototype. `scenes/Main.tscn` has one arena and two test players so
the pole-swing movement and the knockback-on-collision combat can be felt
out before anything else (art, levels, weapons, win conditions) gets built
on top.

## How it plays

A session is an endless run of rounds on rotating stages. A round ends
when one player is left alive; that player scores; the tally keeps running
until everyone stops playing. No health bars — you die by taking enough
damage, or by being knocked into a hazard or off the stage.

Everyone starts a round with a pickaxe, except whoever won the last one:
they keep what they were holding.

## Controls

Everyone plays from their **phone**. One host machine runs the game and
renders the shared screen, and serves a controller web page over the local
network — players join by opening a URL, no install.

Input is a **drag vector**: direction sets the weapon's angle, distance sets
how far it reaches. See [ADR-0003](docs/adr/0003-relative-vector-input.md).

## Running it

1. **Start the host.** `godot --path .` from the repo root, or open the
   project in the editor and press play. The host also starts a small HTTP
   server on `:8080` and a WebSocket input server on `:8081`.
2. **Read the join URL.** It is printed to the console and shown in the
   top-left of the game window, e.g. `http://192.168.1.42:8080/`.
3. **Open it on a phone** on the same network. Prefer a 5 GHz band or the
   host machine's own hotspot — congested 2.4 GHz is the biggest threat to
   input feel ([ADR-0002](docs/adr/0002-phone-browser-controllers.md)).
   The page shows `P1` or `P2` once it is bound to a player.
4. **Drag anywhere on the phone screen to swing.** The drag is relative to
   wherever your thumb lands, so you never need to look at the phone.

Phones bind to players in join order; the first free slot wins, and
disconnecting frees it again.

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

Sequences are `direction`, `reach` and `release`. Two probes run at once
bind two separate players.

### Known limitation

The controller page is served over plain HTTP, and the Screen Wake Lock API
is restricted to secure contexts — so the phone screen can still dim or lock
mid-session. Raise your phone's auto-lock timeout while playing. Adding HTTPS
is deliberately deferred.

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
scenes/      .tscn scene files (Main, Arena, Player)
scripts/     GDScript sources (Player, ControllerServer, KillZone)
controller/  the single-file controller web page served to phones
tools/       headless test fixtures
```

<!-- atlas-v3:readme:start -->
## Atlas

This repo uses Atlas, a Claude Code plugin that acts as a shared path for AI-assisted development — generated, customizable policies, guidelines, and guardrails that keep agent-driven work safe and consistent without locking teams into one rigid workflow. Read [`docs/atlas-operators-guide.md`](./docs/atlas-operators-guide.md) for how to work in this repo, in plain language, and the **Atlas** section in [`CLAUDE.md`](./CLAUDE.md) for the policy the agents follow.

Everything Atlas generated here — hooks, the `CLAUDE.md` section, `docs/agents/` — is a **base recommendation**, not fixed policy. Adapt it to this project's actual needs and processes.
<!-- atlas-v3:readme:end -->
