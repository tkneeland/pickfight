## Binary snapshot encoding/decoding for remote PC clients.
## Carries: stage id, players (body pose, weapon, color, name, team, HP),
## projectiles, pickups, flail/grapple, kill-zone height, round state,
## scores, kill feed, announcer text, timer, modifiers.
##
## Full snapshot every ~1s; frames in between carry only deltas.
## Rate: 30 Hz. Budget: ≤ 40 KB/s per client with 8 players.
## Positions quantized to 16-bit.

## Marker for a full snapshot (highest bit of type byte).
const FULL_SNAPSHOT_MARKER: int = 0x80
## Type codes for different entity kinds in delta snapshots.
const TYPE_PLAYER: int = 0x01
const TYPE_PROJECTILE: int = 0x02
const TYPE_PICKUP: int = 0x03
const TYPE_FLAIL: int = 0x04
const TYPE_GRAPPLE: int = 0x05
const TYPE_MODIFIER: int = 0x06
const TYPE_TIMER: int = 0x07
const TYPE_SCORES: int = 0x08
const TYPE_KILL_FEED: int = 0x09
const TYPE_KILL_ZONE: int = 0x0A

static func encode(world: Dictionary) -> PackedByteArray:
	var bytes = PackedByteArray()

	var is_full = world.get("is_full_snapshot", false)
	var type_byte = FULL_SNAPSHOT_MARKER if is_full else 0x00
	bytes.append(type_byte)

	if is_full:
		_encode_stage_id(bytes, world)
		_encode_static_stage_bodies(bytes, world)
		_encode_all_players(bytes, world)
		_encode_all_projectiles(bytes, world)
		_encode_all_pickups(bytes, world)
		_encode_flail(bytes, world)
		_encode_grapple(bytes, world)
		_encode_modifiers(bytes, world)
		_encode_round_state(bytes, world)
	else:
		_encode_delta_entities(bytes, world)

	return bytes

static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty():
		return {}

	var offset = 0
	var type_byte = bytes[offset]
	offset += 1

	var is_full = (type_byte & FULL_SNAPSHOT_MARKER) != 0
	var snapshot = {"is_full_snapshot": is_full}

	if is_full:
		snapshot["stage_id"] = _decode_u16(bytes, offset)
		offset += 2

		var static_bodies = _decode_static_stage_bodies(bytes, offset)
		snapshot["static_stage_bodies"] = static_bodies["bodies"]
		offset = static_bodies["offset"]

		var players = _decode_all_players(bytes, offset)
		snapshot["players"] = players["players"]
		offset = players["offset"]

		var projectiles = _decode_all_projectiles(bytes, offset)
		snapshot["projectiles"] = projectiles["projectiles"]
		offset = projectiles["offset"]

		var pickups = _decode_all_pickups(bytes, offset)
		snapshot["pickups"] = pickups["pickups"]
		offset = pickups["offset"]

		var flail = _decode_flail(bytes, offset)
		snapshot["flail"] = flail["flail"]
		offset = flail["offset"]

		var grapple = _decode_grapple(bytes, offset)
		snapshot["grapple"] = grapple["grapple"]
		offset = grapple["offset"]

		var modifiers = _decode_modifiers(bytes, offset)
		snapshot["modifiers"] = modifiers["modifiers"]
		offset = modifiers["offset"]

		var round_state = _decode_round_state(bytes, offset)
		snapshot.merge(round_state["state"])
	else:
		var deltas = _decode_delta_entities(bytes, offset)
		snapshot.merge(deltas)

	return snapshot

# ============================================================================
# ENCODING HELPERS
# ============================================================================

static func _encode_stage_id(bytes: PackedByteArray, world: Dictionary) -> void:
	var stage_id = world.get("stage_id", 0)
	_append_u16(bytes, stage_id)

static func _encode_static_stage_bodies(bytes: PackedByteArray, world: Dictionary) -> void:
	var bodies = world.get("static_stage_bodies", [])
	bytes.append(len(bodies) & 0xFF)
	for body in bodies:
		_encode_body_transform(bytes, body)

static func _encode_all_players(bytes: PackedByteArray, world: Dictionary) -> void:
	var players = world.get("players", [])
	bytes.append(len(players) & 0xFF)
	for player in players:
		_encode_player(bytes, player)

static func _encode_player(bytes: PackedByteArray, player: Dictionary) -> void:
	_append_u16(bytes, player.get("player_id", 0))
	_encode_body_transform(bytes, player.get("body", {}))
	_encode_weapon_segments(bytes, player.get("weapon", {}))
	bytes.append(player.get("color", 0) & 0xFF)
	_encode_string(bytes, player.get("name", ""))
	bytes.append(player.get("team", 0) & 0xFF)
	_append_u16(bytes, int(player.get("damage", 0)))
	bytes.append(player.get("state", 0) & 0xFF)

static func _encode_body_transform(bytes: PackedByteArray, body: Dictionary) -> void:
	_encode_vector2_quantized(bytes, body.get("position", Vector2.ZERO))
	_encode_rotation_u16(bytes, body.get("rotation", 0.0))
	_encode_vector2_quantized(bytes, body.get("linear_velocity", Vector2.ZERO))

static func _encode_weapon_segments(bytes: PackedByteArray, weapon: Dictionary) -> void:
	_encode_vector2_quantized(bytes, weapon.get("head_position", Vector2.ZERO))
	_encode_rotation_u16(bytes, weapon.get("head_rotation", 0.0))
	_append_u16(bytes, int(weapon.get("head_shape_index", 0)))

static func _encode_all_projectiles(bytes: PackedByteArray, world: Dictionary) -> void:
	var projectiles = world.get("projectiles", [])
	bytes.append(len(projectiles) & 0xFF)
	for proj in projectiles:
		_encode_projectile(bytes, proj)

static func _encode_projectile(bytes: PackedByteArray, proj: Dictionary) -> void:
	_append_u16(bytes, proj.get("projectile_id", 0))
	_encode_vector2_quantized(bytes, proj.get("position", Vector2.ZERO))
	_encode_vector2_quantized(bytes, proj.get("velocity", Vector2.ZERO))
	bytes.append(proj.get("weapon_type", 0) & 0xFF)

static func _encode_all_pickups(bytes: PackedByteArray, world: Dictionary) -> void:
	var pickups = world.get("pickups", [])
	bytes.append(len(pickups) & 0xFF)
	for pickup in pickups:
		_encode_pickup(bytes, pickup)

static func _encode_pickup(bytes: PackedByteArray, pickup: Dictionary) -> void:
	_append_u16(bytes, pickup.get("pickup_id", 0))
	_encode_vector2_quantized(bytes, pickup.get("position", Vector2.ZERO))
	_append_u16(bytes, pickup.get("weapon_type", 0))

static func _encode_flail(bytes: PackedByteArray, world: Dictionary) -> void:
	var flail = world.get("flail", {})
	var has_flail = not flail.is_empty()
	bytes.append(1 if has_flail else 0)
	if has_flail:
		_append_u16(bytes, flail.get("flail_id", 0))
		_encode_vector2_quantized(bytes, flail.get("ball_position", Vector2.ZERO))
		_encode_vector2_quantized(bytes, flail.get("ball_velocity", Vector2.ZERO))

static func _encode_grapple(bytes: PackedByteArray, world: Dictionary) -> void:
	var grapple = world.get("grapple", {})
	var has_grapple = not grapple.is_empty()
	bytes.append(1 if has_grapple else 0)
	if has_grapple:
		_append_u16(bytes, grapple.get("grapple_id", 0))
		_encode_vector2_quantized(bytes, grapple.get("hook_position", Vector2.ZERO))
		_encode_vector2_quantized(bytes, grapple.get("rope_end", Vector2.ZERO))

static func _encode_modifiers(bytes: PackedByteArray, world: Dictionary) -> void:
	var modifiers = world.get("modifiers", [])
	bytes.append(len(modifiers) & 0xFF)
	for mod in modifiers:
		_append_u16(bytes, mod.get("modifier_id", 0))
		_encode_string(bytes, mod.get("name", ""))

static func _encode_round_state(bytes: PackedByteArray, world: Dictionary) -> void:
	bytes.append(world.get("round_phase", 0) & 0xFF)
	_append_u32(bytes, world.get("timer_ms", 0))

	var scores = world.get("scores", {})
	_append_u16(bytes, len(scores))
	for player_id in scores:
		_append_u16(bytes, player_id)
		_append_u16(bytes, scores[player_id])

	var kill_feed = world.get("kill_feed", [])
	bytes.append(len(kill_feed) & 0xFF)
	for entry in kill_feed:
		_encode_string(bytes, entry.get("text", ""))

	_append_u16(bytes, int(world.get("kill_zone_height", 0.0)))
	_encode_string(bytes, world.get("announcer_text", ""))

static func _encode_delta_entities(bytes: PackedByteArray, world: Dictionary) -> void:
	var entities = world.get("delta_entities", [])
	bytes.append(len(entities) & 0xFF)
	for entity in entities:
		var entity_type = entity.get("type", 0)
		bytes.append(entity_type & 0xFF)
		_append_u16(bytes, entity.get("id", 0))
		match entity_type:
			TYPE_PLAYER:
				_encode_body_transform(bytes, entity.get("body", {}))
				_encode_weapon_segments(bytes, entity.get("weapon", {}))
				_append_u16(bytes, int(entity.get("damage", 0)))
				bytes.append(entity.get("state", 0) & 0xFF)
			TYPE_PROJECTILE:
				_encode_vector2_quantized(bytes, entity.get("position", Vector2.ZERO))
				_encode_vector2_quantized(bytes, entity.get("velocity", Vector2.ZERO))
			TYPE_PICKUP:
				_encode_vector2_quantized(bytes, entity.get("position", Vector2.ZERO))
			TYPE_FLAIL, TYPE_GRAPPLE:
				_encode_vector2_quantized(bytes, entity.get("pos1", Vector2.ZERO))
				_encode_vector2_quantized(bytes, entity.get("pos2", Vector2.ZERO))
			TYPE_TIMER:
				_append_u32(bytes, entity.get("timer_ms", 0))
			TYPE_SCORES:
				_append_u16(bytes, entity.get("score", 0))
			TYPE_KILL_ZONE:
				_append_u16(bytes, int(entity.get("height", 0.0)))

# ============================================================================
# DECODING HELPERS
# ============================================================================

static func _decode_static_stage_bodies(bytes: PackedByteArray, offset: int) -> Dictionary:
	var count = bytes[offset]
	offset += 1
	var bodies = []
	for i in range(count):
		var body_data = _decode_body_transform(bytes, offset)
		bodies.append(body_data["body"])
		offset = body_data["offset"]
	return {"bodies": bodies, "offset": offset}

static func _decode_all_players(bytes: PackedByteArray, offset: int) -> Dictionary:
	var count = bytes[offset]
	offset += 1
	var players = []
	for i in range(count):
		var player_id = _decode_u16(bytes, offset)
		offset += 2
		var body_data = _decode_body_transform(bytes, offset)
		offset = body_data["offset"]
		var weapon_data = _decode_weapon_segments(bytes, offset)
		offset = weapon_data["offset"]
		var color = bytes[offset]
		offset += 1
		var name_data = _decode_string(bytes, offset)
		offset = name_data["offset"]
		var team = bytes[offset]
		offset += 1
		var damage = _decode_u16(bytes, offset)
		offset += 2
		var state = bytes[offset]
		offset += 1

		players.append({
			"player_id": player_id,
			"body": body_data["body"],
			"weapon": weapon_data["weapon"],
			"color": color,
			"name": name_data["string"],
			"team": team,
			"damage": damage,
			"state": state,
		})
	return {"players": players, "offset": offset}

static func _decode_body_transform(bytes: PackedByteArray, offset: int) -> Dictionary:
	var position = _decode_vector2_quantized(bytes, offset)
	offset += 4
	var rotation = _decode_rotation_u16(bytes, offset)
	offset += 2
	var velocity = _decode_vector2_quantized(bytes, offset)
	offset += 4
	return {"body": {
		"position": position,
		"rotation": rotation,
		"linear_velocity": velocity,
	}, "offset": offset}

static func _decode_weapon_segments(bytes: PackedByteArray, offset: int) -> Dictionary:
	var head_pos = _decode_vector2_quantized(bytes, offset)
	offset += 4
	var head_rot = _decode_rotation_u16(bytes, offset)
	offset += 2
	var shape_idx = _decode_u16(bytes, offset)
	offset += 2
	return {"weapon": {
		"head_position": head_pos,
		"head_rotation": head_rot,
		"head_shape_index": shape_idx,
	}, "offset": offset}

static func _decode_all_projectiles(bytes: PackedByteArray, offset: int) -> Dictionary:
	var count = bytes[offset]
	offset += 1
	var projectiles = []
	for i in range(count):
		var proj_id = _decode_u16(bytes, offset)
		offset += 2
		var position = _decode_vector2_quantized(bytes, offset)
		offset += 4
		var velocity = _decode_vector2_quantized(bytes, offset)
		offset += 4
		var weapon_type = bytes[offset]
		offset += 1
		projectiles.append({
			"projectile_id": proj_id,
			"position": position,
			"velocity": velocity,
			"weapon_type": weapon_type,
		})
	return {"projectiles": projectiles, "offset": offset}

static func _decode_all_pickups(bytes: PackedByteArray, offset: int) -> Dictionary:
	var count = bytes[offset]
	offset += 1
	var pickups = []
	for i in range(count):
		var pickup_id = _decode_u16(bytes, offset)
		offset += 2
		var position = _decode_vector2_quantized(bytes, offset)
		offset += 4
		var weapon_type = _decode_u16(bytes, offset)
		offset += 2
		pickups.append({
			"pickup_id": pickup_id,
			"position": position,
			"weapon_type": weapon_type,
		})
	return {"pickups": pickups, "offset": offset}

static func _decode_flail(bytes: PackedByteArray, offset: int) -> Dictionary:
	var has_flail = bytes[offset]
	offset += 1
	var flail = {}
	if has_flail:
		var flail_id = _decode_u16(bytes, offset)
		offset += 2
		var ball_pos = _decode_vector2_quantized(bytes, offset)
		offset += 4
		var ball_vel = _decode_vector2_quantized(bytes, offset)
		offset += 4
		flail = {
			"flail_id": flail_id,
			"ball_position": ball_pos,
			"ball_velocity": ball_vel,
		}
	return {"flail": flail, "offset": offset}

static func _decode_grapple(bytes: PackedByteArray, offset: int) -> Dictionary:
	var has_grapple = bytes[offset]
	offset += 1
	var grapple = {}
	if has_grapple:
		var grapple_id = _decode_u16(bytes, offset)
		offset += 2
		var hook_pos = _decode_vector2_quantized(bytes, offset)
		offset += 4
		var rope_end = _decode_vector2_quantized(bytes, offset)
		offset += 4
		grapple = {
			"grapple_id": grapple_id,
			"hook_position": hook_pos,
			"rope_end": rope_end,
		}
	return {"grapple": grapple, "offset": offset}

static func _decode_modifiers(bytes: PackedByteArray, offset: int) -> Dictionary:
	var count = bytes[offset]
	offset += 1
	var modifiers = []
	for i in range(count):
		var mod_id = _decode_u16(bytes, offset)
		offset += 2
		var name_data = _decode_string(bytes, offset)
		offset = name_data["offset"]
		modifiers.append({
			"modifier_id": mod_id,
			"name": name_data["string"],
		})
	return {"modifiers": modifiers, "offset": offset}

static func _decode_round_state(bytes: PackedByteArray, offset: int) -> Dictionary:
	var round_phase = bytes[offset]
	offset += 1
	var timer_ms = _decode_u32(bytes, offset)
	offset += 4

	var score_count = _decode_u16(bytes, offset)
	offset += 2
	var scores = {}
	for i in range(score_count):
		var player_id = _decode_u16(bytes, offset)
		offset += 2
		var score = _decode_u16(bytes, offset)
		offset += 2
		scores[player_id] = score

	var kill_feed_count = bytes[offset]
	offset += 1
	var kill_feed = []
	for i in range(kill_feed_count):
		var text_data = _decode_string(bytes, offset)
		offset = text_data["offset"]
		kill_feed.append({"text": text_data["string"]})

	var kill_zone_height = int(_decode_u16(bytes, offset))
	offset += 2
	var announcer_data = _decode_string(bytes, offset)
	offset = announcer_data["offset"]

	return {
		"state": {
			"round_phase": round_phase,
			"timer_ms": timer_ms,
			"scores": scores,
			"kill_feed": kill_feed,
			"kill_zone_height": kill_zone_height,
			"announcer_text": announcer_data["string"],
		}
	}

static func _decode_delta_entities(bytes: PackedByteArray, offset: int) -> Dictionary:
	var count = bytes[offset]
	offset += 1
	var deltas = {"delta_entities": []}
	for i in range(count):
		var entity_type = bytes[offset]
		offset += 1
		var entity_id = _decode_u16(bytes, offset)
		offset += 2
		var entity = {"type": entity_type, "id": entity_id}

		match entity_type:
			TYPE_PLAYER:
				var body_data = _decode_body_transform(bytes, offset)
				offset = body_data["offset"]
				var weapon_data = _decode_weapon_segments(bytes, offset)
				offset = weapon_data["offset"]
				var damage = _decode_u16(bytes, offset)
				offset += 2
				var state = bytes[offset]
				offset += 1
				entity.merge(body_data["body"])
				entity.merge(weapon_data["weapon"])
				entity["damage"] = damage
				entity["state"] = state
			TYPE_PROJECTILE:
				var position = _decode_vector2_quantized(bytes, offset)
				offset += 4
				var velocity = _decode_vector2_quantized(bytes, offset)
				offset += 4
				entity["position"] = position
				entity["velocity"] = velocity
			TYPE_PICKUP:
				var position = _decode_vector2_quantized(bytes, offset)
				offset += 4
				entity["position"] = position
			TYPE_FLAIL, TYPE_GRAPPLE:
				var pos1 = _decode_vector2_quantized(bytes, offset)
				offset += 4
				var pos2 = _decode_vector2_quantized(bytes, offset)
				offset += 4
				entity["pos1"] = pos1
				entity["pos2"] = pos2
			TYPE_TIMER:
				var timer_ms = _decode_u32(bytes, offset)
				offset += 4
				entity["timer_ms"] = timer_ms
			TYPE_SCORES:
				var score = _decode_u16(bytes, offset)
				offset += 2
				entity["score"] = score
			TYPE_KILL_ZONE:
				var height = _decode_u16(bytes, offset)
				offset += 2
				entity["height"] = height

		deltas["delta_entities"].append(entity)

	return deltas

# ============================================================================
# BINARY UTILITIES
# ============================================================================

static func _append_u16(bytes: PackedByteArray, value: int) -> void:
	bytes.append((value >> 8) & 0xFF)
	bytes.append(value & 0xFF)

static func _append_u32(bytes: PackedByteArray, value: int) -> void:
	bytes.append((value >> 24) & 0xFF)
	bytes.append((value >> 16) & 0xFF)
	bytes.append((value >> 8) & 0xFF)
	bytes.append(value & 0xFF)

static func _decode_u16(bytes: PackedByteArray, offset: int) -> int:
	return (bytes[offset] << 8) | bytes[offset + 1]

static func _decode_u32(bytes: PackedByteArray, offset: int) -> int:
	return (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3]

static func _encode_vector2_quantized(bytes: PackedByteArray, v: Vector2) -> void:
	var x = int(clamp(v.x, -32768, 32767))
	var y = int(clamp(v.y, -32768, 32767))
	_append_u16(bytes, x & 0xFFFF)
	_append_u16(bytes, y & 0xFFFF)

static func _decode_vector2_quantized(bytes: PackedByteArray, offset: int) -> Vector2:
	var x = _decode_i16(bytes, offset)
	var y = _decode_i16(bytes, offset + 2)
	return Vector2(x, y)

static func _decode_i16(bytes: PackedByteArray, offset: int) -> int:
	var value = _decode_u16(bytes, offset)
	if value > 32767:
		value = -(65536 - value)
	return value

static func _encode_rotation_u16(bytes: PackedByteArray, rotation: float) -> void:
	var normalized = fmod(rotation, TAU)
	if normalized < 0:
		normalized += TAU
	var quantized = int((normalized / TAU) * 65535) & 0xFFFF
	_append_u16(bytes, quantized)

static func _decode_rotation_u16(bytes: PackedByteArray, offset: int) -> float:
	var quantized = _decode_u16(bytes, offset)
	return (quantized / 65535.0) * TAU

static func _encode_string(bytes: PackedByteArray, s: String) -> void:
	var utf8_bytes = s.to_utf8_buffer()
	var length = min(len(utf8_bytes), 255)
	bytes.append(length)
	for i in range(length):
		bytes.append(utf8_bytes[i])

static func _decode_string(bytes: PackedByteArray, offset: int) -> Dictionary:
	var length = bytes[offset]
	offset += 1
	var string_bytes = PackedByteArray()
	for i in range(length):
		string_bytes.append(bytes[offset + i])
	var string_value = string_bytes.get_string_from_utf8()
	return {"string": string_value, "offset": offset + length}
