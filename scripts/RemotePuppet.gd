extends Node2D
## One thing the PC client draws from a snapshot (issue #241): a player, a
## shot, a pickup, a flail, a ghost or a meteor. A puppet has no physics;
## RemoteClient moves it every frame.
##
## Issue #930 / #976: every puppet is drawn by the host's own drawing code,
## never a second copy of it. A player builds the very nodes `Player.gd` does
## (`Player.build_identity_outline_line`, `style_haft_line`, `damage_fill`,
## `build_head_visual_for`, `build_loaded_visual`, `Hat.gd`, `PlayerFace.gd`),
## from the effective weapon stats under the round's modifier; a shot draws
## with `Projectile.draw_bullet`, `Boomerang.draw_boomerang` or
## `GrappleHook.draw_hook`; a pickup is a display-only `Pickup.tscn`; a flail
## is `FlailChain`'s ball and link visuals; a ghost `Ghost.draw_ghost`; a
## meteor `Meteor.draw_meteor`. The puppet offers what the host's face and
## night lighting read off a `Player` (`alive`, `linear_velocity`,
## `eye_look_dir()`, `hat_top()`, `weapon_head_position()`, `_stats`), so those
## run unchanged on it; name tags and their rings run on `RemoteFighter.gd`.
## No `class_name`: consumers preload this by path.

const PlayerScript: GDScript = preload("res://scripts/Player.gd")
const HatScript: GDScript = preload("res://scripts/Hat.gd")
const PlayerFaceScript: GDScript = preload("res://scripts/PlayerFace.gd")
const PickupScript: GDScript = preload("res://scripts/Pickup.gd")
const PickupScene: PackedScene = preload("res://scenes/Pickup.tscn")
const PickupWeaponsScript: GDScript = preload("res://scripts/PickupWeapons.gd")
const ProjectileScript: GDScript = preload("res://scripts/Projectile.gd")
const BoomerangScript: GDScript = preload("res://scripts/Boomerang.gd")
const GrappleHookScript: GDScript = preload("res://scripts/GrappleHook.gd")
const FlailChainScript: GDScript = preload("res://scripts/FlailChain.gd")
const GhostScript: GDScript = preload("res://scripts/Ghost.gd")
const MeteorScript: GDScript = preload("res://scripts/Meteor.gd")
const ShotSweepScript: GDScript = preload("res://scripts/ShotSweep.gd")
const RespawnScript: GDScript = preload("res://scripts/Respawn.gd")
const RoundModifiersScript: GDScript = preload("res://scripts/RoundModifiers.gd")
const SnapshotScript: GDScript = preload("res://scripts/Snapshot.gd")
const PLAYER_SCENE_PATH: String = "res://scenes/Player.tscn"

enum Kind { PLAYER, PROJECTILE, PICKUP, FLAIL, GHOST, METEOR }

## The z the host draws each at: a player's body sits at 1 over its rig at 0
## (Player._build_face); bullets 50, boomerangs and hooks 45, meteors 5; a
## ghost at absolute 0.
const PLAYER_Z: int = 1
const BULLET_Z: int = 50
const THROWN_Z: int = 45
const METEOR_Z: int = 5

var kind: int = Kind.PLAYER
## A player's (and its shots') identity colour.
var color: Color = Color.WHITE
## Unused for drawing: a player's name tag is the host's `NameTags.gd`, run by
## `RemoteEffects.gd` (#976).
var label: String = ""
## Player: world offset from the body to the weapon head.
var head_offset: Vector2 = Vector2.ZERO
var body_rotation: float = 0.0
var damage: int = 0
## 0 dead, 1 alive, 2 spawn-protected (SnapshotCapture's STATE_ constants).
var phase: int = 1
## Player: world rotation of the weapon head's art, and which weapon it is (the
## snapshot's `head_shape_index`; 0 is the pickaxe). Pickup: `weapon_type`.
## A shot: the weapon it came from.
var head_rotation: float = 0.0
var weapon_index: int = 0
## Player: the snapshot's PLAYER_* bits.
var flags: int = 0
## Player: the host's propeller-hat phase (Hat.spin_byte()).
var hat_spin: int = 0
## The host's face squash byte (PlayerFace.squash_byte()).
var squash: int = SnapshotScript.SQUASH_REST
## The round modifier running (its id), which can change how a weapon is drawn.
var modifier: String = ""
## The stage's ink for outlines and pupils (Palette.ink_for).
var ink: Color = PlayerFaceScript.OUTLINE_COLOR
var linear_velocity: Vector2 = Vector2.ZERO
## Player: the effective weapon stats (the boomstick ring reads `_stats`).
var _stats: Resource = null
var alive: bool:
	get:
		return phase != 0

## Shot: its velocity (the bullet's trail), PROJ_KIND_* and ghost bit, and the
## spin (boomerang) or facing (hook) it is drawn at; the shooter's puppet.
var velocity: Vector2 = Vector2.ZERO
var shot_flags: int = 0
var shot_rotation: float = 0.0
var owner_puppet: Node2D = null
## Ghost: fade and boo-puff progress. Meteor: radius.
var ghost_alpha: float = 0.0
var puff: float = 1.0
var radius: float = 0.0
## Pickup: the host's halo phase byte.
var halo: int = 0

var _hat: Node2D
var _face: Node2D
var _figure: Node2D
var _body: Polygon2D
var _outline: Line2D
var _haft: Line2D
var _rig: Node2D
var _head: Node2D
var _head_visual: Polygon2D
var _loaded_visual: Polygon2D
var _head_key: String = ""
var _last_damage: int = -1
var _pickup: Node2D
var _pickup_weapon: int = -1
var _flail_ball: Polygon2D
var _flail_links: Array[Node2D] = []
var _flail_key: String = ""
var _stats_cache: Dictionary = {}

static var _body_polygon_cache: PackedVector2Array = PackedVector2Array()

func _ready() -> void:
	match kind:
		Kind.PROJECTILE:
			z_index = BULLET_Z
		Kind.GHOST:
			z_as_relative = false
			z_index = 0
		Kind.METEOR:
			z_index = METEOR_Z

# --- Player -------------------------------------------------------------------

## The body polygon `Player.tscn` draws, read off the scene itself.
static func body_polygon() -> PackedVector2Array:
	if _body_polygon_cache.is_empty():
		var scene: PackedScene = load(PLAYER_SCENE_PATH)
		var state: SceneState = scene.get_state()
		for i in state.get_node_count():
			if state.get_node_name(i) != &"Body":
				continue
			for j in state.get_node_property_count(i):
				if state.get_node_property_name(i, j) == &"polygon":
					_body_polygon_cache = state.get_node_property_value(i, j)
	return _body_polygon_cache

## The body polygon's top edge (Player._body_top()).
static func body_top() -> float:
	var top: float = 0.0
	for p: Vector2 in body_polygon():
		top = minf(top, p.y)
	return top

func set_pose(position_in: Vector2, rotation_in: float, head_position: Vector2, head_rotation_in: float = 0.0) -> void:
	position = position_in
	body_rotation = rotation_in
	head_offset = head_position - position_in
	head_rotation = head_rotation_in
	if kind == Kind.PLAYER:
		_refresh_player()

## Hat and eyes from the host's `looks` frame (ids as `Hat.IDS` and
## `PlayerFace.EYE_IDS`); `tint` is the hat's identity colour.
func set_look(hat_id_in: String, eyes_id_in: String, tint: Color) -> void:
	_ensure_figure()
	if _hat.hat_id != hat_id_in:
		_hat.set_hat(hat_id_in)
	_hat.set_tint(tint)
	if _face.eyes_style != eyes_id_in:
		_face.set_eyes(eyes_id_in)

## Issue #976: as `Player.set_ink()`: the stage mood's ink on the face and the
## weapon head's outline.
func set_ink(colour: Color) -> void:
	if colour == ink:
		return
	ink = colour
	if kind == Kind.PLAYER and _figure != null:
		_refresh_player()

func hat_id() -> String:
	return _hat.hat_id if _hat != null else HatScript.NONE

func eyes_id() -> String:
	return _face.eyes_style if _face != null else "round"

## The face node, for the scenarios.
func face_node() -> Node2D:
	return _face

func hat_node() -> Node2D:
	return _hat

func figure() -> Node2D:
	return _figure

func head_visual() -> Polygon2D:
	return _head_visual

func loaded_visual() -> Polygon2D:
	return _loaded_visual

func body_visual() -> Polygon2D:
	return _body

func identity_outline() -> Line2D:
	return _outline

func haft_line() -> Line2D:
	return _haft

## As `Player.eye_look_dir()`: toward the weapon head.
func eye_look_dir() -> Vector2:
	if head_offset.length() > 1.0:
		return head_offset.normalized()
	return Vector2.from_angle(head_rotation)

## As `Player.hat_top()`: how far above the body's centre the hat reaches.
func hat_top() -> float:
	return -body_top() + HatScript.height_of(hat_id())

func weapon_head_position() -> Vector2:
	return global_position + head_offset

## The weapon resource for a snapshot weapon index (0 is the pickaxe), or null.
func _stats_for(index: int) -> Resource:
	if not _stats_cache.has(index):
		var path: String = PickupWeaponsScript.PICKAXE_PATH
		if index > 0:
			path = PickupWeaponsScript.WEAPON_PATHS[index - 1] if index <= PickupWeaponsScript.WEAPON_PATHS.size() else ""
		_stats_cache[index] = load(path) if not path.is_empty() else null
	return _stats_cache[index]

## The weapon `index` as the host's player holds it under the round's modifier.
func effective_stats(index: int) -> Resource:
	var key: String = "%d|%s" % [index, modifier]
	if not _stats_cache.has(key):
		_stats_cache[key] = RoundModifiersScript.weapon_stats_under(modifier, _stats_for(index))
	return _stats_cache[key]

## The head-local art a player's weapon head is drawn with (empty: none known).
func head_art() -> PackedVector2Array:
	return _head_visual.polygon if _head_visual != null else PackedVector2Array()

## What a pickup puppet draws, from `Pickup.art_layout`; "fallback" is true
## when its weapon has no art (the diamond).
func pickup_layout() -> Dictionary:
	return PickupScript.art_layout(_stats_for(weapon_index))

func _ensure_figure() -> void:
	if _figure != null:
		return
	# The rig beside the body, as the host's `<name>WeaponRig` sibling (z 0).
	_rig = Node2D.new()
	_rig.name = "Rig"
	add_child(_rig)
	_head = Node2D.new()
	_head.name = "Head"
	_rig.add_child(_head)
	# The body and what hangs on it, as `Player.tscn` plus `_build_*` lay it out.
	_figure = Node2D.new()
	_figure.name = "Figure"
	_figure.z_index = PLAYER_Z
	add_child(_figure)
	_haft = Line2D.new()
	_haft.name = "Haft"
	_haft.points = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	PlayerScript.style_haft_line(_haft)
	_haft.z_index = -1
	_figure.add_child(_haft)
	_body = Polygon2D.new()
	_body.name = "Body"
	_body.polygon = body_polygon()
	_figure.add_child(_body)
	_outline = PlayerScript.build_identity_outline_line(_body.polygon, color)
	_figure.add_child(_outline)
	_hat = HatScript.new()
	_hat.name = "Hat"
	_hat.position = Vector2(0.0, body_top())
	_figure.add_child(_hat)
	_face = PlayerFaceScript.new()
	_face.name = "Face"
	_figure.add_child(_face)
	var visuals: Array[Node2D] = [_body, _outline]
	_face.setup(self, visuals, _hat)

func _refresh_player() -> void:
	_ensure_figure()
	visible = phase != 0
	_stats = effective_stats(weapon_index)
	_body.color = PlayerScript.damage_fill(color, damage)
	_outline.default_color = color
	_face.set_ink(ink)
	if _hat.hat_id == "propeller":
		_hat.set_spin_byte(hat_spin)
	_face.blink_override = 1 if flags & SnapshotScript.PLAYER_BLINKING else 0
	_face.set_squash_byte(squash)
	if _last_damage >= 0 and damage > _last_damage and phase != 0:
		_face.on_hit(float(damage - _last_damage))
	_last_damage = damage
	# The spawn-protection blink is on the player's modulate (Respawn.gd),
	# which the rig beside it does not share.
	_figure.modulate.a = RespawnScript.BLINK_ALPHA if flags & SnapshotScript.PLAYER_DIMMED else 1.0
	var pts: PackedVector2Array = _haft.points
	pts[1] = head_offset
	_haft.points = pts
	var key: String = "%d|%s|%s|%s" % [weapon_index, modifier, color.to_html(), ink.to_html()]
	if key != _head_key or _head_visual == null:
		_head_key = key
		if _head_visual != null:
			_head_visual.free()
		_head_visual = null
		_loaded_visual = null
		if _stats != null:
			_head_visual = PlayerScript.build_head_visual_for(_stats, color, ink)
			_head.add_child(_head_visual)
			_loaded_visual = PlayerScript.build_loaded_visual(_stats, color)
			if _loaded_visual != null:
				_head_visual.add_child(_loaded_visual)
	_head.position = head_offset
	if _head_visual != null:
		_head_visual.rotation = head_rotation
		_head_visual.modulate.a = PlayerScript.PHASED_HEAD_ALPHA if flags & SnapshotScript.PLAYER_HEAD_PHASED else 1.0
	if _loaded_visual != null:
		_loaded_visual.visible = flags & SnapshotScript.PLAYER_SPECIAL_LOADED != 0

# --- Pickup -------------------------------------------------------------------

## Builds (or rebuilds, for a new weapon) the display-only `Pickup.tscn`. Its
## spawn pop-in (#816) is the host's `pickup_ring` event (RemoteEffects.gd).
func show_pickup() -> void:
	if _pickup == null or _pickup_weapon != weapon_index:
		if _pickup != null:
			_pickup.free()
		_pickup = PickupScene.instantiate() as Node2D
		_pickup.name = "Pickup"
		_pickup.set("display_only", true)
		_pickup.set_weapon(_stats_for(weapon_index))
		add_child(_pickup)
		_pickup_weapon = weapon_index
	_pickup.set_halo_phase(halo)

func pickup_node() -> Node2D:
	return _pickup

# --- Flail ----------------------------------------------------------------------

## Places the ball and links (world positions and rotations) of an owner whose
## identity colour is `color`, holding weapon `weapon_index`.
func show_flail(ball_position: Vector2, ball_rotation: float, links: Array, phased: bool) -> void:
	position = Vector2.ZERO
	var key: String = "%d|%s|%s" % [weapon_index, modifier, color.to_html()]
	if key != _flail_key or _flail_ball == null:
		_flail_key = key
		if _flail_ball != null:
			_flail_ball.free()
		var stats: Resource = effective_stats(weapon_index)
		if stats == null:
			return
		_flail_ball = FlailChainScript.build_ball_visual(stats, color)
		add_child(_flail_ball)
	while _flail_links.size() < links.size():
		var link := Node2D.new()
		link.add_child(FlailChainScript.build_link_visual())
		add_child(link)
		move_child(link, 0)
		_flail_links.append(link)
	while _flail_links.size() > links.size():
		_flail_links.pop_back().free()
	for i in links.size():
		var l: Dictionary = links[i] if links[i] is Dictionary else {}
		_flail_links[i].position = l.get("position", Vector2.ZERO)
		_flail_links[i].rotation = float(l.get("rotation", 0.0))
	_flail_ball.position = ball_position
	_flail_ball.rotation = ball_rotation
	_flail_ball.modulate.a = FlailChainScript.PHASED_ALPHA if phased else 1.0

func flail_ball() -> Polygon2D:
	return _flail_ball

func flail_link_count() -> int:
	return _flail_links.size()

# --- Shots, ghosts, meteors ------------------------------------------------------

func shot_kind() -> int:
	return shot_flags & SnapshotScript.PROJ_KIND_MASK

func _process(_delta: float) -> void:
	if kind == Kind.PROJECTILE or kind == Kind.GHOST or kind == Kind.METEOR:
		queue_redraw()

func _draw() -> void:
	match kind:
		Kind.PROJECTILE:
			_draw_shot()
		Kind.GHOST:
			GhostScript.draw_ghost(self, color, ghost_alpha, puff)
		Kind.METEOR:
			MeteorScript.draw_meteor(self, velocity, radius)

## The shot's layer and facing, as the host's node of its kind has them: a
## thrown boomerang or hook above the players, a hook turned along its flight,
## a bullet on top. Set when the shot is placed, not only when it is drawn.
func refresh_shot() -> void:
	match shot_kind():
		SnapshotScript.PROJ_KIND_BOOMERANG:
			z_index = THROWN_Z
			rotation = 0.0
		SnapshotScript.PROJ_KIND_HOOK:
			z_index = THROWN_Z
			rotation = shot_rotation
		_:
			z_index = BULLET_Z
			rotation = 0.0

func _draw_shot() -> void:
	refresh_shot()
	var stats: Resource = effective_stats(weapon_index)
	var r: float = maxf(0.5, float(stats.get("projectile_radius"))) if stats != null else 3.0
	match shot_kind():
		SnapshotScript.PROJ_KIND_BOOMERANG:
			var art: PackedVector2Array = ShotSweepScript.centred(stats.loaded_art) if stats != null else PackedVector2Array()
			BoomerangScript.draw_boomerang(self, art, shot_rotation, color,
				shot_flags & SnapshotScript.PROJ_GHOST != 0, r)
		SnapshotScript.PROJ_KIND_HOOK:
			var art: PackedVector2Array = ShotSweepScript.centred(stats.loaded_art) if stats != null else PackedVector2Array()
			if owner_puppet == null or not is_instance_valid(owner_puppet):
				return # the host draws no hook without its shooter
			GrappleHookScript.draw_hook(self, to_local(owner_puppet.weapon_head_position()), art, color, r)
		_:
			ProjectileScript.draw_bullet(self, velocity, r, color)
