# 2. Phone browsers as controllers

- Status: Accepted
- Date: 2026-09-22

## Context

ADR-0001 makes every player's device an input source. Which device, and what
runs on it?

Laptops were the first candidate (trackpad or mouse). Phones are more
convenient — everyone already has one in hand, nobody needs to open and position
a second laptop, and touch controls were already a stated longer-term goal.

The client can be a web page or a native app. A hard requirement from the
outset: **controls must feel snappy.** Any option that cannot hit that is
disqualified regardless of convenience.

## Decision

Every player — including whoever owns the host machine — uses a phone browser
page as their controller. The host serves that page over the local network and
accepts input connections from it.

## Consequences

- Zero install. Players join by opening a URL, so onboarding is a QR code.
- One client implementation for everyone. The host player is not a special case,
  so input feel is identical across all players.
- Front-loads the touch-control work that mobile play would need anyway.
- The host must run an HTTP server (serving the page) alongside the input
  transport.
- Commits the project to a latency budget that has to be defended rather than
  assumed.

### Latency constraints this decision commits us to

These are load-bearing. Violating them breaks the snappiness requirement.

- **Direct LAN connection only.** The phone talks to the host's IP. Input must
  never relay through an internet server.
- **Prefer 5 GHz, or the host's own hotspot.** Congested 2.4 GHz is a far bigger
  risk to feel than anything in the browser stack.
- **Stream continuously at 60–120 Hz** in a small binary payload — not JSON, not
  event-driven-only.
- **`touchmove` with `preventDefault`** so scroll and zoom stop fighting the
  input; coalesced pointer events to sample above display rate; Wake Lock so the
  phone does not dim mid-match.
- **Upgrade path: WebRTC DataChannel** (unreliable, unordered) if WebSocket's
  TCP head-of-line blocking causes stutter. For input where only the newest
  value matters, dropping a stale packet beats waiting for its retransmit.

Expected budget is roughly 20–40 ms over a directly attached mouse. The arm is a
momentum-carrying physical object, which masks input delay far better than a
twitch shooter would — this genre tolerates that budget.

## Alternatives considered

**Laptop trackpads as controllers.** Equivalent architecture, worse convenience,
and no progress toward touch controls.

**Native companion app.** Marginally better input access, at the cost of
installs and app-store friction. Not worth it at prototype stage.

**Host player uses the host's own mouse directly.** Lowest possible latency for
exactly one player, but it makes that player's feel different from everyone
else's and forks the input code. Rejected for consistency.
