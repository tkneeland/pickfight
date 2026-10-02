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
| **Player** | One participant, represented in-game by a body and its weapon. Bound 1:1 to a controller, a remote seat, or the host-PC seat. |
| **Weapon** | The pole a player holds. It is their only appendage: their only means of movement, their only means of dealing damage, and their only means of blocking. Reach, weight and responsiveness differ per weapon, so a weapon changes how a player moves as much as how they fight. |
| **Head** | The weapon's solid region — the part that strikes, blocks, and plants against geometry. Its shape and extent are per weapon: a pickaxe's is a nub at the tip, a sword's is most of the blade. |
| **Weight** | How heavy a weapon is. Heavy weapons swing slower but win clashes and fling the body harder; light ones answer the input faster. The one stat that sets a weapon's feel. |
| **Reach** | How far a weapon's head can extend from the body. Also the lever a swing has for movement: short reach makes climbing hard. |
| **Pickup** | A weapon lying on the stage during a round. Touching it with the body swaps it for what the player holds; the old weapon is gone. The only way to get a weapon other than the pickaxe. |
| **Haft** | The rest of the weapon. Collides with nothing. |
| **Swing** | The movement verb: planting the head and using the weapon to fling, climb, or launch the body. |
| **Input vector** | The 2D vector a controller sends, giving the weapon's target angle and extension. Relative — never an absolute screen position. |
| **Roster** | The players currently in the session. A phone that connects joins the roster and enters play at the start of the next round. |
| **Damage** | Accumulates within a round and resets at its end. Dealt by a head striking a player, scaled by how fast the head is moving, or by a bullet from a weapon that fires, at a flat amount (ADR-0014). Another player's head in a bullet's path blocks it, and a blocked bullet deals nothing. |
| **Knockback** | The impulse applied when two players' bodies collide above a relative-velocity threshold. Moves players; deals no damage. |
| **Clash** | Two heads meeting. Neither passes through the other; the heavier, more forceful swing gives way last. |
| **Round** | One stage, played until one player remains (in a Teams match, until one team remains). Awards a point: to that player, or in a Teams match to that team. |
| **Team** | One of the two sides, Red and Blue, in a Teams match: the **Format** the host phone picks in the lobby instead of the default free-for-all, fixed for the whole match. Players pick a team on their phone or are balanced onto the smaller one; bots fill whichever team is short. Teammates cannot damage each other (they still knock each other about), hazards hurt everyone, and the round goes to the team with anyone left standing. Each player keeps their own colour and gains a team ring (ADR-0018). |
| **Session** | The endless run of rounds, from launch to quit. Holds the roster and the score tally. |
| **Stage** | One arena layout. Rotates every round. Declares where players spawn, where the death boundary lies, and how the camera frames it. |
| **Rotation** | The run of stages a session cycles through, one per round: a fixed opener (`stage_scenes[0]`, round 1 of each match since #200), then shuffled bags covering the whole roster with no stage playing twice in a row (ADR-0011). |
| **Ring-out** | Leaving the stage into its death boundary. Kills whatever damage a player had taken — stage geometry does not care how healthy anyone is. The other route out of a round is accumulated damage. |
| **Rise** | The stage's death boundary climbing up through it once a round's grace period is over, so a round cannot stall with everyone holding out somewhere safe. Only the floor rises; hazards stay put. Starts afresh with every round. |
| **Buzz** | A short piece of feedback a player's own phone gives them: a vibration, plus a flash of the phone's screen in their colour (the only kind iOS can give). Sent by the host for four things only, each to the one phone it concerns: a round **win**, being **eliminated**, being **struck** for damage, and landing a **hit** that dealt damage (ADR-0013). |
| **Format** | Who is on whose side for a whole match: Free-for-all (the default) or Teams. Chosen in the lobby and combinable with every **Mode**. Not itself a mode. |
| **Mode** | How a round is won, picked in the lobby for the whole match: Classic (last one standing), King of the Hill, Hot Potato, Sudden Death (one damaging hit eliminates, from the first second of every round) or Stock (1-10 lives per player per round, host's choice; no Rise, an optional time limit instead). Applies in either **Format**, except Hot Potato, which is Free-for-all only. Whether the **Rise** runs depends on the mode: on in Classic and Sudden Death (sooner and faster there), off in Stock, King of the Hill and Hot Potato, whose own rules end the round. Each mode can rule out modifiers that make no sense with it. Different from a **Modifier**, which is a one-round twist. |
| **Modifier** | A twist on the rules for one round only, such as low gravity or big heads. Some rounds roll one at random, and its name is shown on screen as the round starts. It is undone when the round ends (ADR-0015). |
| **Sound set** | The family of sounds a weapon makes: its hit, and for a weapon that fires, its shot. Each weapon has its own. How hard something happened sets how loud and how low a sound plays. Sounds play only on the host's shared screen, never on a phone (ADR-0016). |
| **Host-PC seat** | A seat played with the host machine's own mouse ("Play on this PC", toggled on the host screen, never automatic). It holds a player slot like a controller does but has no phone; it never becomes the host player. |
| **Remote seat** | A player joining from a remote PC over the internet, via a relay server. Sends the same relative input as a controller, but unlike a controller it renders the match, from world snapshots the host streams to it. Same roster, same single simulation on the host (ADR-0019). |
| **Room code** | Four letters a remote player types into the game's join screen to reach a host's match. Issued by the relay (ADR-0019). |
| **Relay** | The public server that connects a host to its remote seats by room code and passes messages between them without reading them (ADR-0019). |

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

- The full roster of stages beyond the 24 that exist (ADR-0008 settled the
  authoring format: one `.tscn` per stage under `scenes/stages/`).
- Art direction.
