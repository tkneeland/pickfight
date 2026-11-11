extends RefCounted

## Teams mode (issue #236, ADR-0018): the teams and who goes on which.
##
## A Teams match has two, three or four teams (#1200): Red (0), Blue (1), Green (2)
## and Yellow (3), in that order; -1 means no team, which is every player in a
## free-for-all. The host picks how many (`team_count`); Soccer and Capture the
## Flag are always two. The host phone picks the mode in the
## lobby, each phone may pick a team, and `assign()` sorts out the rest.
## RoundManager owns the mode and the assignment; this only holds the rules,
## so the lobby screen, the name tags and the scenarios all agree on them.
##
## Preloaded by path (CLAUDE.md), never referenced by a `class_name`.

const NONE: int = -1
const RED: int = 0
const BLUE: int = 1
const GREEN: int = 2
const YELLOW: int = 3
## The teams that exist (the most a match can have), not how many one has: every
## drawing path checks a team against this, the match's own count is `team_count`.
const COUNT: int = 4
const MIN_COUNT: int = 2
const MAX_COUNT: int = 4
const NAMES: PackedStringArray = ["RED", "BLUE", "GREEN", "YELLOW"]
const COLORS: Array[Color] = [Color(0.95, 0.27, 0.27, 1.0), Color(0.3, 0.55, 1.0, 1.0),
	Color(0.25, 0.8, 0.35, 1.0), Color(0.98, 0.8, 0.15, 1.0)]

## "RED", "BLUE", "GREEN" or "YELLOW", or "" for no team.
static func team_name(team: int) -> String:
	return TranslationServer.translate("TEAM_" + NAMES[team]) if team >= 0 and team < COUNT else ""

## The team's colour, or white for no team.
static func team_color(team: int) -> Color:
	return COLORS[team] if team >= 0 and team < COUNT else Color.WHITE

## The team's letter, for markers that must not rest on colour alone (#752): the first character of its
## translated name ("R" for Red in English), or "" for no team. Two teams whose names start alike in a
## language (Spanish Azul and Amarillo, Portuguese Vermelho and Verde) must still differ, so a later team
## whose first character an earlier team already has takes its next character instead.
static func team_letter(team: int) -> String:
	if team_name(team).is_empty():
		return ""
	var locale: String = TranslationServer.get_locale()
	if not _letter_cache.has(locale):
		var letters: PackedStringArray = PackedStringArray()
		for t: int in COUNT:
			var override: String = str(LETTER_OVERRIDES.get(locale, {}).get(t, ""))
			letters.append(override if not override.is_empty() else _letter_of(t, letters))
		_letter_cache[locale] = letters
	return _letter_cache[locale][team]

## Locale -> team -> letter where the first-character rule gives an unclear one: German Gelb (G is Gruen's),
## Spanish Amarillo (A is Azul's) and Portuguese Amarelo (A is Azul's) take L, a letter in each name.
const LETTER_OVERRIDES: Dictionary = {
	"de": {3: "L"},
	"es": {3: "L"},
	"pt_BR": {3: "L"},
}

## Letters per locale, filled on first use (the translated names do not change while a locale is set).
static var _letter_cache: Dictionary = {}

## `team`'s letter given the `taken` letters of the teams before it.
static func _letter_of(team: int, taken: PackedStringArray) -> String:
	var name_text: String = team_name(team)
	for i: int in name_text.length():
		var letter: String = name_text.substr(i, 1).to_upper()
		if not taken.has(letter):
			return letter
	return name_text.left(1).to_upper()

## `wanted` as a team count: 2 to 4, and 2 for `mode_id` when that mode has two sides only
## (Soccer, Capture the Flag).
static func clamp_count(wanted: int, mode_id: String = "") -> int:
	return clampi(wanted, MIN_COUNT, preload("res://scripts/GameModes.gd").max_teams(mode_id))

## Who goes on which team, as slot -> team, for every slot in `roster`, over the
## first `team_count` teams:
## 1. a slot `keep` already has on a team stays there (a match under way);
## 2. then every pick in `picks` (slot -> team) is honoured;
## 3. then everyone else goes, one at a time in roster order, to whichever
##    team is smallest right now, the lowest-numbered on a tie: phones first, then
##    the bots in `bots`, so bots fill whichever teams the humans left short.
## Picks are never overruled, so two phones that both pick Red leave Blue
## empty: RoundManager will not start a match like that. A pick or kept team
## outside the count (a pick of Yellow after the host went back to two teams) counts as Auto.
static func assign(roster: Array[int], picks: Dictionary, bots: Array[int], keep: Dictionary = {}, team_count: int = MIN_COUNT) -> Dictionary:
	var teams: Dictionary = {}
	var counts: Array[int] = []
	counts.resize(team_count)
	counts.fill(0)
	for slot: int in roster:
		var kept: int = int(keep.get(slot, NONE))
		if kept >= 0 and kept < team_count:
			teams[slot] = kept
			counts[kept] += 1
	for slot: int in roster:
		var pick: int = int(picks.get(slot, NONE))
		if not teams.has(slot) and pick >= 0 and pick < team_count:
			teams[slot] = pick
			counts[pick] += 1
	for bot_pass: bool in [false, true]:
		for slot: int in roster:
			if teams.has(slot) or bots.has(slot) != bot_pass:
				continue
			var team: int = 0
			for candidate: int in team_count:
				if counts[candidate] < counts[team]:
					team = candidate
			teams[slot] = team
			counts[team] += 1
	return teams

## How many of `teams`' slots are on each of the first `team_count` teams.
static func counts(teams: Dictionary, team_count: int = MIN_COUNT) -> Array[int]:
	var out: Array[int] = []
	out.resize(team_count)
	out.fill(0)
	for slot: Variant in teams:
		var team: int = int(teams[slot])
		if team >= 0 and team < team_count:
			out[team] += 1
	return out

## Whether every one of the first `team_count` teams has somebody on it.
static func all_manned(teams: Dictionary, team_count: int = MIN_COUNT) -> bool:
	for n: int in counts(teams, team_count):
		if n == 0:
			return false
	return true

## Whether the first `team_count` teams do not all have the same number of players.
static func uneven(teams: Dictionary, team_count: int = MIN_COUNT) -> bool:
	var c: Array[int] = counts(teams, team_count)
	return c.min() != c.max()
