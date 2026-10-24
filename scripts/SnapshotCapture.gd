extends RefCounted
## Builds the `world` Dictionary that `Snapshot.encode()` expects (issue #251,
## #212) from the live game, and the delta frames between full snapshots.
## The key names are `Snapshot.gd`'s; nothing here invents a schema. Preload
## this script by path; never reference it by `class_name` (CLAUDE.md).
##
## Keys the live game has no source for are filled with a default:
## - `modifiers[].modifier_id`: 1 for the round modifier (the name carries the
##   identity); 2, named "night", while the stage is its night variant (#332,
##   so the Online joiner builds the same night stage, #976).
## - `timer_ms`: the lobby countdown's time left, else 0 (rounds are untimed).
## - `announcer_text`: the on-screen modifier banner while it shows, else "".
## - `color`: the slot number (the client picks the palette).
## - `flail` / `grapple`: one of each at most; the first player holding one.

const PickupWeaponsScript := preload("res://scripts/PickupWeapons.gd")
const GameClockScript := preload("res://scripts/GameClock.gd")
const SnapshotScript := preload("res://scripts/Snapshot.gd")
const BoomerangScript := preload("res://scripts/Boomerang.gd")
const GrappleHookScript := preload("res://scripts/GrappleHook.gd")
const MeteorScript := preload("res://scripts/Meteor.gd")
const NetSyncScript := preload("res://scripts/NetSync.gd")
## The `modifiers` entry that marks a night stage (#976).
const NIGHT_MODIFIER_ID: int = 2

## Frames captured since boot; scenarios read it to prove a phones-only game
## captures nothing.
static var capture_count: int = 0

## Player `state` byte.
const STATE_DEAD: int = 0
const STATE_ALIVE: int = 1
const STATE_PROTECTED: int = 2
## `static_stage_bodies` carries a one-byte count.
const MAX_STAGE_BODIES: int = 255

## A full world snapshot of `round_manager`'s game, ready for `Snapshot.encode()`.
static func capture(round_manager: Node) -> Dictionary:
	capture_count += 1
	var rm: Node = round_manager
	var state: int = int(rm.get("_state"))
	var players: Array = _players(rm, state)
	var world: Dictionary = {
		"is_full_snapshot": true,
		"stage_id": maxi(0, int(rm.get("_stage_rotation").stage_index)),
		"static_stage_bodies": _stage_bodies(rm.get("_current_stage")),
		"players": players,
		"projectiles": _projectiles(rm),
		"pickups": _pickups(rm),
		"flail": {},
		"grapple": {},
		"modifiers": _modifiers(rm),
		"round_phase": state,
		"timer_ms": _timer_ms(rm, state),
		"scores": {},
		"kill_feed": _kill_feed(rm),
		"kill_zone_height": _kill_zone_height(rm),
		"announcer_text": _announcer_text(rm),
		# Issue #976: what an Online joiner needs to draw these exactly.
		"flails": _flails(rm, players),
		"ghosts": _ghosts(rm),
		"meteors": _meteors(rm),
		"parts": _parts(rm.get("_current_stage")),
		"props": _props(rm),
	}
	var scores: Dictionary = {}
	for entry: Dictionary in players:
		var slot: int = entry["player_id"]
		scores[slot] = clampi(rm.score_of(slot), 0, 65535)
		var player: Node = rm.get("_players")[slot]
		if world["flail"].is_empty() and player.flail_ball() != null:
			var ball: RigidBody2D = player.flail_ball()
			world["flail"] = {
				"flail_id": slot,
				"ball_position": ball.global_position,
				"ball_velocity": player.flail_chain().ball_velocity,
			}
		var hook: Node2D = player.launched_hook()
		if world["grapple"].is_empty() and hook != null:
			world["grapple"] = {
				"grapple_id": slot,
				"hook_position": hook.global_position,
				"rope_end": player.global_position,
			}
	world["scores"] = scores
	return world

## The frame after `previous`: only what changed since it, as the
## `delta_entities` list `Snapshot.encode()` writes for a non-full frame.
## Things that left the world are not expressible in a delta; the next full
## snapshot (about once a second) removes them.
static func delta(world: Dictionary, previous: Dictionary) -> Dictionary:
	var entities: Array = []
	var before: Dictionary = _by_key(previous.get("players", []), "player_id")
	for p: Dictionary in world.get("players", []):
		if before.get(p["player_id"]) != p:
			entities.append({"type": 0x01, "id": p["player_id"], "body": p["body"],
				"weapon": p["weapon"], "damage": p["damage"], "state": p["state"],
				"flags": p.get("flags", 0),
				"hat_spin": p.get("hat_spin", 0), "squash": p.get("squash", SnapshotScript.SQUASH_REST)})
	before = _by_key(previous.get("projectiles", []), "projectile_id")
	for p: Dictionary in world.get("projectiles", []):
		if before.get(p["projectile_id"]) != p:
			entities.append({"type": 0x02, "id": p["projectile_id"],
				"position": p["position"], "velocity": p["velocity"],
				"rotation": p.get("rotation", 0.0), "flags": p.get("flags", 0)})
	before = _by_key(previous.get("pickups", []), "pickup_id")
	for p: Dictionary in world.get("pickups", []):
		if before.get(p["pickup_id"]) != p:
			entities.append({"type": 0x03, "id": p["pickup_id"], "position": p["position"]})
	var flail: Dictionary = world.get("flail", {})
	if not flail.is_empty() and flail != previous.get("flail", {}):
		entities.append({"type": 0x04, "id": flail["flail_id"],
			"pos1": flail["ball_position"], "pos2": flail["ball_velocity"]})
	var grapple: Dictionary = world.get("grapple", {})
	if not grapple.is_empty() and grapple != previous.get("grapple", {}):
		entities.append({"type": 0x05, "id": grapple["grapple_id"],
			"pos1": grapple["hook_position"], "pos2": grapple["rope_end"]})
	before = _by_key(previous.get("flails", []), "owner")
	for f: Dictionary in world.get("flails", []):
		if before.get(f["owner"]) != f:
			var e: Dictionary = f.duplicate()
			e["type"] = SnapshotScript.TYPE_CHAIN
			e["id"] = f["owner"]
			entities.append(e)
	before = _by_key(previous.get("ghosts", []), "owner")
	for g: Dictionary in world.get("ghosts", []):
		if before.get(g["owner"]) != g:
			var e: Dictionary = g.duplicate()
			e["type"] = SnapshotScript.TYPE_GHOST
			e["id"] = g["owner"]
			entities.append(e)
	before = _by_key(previous.get("meteors", []), "meteor_id")
	for m: Dictionary in world.get("meteors", []):
		if before.get(m["meteor_id"]) != m:
			var e: Dictionary = m.duplicate()
			e["type"] = SnapshotScript.TYPE_METEOR
			e["id"] = m["meteor_id"]
			entities.append(e)
	# A part's clocks run on the client too: only a change in its looks sends it.
	before = _by_key(previous.get("parts", []), "part_id")
	for part: Dictionary in world.get("parts", []):
		var was: Variant = before.get(part["part_id"])
		var nvars: int = int(part.get("nvars", 0))
		if was == null or (part["state"] as Array).slice(0, nvars) != (was["state"] as Array).slice(0, nvars):
			entities.append({"type": SnapshotScript.TYPE_PART, "id": 0, "part_id": part["part_id"],
				"state": part["state"]})
	before = _by_key(previous.get("props", []), "prop_id")
	for prop: Dictionary in world.get("props", []):
		if before.get(prop["prop_id"]) != prop:
			entities.append({"type": SnapshotScript.TYPE_PROP, "id": prop["prop_id"], "kind": prop["kind"],
				"state": prop["state"]})
	if world.get("timer_ms") != previous.get("timer_ms"):
		entities.append({"type": 0x07, "id": 0, "timer_ms": world.get("timer_ms", 0)})
	var old_scores: Dictionary = previous.get("scores", {})
	for slot: int in world.get("scores", {}):
		if old_scores.get(slot) != world["scores"][slot]:
			entities.append({"type": 0x08, "id": slot, "score": world["scores"][slot]})
	if world.get("kill_zone_height") != previous.get("kill_zone_height"):
		entities.append({"type": 0x0A, "id": 0, "height": world.get("kill_zone_height", 0)})
	return {"is_full_snapshot": false, "delta_entities": entities}

## Whether `world` lost or gained a body, projectile, pickup, flail or hook
## against `previous`, changed round phase or stage, or changed its kill feed,
## banner or modifiers: things a delta cannot say.
static func structure_changed(world: Dictionary, previous: Dictionary) -> bool:
	if previous.is_empty():
		return true
	if world.get("round_phase") != previous.get("round_phase") or world.get("stage_id") != previous.get("stage_id"):
		return true
	for pair: Array in [["players", "player_id"], ["projectiles", "projectile_id"], ["pickups", "pickup_id"],
			["flails", "owner"], ["ghosts", "owner"], ["meteors", "meteor_id"], ["parts", "part_id"],
			["props", "prop_id"]]:
		var now: Dictionary = _by_key(world.get(pair[0], []), pair[1])
		var before: Dictionary = _by_key(previous.get(pair[0], []), pair[1])
		for id: Variant in before:
			if not now.has(id):
				return true
		for id: Variant in now:
			if not before.has(id):
				return true # a delta only moves what the client already has
	for key: String in ["flail", "grapple"]:
		if world.get(key, {}).is_empty() != previous.get(key, {}).is_empty():
			return true
	# A delta carries none of these.
	for key: String in ["kill_feed", "announcer_text", "modifiers"]:
		if world.get(key) != previous.get(key):
			return true
	return false

static func _by_key(list: Array, key: String) -> Dictionary:
	var out: Dictionary = {}
	for entry: Dictionary in list:
		out[entry[key]] = entry
	return out

static func _weapon_index(stats: Resource) -> int:
	if stats == null:
		return 0
	var at: int = PickupWeaponsScript.WEAPON_PATHS.find(stats.resource_path)
	return at + 1 if at >= 0 else 0

static func _players(rm: Node, state: int) -> Array:
	var out: Array = []
	if state != 1 and state != 2: # State.ROUND_ACTIVE, State.ROUND_END
		return out
	var nodes: Array = rm.get("_players")
	for slot: int in rm.get("_in_round"):
		var p: RigidBody2D = nodes[slot]
		var head: Node2D = p.get("_head")
		var head_visual: Node2D = p.get("_head_visual")
		var phase: int = STATE_DEAD
		if p.alive:
			phase = STATE_PROTECTED if p.spawn_protected else STATE_ALIVE
		out.append({
			"player_id": slot,
			"body": {"position": p.global_position, "rotation": p.global_rotation,
				"linear_velocity": p.linear_velocity},
			"weapon": {
				"head_position": p.weapon_head_position(),
				# The drawn head's facing (#976): the head body is rotation-locked,
				# so its own rotation never turns; the art on it does.
				"head_rotation": _head_rotation(head, head_visual),
				# The weapon held, by its file (`_stats` is a modifier's copy
				# with no path while Big heads or Tiny weapons run).
				"head_shape_index": _weapon_index(p.weapon_stats if p.weapon_stats != null else p.get("_stats")),
				"loaded": p.has_method("special_loaded") and p.special_loaded(),
			},
			"color": slot,
			"name": rm.call("_slot_name", slot),
			"team": p.team,
			"damage": p.damage,
			"state": phase,
			"flags": _player_flags(p, head),
			"hat_spin": _hat_spin(p),
			"squash": _squash_byte(p),
		})
	return out

## Where the player's propeller hat's blades are (Hat.spin_byte()), 0 bare.
static func _hat_spin(p: Node) -> int:
	var hat: Node = p.call("hat_node") if p.has_method("hat_node") else null
	return int(hat.call("spin_byte")) if hat != null and is_instance_valid(hat) else 0

## The player's face squash (PlayerFace.squash_byte()), at rest without one.
static func _squash_byte(p: Node) -> int:
	var face: Node = p.get("_face")
	return int(face.call("squash_byte")) if face != null and is_instance_valid(face) else SnapshotScript.SQUASH_REST

static func _head_rotation(head: Node2D, head_visual: Node2D) -> float:
	if head_visual != null and is_instance_valid(head_visual) and head_visual.is_inside_tree():
		return head_visual.global_rotation
	return head.global_rotation if head != null and is_instance_valid(head) else 0.0

static func _player_flags(p: Node, head: Node2D) -> int:
	var flags: int = 0
	if head != null and is_instance_valid(head) and bool(head.get("phased")):
		flags |= SnapshotScript.PLAYER_HEAD_PHASED
	if p.has_method("eye_state") and p.eye_state() == "blink":
		flags |= SnapshotScript.PLAYER_BLINKING
	if (p as CanvasItem).modulate.a < 1.0:
		flags |= SnapshotScript.PLAYER_DIMMED
	return flags

static func _stage_bodies(stage: Node) -> Array:
	var out: Array = []
	if stage == null:
		return out
	for node: Node in stage.find_children("*", "StaticBody2D", true, false):
		if out.size() >= MAX_STAGE_BODIES:
			break
		var body: StaticBody2D = node
		out.append({"position": body.global_position, "rotation": body.global_rotation,
			"linear_velocity": Vector2.ZERO})
	return out

## Every shot in flight (issue #976): the boomstick's bullets, thrown
## boomerangs and launched hooks, each with its kind, owner and facing.
static func _projectiles(rm: Node) -> Array:
	var out: Array = []
	var players: Array = rm.get("_players")
	for node: Node in rm.get_tree().get_nodes_in_group("projectiles"):
		var shooter: Variant = node.get("shooter")
		var index: int = _weapon_index_named(str(node.get("weapon_id")))
		if index == 0 and shooter != null and is_instance_valid(shooter):
			index = _weapon_index(shooter.get("weapon_stats"))
		out.append(_shot(node, players, index, node.direction * node.speed, 0.0, SnapshotScript.PROJ_KIND_BULLET))
	for node: Node in rm.get_tree().get_nodes_in_group(BoomerangScript.GROUP):
		var flags: int = SnapshotScript.PROJ_KIND_BOOMERANG | (SnapshotScript.PROJ_GHOST if bool(node.get("ghost")) else 0)
		out.append(_shot(node, players, _special_index(node, &"boomerang"), node.get("velocity"), node.spin(), flags))
	for node: Node in rm.get_tree().get_nodes_in_group(GrappleHookScript.GROUP):
		out.append(_shot(node, players, _special_index(node, &"grapple"), Vector2.ZERO, (node as Node2D).global_rotation, SnapshotScript.PROJ_KIND_HOOK))
	return out

static func _shot(node: Node, players: Array, index: int, velocity: Variant, rotation: float, flags: int) -> Dictionary:
	var shooter: Variant = node.get("shooter")
	var owner: int = players.find(shooter) if shooter != null and is_instance_valid(shooter) else -1
	return {
		"projectile_id": node.get_instance_id() & 0xFFFF,
		"position": (node as Node2D).global_position,
		"velocity": velocity if velocity is Vector2 else Vector2.ZERO,
		"weapon_type": index,
		"owner": owner,
		"rotation": rotation,
		"flags": flags,
	}

## The weapon a thrown boomerang or launched hook came from: its shooter's,
## while that is still a weapon with the same special, else the first weapon
## that has it.
static func _special_index(node: Node, special: StringName) -> int:
	var shooter: Variant = node.get("shooter")
	if shooter != null and is_instance_valid(shooter):
		var held: Resource = shooter.get("weapon_stats")
		if held != null and StringName(held.get("special")) == special:
			return _weapon_index(held)
	for i in PickupWeaponsScript.WEAPON_PATHS.size():
		var stats: Resource = load(PickupWeaponsScript.WEAPON_PATHS[i])
		if stats != null and StringName(stats.get("special")) == special:
			return i + 1
	return 0

## The snapshot weapon index of the weapon file named `id` ("boomstick"), 0 for none.
static func _weapon_index_named(id: String) -> int:
	if id.is_empty():
		return 0
	for i in PickupWeaponsScript.WEAPON_PATHS.size():
		if PickupWeaponsScript.WEAPON_PATHS[i].get_file().get_basename() == id:
			return i + 1
	return 0

## Every flail in play (issue #976): its owner, ball and links.
static func _flails(rm: Node, players: Array) -> Array:
	var out: Array = []
	var nodes: Array = rm.get("_players")
	for entry: Dictionary in players:
		var player: Node = nodes[entry["player_id"]]
		var chain: RefCounted = player.flail_chain()
		var ball: Node2D = player.flail_ball()
		if chain == null or ball == null or not is_instance_valid(ball):
			continue
		var links: Array = []
		for link: Node2D in chain.get("links"):
			if is_instance_valid(link):
				links.append({"position": link.global_position, "rotation": link.global_rotation})
		out.append({"owner": entry["player_id"], "ball_position": ball.global_position,
			"ball_rotation": ball.global_rotation,
			"flags": SnapshotScript.FLAIL_PHASED if bool(ball.get("phased")) else 0, "links": links})
	return out

## Every KO'd player's ghost (issue #976), shown or still fading in.
static func _ghosts(rm: Node) -> Array:
	var out: Array = []
	var ghosts: Variant = rm.get("_ghosts")
	if not ghosts is Dictionary:
		return out
	for slot: int in ghosts:
		var ghost: Node2D = ghosts[slot]
		if ghost == null or not is_instance_valid(ghost):
			continue
		out.append({"owner": slot, "position": ghost.global_position,
			"alpha": ghost.alpha(), "puff": clampf(ghost.puff_progress(), 0.0, 1.0)})
	return out

## Every stage part whose look the host sends (issue #976), by its id.
## `nvars` (host-side only, never encoded) is how many of `state`'s values
## are looks rather than clocks.
static func _parts(stage: Node) -> Array:
	var out: Array = []
	if stage == null or not is_instance_valid(stage):
		return out
	for node: Node in NetSyncScript.parts_of(stage):
		if out.size() >= SnapshotScript.MAX_COUNT_U8:
			break
		out.append({"part_id": NetSyncScript.part_id(stage, node), "state": NetSyncScript.part_state(node),
			"nvars": NetSyncScript.vars_of(node).size()})
	return out

## Every runtime prop the host marked (issue #976): the soccer ball, CTF
## flags, the hill, tiebreaker rocks, the gale.
static func _props(rm: Node) -> Array:
	var out: Array = []
	for node: Node in rm.get_tree().get_nodes_in_group(NetSyncScript.PROPS_GROUP):
		if out.size() >= SnapshotScript.MAX_COUNT_U8:
			break
		if not node.is_inside_tree() or node.is_queued_for_deletion():
			continue
		out.append({"prop_id": node.get_instance_id() & 0xFFFF, "kind": NetSyncScript.prop_kind(node),
			"state": NetSyncScript.prop_state(node)})
	return out

static func _meteors(rm: Node) -> Array:
	var out: Array = []
	for node: Node in rm.get_tree().get_nodes_in_group(MeteorScript.GROUP):
		out.append({"meteor_id": node.get_instance_id() & 0xFFFF, "position": (node as Node2D).global_position,
			"velocity": node.velocity, "radius": node.radius})
	return out

static func _pickups(rm: Node) -> Array:
	var out: Array = []
	for node: Node in rm.get_tree().get_nodes_in_group("pickups"):
		out.append({
			"pickup_id": node.get_instance_id() & 0xFFFF,
			"position": node.global_position,
			"weapon_type": _weapon_index(node.weapon_stats),
			"halo": node.halo_phase_byte(),
		})
	return out

static func _modifiers(rm: Node) -> Array:
	var id: String = rm.active_modifier_id()
	var out: Array = [] if id.is_empty() else [{"modifier_id": 1, "name": id}]
	var stage: Variant = rm.get("_current_stage")
	if stage is Node and is_instance_valid(stage) and stage.get("night") == true:
		out.append({"modifier_id": NIGHT_MODIFIER_ID, "name": "night"})
	return out

static func _timer_ms(rm: Node, state: int) -> int:
	if state != 4: # State.COUNTDOWN
		return 0
	return maxi(0, int(rm.get("_countdown_until_msec")) - GameClockScript.now_msec())

static func _kill_feed(rm: Node) -> Array:
	var out: Array = []
	var feed: Control = rm.kill_feed()
	if feed == null:
		return out
	for line: String in feed.entries():
		out.append({"text": line})
	return out

static func _kill_zone_height(rm: Node) -> int:
	var zone: Node2D = rm.call("_floor_kill_zone")
	return clampi(int(zone.surface_y()), 0, 65535) if zone != null else 0

static func _announcer_text(rm: Node) -> String:
	var label: Label = rm.modifier_label()
	return label.text if label != null and label.is_visible_in_tree() else ""

# --- Sound trailer (issue #251) --------------------------------------------------
#
# `Snapshot.gd` has no sound field, so each streamed frame carries one after
# its own bytes. Layout of a frame's payload (after the relay envelope's
# KIND_SNAPSHOT byte), all integers big-endian:
#
#   [Snapshot.encode() bytes][trailer]
#
#   trailer = events, track, size, magic
#     events: u8 count (at most MAX_SOUND_EVENTS), then per event:
#               u8 name length, name (UTF-8: an `Sfx.SOUNDS` key),
#               u8 has_position (0/1), if 1: i16 x, i16 y (world px, truncated),
#               u8 strength (0..255 = 0.0..1.0)
#     track:  u8 length, UTF-8 key of the playing music track ("" = silence)
#     effects (optional, issue #976): u16 length, then `EffectStream.encode()`
#             bytes -- the host's one-shot effects since the previous frame.
#             Absent (the track ends the body) when there were none.
#     size:   u16, the byte count of events + track + effects
#     magic:  2 bytes, 0x53 0x58 ("SX")
#
# Events are the sounds played since the previous frame. A client reads the
# trailer from the END of the packet (`split_sound_trailer()` does it) and
# hands the remaining prefix to `Snapshot.decode()`. A packet without the
# magic is a plain snapshot.

const MAX_SOUND_EVENTS: int = 32
const TRAILER_MAGIC: PackedByteArray = [0x53, 0x58]

const EffectStreamScript: GDScript = preload("res://scripts/EffectStream.gd")

## `events` as [{"name": String, "position": Vector2 or null, "strength": float}];
## `effects` as `EffectStream` events (#976), none by default.
static func encode_sound_trailer(events: Array, track: String, effects: Array = []) -> PackedByteArray:
	var body := PackedByteArray()
	var count: int = mini(events.size(), MAX_SOUND_EVENTS)
	body.append(count)
	for i in count:
		var ev: Dictionary = events[i]
		var name_bytes: PackedByteArray = String(ev["name"]).to_utf8_buffer().slice(0, 255)
		body.append(name_bytes.size())
		body.append_array(name_bytes)
		var pos: Variant = ev.get("position")
		body.append(1 if pos is Vector2 else 0)
		if pos is Vector2:
			for v: float in [pos.x, pos.y]:
				var q: int = int(clampf(v, -32768.0, 32767.0)) & 0xFFFF
				body.append(q >> 8)
				body.append(q & 0xFF)
		body.append(clampi(roundi(float(ev.get("strength", 1.0)) * 255.0), 0, 255))
	var track_bytes: PackedByteArray = track.to_utf8_buffer().slice(0, 255)
	body.append(track_bytes.size())
	body.append_array(track_bytes)
	var fx: PackedByteArray = EffectStreamScript.encode(effects)
	if not fx.is_empty():
		body.append(fx.size() >> 8)
		body.append(fx.size() & 0xFF)
		body.append_array(fx)
	var out := body.duplicate()
	out.append(body.size() >> 8)
	out.append(body.size() & 0xFF)
	out.append_array(TRAILER_MAGIC)
	return out

## Splits a streamed payload into {"snapshot": PackedByteArray for
## `Snapshot.decode()`, "events": Array (as `encode_sound_trailer()` takes),
## "track": String, "effects": Array of `EffectStream` events}. No trailer:
## the whole packet is the snapshot, no events.
static func split_sound_trailer(packet: PackedByteArray) -> Dictionary:
	var n: int = packet.size()
	var none: Dictionary = {"snapshot": packet, "events": [], "track": "", "effects": []}
	if n < 5 or packet[n - 2] != TRAILER_MAGIC[0] or packet[n - 1] != TRAILER_MAGIC[1]:
		return none
	var size: int = (packet[n - 4] << 8) | packet[n - 3]
	var start: int = n - 4 - size
	if start < 0:
		return none
	# Every read stays inside the trailer body [start, end); a body that does
	# not parse to exactly its end is not a trailer, so the whole packet is
	# handed on as a plain snapshot (Snapshot.decode() rejects junk itself).
	var end: int = n - 4
	var at: int = start
	var events: Array = []
	if at >= end:
		return none
	var count: int = packet[at]
	at += 1
	for i in count:
		if at >= end:
			return none
		var name_len: int = packet[at]
		if at + 1 + name_len + 1 > end:
			return none
		var ev_name: String = packet.slice(at + 1, at + 1 + name_len).get_string_from_utf8()
		at += 1 + name_len
		var position: Variant = null
		if packet[at] == 1:
			if at + 5 > end:
				return none
			position = Vector2(_i16(packet, at + 1), _i16(packet, at + 3))
			at += 4
		at += 1
		if at >= end:
			return none
		events.append({"name": ev_name, "position": position, "strength": packet[at] / 255.0})
		at += 1
	if at >= end:
		return none
	var track_len: int = packet[at]
	if at + 1 + track_len > end:
		return none
	var track: String = packet.slice(at + 1, at + 1 + track_len).get_string_from_utf8()
	at += 1 + track_len
	var effects: Array = []
	if at != end:
		if at + 2 > end:
			return none
		var fx_len: int = (packet[at] << 8) | packet[at + 1]
		if at + 2 + fx_len != end:
			return none
		effects = EffectStreamScript.decode(packet.slice(at + 2, end))
	return {"snapshot": packet.slice(0, start), "events": events, "track": track, "effects": effects}

static func _i16(bytes: PackedByteArray, at: int) -> int:
	var v: int = (bytes[at] << 8) | bytes[at + 1]
	return v - 65536 if v > 32767 else v
