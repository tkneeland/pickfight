# 23. Solo is its own offline match kind

- Status: Accepted
- Date: 2026-10-03
- Supersedes: the Solo part of ADR-0021 ("Solo is an Online match with the room closed")

## Context

ADR-0021 and #435 made Solo an Online match whose room never opens: it ran
through the Online kind, so a relay link object existed, the lobby was the Online
lobby, and the match was one flag away from being a real room. The owner decided
on 2026-10-03 (#522): "solo mode shouldn't have an online join code, and should
just not involve any sort of netplay."

## Decision

Solo is a third match kind, beside Local (Couch) and Online, and it is offline.

- The relay is never contacted. No `RelayLink` is created or opened in a Solo
  match, and going online is refused there (the host command and `go_online`).
- No room code, QR or LAN URL is generated or shown.
- Phone joins are refused ("solo match: nobody else can join"). A remote seat
  cannot arrive, since there is no relay to arrive by; one that somehow did would
  be refused ("room closed").
- The host PC's mouse and keyboard seat plays against bots: three by default, and
  the host's bot counter still works. It picks a look with the same picker as an
  Online host seat; the picker UI is #507's to restyle.
- The host readies explicitly (Start, Enter) and bots are ready already (#505).
  The lone host must also Continue on the victory screen (key or timeout), so the
  podium shows instead of flashing past.
- Switching away from Solo sends its bots away, so none reach Couch or Online
  (#505). Switching to Online opens the room; switching back closes it again.

The `RelayLink` node is now made the first time a match goes online, not at
launch, so a Couch or Solo match has none.

## Consequences

- `match_kind()` returns "solo"; code that meant "no QR, no phones" treats Online
  and Solo alike, and only Online touches the relay.
- ADR-0021's Local and Online rules, and its cosmetics and gamepad parity rules,
  are unchanged.

## Alternatives considered

**Keep Solo as Online with the room closed.** Rejected: it still builds the relay
link and routes through Online code, which the owner ruled out.
