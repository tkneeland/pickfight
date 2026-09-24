# 13. The phone buzzes for what happens to its own player

- Status: Accepted
- Date: 2026-09-24

## Context

The controller page sends input and renders no game state (ADR-0002). Players
watch the shared screen, but in a four-player scramble it is easy to miss that
it was you who just got hit, or that your swing connected. The phone is in
every player's hand, and it is the one device that belongs to a single player.
Issue #34 asked for haptic feedback on it.

The phone is also what makes this awkward. `navigator.vibrate` exists on
Android browsers but not on iOS Safari. Until now the host sent the page one
message, the slot assignment.

## Decision

- **Four events, each sent only to the phone that owns the affected slot.**
  `win` (a long buzz) goes to the round winner, and `eliminated` (a double
  buzz) to the player just eliminated. `struck` (a short buzz) goes to the
  victim of a strike that dealt damage, and `hit` (a light tick) to the
  attacker who landed it. A 0-damage swing sends nothing. Survivors put through
  `leave_round()` at the end of a round get no `eliminated`.
- **Wire format.** One JSON text frame over the existing controller WebSocket:
  `{"t":"buzz","kind":"win"|"eliminated"|"struck"|"hit"}`. The slot message
  `{"slot":<i>}` is unchanged, and the page tells the two apart by their keys.
- **`ControllerServer.send_buzz(slot, kind)`** builds and sends the frame. It is
  a no-op when the slot has no connected phone. A missed buzz is feedback, not
  state, so it is never replayed on reconnect.
- **`RoundManager` does the wiring.** It already holds the roster, and it
  connects to each player's existing `strike_landed` signal, binding the
  attacker's slot, and to a new `Player.eliminated` signal. It sends `win` where
  it scores the winner. `Player` never learns about phones and
  `ControllerServer` never learns about rounds. A roster without `send_buzz`
  (an older test stub) is skipped.
- **The flash is the iOS fallback, and it plays everywhere.** On every buzz the
  page washes the screen in the slot's colour (`SLOT_COLORS`) and fades it.
  Strength and length follow the kind: `win` is the longest and strongest, `hit`
  the faintest. The page calls `navigator.vibrate` only where it exists.
- **A weaker buzz does not cut off a stronger one still playing.** A lethal
  strike sends `eliminated` then `struck` in the same tick, and `vibrate()`
  cancels whatever pattern was running. The page therefore ignores a
  lower-ranked kind until the current one has finished.

## Consequences

- The host sends every event and the page decides what it feels like. Tuning
  a pattern or a flash means editing `controller/index.html` only. The host
  re-reads it per request, so a reload picks up the change.
- `struck` and `hit` fire per damaging strike. A flurry of strikes is a flurry
  of buzzes, and the light `hit` tick is kept short for that reason.
- iOS players get the flash only. Whether a flash is enough feedback needs
  real phones to judge, and the scenarios cannot prove it.
