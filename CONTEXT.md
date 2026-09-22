# Pickfight — Context

Stick Fight's round-based physics brawling, with Getting Over It's pole-swing
as the only way to move.

## Shape of the game

A **match** is a rapid succession of **rounds**. Each round loads a different
**stage**, spawns every **player**, and ends when one player is left alive.
That player scores. First to the match's score target wins.

There are no health bars. Players die by being knocked into a hazard or off
the stage.

## Glossary

| Term | Meaning |
|---|---|
| **Host** | The one machine that runs the simulation and renders the shared screen everyone watches. Authoritative for all game state. |
| **Controller** | A player's phone, running the controller web page, connected to the host over the local network. Sends input only; renders no game state. |
| **Player** | One participant, represented in-game by a body and its arm. Bound 1:1 to a controller for the length of a match. |
| **Arm** | The rigid pole extending from a player's body. The only means of movement — it plants against geometry and pushes or pulls the body. |
| **Swing** | The movement verb: planting the arm and using it to fling, climb, or launch the body. |
| **Input vector** | The 2D vector a controller sends, giving the arm's target angle and extension. Relative — never an absolute screen position. |
| **Player slot** | Implementation-level: the index a controller is bound to in join order, identifying which player it drives. Appears in the host→controller `{"slot":n}` frame and in host diagnostics. A slot is *how* a controller reaches a player; the participant itself is still a **player**. |
| **Knockback** | The impulse applied when players collide above a relative-velocity threshold. The only damage model. |
| **Round** | One stage, played until one player remains. Awards a point. |
| **Match** | A sequence of rounds on rotating stages, ending when a player reaches the score target. |
| **Stage** | One arena layout. Rotates every round. |
| **Weapon** | A stage pickup that modifies attack or movement. Not yet designed. |

## Design intent

Movement should be smooth and learnable, not the deliberate frustration of
Getting Over It — but with a high enough skill ceiling that better movement
meaningfully beats worse movement.

Rapid stage rotation is a feature, not scaffolding: short rounds on varied
geometry create the situational variety that makes a swing-based moveset
interesting.

## Deliberately not decided

- Weapon roster and pickup rules
- Stage roster, authoring format, and rotation order
- Score target and player-count bounds
- Art direction
