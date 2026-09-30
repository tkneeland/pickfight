# 1. Same-room multiplayer with a host-rendered screen

- Status: Accepted
- Date: 2026-09-22

## Context

The prototype was framed as local multiplayer: players on one machine sharing
input devices. That framing produced an unresolved question — gamepad-per-player
vs keyboard-only — because Getting Over It's analog, precise pole control does
not survive being split across one shared keyboard.

The actual target is different: players each bring their own device, sit in the
same room, and watch one screen.

Two ways to deliver that:

1. **Networked multiplayer** — every player runs a full game client on their own
   machine, synchronised over LAN or internet.
2. **Host-rendered, devices-as-controllers** — one machine simulates and renders;
   every other device is an input source only.

## Decision

Host-rendered, devices-as-controllers.

## Consequences

- One authoritative simulation. No state replication, no prediction, no
  reconciliation, and none of the desync bug class.
- Physics-driven combat stays deterministic, which is the whole reason this is
  tractable — swing momentum and collision knockback are notoriously difficult
  to network well.
- The controller transport is a thin input relay, not a game protocol.
- Remote play is out of scope. Revisiting it means swapping the transport layer;
  the simulation code is unaffected either way. (Extended by ADR-0019.)
- The README's gamepad-vs-keyboard question is void, superseded by ADR-0003.

## Alternatives considered

**Networked multiplayer.** Rejected for now. Godot's high-level multiplayer
would carry the transport, but authoritative physics with client-side prediction
is a large, bug-prone investment, and remote play was never an actual goal for
this prototype.
