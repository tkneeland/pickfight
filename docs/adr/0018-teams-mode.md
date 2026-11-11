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
- There are two teams, Red and Blue (amended by #1200: the host may raise this
  to three or four, adding Green and Yellow, see Amendment). Each phone may pick one, and anyone who
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
  Since #1199 a pick is not phone-only: the lobby's player card has a switch
  (host mouse for any human seat, an Online joiner for its own), and a gamepad's
  X sends the same pick through `ControllerServer.set_slot_team_pick`. Uneven
  team sizes never block Start (the lobby only notes it); an empty team still does.
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

## Amendment: Green and Yellow (#1200)

The host may play with 2, 3 or 4 teams. Everything above holds for N teams.

- **Team ids.** 0 Red, 1 Blue, 2 Green, 3 Yellow, -1 none. `Teams.COUNT` is
  the four teams that exist; `MIN_COUNT` 2 and `MAX_COUNT` 4 bound a match.
- **The count is a host setting.** `HostSettings.team_count` (saved, default 2)
  is set by the `team_count` host command: the Host panel's "N Teams" button
  next to the Teams switch (cycles 2, 3, 4), the gamepad menu, the phone
  menu's `teamcount` message (host only) and the Online host row. Lobby only.
- **Soccer and Capture the Flag stay at two.** `GameModes.max_teams()` is 2
  for them (`two_teams_only`). `ControllerServer.team_count()` is the
  effective count, so the host's stored choice survives a trip through Soccer;
  the button is greyed out there. Classic, King of the Hill, Sudden Death and
  Stock take up to four.
- **Balance.** `assign()` takes the match's count: a pick or kept team outside
  it is treated as auto, and everyone else goes to the smallest team, lowest
  index on a tie. Start needs every team in the count manned (`all_manned`);
  uneven sizes still only note (#1199). Bots fill the smallest team.
- **Lobby state.** Carries `team_count`, `team_scores` (sliced to the count)
  and `two_teams_only`, so the Online client and phones draw the same cards,
  switch cycle (`(team + 1) % count`) and host row. The snapshot already
  carries the team as a byte.
- **Letters.** The colour-blind letter is the first character of the
  translated name, except that a later team whose first character an earlier
  team has takes its next character, so letters are distinct in every language.
  Where that next character would be unclear, `Teams.LETTER_OVERRIDES` picks one
  from the name: Yellow is L in German (Gelb), Spanish (Amarillo) and
  Portuguese (Amarelo).
- **Scoring and screens.** Round and match wins are counted per team over the
  count. The score label and banner list every team (two teams keep
  `RED n - m BLUE`). The victory screen, podium and announcer name the winner:
  two new announcer lines, "Green team wins!" and "Yellow team wins!".

## Consequences

- ADR-0004's "one point to the last player standing" still holds for the
  free-for-all. In Teams the point goes to the team instead. Nothing else in
  the round loop, the stage rotation, the pickups or the modifiers changes.
- A player who joins mid-match is balanced onto the smaller team at the next
  round start and stays on it until the match ends.
- A projectile whose shooter lacks `land_projectile_hit` falls back to
  `take_damage()` and ignores teams. Every player has that method, so this
  only matters for test doubles.
