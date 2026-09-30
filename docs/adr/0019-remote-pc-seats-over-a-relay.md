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

Amend ADR-0001: alongside same-room phones, a match can have **remote seats**.
These are players on their own PC, anywhere on the internet, who reach the host
through a relay by typing a 4-letter room code into the game's join screen.

- **Input:** a remote seat sends the same relative input vector as a phone
  (ADR-0003), built from the captured mouse. It claims a slot in the same
  roster and follows the same claim, rejoin and disconnect rules (ADR-0007).
  Remote seats and phones share the 8-player cap.
- **Rendering:** unlike a phone, a remote seat renders the match. The host
  streams it world snapshots, which it interpolates and draws. This is state
  replication, one way only: the host stays the only simulation, and a remote
  PC never simulates or predicts.
- **The relay:** a headless GDScript program in `relay/` on a public machine.
  It pairs a host with its remote seats by room code and forwards frames
  without parsing them. A connection picks its role with its first text
  message, `{"t":"host"}` or `{"t":"join","room":"ABCD"}`, because
  `WebSocketPeer.accept_stream` doesn't expose the request path.
- **Same-room play is unchanged:** phones connect directly over the LAN as
  before, and remain input-only.

## Consequences

- Remote players feel their round-trip latency as input delay. No client-side
  prediction softens it.
- The host now serializes and streams state (#240, budget ≤ 40 KB/s per remote
  seat) and maps relay peers to roster slots (#239). The simulation itself is
  unchanged.
- There is now a PC client (#241) that renders from snapshots and never runs
  gameplay physics.
- The relay must be hosted (#242).

## Alternatives considered

**Rollback/lockstep.** Rejecting determinism. Godot's physics does not replay
identically across machines given the same inputs (floating-point execution order varies), so
lockstep would require a deterministic physics fork — large, fragile, and
unsupported by Godot.

**Direct IP with port forwarding.** The host forwards a port and shares its
public IP. No relay to run, but the host has to configure their router, and
many networks (CGNAT, campus Wi-Fi) can't forward a port at all. The relay and room code are friendlier.

**Steam networking.** Valve's transport and lobby server. Rejected: the game
is too new to assume every player has Steam, and the relay is simpler to
reason about and deploy.
