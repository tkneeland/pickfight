# 25. Phones over the relay in a Local match

- Status: Accepted
- Date: 2026-10-19
- Amends: ADR-0021 (a Local match may carry phone controllers over the relay)

## Context

ADR-0021 made a Local match a same-room affair: phones reach the host over its
LAN, and remote seats are refused. In practice some rooms cannot do that: guest,
hotel or school Wi-Fi isolates clients, a VPN hides the right address, or the
phones are on mobile data. The "Phones can't join?" popup (#680) lists the
usual fixes, but sometimes none of them is available to the player.

The relay (ADR-0019) is already how Online players reach a host, and it
forwards frames without parsing them, so a phone can ride it. Ticket #683 asks
for that as a fallback.

## Decision

A Local match may carry *phone controllers* over the relay, as an explicit,
host-chosen **relay fallback**.

- **LAN stays the default.** Nothing opens a relay room unless the host presses
  "Join over the internet instead" in the "Phones can't join?" popup. It is
  never automatic.
- **A transport, not a match kind.** The match stays Local: its lobby, rules
  and seats are unchanged. Phones over the relay are the same phones, on a
  different wire, and the lobby card tags them "(internet)".
- **Online PC clients still never join a Local match.** A relay peer's hello
  must carry `"client": "phone"` (the PC client's hello carries `proto` and
  `demo` instead); anything else is refused with the usual match-kind close
  (code 4003, "couch match"). So "Local or Online, never mixed" holds for match
  kinds. The reverse holds too: a phone hello is refused in an Online match.
- **The page comes from GitHub Pages.** The relay cannot serve HTTP, and the
  host's own page is plain HTTP on a LAN address, which an HTTPS page cannot
  load or open a socket from (mixed content), so this can never be automatic or
  point at the host. The QR and short link are
  `https://tkneeland.github.io/pickfight/controller/index.html?room=ABCD&relay=<urlencoded wss url>`.
  The page accepts only a `wss://` relay (and `ws://127.0.0.1` for tests).
- **Closing it.** A "Stop internet join" control closes the room; phones that
  joined over it lose their socket and keep their seat claim (ADR-0007). Phones
  on the LAN are unaffected. Switching the match to Online or Solo closes the
  fallback room first, and drops the relay phones like any phone refused by the
  new kind.

## Consequences

- Latency is worse than the LAN (a round trip through the relay), so this is a
  fallback, not a peer of the LAN join.
- A relay outage or an offline host machine breaks only this fallback; the LAN
  join and the match itself do not depend on the internet (no always-online
  requirement).
- Relay traffic costs server capacity, so it is opt-in per match and idle rooms
  time out as they already do.
- The phone page is now served in two places (the host and Pages), so the page
  must run when served raw: its port placeholder reads as 0 there.
- A relay phone is exempt from the PC client's version and build checks, as a
  LAN phone is, but it loads the page Pages serves, which can lag the host's
  build.
- Relay phones never become the host phone, are not streamed snapshots, and are
  not pinged: they play as phones do.

## Alternatives considered

**Open the relay room automatically when the LAN fails.** Rejected: the host
cannot tell why a phone failed, and an always-online path in a Couch match
contradicts ADR-0021.

**A new match kind for internet phones.** Rejected: it would multiply lobbies
for what is only a different wire.

**Let PC clients join Local matches too.** Rejected: it brings back the mixed
room ADR-0021 removed.
