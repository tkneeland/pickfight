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
## The one exception is Weapon roulette (issue #147), whose whole point is to
## change the weapon held: it hands every player back the weapon they started
## the round with on `undo()`, so the next round still starts as authored.
##
## Modifiers that act on a clock (Weapon roulette, Meteor shower) own a Timer
## under the `RoundManager` for the round and free it on `undo()`; meteors are
## `Meteor.gd` nodes on the stage, cleared on `undo()` too.

const LOW_GRAVITY: String = "low_gravity"
const HEAVY_WEAPONS: String = "heavy_weapons"
const BIG_HEADS: String = "big_heads"
const FAST_LAVA: String = "fast_lava"
const SLIPPERY_FLOOR: String = "slippery_floor"
const TINY_WEAPONS: String = "tiny_weapons"
const WEAPON_ROULETTE: String = "weapon_roulette"
const METEOR_SHOWER: String = "meteor_shower"
const BOUNCY: String = "bouncy"
const DOUBLE_DAMAGE: String = "double_damage"

const PickupWeaponsScript := preload("res://scripts/PickupWeapons.gd")
const FallingRockScript := preload("res://scripts/FallingRock.gd")
const MeteorScript := preload("res://scripts/Meteor.gd")

## Every modifier a round can roll, in a fixed order so a seeded roll picks
## the same one every run.
const IDS: PackedStringArray = [LOW_GRAVITY, HEAVY_WEAPONS, BIG_HEADS, FAST_LAVA, SLIPPERY_FLOOR,
	TINY_WEAPONS, WEAPON_ROULETTE, METEOR_SHOWER, BOUNCY, DOUBLE_DAMAGE]

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

## Tiny weapons (issue #147): Big heads turned the other way, plus a shorter
## haft. Every head circle's offset and radius and every point of the art are
## scaled about the anchor (so the circles stay inside the art, ADR-0010), and
## the haft's full reach is scaled too. The shortest reach is left alone: it is
## what keeps a wound-in head clear of its own body.
const TINY_HEAD_SCALE: float = 0.6
const TINY_REACH_SCALE: float = 0.6

## Weapon roulette (issue #147): every this many seconds, every player still
## in the round is handed the same weapon, drawn from the whole roster -- the
## pickups' list (`PickupWeapons.WEAPON_PATHS`, so a new weapon joins the draw
## by being added there) plus the pickaxe -- and never the one the last swap
## handed out, so a swap always shows. At round end each player gets back the
## weapon they walked into the round with.
const ROULETTE_INTERVAL_SEC: float = 10.0

## Meteor shower (issue #147): a meteor every `METEOR_INTERVAL_SEC`, starting
## `METEOR_HEIGHT` above the stage's highest spawn point at a random x across
## the spawns' span widened by `METEOR_X_MARGIN` each side, flying down at
## `METEOR_FALL_SPEED` with up to `METEOR_DRIFT_SPEED` of sideways drift.
## A hit is a flat `METEOR_DAMAGE` and a knock of `METEOR_KNOCK_SPEED`: enough
## to matter, well short of a kill on its own -- the ring-out is still the
## threat. 900 px/s is 15 px a tick at 60 Hz, well under the 32 px meteor plus
## the thinnest (24 px) platform, so nothing is stepped through.
const METEOR_INTERVAL_SEC: float = 0.7
const METEOR_HEIGHT: float = 800.0
const METEOR_X_MARGIN: float = 250.0
const METEOR_FALL_SPEED: float = 900.0
const METEOR_DRIFT_SPEED: float = 180.0
const METEOR_RADIUS: float = 16.0
const METEOR_DAMAGE: float = 12.0
const METEOR_KNOCK_SPEED: float = 650.0
## On a stage with a view rect (`Stage.get_view_rect()`, issue #144) meteors
## instead start this far above the top of the view, at a random x across the
## whole view (issue #162), so they always fall in from out of sight and reach
## every part of a large stage. The margin is more than the meteor's size,
## so it is never already on screen when it appears.
const METEOR_VIEW_MARGIN: float = 80.0
## How far below the lowest spawn a meteor that met nothing is dropped.
const METEOR_DROP_BELOW: float = 2000.0

## Bouncy (issue #147): the bounce on every player's body. Godot adds two
## bodies' bounces together (capped at 1), and terrain has none authored, so
## this is the bounce against every floor, wall and platform, and a player
## meeting another bouncy player rebounds fully. Friction is kept as it was.
const BOUNCY_BOUNCE: float = 0.85

## Double Damage (issue #147): every source of damage to a player, doubled --
## weapon strikes and bullets through the held weapon's effective stats, and
## the stage's falling rocks through their `damage`. A strike is still capped
## at `Player.MAX_STRIKE_DAMAGE` per hit.
const DOUBLE_DAMAGE_SCALE: float = 2.0

## The on-screen name of modifier `id`, or "" for an unknown id. Every title
## is in Title Case (issue #162), set by "Double Damage", the one the owner
## named exactly. `Announcer.modifier_line` lower-cases a title and joins its
## words with "_" to find the clip, so the casing never changes the line.
static func title_of(id: String) -> String:
	match id:
		LOW_GRAVITY:
			return "Low Gravity"
		HEAVY_WEAPONS:
			return "Heavy Weapons"
		BIG_HEADS:
			return "Big Heads"
		FAST_LAVA:
			return "Fast Lava"
		SLIPPERY_FLOOR:
			return "Slippery Floor"
		TINY_WEAPONS:
			return "Tiny Weapons"
		WEAPON_ROULETTE:
			return "Weapon Roulette"
		METEOR_SHOWER:
			return "Meteor Shower"
		BOUNCY:
			return "Bouncy"
		DOUBLE_DAMAGE:
			# Exactly this, as the owner asked (issue #147).
			return "Double Damage"
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
		TINY_WEAPONS:
			modifier = TinyWeapons.new()
		WEAPON_ROULETTE:
			modifier = WeaponRoulette.new()
		METEOR_SHOWER:
			modifier = MeteorShower.new()
		BOUNCY:
			modifier = Bouncy.new()
		DOUBLE_DAMAGE:
			modifier = DoubleDamage.new()
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

	## The random numbers a modifier draws with (issue #162): the round
	## manager's own modifier RNG, the one `modifier_seed` seeds, so a seeded
	## run draws the same roulette weapons and the same meteors every time.
	## A round that was forced rather than rolled has not made that RNG yet,
	## so it is made here exactly as `RoundManager._roll_modifier` makes it
	## and handed back to the round manager, keeping one stream for the rolls
	## and the draws alike. With no round manager (a scenario applying a
	## modifier by hand) it is an unseeded RNG of the modifier's own. A
	## scenario may also set `rng` before the first draw.
	var rng: RandomNumberGenerator

	func _rng() -> RandomNumberGenerator:
		if rng != null:
			return rng
		var holder: Object = _round if _round != null and is_instance_valid(_round) else null
		if holder != null and holder.get("_modifier_rng") is RandomNumberGenerator:
			rng = holder.get("_modifier_rng")
			return rng
		rng = RandomNumberGenerator.new()
		var seed_value: Variant = holder.get("modifier_seed") if holder != null else null
		if seed_value == null or int(seed_value) == -1:
			rng.randomize()
		else:
			rng.seed = int(seed_value)
		if holder != null and "_modifier_rng" in holder:
			holder.set("_modifier_rng", rng)
		return rng

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

	## Scales what the three special weapons (issue #150) draw and hit with
	## beyond the head: the loaded hook or boomerang's art and the flail's
	## ball. Nothing for any other weapon, whose fields are empty.
	func _scale_special_art(scaled: Resource, stats: Resource, factor: float) -> void:
		scaled.loaded_art = _scaled_points(stats.loaded_art, factor)
		scaled.ball_art = _scaled_points(stats.ball_art, factor)
		scaled.ball_radius = stats.ball_radius * factor

	func _scaled_points(points: PackedVector2Array, factor: float) -> PackedVector2Array:
		var out: PackedVector2Array = points.duplicate()
		for i in out.size():
			out[i] = out[i] * factor
		return out

class HeavyWeapons extends WeaponStatsModifier:
	func _modified(stats: Resource) -> Resource:
		var heavy: Resource = stats.duplicate()
		heavy.mass = stats.mass * HEAVY_MASS_SCALE
		heavy.max_drive_force = stats.max_drive_force * HEAVY_FORCE_SCALE
		# The flail's ball and chain are weapon weight too (issue #150).
		heavy.ball_mass = stats.ball_mass * HEAVY_MASS_SCALE
		heavy.chain_link_mass = stats.chain_link_mass * HEAVY_MASS_SCALE
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
		_scale_special_art(big, stats, BIG_HEAD_SCALE)
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

class TinyWeapons extends WeaponStatsModifier:
	func _modified(stats: Resource) -> Resource:
		var tiny: Resource = stats.duplicate()
		var offsets: PackedVector2Array = stats.head_circle_offsets.duplicate()
		for i in offsets.size():
			offsets[i] = offsets[i] * TINY_HEAD_SCALE
		var radii: PackedFloat32Array = stats.head_circle_radii.duplicate()
		for i in radii.size():
			radii[i] = radii[i] * TINY_HEAD_SCALE
		var outline: PackedVector2Array = stats.art_outline.duplicate()
		for i in outline.size():
			outline[i] = outline[i] * TINY_HEAD_SCALE
		tiny.head_circle_offsets = offsets
		tiny.head_circle_radii = radii
		tiny.art_outline = outline
		tiny.projectile_radius = stats.projectile_radius * TINY_HEAD_SCALE
		tiny.max_reach = maxf(stats.min_reach, stats.max_reach * TINY_REACH_SCALE)
		_scale_special_art(tiny, stats, TINY_HEAD_SCALE)
		tiny.chain_length = stats.chain_length * TINY_REACH_SCALE
		return tiny

## Owns a Timer under the RoundManager for the length of one round: the two
## modifiers below that do something on a clock rather than once.
class TimedModifier extends RoundModifier:
	var _timer: Timer

	func _start_timer(interval_sec: float, on_timeout: Callable) -> void:
		if _round == null:
			return
		_timer = Timer.new()
		_timer.name = "RoundModifierTimer"
		_timer.wait_time = interval_sec
		_timer.one_shot = false
		# On the physics clock, like the rest of the round.
		_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
		_timer.timeout.connect(on_timeout)
		_round.add_child(_timer)
		_timer.start()

	func _stop_timer() -> void:
		if _timer != null and is_instance_valid(_timer):
			_timer.stop()
			_timer.queue_free()
		_timer = null

class WeaponRoulette extends TimedModifier:
	## Each player's weapon when the round started, handed back on undo.
	var _saved: Dictionary = {}
	var _last_pick: Resource
	var _swaps: int = 0

	func _apply() -> void:
		for player: Variant in _live_players():
			_saved[player] = player.weapon_stats
		_start_timer(ROULETTE_INTERVAL_SEC, _swap)

	func _undo() -> void:
		_stop_timer()
		for player: Variant in _live_players():
			if _saved.has(player) and player.weapon_stats != _saved[player]:
				player.set_weapon_stats(_saved[player])
		_saved.clear()
		_last_pick = null

	## Swaps done this round: a scenario seam.
	func swap_count() -> int:
		return _swaps

	## The whole roster: every pickup weapon plus the pickaxe.
	static func roster() -> Array[Resource]:
		var weapons: Array[Resource] = PickupWeaponsScript.available_weapons()
		if ResourceLoader.exists(PickupWeaponsScript.PICKAXE_PATH):
			weapons.append(load(PickupWeaponsScript.PICKAXE_PATH))
		return weapons

	func _swap() -> void:
		var in_play: Array = []
		for player: Variant in _live_players():
			if player.alive:
				in_play.append(player)
		if in_play.is_empty():
			return
		# Never what the last swap handed out, nor -- on the first swap --
		# what the first player in play already holds, so a swap always shows.
		var avoid: Resource = _last_pick if _last_pick != null else in_play[0].weapon_stats
		var choices: Array[Resource] = []
		for stats: Resource in roster():
			if stats != null and stats != avoid:
				choices.append(stats)
		if choices.is_empty():
			return
		_last_pick = choices[_rng().randi() % choices.size()]
		_swaps += 1
		for player: Variant in in_play:
			player.set_weapon_stats(_last_pick)

class MeteorShower extends TimedModifier:
	var _meteors: Array = []
	var _spawned: int = 0
	var _min_x: float = -600.0
	var _max_x: float = 600.0
	var _top_y: float = -800.0
	var _lowest_y: float = 2000.0

	func _apply() -> void:
		var points: Array[Vector2] = []
		if _stage != null and _stage.has_method("get_spawn_points"):
			points = _stage.get_spawn_points()
		if points.is_empty():
			for player: Variant in _live_players():
				points.append(player.global_position)
		if not points.is_empty():
			_min_x = INF
			_max_x = -INF
			var high: float = INF
			var low: float = -INF
			for point: Vector2 in points:
				_min_x = minf(_min_x, point.x)
				_max_x = maxf(_max_x, point.x)
				high = minf(high, point.y)
				low = maxf(low, point.y)
			_min_x -= METEOR_X_MARGIN
			_max_x += METEOR_X_MARGIN
			_top_y = high - METEOR_HEIGHT
			_lowest_y = low + METEOR_DROP_BELOW
		# A stage that says what the camera shows (issue #144) rains across
		# all of it, from just out of sight above it (issue #162): on a large
		# stage the spawns' span misses the outer edges, and a fixed height
		# over the spawns is inside the view, so meteors popped into being.
		if _stage != null and is_instance_valid(_stage) and _stage.has_method("get_view_rect"):
			var view: Rect2 = _stage.get_view_rect()
			if view.size.x > 0.0 and view.size.y > 0.0:
				_min_x = view.position.x
				_max_x = view.end.x
				_top_y = view.position.y - METEOR_VIEW_MARGIN
				_lowest_y = maxf(_lowest_y, view.end.y + METEOR_DROP_BELOW)
		_start_timer(METEOR_INTERVAL_SEC, _spawn_meteor)

	func _undo() -> void:
		_stop_timer()
		for meteor: Variant in _meteors:
			if meteor != null and is_instance_valid(meteor):
				meteor.queue_free()
		_meteors.clear()

	## Meteors spawned this round, and the ones still in flight: scenario seams.
	func spawned_count() -> int:
		return _spawned

	func live_meteors() -> Array:
		var live: Array = []
		for meteor: Variant in _meteors:
			if meteor != null and is_instance_valid(meteor) and not meteor.is_queued_for_deletion():
				live.append(meteor)
		return live

	## One meteor at `from` flying at `flight_velocity`, parented to the stage
	## (or the RoundManager with no stage) and tracked so undo can clear it.
	func spawn_meteor_at(from: Vector2, flight_velocity: Vector2) -> Node2D:
		var host: Node = _stage if _stage != null and is_instance_valid(_stage) else _round
		if host == null or not is_instance_valid(host):
			return null
		var meteor: Node2D = MeteorScript.new()
		meteor.name = "Meteor%d" % _spawned
		meteor.setup(from, flight_velocity, METEOR_DAMAGE, METEOR_KNOCK_SPEED, METEOR_RADIUS, _lowest_y)
		host.add_child(meteor)
		_spawned += 1
		_meteors = live_meteors()
		_meteors.append(meteor)
		return meteor

	func _spawn_meteor() -> void:
		var draw: RandomNumberGenerator = _rng()
		var from := Vector2(draw.randf_range(_min_x, _max_x), _top_y)
		var drift: float = draw.randf_range(-METEOR_DRIFT_SPEED, METEOR_DRIFT_SPEED)
		spawn_meteor_at(from, Vector2(drift, METEOR_FALL_SPEED))

class Bouncy extends RoundModifier:
	## Whatever each player had before, which may be null (none authored).
	var _saved: Dictionary = {}

	func _apply() -> void:
		for player: Variant in _live_players():
			var before: PhysicsMaterial = player.physics_material_override
			var material := PhysicsMaterial.new()
			material.friction = before.friction if before != null else 1.0
			material.rough = before.rough if before != null else false
			material.bounce = BOUNCY_BOUNCE
			_saved[player] = before
			player.physics_material_override = material

	func _undo() -> void:
		for player: Variant in _live_players():
			if _saved.has(player):
				player.physics_material_override = _saved[player]
		_saved.clear()

class DoubleDamage extends WeaponStatsModifier:
	## Each of the stage's falling rocks, and the damage it was authored with.
	var _rocks: Dictionary = {}

	func _apply() -> void:
		super()
		if _stage == null:
			return
		for node: Node in _stage.find_children("*", "Node2D", true, false):
			if node.get_script() == FallingRockScript:
				_rocks[node] = node.damage
				node.damage = node.damage * DOUBLE_DAMAGE_SCALE

	func _undo() -> void:
		super()
		for rock: Variant in _rocks:
			if rock != null and is_instance_valid(rock):
				rock.damage = _rocks[rock]
		_rocks.clear()

	func _modified(stats: Resource) -> Resource:
		var doubled: Resource = stats.duplicate()
		doubled.damage = stats.damage * DOUBLE_DAMAGE_SCALE
		doubled.projectile_damage = stats.projectile_damage * DOUBLE_DAMAGE_SCALE
		doubled.ball_damage = stats.ball_damage * DOUBLE_DAMAGE_SCALE
		return doubled
