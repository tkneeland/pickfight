extends RefCounted

## Teams mode (issue #236, ADR-0018): the two teams and who goes on which.
##
## A Teams match has two teams, Red (0) and Blue (1); -1 means no team, which
## is every player in a free-for-all. The host phone picks the mode in the
## lobby, each phone may pick a team, and `assign()` sorts out the rest.
## RoundManager owns the mode and the assignment; this only holds the rules,
## so the lobby screen, the name tags and the scenarios all agree on them.
##
## Preloaded by path (CLAUDE.md), never referenced by a `class_name`.

const NONE: int = -1
const RED: int = 0
const BLUE: int = 1
const COUNT: int = 2
const NAMES: PackedStringArray = ["RED", "BLUE"]
const COLORS: Array[Color] = [Color(0.95, 0.27, 0.27, 1.0), Color(0.3, 0.55, 1.0, 1.0)]

## "RED" or "BLUE", or "" for no team.
static func team_name(team: int) -> String:
	return TranslationServer.translate("TEAM_" + NAMES[team]) if team >= 0 and team < COUNT else ""

## The team's colour, or white for no team.
static func team_color(team: int) -> Color:
	return COLORS[team] if team >= 0 and team < COUNT else Color.WHITE

## Who goes on which team, as slot -> team, for every slot in `roster`:
## 1. a slot `keep` already has on a team stays there (a match under way);
## 2. then every pick in `picks` (slot -> RED or BLUE) is honoured;
## 3. then everyone else goes, one at a time in roster order, to whichever
##    team is smaller right now, Red on a tie: phones first, then the bots in
##    `bots`, so bots fill whichever team the humans left short.
## Picks are never overruled, so two phones that both pick Red leave Blue
## empty: RoundManager will not start a match like that.
static func assign(roster: Array[int], picks: Dictionary, bots: Array[int], keep: Dictionary = {}) -> Dictionary:
	var teams: Dictionary = {}
	var counts: Array[int] = [0, 0]
	for slot: int in roster:
		var kept: int = int(keep.get(slot, NONE))
		if kept == RED or kept == BLUE:
			teams[slot] = kept
			counts[kept] += 1
	for slot: int in roster:
		var pick: int = int(picks.get(slot, NONE))
		if not teams.has(slot) and (pick == RED or pick == BLUE):
			teams[slot] = pick
			counts[pick] += 1
	for bot_pass: bool in [false, true]:
		for slot: int in roster:
			if teams.has(slot) or bots.has(slot) != bot_pass:
				continue
			var team: int = RED if counts[RED] <= counts[BLUE] else BLUE
			teams[slot] = team
			counts[team] += 1
	return teams

## How many of `teams`' slots are on each team, as [red, blue].
static func counts(teams: Dictionary) -> Array[int]:
	var out: Array[int] = [0, 0]
	for slot: Variant in teams:
		var team: int = int(teams[slot])
		if team == RED or team == BLUE:
			out[team] += 1
	return out

## Whether both teams have somebody on them.
static func both_manned(teams: Dictionary) -> bool:
	var c: Array[int] = counts(teams)
	return c[RED] > 0 and c[BLUE] > 0
