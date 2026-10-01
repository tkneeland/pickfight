extends RefCounted
## Builds the `world` Dictionary that `Snapshot.encode()` expects (issue #251,
## #212) from the live game, and the delta frames between full snapshots.
## The key names are `Snapshot.gd`'s; nothing here invents a schema. Preload
## this script by path; never reference it by `class_name` (CLAUDE.md).
##
## Keys the live game has no source for are filled with a default:
## - `modifiers[].modifier_id`: always 1 (the name carries the identity).
## - `timer_ms`: the lobby countdown's time left, else 0 (rounds are untimed).
## - `announcer_text`: the on-screen modifier banner while it shows, else "".
## - `color`: the slot number (the client picks the palette).
## - `flail` / `grapple`: one of each at most; the first player holding one.

const PickupWeaponsScript := preload("res://scripts/PickupWeapons.gd")
const GameClockScript := preload("res://scripts/GameClock.gd")

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
				"weapon": p["weapon"], "damage": p["damage"], "state": p["state"]})
	before = _by_key(previous.get("projectiles", []), "projectile_id")
	for p: Dictionary in world.get("projectiles", []):
		if before.get(p["projectile_id"]) != p:
			entities.append({"type": 0x02, "id": p["projectile_id"],
				"position": p["position"], "velocity": p["velocity"]})
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
	if world.get("timer_ms") != previous.get("timer_ms"):
		entities.append({"type": 0x07, "id": 0, "timer_ms": world.get("timer_ms", 0)})
	var old_scores: Dictionary = previous.get("scores", {})
	for slot: int in world.get("scores", {}):
		if old_scores.get(slot) != world["scores"][slot]:
			entities.append({"type": 0x08, "id": slot, "score": world["scores"][slot]})
	if world.get("kill_zone_height") != previous.get("kill_zone_height"):
		entities.append({"type": 0x0A, "id": 0, "height": world.get("kill_zone_height", 0)})
	return {"is_full_snapshot": false, "delta_entities": entities}

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
		var phase: int = STATE_DEAD
		if p.alive:
			phase = STATE_PROTECTED if p.spawn_protected else STATE_ALIVE
		out.append({
			"player_id": slot,
			"body": {"position": p.global_position, "rotation": p.global_rotation,
				"linear_velocity": p.linear_velocity},
			"weapon": {
				"head_position": p.weapon_head_position(),
				"head_rotation": head.global_rotation if head != null else 0.0,
				"head_shape_index": _weapon_index(p.get("_stats")),
			},
			"color": slot,
			"name": rm.call("_slot_name", slot),
			"team": p.team,
			"damage": p.damage,
			"state": phase,
		})
	return out

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

static func _projectiles(rm: Node) -> Array:
	var out: Array = []
	for node: Node in rm.get_tree().get_nodes_in_group("projectiles"):
		var shooter: Variant = node.get("shooter")
		out.append({
			"projectile_id": node.get_instance_id() & 0xFFFF,
			"position": node.global_position,
			"velocity": node.direction * node.speed,
			"weapon_type": _weapon_index(shooter.get("_stats")) if shooter != null else 0,
		})
	return out

static func _pickups(rm: Node) -> Array:
	var out: Array = []
	for node: Node in rm.get_tree().get_nodes_in_group("pickups"):
		out.append({
			"pickup_id": node.get_instance_id() & 0xFFFF,
			"position": node.global_position,
			"weapon_type": _weapon_index(node.weapon_stats),
		})
	return out

static func _modifiers(rm: Node) -> Array:
	var id: String = rm.active_modifier_id()
	return [] if id.is_empty() else [{"modifier_id": 1, "name": id}]

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
#     size:   u16, the byte count of events + track
#     magic:  2 bytes, 0x53 0x58 ("SX")
#
# Events are the sounds played since the previous frame. A client reads the
# trailer from the END of the packet (`split_sound_trailer()` does it) and
# hands the remaining prefix to `Snapshot.decode()`. A packet without the
# magic is a plain snapshot.

const MAX_SOUND_EVENTS: int = 32
const TRAILER_MAGIC: PackedByteArray = [0x53, 0x58]

## `events` as [{"name": String, "position": Vector2 or null, "strength": float}].
static func encode_sound_trailer(events: Array, track: String) -> PackedByteArray:
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
	var out := body.duplicate()
	out.append(body.size() >> 8)
	out.append(body.size() & 0xFF)
	out.append_array(TRAILER_MAGIC)
	return out

## Splits a streamed payload into {"snapshot": PackedByteArray for
## `Snapshot.decode()`, "events": Array (as `encode_sound_trailer()` takes),
## "track": String}. No trailer: the whole packet is the snapshot, no events.
static func split_sound_trailer(packet: PackedByteArray) -> Dictionary:
	var n: int = packet.size()
	var none: Dictionary = {"snapshot": packet, "events": [], "track": ""}
	if n < 5 or packet[n - 2] != TRAILER_MAGIC[0] or packet[n - 1] != TRAILER_MAGIC[1]:
		return none
	var size: int = (packet[n - 4] << 8) | packet[n - 3]
	var start: int = n - 4 - size
	if start < 0:
		return none
	var at: int = start
	var events: Array = []
	var count: int = packet[at]
	at += 1
	for i in count:
		var name_len: int = packet[at]
		var ev_name: String = packet.slice(at + 1, at + 1 + name_len).get_string_from_utf8()
		at += 1 + name_len
		var position: Variant = null
		if packet[at] == 1:
			position = Vector2(_i16(packet, at + 1), _i16(packet, at + 3))
			at += 4
		at += 1
		events.append({"name": ev_name, "position": position, "strength": packet[at] / 255.0})
		at += 1
	var track_len: int = packet[at]
	var track: String = packet.slice(at + 1, at + 1 + track_len).get_string_from_utf8()
	return {"snapshot": packet.slice(0, start), "events": events, "track": track}

static func _i16(bytes: PackedByteArray, at: int) -> int:
	var v: int = (bytes[at] << 8) | bytes[at + 1]
	return v - 65536 if v > 32767 else v
