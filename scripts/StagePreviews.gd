extends RefCounted
## Baked stage preview images (#647): art/stage_previews/<StageName>.png, made
## by tools/capture_stage_previews.gd. Consumers preload this script by path.
const DIR: String = "res://art/stage_previews"
static func preview_path(stage_name: String) -> String:
	return "%s/%s.png" % [DIR, stage_name]
## The preview texture, or null when none has been baked for that stage.
static func load_preview(stage_name: String) -> Texture2D:
	var path: String = preview_path(stage_name)
	if not ResourceLoader.exists(path): return null
	return load(path) as Texture2D

## Preview size, the same as the baked ones.
const SIZE: Vector2i = Vector2i(480, 270)
const SKY_TOP: Color = Color("27304a")
const SKY_BOTTOM: Color = Color("5a6b8c")
const PLATFORM: Color = Color("e8e2d0")
const ONE_WAY: Color = Color("b9d7ff")
const KILL: Color = Color("e0503c")
const SPAWN: Color = Color("ffd23f")

## #1047: a drawn preview of a custom stage (a definition in JSON shape, as
## `StageDef.to_json_data()` gives), which has no baked art: sky, platforms
## (one-way ones lighter), the kill floor's line and the spawn points, framed on
## their bounds. Null for anything that is not a definition.
static func draw_preview(def: Dictionary) -> Texture2D:
	if not def.get("parts") is Array or not def.get("spawns") is Array:
		return null
	var boxes: Array[Rect2] = []
	var kinds: Array[Color] = []
	var kill_y: float = NAN
	var bounds := Rect2()
	var first: bool = true
	for part: Variant in def["parts"]:
		if not part is Dictionary or not part.get("pos") is Array:
			continue
		var pos := Vector2(float(part["pos"][0]), float(part["pos"][1]))
		if part.get("type") == "KillFloor":
			kill_y = pos.y
			continue
		var size := Vector2(float(part["size"][0]), float(part["size"][1])) if part.get("size") is Array else Vector2(8, 8)
		var box := Rect2(pos - size * 0.5, size)
		boxes.append(box)
		var one_way: bool = part.get("params") is Dictionary and bool((part["params"] as Dictionary).get("one_way", false))
		kinds.append(ONE_WAY if one_way else PLATFORM)
		bounds = box if first else bounds.merge(box)
		first = false
	var spawns: Array[Vector2] = []
	for p: Variant in def["spawns"]:
		if p is Array and (p as Array).size() == 2:
			var v := Vector2(float(p[0]), float(p[1]))
			spawns.append(v)
			bounds = Rect2(v, Vector2.ZERO) if first else bounds.expand(v)
			first = false
	if first:
		bounds = Rect2(-800, -450, 1600, 900)
	bounds = bounds.grow(120.0)
	if not is_nan(kill_y):
		bounds = bounds.expand(Vector2(bounds.position.x, kill_y + 40.0))
	# Fit the bounds into SIZE, keeping the aspect.
	var scale: float = minf(SIZE.x / bounds.size.x, SIZE.y / bounds.size.y)
	var offset: Vector2 = (Vector2(SIZE) - bounds.size * scale) * 0.5 - bounds.position * scale
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	for y in SIZE.y:
		image.fill_rect(Rect2i(0, y, SIZE.x, 1), SKY_TOP.lerp(SKY_BOTTOM, float(y) / SIZE.y))
	for i in boxes.size():
		var r := Rect2(boxes[i].position * scale + offset, boxes[i].size * scale)
		image.fill_rect(Rect2i(r.position.round(), Vector2i(maxi(2, roundi(r.size.x)), maxi(2, roundi(r.size.y)))), kinds[i])
	if not is_nan(kill_y):
		var ky: int = clampi(roundi(kill_y * scale + offset.y), 0, SIZE.y - 3)
		image.fill_rect(Rect2i(0, ky, SIZE.x, 3), KILL)
	for v: Vector2 in spawns:
		var c: Vector2i = (v * scale + offset).round()
		image.fill_rect(Rect2i(c - Vector2i(3, 3), Vector2i(6, 6)), SPAWN)
	return ImageTexture.create_from_image(image)
