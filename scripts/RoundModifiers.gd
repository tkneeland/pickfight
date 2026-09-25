extends RefCounted

## Round modifiers (issue #50, ADR-0015): a random twist on some rounds.
##
## Each modifier is a small object that applies itself to one round -- its
## players, its stage and the `RoundManager` running it -- remembers exactly
## what it changed, and puts every bit of it back on `undo()`. `RoundManager`
## rolls at most one per round, applies it right after spawning the round's
## players and undoes it the moment the round ends, so the next round always
## starts from the game as authored.
##
## Consumers `preload()` this script by path rather than naming a
## `class_name`: a fresh clone has no global class cache (CLAUDE.md, #21).
##
## **When `apply()` runs matters.** `Player.start_round()` defers its rig
## build, and `RoundManager` arms the rising kill zone after spawning.
## `apply()` runs in between, in the same frame, so:
## - the rig is built from the player's (already modified) `gravity_scale`
##   and from its modified weapon stats, with no rebuild needed;
## - the kill zone is armed from the (already shortened) deadline.
## `undo()` runs once every player has left the round and gone inert, with
## its rig freed, so there is nothing live left to rebuild either.
##
## Every modifier changes only a player's *effective* physics, never the
## `WeaponStats` resource a player holds: `Player.weapon_stats` stays the
## pristine shared resource, so the round's winner carries the real weapon
## into the next round, and a pickup collected mid-round is modified too.

const LOW_GRAVITY: String = "low_gravity"
const HEAVY_WEAPONS: String = "heavy_weapons"
const BIG_HEADS: String = "big_heads"
const FAST_LAVA: String = "fast_lava"
const SLIPPERY_FLOOR: String = "slippery_floor"

## Every modifier a round can roll, in a fixed order so a seeded roll picks
## the same one every run.
const IDS: PackedStringArray = [LOW_GRAVITY, HEAVY_WEAPONS, BIG_HEADS, FAST_LAVA, SLIPPERY_FLOOR]

## Low gravity: players and their weapons fall at this fraction of their
## usual gravity. Half, not less: a swing still has to come back down onto
## something, and the kill zone is only ever below.
const LOW_GRAVITY_SCALE: float = 0.5

## Heavy weapons: every weapon's mass, and the force its drive can push with.
## Force is scaled less than mass, so a heavy weapon answers the input a
## little slower but hits a clash, and flings the body, harder -- the
## glossary's "weight", turned up.
const HEAVY_MASS_SCALE: float = 1.6
const HEAVY_FORCE_SCALE: float = 1.4

## Big heads: every head circle's offset and radius, and every point of the
## head's drawn art, scaled together about the head's anchor. Scaling a
## circle and the polygon around it by the same factor about the same point
## keeps the circle inside, so ADR-0010's guarantee holds by construction.
## Reach is left alone: the head gets bigger, not further away.
const BIG_HEAD_SCALE: float = 1.5

## Fast lava: the rising kill zone's grace and its rise deadline (ADR-0012)
## are scaled by these. At the rotation's 50 s and 80 s: 20 s and 40 s.
const FAST_LAVA_GRACE_SCALE: float = 0.4
const FAST_LAVA_RISE_SCALE: float = 0.5

## Slippery floor: the friction a player's body slides on. Godot combines
## two bodies' friction by taking the lower, so a low value on the body is
## a low value against every floor. Heads keep theirs: a head that slid off
## everything it planted on would take away the only way to move. That
## includes the grip a head gets on terrain (issue #110, `Player`), which
## never reaches a player's body, so a slippery body stays slippery.
const SLIPPERY_FRICTION: float = 0.05

## The on-screen name of modifier `id`, or "" for an unknown id.
static func title_of(id: String) -> String:
	match id:
		LOW_GRAVITY:
			return "LOW GRAVITY"
		HEAVY_WEAPONS:
			return "HEAVY WEAPONS"
		BIG_HEADS:
			return "BIG HEADS"
		FAST_LAVA:
			return "FAST LAVA"
		SLIPPERY_FLOOR:
			return "SLIPPERY FLOOR"
	return ""

## A fresh, unapplied modifier for `id`, or null for an unknown id.
static func create(id: String) -> RoundModifier:
	var modifier: RoundModifier = null
	match id:
		LOW_GRAVITY:
			modifier = LowGravity.new()
		HEAVY_WEAPONS:
			modifier = HeavyWeapons.new()
		BIG_HEADS:
			modifier = BigHeads.new()
		FAST_LAVA:
			modifier = FastLava.new()
		SLIPPERY_FLOOR:
			modifier = SlipperyFloor.new()
	if modifier != null:
		modifier.id = id
		modifier.title = title_of(id)
	return modifier

## One modifier. `apply()` and `undo()` are each safe to call twice; only the
## first of each does anything, and `undo()` before `apply()` does nothing.
class RoundModifier extends RefCounted:
	var id: String = ""
	var title: String = ""
	var _applied: bool = false
	var _round: Node
	var _players: Array = []
	var _stage: Node

	## `players` are the ones in this round; `stage` is its stage instance
	## (may be null); `round_manager` is the node running the round.
	func apply(round_manager: Node, players: Array, stage: Node) -> void:
		if _applied:
			return
		_applied = true
		_round = round_manager
		_players = players.duplicate()
		_stage = stage
		_apply()

	func undo() -> void:
		if not _applied:
			return
		_undo()
		_applied = false
		_round = null
		_players.clear()
		_stage = null

	func is_applied() -> bool:
		return _applied

	## The round's players that still exist; a scenario tearing its stage
	## down can free them before the round ends.
	func _live_players() -> Array:
		var live: Array = []
		for player: Variant in _players:
			if player != null and is_instance_valid(player):
				live.append(player)
		return live

	func _apply() -> void:
		pass

	func _undo() -> void:
		pass

class LowGravity extends RoundModifier:
	var _saved: Dictionary = {}

	func _apply() -> void:
		for player: Variant in _live_players():
			_saved[player] = player.gravity_scale
			player.gravity_scale = player.gravity_scale * LOW_GRAVITY_SCALE

	func _undo() -> void:
		for player: Variant in _live_players():
			if _saved.has(player):
				player.gravity_scale = _saved[player]
		_saved.clear()

## Shared by the two weapon modifiers: hands each player a function its rig
## runs the held weapon's stats through (`Player.set_weapon_stats_modifier`),
## and takes it back on undo.
class WeaponStatsModifier extends RoundModifier:
	func _apply() -> void:
		for player: Variant in _live_players():
			player.set_weapon_stats_modifier(_modified)

	func _undo() -> void:
		for player: Variant in _live_players():
			player.set_weapon_stats_modifier(Callable())

	## A modified copy of `stats`; never `stats` itself, which is a shared
	## resource every player and pickup holding that weapon points at.
	func _modified(stats: Resource) -> Resource:
		return stats.duplicate()

class HeavyWeapons extends WeaponStatsModifier:
	func _modified(stats: Resource) -> Resource:
		var heavy: Resource = stats.duplicate()
		heavy.mass = stats.mass * HEAVY_MASS_SCALE
		heavy.max_drive_force = stats.max_drive_force * HEAVY_FORCE_SCALE
		return heavy

class BigHeads extends WeaponStatsModifier:
	func _modified(stats: Resource) -> Resource:
		var big: Resource = stats.duplicate()
		var offsets: PackedVector2Array = stats.head_circle_offsets.duplicate()
		for i in offsets.size():
			offsets[i] = offsets[i] * BIG_HEAD_SCALE
		var radii: PackedFloat32Array = stats.head_circle_radii.duplicate()
		for i in radii.size():
			radii[i] = radii[i] * BIG_HEAD_SCALE
		var outline: PackedVector2Array = stats.art_outline.duplicate()
		for i in outline.size():
			outline[i] = outline[i] * BIG_HEAD_SCALE
		big.head_circle_offsets = offsets
		big.head_circle_radii = radii
		big.art_outline = outline
		# The boomstick's bullet grows with its head (owner, hackathon playtest).
		big.projectile_radius = stats.projectile_radius * BIG_HEAD_SCALE
		return big

class FastLava extends RoundModifier:
	var _saved_grace: float = 0.0
	var _saved_rise: float = 0.0

	func _apply() -> void:
		if _round == null:
			return
		_saved_grace = _round.kill_zone_grace_sec
		_saved_rise = _round.kill_zone_rise_sec
		_round.kill_zone_grace_sec = _saved_grace * FAST_LAVA_GRACE_SCALE
		_round.kill_zone_rise_sec = _saved_rise * FAST_LAVA_RISE_SCALE

	func _undo() -> void:
		if _round == null or not is_instance_valid(_round):
			return
		_round.kill_zone_grace_sec = _saved_grace
		_round.kill_zone_rise_sec = _saved_rise

class SlipperyFloor extends RoundModifier:
	## Whatever each player had before, which may be null (none authored).
	var _saved: Dictionary = {}

	func _apply() -> void:
		var material := PhysicsMaterial.new()
		material.friction = SLIPPERY_FRICTION
		for player: Variant in _live_players():
			_saved[player] = player.physics_material_override
			player.physics_material_override = material

	func _undo() -> void:
		for player: Variant in _live_players():
			if _saved.has(player):
				player.physics_material_override = _saved[player]
		_saved.clear()
