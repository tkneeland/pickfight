# Pickfight

A local-multiplayer platform fighter that combines **Stick Fight**'s scrappy
physics-based combat with **Getting Over It with Bennett Foddy**'s
pole/hammer movement scheme.

Instead of walking and jumping, each player controls a single arm that
plants against the world and pushes, pulls, or swings their body around.
Colliding into another player hard enough knocks them back; falling off
the arena resets your position.

Built with Godot 4.6.

## Status

Early prototype. `scenes/Main.tscn` has one arena and two test players so
the pole-swing movement and the knockback-on-collision combat can be felt
out before anything else (art, levels, weapons, win conditions) gets built
on top.

## Controls (prototype only, not final)

- **Player 1** — mouse. The arm points at and reaches for your cursor;
  moving the cursor away plants the tip and pulls/pushes your body toward
  or past it, like the hammer in Getting Over It.
- **Player 2** — keyboard (A/D rotate the arm, W/S extend/retract). This
  is a temporary stand-in for testing collisions locally, not a real
  control scheme.

## Open design question: local multiplayer input

Getting Over It's movement is precise and analog, and naturally maps to a
single mouse or a single analog stick — it doesn't work with two players
sharing one mouse. Stick Fight, on the other hand, is built around
multiple players on one keyboard. To combine them for real local
multiplayer, each player likely needs their own **gamepad** (stick angle +
magnitude standing in for the mouse vector), rather than keyboard-only
input. That decision — gamepad-only vs. keyboard-with-some-tradeoff — is
still open and should be settled before building out full multiplayer.

## Project layout

```
scenes/   .tscn scene files (Main, Arena, Player)
scripts/  GDScript sources
```
