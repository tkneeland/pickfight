# 19. Remote PC seats over a relay

- Status: Accepted
- Date: 2026-09-30

## Context

ADR-0001 established same-room host-rendered multiplayer: one host machine
simulates and renders, and every player brings their own phone as an input
device. Remote play was deliberately out of scope — it meant swapping the
transport layer, and the game's target was in-room co-location.

Issue #212 asks for remote play. The owner wants to support remote players
joining from PCs over the internet, not just same-room phones.

## Decision

Remote PC players are additional seats in the same roster. They connect through
a relay server (a 4-letter room code in the controller URL) and join the round
pool with phones.

- **Input:** Remote PCs send the same relative input vector as phones, driven
  by captured mouse on the controller page, per ADR-0003.
- **Rendering:** Remote PCs receive world snapshots streamed by the host, which
  they interpolate and render on their own screen. Same as phones.
- **The relay:** A headless GDScript program in `relay/` that runs on a
  publicly-hosted machine, forwards frames from host to seats and input from
  seats to host, and declines to parse or understand the frames — it is a dumb
  pipe that knows only the room code and the roster.
- **Same-room play unchanged:** Phones connect directly over the LAN as before.
  The host remains the only authoritative simulation. ADR-0001 stands: one
  simulation, no prediction, no replication.

## Consequences

- Remote players feel their round-trip latency as input delay. No client-side
  prediction softens it.
- The host's upload bandwidth grows by ≤ 40 KB/s per remote seat (budgeted in
  #240).
- The relay must be hosted somewhere. Deployments and ops are out of scope of
  this ADR (see #242).
- The simulation code is unaffected. Adding or removing remote seats changes
  only the relay and the controller page.

## Alternatives considered

**Rollback/lockstep.** Rejecting determinism. Godot's physics does not replay
identically given the same inputs (floating-point execution order varies), so
lockstep would require a deterministic physics fork — large, fragile, and
unsupported by Godot.

**Direct IP with port forwarding.** The host forwards a port and shares its
public IP. No relay to run, but the host has to configure their router, and
many networks (CGNAT, campus Wi-Fi) can't forward a port at all. The relay and room code are friendlier.

**Steam networking.** Valve's transport and lobby server. Rejected: the game
is too new to assume every player has Steam, and the relay is simpler to
reason about and deploy.
