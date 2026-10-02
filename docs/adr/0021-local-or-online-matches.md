# 21. Local or online matches, never mixed

- Status: Accepted
- Date: 2026-10-02

## Context

ADR-0019 let a single match mix same-room phones, a host-PC seat and remote PC
seats reaching the host through a relay. In practice that means one room has two
input UIs at once (a phone drag and a captured mouse), and one lobby has to serve
both: the phone controller page shows the player's cosmetics and buzz, while an
online player sees the host's screen on their own computer. It also leaves open
the host's own mouse taking a seat in a TV party, and phones that cannot work
online anyway because they need the host's LAN.

The owner decided the split on 2026-10-02 (#435), and the same day settled how
gamepad and online players get what a phone gives (#441, #442). #437 asks for it
to be written down.

## Decision

Amend ADR-0019: a match is either **Local** or **Online**, never mixed.

- **Local:** the host PC (often on a TV) shows the join QR. Players use phones,
  the browser controller page, or gamepads plugged into the host. The host's
  mouse never takes a seat. Remote seats are refused.
- **Online:** every player runs their own copy on their own computer and plays
  with the mouse or a gamepad. The host's own seat is always on, and the "Play
  on this PC" toggle is removed. Phones and the LAN controller page are
  refused, and no QR is shown.
- **Host authority in Local:** the host PC's keyboard and mouse always control
  the host, plus the first gamepad through the Y host menu (#368).
- **Cosmetics without a phone:** hat, colour and eyes are picked in-game. One
  picker model is shared by two layouts: a compact slot-style picker on a
  gamepad player's lobby card on the shared screen, shown only while a gamepad
  holds that seat; and a large mouse-friendly panel in an Online player's own
  lobby.
  - The Online panel sits in the Online lobby beside the player list and stays
    visible until the player readies up.
  - An Online player's picks are saved in their own copy and sent on join. A
    Local gamepad's picks last only for the session.
  - Cosmetics change in the lobby only, never between rounds.
  - A colour another player has taken is greyed out on every input: phone,
    gamepad and online. It is first come, first served, as the phone picker
    already works.
- **Other gamepad parity:** a gamepad player presses A to Continue after the
  podium and counts toward "every human continued". The right stick drives
  their KO ghost. Phone buzz maps to controller rumble. There is no damage bar
  for gamepads. A one-time "right stick swings" tip shows on their card. A
  replugged gamepad reclaims its seat and cosmetics.

## Consequences

- Each lobby serves one kind of input, so each can be built and tested for that
  kind alone.
- The Online lobby loses the QR and the phone join path; the Local lobby loses
  the room-code join path for remote seats.
- Gamepad players no longer need a phone for any feature the phone gave them,
  so the cosmetics picker, Continue, ghost control and rumble must all exist
  without one.
- The relay, snapshots and remote seat mechanics of ADR-0019 are unchanged;
  they apply to Online matches only.
- Docs and store copy must not promise that phones play online.

## Alternatives considered

**Mixed matches (ADR-0019 as written).** Rejected. A mixed room needs two input
UIs at once, and online play assumes everyone owns the game, which is not true
of phone players who join free.

**Phone pairing for gamepad cosmetics.** A gamepad player scans a QR with a
phone just to pick a hat. Rejected: it is clunky, and it brings back the phone
the gamepad player was avoiding.
