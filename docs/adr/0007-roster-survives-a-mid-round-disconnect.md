# 7. A player's roster entry survives a mid-round disconnect

- Status: Accepted
- Date: 2026-09-22

## Context

Under ADR-0001 and ADR-0002, a player's controller is a phone on Wi-Fi. A
gamepad does not drop for 900 ms and come back; Wi-Fi does. Stick Fight has no
equivalent failure mode, so the reference game offers no answer here.

The transport already treats silence as departure: `controller_timeout_sec` is
2.0 seconds, after which the slot unbinds and frees. Combined with binding to
the lowest free slot, that means a player whose phone hiccups can have their
body taken over by the next person to open the join URL — mid-round, mid-swing.

Rounds are also now elimination-based (ADR-0004), so "this player is gone"
became a decision with stakes: it hands someone else the round.

## Decision

Controllers bind to a **roster entry**, not to a live body.

When a controller goes silent, the player's input zeroes — the weapon eases to
rest and the body goes limp — but the player stays alive and killable, and the
roster entry is held until the end of the current round. A controller
reconnecting within that window reclaims the same player.

A roster entry not reclaimed by the round's end is dropped, and the player does
not spawn into the next round.

The roster is open: a phone may connect at any time, and that player enters at
the start of the next round. The cap is four.

## Consequences

- A brief Wi-Fi hiccup costs a player their momentum, not their round.
- A limp body remains a target. That is the honest outcome — they stopped
  swinging, so they are easy to hit — and it means a disconnect can never be
  used as a defence.
- Slot-stealing becomes structurally impossible, because binding no longer
  targets a body.
- Round boundaries are the only time the roster changes, which gives joins,
  drops and weapon carry-over a single well-defined moment to happen in.
- The transport must distinguish reclaiming an existing entry from creating a
  new one, which the current lowest-free-slot bind does not do.
- Four spawn points per stage becomes part of the stage contract, and the
  player-count bound stops being an open question.

## Amendment (2026-09-23, issue #12)

Two gaps in how the hold is bounded, found in review:

- **No round, no hold.** An entry whose controller drops while no round is
  running is released right away. "Until the end of the current round" has
  nothing to hold it for, and holding it anyway let a dropped phone be
  counted as present and spawned as a limp body.
- **A round nobody can finish ends.** If no player still alive in a round has
  a connected controller, the round ends with no winner after a grace period
  (`RoundManager.abandoned_round_grace_sec`, 10 s). A controller reconnecting
  inside the grace period cancels it. Without this, a round everyone walked
  away from could never end, its entries never expired, and every new phone
  was refused until the host restarted. The grace period keeps the original
  promise: a Wi-Fi blip that hits the whole room still costs momentum, not
  the round.

## Alternatives considered

**Disconnect eliminates immediately.** Makes flaky Wi-Fi indistinguishable from
rage-quitting, and hands out rounds for network events.

**Roster entry persists indefinitely until an explicit leave.** Leaks entries
from people who walked away, and with a cap of four that locks out anyone who
wants to play.

**Freeze the body, or make it invulnerable, while disconnected.** Turns a
network problem into a combat advantage.
