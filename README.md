# Pickfight

A local-multiplayer platform fighter that combines **Stick Fight**'s scrappy
physics-based combat with **Getting Over It with Bennett Foddy**'s
pole/hammer movement scheme.

Instead of walking and jumping, each player controls a single arm that
plants against the world and pushes, pulls, or swings their body around.
Colliding into another player hard enough knocks them back; falling off
the arena resets your position.

Built with Godot 4.6.

## Status

Early prototype. `scenes/Main.tscn` has one arena and two test players so
the pole-swing movement and the knockback-on-collision combat can be felt
out before anything else (art, levels, weapons, win conditions) gets built
on top.

## How it plays

A match is a rapid run of rounds on rotating stages. A round ends when one
player is left alive; that player scores; first to the score target wins
the match. No health bars — you die by being knocked into a hazard or off
the stage.

## Controls

Everyone plays from their **phone**. One host machine runs the game and
renders the shared screen, and serves a controller web page over the local
network — players join by opening a URL, no install.

Input is a **drag vector**: direction sets the arm's angle, distance sets
how far it reaches. See [ADR-0003](docs/adr/0003-relative-vector-input.md).

> The code currently in this repo still uses the old mouse/keyboard
> prototype scheme and predates these decisions. It is being replaced.

## Decisions

See [`CONTEXT.md`](./CONTEXT.md) for the glossary and shape of the game,
and [`docs/adr/`](./docs/adr/) for the architecture decisions — notably
that this is same-room, host-rendered play rather than networked
multiplayer ([ADR-0001](docs/adr/0001-same-room-host-rendered-multiplayer.md)).
The earlier open question about gamepad-vs-keyboard local input is
resolved and no longer applies.

## Project layout

```
scenes/   .tscn scene files (Main, Arena, Player)
scripts/  GDScript sources
```

<!-- atlas-v3:readme:start -->
## Atlas

This repo uses Atlas, a Claude Code plugin that acts as a shared path for AI-assisted development — generated, customizable policies, guidelines, and guardrails that keep agent-driven work safe and consistent without locking teams into one rigid workflow. Read [`docs/atlas-operators-guide.md`](./docs/atlas-operators-guide.md) for how to work in this repo, in plain language, and the **Atlas** section in [`CLAUDE.md`](./CLAUDE.md) for the policy the agents follow.

Everything Atlas generated here — hooks, the `CLAUDE.md` section, `docs/agents/` — is a **base recommendation**, not fixed policy. Adapt it to this project's actual needs and processes.
<!-- atlas-v3:readme:end -->
