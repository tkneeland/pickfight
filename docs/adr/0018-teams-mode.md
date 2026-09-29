# 18. Teams mode

- Status: Accepted
- Date: 2026-09-29

## Context

Issue #236 asks for a Teams mode beside the free-for-all. Until now a round
was won by the last player standing and scored that player a point
(ADR-0004), and a lobby match (#120) was first to N of those points. The
owner's default decisions:

- The host phone picks *Free-for-all* (the default) or *Teams* in the lobby.
  It never changes mid-match.
- There are two teams, Red and Blue. Each phone may pick one, and anyone who
  has not picked is auto-balanced. A match cannot start with a team empty.
  Bots fill the smaller team.
- Friendly fire is off for strikes, projectiles, the flail ball and the
  grapple. Hazards and the lava still hurt everyone.
- A round goes to the team with anyone left standing. A match is first to
  the existing "first to N", counted in team round wins.
- Players keep their identity colour and gain a team marker. The screens
  and the announcer name the winning team. The kill feed and the awards
  still credit individuals.
- A free-for-all must be unchanged when the toggle is off.

## Decision

- **The rules live in one small script, `scripts/Teams.gd`.** It holds the
  names, the colours and `assign()`:
  1. a player already on a team in this match stays there;
  2. every phone's pick is honoured;
  3. the rest go, one at a time, onto the smaller team (Red on a tie),
     phones before bots.

  So bots fill whichever team the phones leave short. A pick is never
  overruled: if both phones pick Red, Blue stays empty and the lobby waits.
- **The mode is fixed when the countdown runs out.** The host phone sends
  `{"t":"mode","v":"ffa"|"teams"}`, and ControllerServer heeds it only from
  the host and only in the lobby, countdown and victory phases. Any phone
  sends `{"t":"team","v":0|1|-1}` (-1 is Auto) in the lobby or the
  countdown. RoundManager reads both when a match begins. A countdown needs
  both teams manned, and a change of mode or teams cancels it.
- **Protocol, backward-compatible.** Both messages are new, and an old host
  ignores them. The lobby state gains keys only while Teams is chosen or
  being played:
  - `mode: "teams"`
  - `teams: true`
  - each player's `team`, plus their `pick` in the lobby
  - `team_scores`
  - `winner_team`

  A free-for-all state has exactly the keys it always had, and an old page
  just ignores the new ones.
- **Friendly fire is off at one choke point, `Player.is_teammate()`.** Every
  weapon hit lands through one of three places:
  - `_land_strike` (head strikes)
  - `land_projectile_hit` (the bullet, the grapple hook, the boomerang)
  - `_land_ball_strike` (the flail)

  Each returns before dealing damage or reporting the hit when the victim
  is a teammate. That means no damage, no hitmarker and no KO credit.
  `team` is -1 for everyone in a free-for-all, so `is_teammate()` is always
  false there, and nothing else changes. Hazards, falling rocks, meteors,
  the kill zone and the lava call `take_damage()` / `eliminate()` directly,
  so they hurt everyone.
- **Knockback stays between teammates.** The body-on-body knockback, the
  bullet's and hook's shove, the boomerang's push and the flail ball's
  shove all still apply. They are physics applied before the damage call.
  Being able to bump or shove a teammate (into the lava, even) keeps the
  stage lively, and it keeps the change to the weapon scripts at zero.
- **A round ends when at most one team is standing**, and that team scores
  a point. All its survivors keep their weapons, as a lone winner does. An
  abandoned round, or one a kick decided, is won by nobody, as before. The
  #163 same-frame guard works per team: the team left standing is recorded
  the moment an elimination leaves only it. The team to reach "first to N"
  wins the match. Personal scores are not added to.
- **Readability.**
  - Each player keeps their colour. On the host screen, the name tag's
    outline turns the team colour and a ring in that colour is drawn round
    the body.
  - Each phone gets a second, inner rim in its team colour and a "You're on
    Red team" line.
  - The lobby shows two rosters.
  - The scoreboard shows each player's team points and team name, and the
    score label reads `RED: n  BLUE: m`.
  - The kill-feed banner reads "RED TEAM WINS".
  - The victory screen reads "RED TEAM WINS!".
  - The announcer says "Red team wins!" or "Blue team wins!".
  - The kill feed, KO credit and awards stay per player.

## Consequences

- ADR-0004's "one point to the last player standing" still holds for the
  free-for-all. In Teams the point goes to the team instead. Nothing else in
  the round loop, the stage rotation, the pickups or the modifiers changes.
- A player who joins mid-match is balanced onto the smaller team at the next
  round start and stays on it until the match ends.
- A projectile whose shooter lacks `land_projectile_hit` falls back to
  `take_damage()` and ignores teams. Every player has that method, so this
  only matters for test doubles.
