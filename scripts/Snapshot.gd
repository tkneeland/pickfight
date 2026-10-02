## Binary snapshot encoding/decoding for remote PC clients.
## Carries: stage id, players (body pose, weapon, color, name, team, HP),
## projectiles, pickups, flail/grapple, kill-zone height, round state,
## scores, kill feed, announcer text, timer, modifiers.
##
## Full snapshot every ~1s; frames in between carry only deltas.
## Rate: 30 Hz. Budget: ≤ 40 KB/s per client with 8 players.
## Positions quantized to 16-bit (rounded to the nearest pixel).
##
## `decode()` never raises on bad input: a truncated, hostile or unknown-version
## frame returns `{}`. Trailing bytes after a frame are ignored (the sound
## trailer of SnapshotCapture rides there). `encode()` clamps every value into
## its field's range, so NaN, floats, negatives and oversized counts cannot
## error or wrap.

## Marker for a full snapshot (highest bit of type byte).
const FULL_SNAPSHOT_MARKER: int = 0x80
## Wire format version, in the low 7 bits of the first byte (the top bit is
## the full-snapshot marker). `decode()` rejects any other version.
const FORMAT_VERSION: int = 1
const VERSION_MASK: int = 0x7F
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
## Counts are one byte (255 max); `encode()` clamps the count and the loop together.
const MAX_COUNT_U8: int = 255
const MAX_COUNT_U16: int = 65535

static func encode(world: Dictionary) -> PackedByteArray:
	var bytes = PackedByteArray()
	var is_full = bool(world.get("is_full_snapshot", false))
	bytes.append((FULL_SNAPSHOT_MARKER if is_full else 0) | FORMAT_VERSION)
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

## Decodes one frame. Returns {} when the bytes are empty, truncated, of an
## unknown version, or hold an unknown delta type.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty():
		return {}
	var r := _Reader.new(bytes)
	var type_byte: int = r.u8()
	if (type_byte & VERSION_MASK) != FORMAT_VERSION:
		return {}
	var is_full: bool = (type_byte & FULL_SNAPSHOT_MARKER) != 0
	var snapshot: Dictionary = {"is_full_snapshot": is_full}
	if is_full:
		snapshot["stage_id"] = r.u16()
		snapshot["static_stage_bodies"] = _decode_static_stage_bodies(r)
		snapshot["players"] = _decode_all_players(r)
		snapshot["projectiles"] = _decode_all_projectiles(r)
		snapshot["pickups"] = _decode_all_pickups(r)
		snapshot["flail"] = _decode_flail(r)
		snapshot["grapple"] = _decode_grapple(r)
		snapshot["modifiers"] = _decode_modifiers(r)
		snapshot.merge(_decode_round_state(r))
	else:
		snapshot["delta_entities"] = _decode_delta_entities(r)
	if not r.ok:
		return {}
	return snapshot

## Applies a decoded delta frame onto a decoded full snapshot and returns the
## updated copy (neither argument is changed). Entities the full snapshot does
## not hold (a player, projectile or pickup that appeared since) are skipped:
## their static fields travel only in the next full snapshot.
static func apply_delta(full: Dictionary, delta: Dictionary) -> Dictionary:
	var out: Dictionary = full.duplicate(true)
	for e: Dictionary in delta.get("delta_entities", []):
		var id: int = e.get("id", 0)
		match e.get("type", 0):
			TYPE_PLAYER:
				var p: Dictionary = _find(out.get("players", []), "player_id", id)
				if not p.is_empty():
					p["body"] = {"position": e["position"], "rotation": e["rotation"],
						"linear_velocity": e["linear_velocity"]}
					p["weapon"] = {"head_position": e["head_position"],
						"head_rotation": e["head_rotation"], "head_shape_index": e["head_shape_index"]}
					p["damage"] = e["damage"]
					p["state"] = e["state"]
			TYPE_PROJECTILE:
				var p: Dictionary = _find(out.get("projectiles", []), "projectile_id", id)
				if not p.is_empty():
					p["position"] = e["position"]
					p["velocity"] = e["velocity"]
			TYPE_PICKUP:
				var p: Dictionary = _find(out.get("pickups", []), "pickup_id", id)
				if not p.is_empty():
					p["position"] = e["position"]
			TYPE_FLAIL:
				out["flail"] = {"flail_id": id, "ball_position": e["pos1"], "ball_velocity": e["pos2"]}
			TYPE_GRAPPLE:
				out["grapple"] = {"grapple_id": id, "hook_position": e["pos1"], "rope_end": e["pos2"]}
			TYPE_MODIFIER:
				var m: Dictionary = _find(out.get("modifiers", []), "modifier_id", id)
				if m.is_empty():
					out["modifiers"].append({"modifier_id": id, "name": e["name"]})
				else:
					m["name"] = e["name"]
			TYPE_TIMER:
				out["timer_ms"] = e["timer_ms"]
			TYPE_SCORES:
				out["scores"][id] = e["score"]
			TYPE_KILL_FEED:
				out["kill_feed"].append({"text": e["text"]})
			TYPE_KILL_ZONE:
				out["kill_zone_height"] = e["height"]
	return out

static func _find(list: Array, key: String, id: int) -> Dictionary:
	for entry: Dictionary in list:
		if entry.get(key) == id:
			return entry
	return {}

# ============================================================================
# READER
# ============================================================================

## The bounded reader every decode goes through. An overrun clears `ok` and
## every read after it returns 0 / "" instead of indexing out of range.
class _Reader extends RefCounted:
	var bytes: PackedByteArray
	var pos: int = 0
	var ok: bool = true

	func _init(b: PackedByteArray) -> void:
		bytes = b

	func remaining() -> int:
		return bytes.size() - pos

	func need(n: int) -> bool:
		if not ok or n < 0 or pos + n > bytes.size():
			ok = false
			return false
		return true

	func u8() -> int:
		if not need(1):
			return 0
		pos += 1
		return bytes[pos - 1]

	func u16() -> int:
		if not need(2):
			return 0
		pos += 2
		return (bytes[pos - 2] << 8) | bytes[pos - 1]

	func i16() -> int:
		var v: int = u16()
		return v - 65536 if v > 32767 else v

	func u32() -> int:
		if not need(4):
			return 0
		pos += 4
		return (bytes[pos - 4] << 24) | (bytes[pos - 3] << 16) | (bytes[pos - 2] << 8) | bytes[pos - 1]

	func vec2() -> Vector2:
		var x: int = i16()
		var y: int = i16()
		return Vector2(x, y)

	func rotation() -> float:
		return (u16() / 65535.0) * TAU

	func text() -> String:
		var n: int = u8()
		if not need(n):
			return ""
		pos += n
		return bytes.slice(pos - n, pos).get_string_from_utf8()

	## A count whose items are each at least `min_size` bytes: a count the rest
	## of the frame cannot hold marks the frame bad and returns 0.
	func count(n: int, min_size: int) -> int:
		if not ok:
			return 0
		if n * min_size > remaining():
			ok = false
			return 0
		return n

# ============================================================================
# ENCODING HELPERS
# ============================================================================

## Any value as a float that is safe to round: non-numbers and NaN are 0, infinities clamp.
static func _num(v: Variant) -> float:
	if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
		return 0.0
	var f: float = v
	if is_nan(f):
		return 0.0
	return clampf(f, -1.0e15, 1.0e15)

static func _int(v: Variant, lo: int, hi: int) -> int:
	return clampi(roundi(_num(v)), lo, hi)

## Display values (damage percent, kill-zone height) truncate, as `int()` did, rather than round.
static func _floor(v: Variant) -> float:
	return floorf(_num(v))

## Team byte: 255 means "no team" (the game's -1); anything else clamps to 0..255.
static func _append_team(bytes: PackedByteArray, team: Variant) -> void:
	bytes.append(255 if _num(team) < 0.0 else _int(team, 0, 255))

static func _vec(v: Variant) -> Vector2:
	return v if v is Vector2 else Vector2.ZERO

static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}

static func _arr(v: Variant) -> Array:
	return v if v is Array else []

static func _append_u8(bytes: PackedByteArray, value: Variant) -> void:
	bytes.append(_int(value, 0, 255))

static func _encode_stage_id(bytes: PackedByteArray, world: Dictionary) -> void:
	_append_u16(bytes, world.get("stage_id", 0))

static func _encode_static_stage_bodies(bytes: PackedByteArray, world: Dictionary) -> void:
	var bodies: Array = _arr(world.get("static_stage_bodies", []))
	var n: int = mini(bodies.size(), MAX_COUNT_U8)
	bytes.append(n)
	for i in n:
		_encode_body_transform(bytes, _dict(bodies[i]))

static func _encode_all_players(bytes: PackedByteArray, world: Dictionary) -> void:
	var players: Array = _arr(world.get("players", []))
	var n: int = mini(players.size(), MAX_COUNT_U8)
	bytes.append(n)
	for i in n:
		_encode_player(bytes, _dict(players[i]))

static func _encode_player(bytes: PackedByteArray, player: Dictionary) -> void:
	_append_u16(bytes, player.get("player_id", 0))
	_encode_body_transform(bytes, _dict(player.get("body", {})))
	_encode_weapon_segments(bytes, _dict(player.get("weapon", {})))
	_append_u8(bytes, player.get("color", 0))
	_encode_string(bytes, player.get("name", ""))
	_append_team(bytes, player.get("team", 0))
	_append_u16(bytes, _floor(player.get("damage", 0)))
	_append_u8(bytes, player.get("state", 0))

static func _encode_body_transform(bytes: PackedByteArray, body: Dictionary) -> void:
	_encode_vector2_quantized(bytes, _vec(body.get("position", Vector2.ZERO)))
	_encode_rotation_u16(bytes, body.get("rotation", 0.0))
	_encode_vector2_quantized(bytes, _vec(body.get("linear_velocity", Vector2.ZERO)))

static func _encode_weapon_segments(bytes: PackedByteArray, weapon: Dictionary) -> void:
	_encode_vector2_quantized(bytes, _vec(weapon.get("head_position", Vector2.ZERO)))
	_encode_rotation_u16(bytes, weapon.get("head_rotation", 0.0))
	_append_u16(bytes, weapon.get("head_shape_index", 0))

static func _encode_all_projectiles(bytes: PackedByteArray, world: Dictionary) -> void:
	var projectiles: Array = _arr(world.get("projectiles", []))
	var n: int = mini(projectiles.size(), MAX_COUNT_U8)
	bytes.append(n)
	for i in n:
		_encode_projectile(bytes, _dict(projectiles[i]))

static func _encode_projectile(bytes: PackedByteArray, proj: Dictionary) -> void:
	_append_u16(bytes, proj.get("projectile_id", 0))
	_encode_vector2_quantized(bytes, _vec(proj.get("position", Vector2.ZERO)))
	_encode_vector2_quantized(bytes, _vec(proj.get("velocity", Vector2.ZERO)))
	_append_u8(bytes, proj.get("weapon_type", 0))

static func _encode_all_pickups(bytes: PackedByteArray, world: Dictionary) -> void:
	var pickups: Array = _arr(world.get("pickups", []))
	var n: int = mini(pickups.size(), MAX_COUNT_U8)
	bytes.append(n)
	for i in n:
		_encode_pickup(bytes, _dict(pickups[i]))

static func _encode_pickup(bytes: PackedByteArray, pickup: Dictionary) -> void:
	_append_u16(bytes, pickup.get("pickup_id", 0))
	_encode_vector2_quantized(bytes, _vec(pickup.get("position", Vector2.ZERO)))
	_append_u16(bytes, pickup.get("weapon_type", 0))

static func _encode_flail(bytes: PackedByteArray, world: Dictionary) -> void:
	var flail: Dictionary = _dict(world.get("flail", {}))
	bytes.append(0 if flail.is_empty() else 1)
	if not flail.is_empty():
		_append_u16(bytes, flail.get("flail_id", 0))
		_encode_vector2_quantized(bytes, _vec(flail.get("ball_position", Vector2.ZERO)))
		_encode_vector2_quantized(bytes, _vec(flail.get("ball_velocity", Vector2.ZERO)))

static func _encode_grapple(bytes: PackedByteArray, world: Dictionary) -> void:
	var grapple: Dictionary = _dict(world.get("grapple", {}))
	bytes.append(0 if grapple.is_empty() else 1)
	if not grapple.is_empty():
		_append_u16(bytes, grapple.get("grapple_id", 0))
		_encode_vector2_quantized(bytes, _vec(grapple.get("hook_position", Vector2.ZERO)))
		_encode_vector2_quantized(bytes, _vec(grapple.get("rope_end", Vector2.ZERO)))

static func _encode_modifiers(bytes: PackedByteArray, world: Dictionary) -> void:
	var modifiers: Array = _arr(world.get("modifiers", []))
	var n: int = mini(modifiers.size(), MAX_COUNT_U8)
	bytes.append(n)
	for i in n:
		var mod: Dictionary = _dict(modifiers[i])
		_append_u16(bytes, mod.get("modifier_id", 0))
		_encode_string(bytes, mod.get("name", ""))

static func _encode_round_state(bytes: PackedByteArray, world: Dictionary) -> void:
	_append_u8(bytes, world.get("round_phase", 0))
	_append_u32(bytes, world.get("timer_ms", 0))

	var scores: Dictionary = _dict(world.get("scores", {}))
	var keys: Array = scores.keys()
	var sn: int = mini(keys.size(), MAX_COUNT_U16)
	_append_u16(bytes, sn)
	for i in sn:
		_append_u16(bytes, keys[i])
		_append_u16(bytes, scores[keys[i]])

	var kill_feed: Array = _arr(world.get("kill_feed", []))
	var kn: int = mini(kill_feed.size(), MAX_COUNT_U8)
	bytes.append(kn)
	for i in kn:
		_encode_string(bytes, _dict(kill_feed[i]).get("text", ""))

	_append_u16(bytes, _floor(world.get("kill_zone_height", 0.0)))
	_encode_string(bytes, world.get("announcer_text", ""))

static func _encode_delta_entities(bytes: PackedByteArray, world: Dictionary) -> void:
	var entities: Array = _arr(world.get("delta_entities", []))
	var n: int = mini(entities.size(), MAX_COUNT_U8)
	bytes.append(n)
	for i in n:
		var entity: Dictionary = _dict(entities[i])
		var entity_type: int = _int(entity.get("type", 0), 0, 255)
		bytes.append(entity_type)
		_append_u16(bytes, entity.get("id", 0))
		match entity_type:
			TYPE_PLAYER:
				_encode_body_transform(bytes, _dict(entity.get("body", {})))
				_encode_weapon_segments(bytes, _dict(entity.get("weapon", {})))
				_append_u16(bytes, _floor(entity.get("damage", 0)))
				_append_u8(bytes, entity.get("state", 0))
			TYPE_PROJECTILE:
				_encode_vector2_quantized(bytes, _vec(entity.get("position", Vector2.ZERO)))
				_encode_vector2_quantized(bytes, _vec(entity.get("velocity", Vector2.ZERO)))
			TYPE_PICKUP:
				_encode_vector2_quantized(bytes, _vec(entity.get("position", Vector2.ZERO)))
			TYPE_FLAIL, TYPE_GRAPPLE:
				_encode_vector2_quantized(bytes, _vec(entity.get("pos1", Vector2.ZERO)))
				_encode_vector2_quantized(bytes, _vec(entity.get("pos2", Vector2.ZERO)))
			TYPE_MODIFIER:
				_encode_string(bytes, entity.get("name", ""))
			TYPE_TIMER:
				_append_u32(bytes, entity.get("timer_ms", 0))
			TYPE_SCORES:
				_append_u16(bytes, entity.get("score", 0))
			TYPE_KILL_FEED:
				_encode_string(bytes, entity.get("text", ""))
			TYPE_KILL_ZONE:
				_append_u16(bytes, _floor(entity.get("height", 0.0)))

# ============================================================================
# DECODING HELPERS
# ============================================================================

static func _decode_body_transform(r: _Reader) -> Dictionary:
	var position: Vector2 = r.vec2()
	var rotation: float = r.rotation()
	var velocity: Vector2 = r.vec2()
	return {"position": position, "rotation": rotation, "linear_velocity": velocity}

static func _decode_weapon_segments(r: _Reader) -> Dictionary:
	var head_pos: Vector2 = r.vec2()
	var head_rot: float = r.rotation()
	var shape_idx: int = r.u16()
	return {"head_position": head_pos, "head_rotation": head_rot, "head_shape_index": shape_idx}

static func _decode_static_stage_bodies(r: _Reader) -> Array:
	var bodies: Array = []
	for i in r.count(r.u8(), 10):
		bodies.append(_decode_body_transform(r))
	return bodies

static func _decode_all_players(r: _Reader) -> Array:
	var players: Array = []
	for i in r.count(r.u8(), 26):
		var player_id: int = r.u16()
		var body: Dictionary = _decode_body_transform(r)
		var weapon: Dictionary = _decode_weapon_segments(r)
		var color: int = r.u8()
		var pname: String = r.text()
		var team: int = r.u8()
		var damage: int = r.u16()
		var state: int = r.u8()
		players.append({
			"player_id": player_id,
			"body": body,
			"weapon": weapon,
			"color": color,
			"name": pname,
			"team": team,
			"damage": damage,
			"state": state,
		})
	return players

static func _decode_all_projectiles(r: _Reader) -> Array:
	var projectiles: Array = []
	for i in r.count(r.u8(), 11):
		var proj_id: int = r.u16()
		var position: Vector2 = r.vec2()
		var velocity: Vector2 = r.vec2()
		var weapon_type: int = r.u8()
		projectiles.append({
			"projectile_id": proj_id,
			"position": position,
			"velocity": velocity,
			"weapon_type": weapon_type,
		})
	return projectiles

static func _decode_all_pickups(r: _Reader) -> Array:
	var pickups: Array = []
	for i in r.count(r.u8(), 8):
		var pickup_id: int = r.u16()
		var position: Vector2 = r.vec2()
		var weapon_type: int = r.u16()
		pickups.append({"pickup_id": pickup_id, "position": position, "weapon_type": weapon_type})
	return pickups

static func _decode_flail(r: _Reader) -> Dictionary:
	if r.u8() == 0:
		return {}
	var flail_id: int = r.u16()
	var ball_pos: Vector2 = r.vec2()
	var ball_vel: Vector2 = r.vec2()
	return {"flail_id": flail_id, "ball_position": ball_pos, "ball_velocity": ball_vel}

static func _decode_grapple(r: _Reader) -> Dictionary:
	if r.u8() == 0:
		return {}
	var grapple_id: int = r.u16()
	var hook_pos: Vector2 = r.vec2()
	var rope_end: Vector2 = r.vec2()
	return {"grapple_id": grapple_id, "hook_position": hook_pos, "rope_end": rope_end}

static func _decode_modifiers(r: _Reader) -> Array:
	var modifiers: Array = []
	for i in r.count(r.u8(), 3):
		var mod_id: int = r.u16()
		var mname: String = r.text()
		modifiers.append({"modifier_id": mod_id, "name": mname})
	return modifiers

static func _decode_round_state(r: _Reader) -> Dictionary:
	var round_phase: int = r.u8()
	var timer_ms: int = r.u32()

	var scores: Dictionary = {}
	for i in r.count(r.u16(), 4):
		var player_id: int = r.u16()
		scores[player_id] = r.u16()

	var kill_feed: Array = []
	for i in r.count(r.u8(), 1):
		kill_feed.append({"text": r.text()})

	var kill_zone_height: int = r.u16()
	var announcer: String = r.text()
	return {
		"round_phase": round_phase,
		"timer_ms": timer_ms,
		"scores": scores,
		"kill_feed": kill_feed,
		"kill_zone_height": kill_zone_height,
		"announcer_text": announcer,
	}

static func _decode_delta_entities(r: _Reader) -> Array:
	var entities: Array = []
	for i in r.count(r.u8(), 3):
		var entity_type: int = r.u8()
		var entity: Dictionary = {"type": entity_type, "id": r.u16()}
		match entity_type:
			TYPE_PLAYER:
				entity.merge(_decode_body_transform(r))
				entity.merge(_decode_weapon_segments(r))
				entity["damage"] = r.u16()
				entity["state"] = r.u8()
			TYPE_PROJECTILE:
				entity["position"] = r.vec2()
				entity["velocity"] = r.vec2()
			TYPE_PICKUP:
				entity["position"] = r.vec2()
			TYPE_FLAIL, TYPE_GRAPPLE:
				entity["pos1"] = r.vec2()
				entity["pos2"] = r.vec2()
			TYPE_MODIFIER:
				entity["name"] = r.text()
			TYPE_TIMER:
				entity["timer_ms"] = r.u32()
			TYPE_SCORES:
				entity["score"] = r.u16()
			TYPE_KILL_FEED:
				entity["text"] = r.text()
			TYPE_KILL_ZONE:
				entity["height"] = r.u16()
			_:
				# Unknown type: its size is unknown, so nothing after it can be trusted.
				r.ok = false
				return []
		entities.append(entity)
	return entities

# ============================================================================
# BINARY UTILITIES
# ============================================================================

static func _append_u16(bytes: PackedByteArray, value: Variant) -> void:
	var v: int = _int(value, 0, 65535)
	bytes.append(v >> 8)
	bytes.append(v & 0xFF)

static func _append_u32(bytes: PackedByteArray, value: Variant) -> void:
	var v: int = _int(value, 0, 4294967295)
	bytes.append((v >> 24) & 0xFF)
	bytes.append((v >> 16) & 0xFF)
	bytes.append((v >> 8) & 0xFF)
	bytes.append(v & 0xFF)

## Rounds to the nearest pixel (worst case error 0.5 per axis) and clamps to int16.
static func _encode_vector2_quantized(bytes: PackedByteArray, v: Vector2) -> void:
	var x: int = _int(v.x, -32768, 32767)
	var y: int = _int(v.y, -32768, 32767)
	_append_u16(bytes, x & 0xFFFF)
	_append_u16(bytes, y & 0xFFFF)

static func _encode_rotation_u16(bytes: PackedByteArray, rotation: Variant) -> void:
	var normalized: float = fmod(_num(rotation), TAU)
	if normalized < 0:
		normalized += TAU
	_append_u16(bytes, roundi((normalized / TAU) * 65535.0))

static func _encode_string(bytes: PackedByteArray, s: Variant) -> void:
	var utf8_bytes: PackedByteArray = String(s).to_utf8_buffer() if s is String else PackedByteArray()
	var length: int = mini(utf8_bytes.size(), 255)
	bytes.append(length)
	bytes.append_array(utf8_bytes.slice(0, length))
