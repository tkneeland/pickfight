# Pickfight — Context

Stick Fight's round-based physics brawling, with Getting Over It's pole-swing
as the only way to move.

## Shape of the game

A **session** is an endless succession of **rounds**. Each round loads a
different **stage**, spawns every **player**, and ends when one player is left
alive. That player scores. Nothing ends a session — it runs until people stop
playing, and the tally is forgotten when the game closes.

Players die by being knocked into a hazard, knocked off the stage, or taking
enough damage. There are no health bars; how hurt a player is shows on their
body.

Everyone starts a round holding a pickaxe. The player who won the previous
round is the exception: they keep whatever they were holding.

## Glossary

| Term | Meaning |
|---|---|
| **Host** | The one machine that runs the simulation and renders the shared screen everyone watches. Authoritative for all game state. |
| **Controller** | A player's phone, running the controller web page, connected to the host over the local network. Sends input only; renders no game state. |
| **Player** | One participant, represented in-game by a body and its weapon. Bound 1:1 to a controller. |
| **Weapon** | The pole a player holds. It is their only appendage: their only means of movement, their only means of dealing damage, and their only means of blocking. Reach, weight and responsiveness differ per weapon, so a weapon changes how a player moves as much as how they fight. |
| **Head** | The weapon's solid region — the part that strikes, blocks, and plants against geometry. Its shape and extent are per weapon: a pickaxe's is a nub at the tip, a sword's is most of the blade. |
| **Weight** | How heavy a weapon is. Heavy weapons swing slower but win clashes and fling the body harder; light ones answer the input faster. The one stat that sets a weapon's feel. |
| **Reach** | How far a weapon's head can extend from the body. Also the lever a swing has for movement: short reach makes climbing hard. |
| **Pickup** | A weapon lying on the stage during a round. Touching it with the body swaps it for what the player holds; the old weapon is gone. The only way to get a weapon other than the pickaxe. |
| **Haft** | The rest of the weapon. Collides with nothing. |
| **Swing** | The movement verb: planting the head and using the weapon to fling, climb, or launch the body. |
| **Input vector** | The 2D vector a controller sends, giving the weapon's target angle and extension. Relative — never an absolute screen position. |
| **Roster** | The players currently in the session. A phone that connects joins the roster and enters play at the start of the next round. |
| **Damage** | Accumulates within a round and resets at its end. Dealt by a head striking a player, scaled by how fast the head is moving. |
| **Knockback** | The impulse applied when two players' bodies collide above a relative-velocity threshold. Moves players; deals no damage. |
| **Clash** | Two heads meeting. Neither passes through the other; the heavier, more forceful swing gives way last. |
| **Round** | One stage, played until one player remains. Awards a point. |
| **Session** | The endless run of rounds, from launch to quit. Holds the roster and the score tally. |
| **Stage** | One arena layout. Rotates every round. Declares where players spawn, where the death boundary lies, and how the camera frames it. |
| **Rotation** | The ordered run of stages a session cycles through, one per round, wrapping at the end. |
| **Ring-out** | Leaving the stage into its death boundary. Kills whatever damage a player had taken — stage geometry does not care how healthy anyone is. The other route out of a round is accumulated damage. |

## Design intent

Movement should be smooth and learnable, not the deliberate frustration of
Getting Over It — but with a high enough skill ceiling that better movement
meaningfully beats worse movement. The weapon answers the player's aim
precisely; the difficulty is in what the body attached to it then does.

Because the weapon is both the moveset and the arsenal, picking one up is a
commitment, not an upgrade. A heavy weapon that wins every clash is a liability
on a stage that demands quick climbing — and the stage changes every round.

Rapid stage rotation is a feature, not scaffolding: short rounds on varied
geometry create the situational variety that makes a swing-based moveset
interesting.

## Deliberately not decided

- The full roster of stages beyond the eleven that exist (ADR-0008 settled the
  authoring format: one `.tscn` per stage under `scenes/stages/`).
- Whether the rotation stays sequential now that it is past a handful of
  stages, or becomes a shuffle that never repeats back to back (#20).
- Art direction.
