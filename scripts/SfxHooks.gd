extends Node

## Which game event makes which sound (issue #75, ADR-0016).
##
## The same pattern `HitFeedback.gd` uses for hitmarkers: rather than the game
## calling into audio, this watches the tree for the nodes that emit events
## and connects to their signals. So `Player`, `WeaponHead`, `Projectile`,
## `KillZone`, `RoundManager` and `ControllerServer` never learn that sound
## exists, and a scenario that builds any of them gets its sounds for free.
##
## Nodes are recognised by the signals they carry, never by `class_name`
## (CLAUDE.md): a node with `strike_landed` and `eliminated` is a player, one
## with `struck_world` and `clashed` is a weapon head, and so on.
##
## A new sound source -- a stage part (#76) -- is one `_watch_*` line here
## plus a signal on the part, or, for a part that already knows when it
## acts, one `get_node("/root/Sfx").play(...)` call in the part itself.

## Lobby how-to-play demo nodes (#219) are left alone: `is_demo_node()`.
const HowToPlayDemoScript := preload("res://scripts/HowToPlayDemo.gd")

## Damage that plays a weapon's hit at full strength. A committed swing does
## 34-60 depending on the weapon (Player._strike_damage), so a full-speed
## strike from any of them is at or near the top.
const HIT_FULL_DAMAGE: float = 60.0
## Head speeds, px/s, for the terrain knock and the clash: below MIN is
## silent, FULL and above is full strength. A plant or a nudge is quieter
## than a slam; a head at rest makes nothing.
const TERRAIN_MIN_SPEED: float = 300.0
const TERRAIN_FULL_SPEED: float = 2000.0
const CLASH_MIN_SPEED: float = 150.0
const CLASH_FULL_SPEED: float = 2500.0
## Downward speed, px/s, a body has to arrive at a surface with to be a
## landing, and the speed that lands at full strength. Resting contact and
## walking along a floor stay silent.
const LAND_MIN_SPEED: float = 350.0
const LAND_FULL_SPEED: float = 1400.0
## Per-source repeat guards, in physics frames: a head grinding in a corner or
## a body bouncing on two touching tiles is one sound, not one a tick.
const HEAD_COOLDOWN_FRAMES: int = 5
const LAND_COOLDOWN_FRAMES: int = 10
## Voice grunts (#290): the number of voices (one per slot), and the quiet
## gap between one victim's hit grunts.
const VOICE_COUNT: int = 8
const GRUNT_HIT_COOLDOWN_FRAMES: int = 30
const PRUNE_AT: int = 256
const PRUNE_AFTER_FRAMES: int = 600
## Where a landing sounds from: the bottom of the body, not its middle.
const BODY_RADIUS: float = 24.0
## Marks a node already connected, so one re-added to the tree is not
## connected twice.
const META_WATCHED: StringName = &"_sfx_watched"

var sfx: Node

## Players whose pre-step velocity is tracked for landings.
var _players: Array[Node] = []
## instance id -> linear velocity at the start of this physics step.
var _velocity_before: Dictionary = {}
## instance id -> the physics frame that source last made a sound on.
var _last_frame: Dictionary = {}

func _ready() -> void:
	# Before every game node in the tree order, so `_physics_process` reads
	# each body's velocity before the step that may land it.
	process_physics_priority = -100
	get_tree().node_added.connect(_on_node_added)
	_watch_subtree(get_tree().root)

func _physics_process(_delta: float) -> void:
	if _velocity_before.size() > _players.size() * 4 + 16:
		_velocity_before.clear()
	var still: Array[Node] = []
	for player in _players:
		if is_instance_valid(player) and player.is_inside_tree():
			_velocity_before[player.get_instance_id()] = player.linear_velocity
			still.append(player)
	_players = still

func _watch_subtree(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_watch_subtree(child)

func _on_node_added(node: Node) -> void:
	# A lobby how-to-play demo's puppets (#219) make no sound.
	if node.has_meta(META_WATCHED) or HowToPlayDemoScript.is_demo_node(node):
		return
	if node.has_signal("strike_landed") and node.has_signal("eliminated"):
		_watch_player(node)
	elif node.has_signal("struck_world") and node.has_signal("clashed"):
		_watch_head(node)
	elif node.has_signal("impacted") and node.has_method("setup"):
		_watch_projectile(node)
	elif node.has_signal("rise_countdown"):
		_watch_kill_zone(node)
	elif node.has_signal("round_started"):
		_watch_round_manager(node)
	elif node.has_signal("player_joined"):
		_watch_roster(node)
	else:
		return
	node.set_meta(META_WATCHED, true)

# --- Players ----------------------------------------------------------------

func _watch_player(player: Node) -> void:
	player.connect("strike_landed", _on_strike_landed.bind(player))
	player.connect("eliminated", _on_eliminated.bind(player))
	if player.has_signal("body_entered"):
		player.connect("body_entered", _on_player_touched.bind(player))
	_players.append(player)

## Every strike that dealt damage, sword swing or bullet, sounds as the
## attacker's weapon. A 0-damage contact is silent: it is a nudge, and a head
## dragged along someone would otherwise chatter.
func _on_strike_landed(victim: Node, amount: float, point: Vector2, lethal: bool, attacker: Node) -> void:
	if amount <= 0.0:
		return
	var sound: String = "hit_%s" % _sound_set(attacker)
	if not sfx.has_sound(sound):
		sound = "hit_pickaxe"
	sfx.play(sound, point, amount / HIT_FULL_DAMAGE)
	# The victim's grunt (#290); a lethal blow gets the KO grunt instead.
	if not lethal:
		_grunt(&"grunt_hit_", victim, point, GRUNT_HIT_COOLDOWN_FRAMES)

func _on_eliminated(player: Node) -> void:
	sfx.play(&"eliminated", player.global_position, 1.0)
	_grunt(&"grunt_ko_", player, player.global_position, 0)

## Voice grunts (#290): one voice per player slot, kept quiet in the table so
## they sit under the weapon sounds. `prefix` is `grunt_hit_` or `grunt_ko_`.
## A victim grunts at most once per `frames` physics frames, so a flurry of
## blows is not a stream of "hnh".
func _grunt(prefix: StringName, victim: Node, point: Vector2, frames: int) -> void:
	if victim == null or not is_instance_valid(victim) or not victim.is_in_group("players"):
		return
	var sound := StringName("%s%d" % [prefix, voice_slot(victim)])
	if not sfx.has_sound(sound):
		return
	if frames > 0 and not _off_cooldown(victim, frames, "grunt"):
		return
	sfx.play(sound, point, 1.0)

## Which of the eight voices `player` speaks with: the number in its `PlayerN`
## node name (so a slot keeps its voice every round), else the order the
## player was first seen in. Always 0..VOICE_COUNT-1.
func voice_slot(player: Node) -> int:
	var name_text: String = String(player.name)
	if name_text.begins_with("Player") and name_text.substr(6).is_valid_int():
		return posmod(name_text.substr(6).to_int() - 1, VOICE_COUNT)
	var index: int = _players.find(player)
	return posmod(index if index != -1 else 0, VOICE_COUNT)

## A body meeting anything that is not another player, moving down fast
## enough to be a landing. Judged on the velocity it had going into the step:
## by the time the contact is reported, the solver has already stopped it.
func _on_player_touched(other: Node, player: Node) -> void:
	if other.is_in_group("players") or not bool(player.get("alive")):
		return
	var before: Vector2 = _velocity_before.get(player.get_instance_id(), Vector2.ZERO)
	if before.y < LAND_MIN_SPEED or not _off_cooldown(player, LAND_COOLDOWN_FRAMES):
		return
	var strength: float = (before.y - LAND_MIN_SPEED) / (LAND_FULL_SPEED - LAND_MIN_SPEED)
	sfx.play(&"land", player.global_position + Vector2(0.0, BODY_RADIUS), strength)

# --- Weapon heads -----------------------------------------------------------

func _watch_head(head: Node) -> void:
	head.connect("struck_world", _on_head_struck_world.bind(head))
	head.connect("clashed", _on_head_clashed.bind(head))

## A head arriving on something at speed. A player is a strike, and sounds
## through `strike_landed` instead; everything else is terrain.
func _on_head_struck_world(collider: Object, speed: float, point: Vector2, head: Node) -> void:
	var node: Node = collider as Node
	if node != null and node.is_in_group("players"):
		return
	if speed < TERRAIN_MIN_SPEED or not _off_cooldown(head, HEAD_COOLDOWN_FRAMES):
		return
	var strength: float = (speed - TERRAIN_MIN_SPEED) / (TERRAIN_FULL_SPEED - TERRAIN_MIN_SPEED)
	sfx.play(&"head_terrain", point, strength)

## Two heads meeting. `WeaponHead` reports it from the one head that corrects
## the pair, so a clash is one sound.
func _on_head_clashed(speed: float, point: Vector2, head: Node) -> void:
	if speed < CLASH_MIN_SPEED or not _off_cooldown(head, HEAD_COOLDOWN_FRAMES):
		return
	sfx.play(&"clash", point, speed / CLASH_FULL_SPEED)

# --- Bullets ----------------------------------------------------------------

func _watch_projectile(bullet: Node) -> void:
	# The shot sounds once the bullet is placed, which `_ready` does.
	bullet.ready.connect(_on_projectile_fired.bind(bullet), CONNECT_ONE_SHOT)
	bullet.connect("impacted", _on_projectile_impacted)

func _on_projectile_fired(bullet: Node) -> void:
	var sound: String = "fire_%s" % _sound_set(bullet.get("shooter"))
	if not sfx.has_sound(sound):
		sound = "fire_boomstick"
	sfx.play(sound, bullet.global_position, 1.0)

func _on_projectile_impacted(_collider: Object, point: Vector2) -> void:
	sfx.play(&"bullet_impact", point, 1.0)

# --- Lava -------------------------------------------------------------------

func _watch_kill_zone(zone: Node) -> void:
	zone.connect("rise_countdown", _on_rise_countdown)
	zone.connect("rise_began", _on_rise_began)
	zone.connect("body_entered", _on_kill_zone_entered)

func _on_rise_countdown(_seconds_left: int) -> void:
	sfx.play(&"countdown")

func _on_rise_began() -> void:
	sfx.play(&"lava_rise")

func _on_kill_zone_entered(body: Node) -> void:
	if body.is_in_group("players") and bool(body.get("alive")):
		sfx.play(&"lava_sizzle", (body as Node2D).global_position, 1.0)

# --- Rounds and the roster ---------------------------------------------------

func _watch_round_manager(round_manager: Node) -> void:
	round_manager.connect("round_started", _on_round_started)
	round_manager.connect("round_won", _on_round_won)
	round_manager.connect("modifier_announced", _on_modifier_announced)

func _on_round_started() -> void:
	sfx.play(&"round_start")

func _on_round_won(_slot: int) -> void:
	sfx.play(&"round_win")

func _on_modifier_announced(_title: String) -> void:
	sfx.play(&"modifier")

func _watch_roster(roster: Node) -> void:
	roster.connect("player_joined", _on_player_joined)

func _on_player_joined(_slot: int) -> void:
	sfx.play(&"join")

# --- Helpers ----------------------------------------------------------------

## The sound set of the weapon `player` really holds (`weapon_stats`, not a
## round modifier's copy), or "pickaxe" for anything without one.
func _sound_set(player: Variant) -> String:
	if player is Object and is_instance_valid(player):
		var stats: Variant = (player as Object).get("weapon_stats")
		if stats is Resource:
			var set_name: Variant = (stats as Resource).get("sound_set")
			if set_name != null and String(set_name) != "":
				return String(set_name)
	return "pickaxe"

func _off_cooldown(source: Node, frames: int, channel: String = "") -> bool:
	# A separate `channel` keeps a source's grunt from muting its other sounds.
	var id: int = source.get_instance_id() if channel == "" else hash([source.get_instance_id(), channel])
	var now: int = Engine.get_physics_frames()
	if _last_frame.has(id) and now - int(_last_frame[id]) < frames:
		return false
	if _last_frame.size() > PRUNE_AT:
		# Heads are rebuilt every round; forget the ones long gone quiet.
		for key: int in _last_frame.keys():
			if now - int(_last_frame[key]) > PRUNE_AFTER_FRAMES:
				_last_frame.erase(key)
	_last_frame[id] = now
	return true
