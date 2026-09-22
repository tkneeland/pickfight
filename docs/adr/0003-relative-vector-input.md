# 3. Relative vector input replaces absolute cursor aiming

- Status: Accepted
- Date: 2026-09-22
- Supersedes: the "Open design question: local multiplayer input" section of the README

## Context

The original prototype aimed the arm at the mouse cursor: angle and extension
were both derived from `mouse_position - body_position`, an **absolute** point
on the screen the player is looking at.

That only works when the controlling device is also the display. Under ADR-0001
and ADR-0002 it never is — a phone showing a blank touch surface has no cursor
on the host's screen to point at.

## Decision

Controllers send a **relative 2D vector**: a drag offset, normalised against a
maximum drag radius. The host derives arm angle from the vector's direction and
arm extension from its magnitude.

## Consequences

- One input model covers every source. A touch drag, a trackpad drag, and a
  gamepad stick all produce the same vector, so the host does not care which is
  which.
- Dissolves the README's gamepad-vs-keyboard question rather than answering it:
  that question assumed a shared screen and shared input devices, and neither
  survives ADR-0001.
- `Player.gd`'s `_update_arm_input` changes less than expected — it already
  reduces the mouse to a single vector, so the mouse path becomes one vector
  source among several rather than a special case.
- The keyboard fallback (`use_mouse = false`, A/D/W/S) loses its reason to
  exist. Keep it only as host-side debug input.
- Drag radius becomes a feel-tuning parameter with no equivalent in the mouse
  scheme. Expect to tune it.

## Alternatives considered

**Absolute touch position mapped to stage coordinates.** Would let a player
point at a spot on a stage they cannot see on their own device. Unusable.

**Gamepad per player.** The README's original candidate. Still compatible with
this decision (a stick is a vector source), but no longer necessary, and it
would require every player to bring a gamepad.
