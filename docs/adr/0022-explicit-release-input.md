# 22. Explicit release input

- Status: Accepted
- Date: 2026-10-02
- Amends: ADR-0003 (zero vector means release)

## Context

ADR-0003 made the controller's input a relative vector and treated the zero
vector as "not touching": a phone drag that ends sends (0, 0), and the weapon
rests. Several weapons read that as a *release*: the grapple retracts, the
plunger lets go after 0.35 s, a flail's swing times its release, and gridlock
unsticks a head.

That assumption only holds for a touchscreen. A mouse or trackpad accumulates
an offset that never decays, and a gamepad stick is read as a vector too, so
the Online PC client and the host PC's seat never send zero during play (#463).
On a mouse these four behaviours simply never happened.

## Decision

A controller reports **released** as an explicit state beside its vector.

- The player is released when the vector is zero (unchanged, so phones behave
  exactly as before) **or** when the controller's released flag is set.
- PC (mouse or trackpad, for the Online client and the host PC seat): a tap of
  Space toggles released on and off, as if the finger lifted and touched again.
- Gamepad: holding either shoulder button (LB/RB) is released while held;
  clicking either stick (L3/R3) toggles it like Space.
- Every seat starts not released and is reset to not released at round start and
  respawn.
- On the wire, an input packet stays eight bytes (two little-endian float32).
  A client that is released appends one nonzero ninth byte. A packet without it
  (every phone, every older client) means not released. The host tells a remote
  client when its toggle is cleared with `{"t":"release","v":false}`.

## Consequences

- The four release behaviours work on every input device.
- Phones are untouched: no new packet shape, no new control.
- Releasing keeps the vector, so the arm stays where it was aimed while the
  weapon lets go.
- A PC or pad player must learn one more input; the pad lobby tip says "a
  bumper lets go".
- The shoulder buttons are free in rounds; any lobby use of them (cosmetics) is
  unaffected because the release flag does nothing outside a round.

## Alternatives considered

- Held mouse click: conflicts with the captured-mouse model and wearies the hand.
- Arm-to-centre: needs a deadzone the mouse offset has no way to return to.
- Redesigning the weapons around a vector-only input: larger, and leaves phones
  working fine.

## Amendment (issue #481): the action press also throws the boomerang

The release inputs are really one "action press": a PC Space tap, a pad bumper
press or a pad stick click. With the boomerang held, an action press throws it
along the arm's current aim, through the same launch as a flick and under the
same rules (not already out, cooldown over, head not phased); it then does
**not** toggle or hold release, since the boomerang has no release use. With any
other weapon nothing changes. The flick throw stays, phones are unchanged, and
the boomstick stays automatic.

On the wire, the host owns the toggle. An Online client's input frame grows to
ten bytes: byte 8 stays the held-release flag (shoulder held), and byte 9 is a
wrapping 7-bit count of action presses with bit 7 set when the latest press was
a shoulder (a hold: it may throw but never toggles). The host acts when the
count differs from the last one it saw for that seat, so a press is not lost
between packets; the first count after a seat is bound is only adopted. Eight-
and nine-byte frames from phones and older clients carry no press.

## Amendment 2 (issue #485): tap for the weapon's job, hold to unstick

The action button now tells a tap from a hold. A **tap** is down and up within
`TAP_MAX_SEC` (0.25 s) and fires **on key-up**: with the boomerang it throws
(#481), with any other weapon it toggles release (#463). A **hold** is still
down after 0.25 s: the seat counts as released while the button is held, never
throws, and does not toggle on key-up; letting go returns to the previous
toggle state. With the cut-off head's release the existing 1.5 s gridlock
phase-home then unsticks it whatever the weapon, the boomerang included. This
covers PC Space (Online client and host PC seat) and gamepad L3/R3. Bumpers
keep released-while-held from the moment they go down; a bumper tap with the
boomerang throws on key-up. Phones are unchanged.

On the host seat and the pad, ControllerServer times down and up on the game
clock. On the wire the Online client decides tap vs hold itself on key-up, so
the host never needs the timing: byte 9 now counts **taps** (still a wrapping
7-bit counter, bit 7 set when the latest tap was a shoulder, which only ever
throws), so a tap is not lost between packets; and byte 8, the held flag, is
set while a shoulder is down or while Space or L3/R3 has been down past 0.25 s.
The host still owns the toggle and the throw: on a count change it throws the
boomerang, else toggles. Eight- and nine-byte frames still mean no press.

## Amendment 3 (issue #487): button seats do not flick-launch

A seat with an action button (host PC, Online client, gamepad) no longer
launches the grapple or the boomerang by flick: on a mouse, fast drags are how
you swing, so flick launches misfired. `Player.flick_launch_enabled` (default
true) is set false by `ControllerServer._attach()` for `LocalSeat` (host PC and
`PadSeat`) and `RemoteSeat` peers, true for phones, and reset to true on unbind;
bots never bind a seat and keep it. The action tap launches instead: the
boomerang as before (#481), and now the grapple, fired along the arm's aim when
ready and not out through the same `_launch_special()`. A tap while the hook is
out is not a launch, so it falls through to the release toggle and retracts.
Holds are unchanged, and so is every other weapon. Phones are unchanged.
