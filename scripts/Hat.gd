extends Node2D

## The hat a player wears (issue #151), drawn in code in the game's art style:
## flat fills with a dark outline, no image assets. A child of the player's
## body, sitting on the body's top edge, so it goes wherever the body goes --
## through swings (the body never rotates; `lock_rotation`), eliminations
## (hidden with the body) and the next round's spawn (shown with it again).
##
## Every hat is described once, as data, by `parts()`: `_draw()` paints that
## list here, and ControllerServer sends the same list to the phones
## (`art_for_phone()`) so the picker's previews are these exact shapes. Local
## space: the origin is the middle of the body's top edge, and up is -y.
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

const NONE: String = "none"
## Every hat a phone may pick, in the order the picker shows them.
const IDS: PackedStringArray = ["none", "crown", "top_hat", "cap", "beanie", "viking", "party", "halo", "propeller"]
const LABELS: Dictionary = {
	"none": "None", "crown": "Crown", "top_hat": "Top hat", "cap": "Cap",
	"beanie": "Beanie", "viking": "Viking", "party": "Party hat", "halo": "Halo",
	"propeller": "Propeller",
}
## How far each hat reaches above the body's top edge, in px, outline
## included (half of OUTLINE_WIDTH past a polygon's points, and so on). A name
## tag sits above this (NameTags), and `hat_parts_stay_in_their_box` in the
## scenario runner checks every drawn part, stroke and all, stays under it.
const HEIGHTS: Dictionary = {
	"none": 0.0, "crown": 26.0, "top_hat": 35.0, "cap": 21.0, "beanie": 29.0,
	"viking": 34.0, "party": 41.0, "halo": 22.0, "propeller": 28.0,
}
## No part, stroke included, reaches further than this either side of the
## body's centre. Only the scenario runner reads it: it is the box's side.
const HALF_WIDTH: float = 34.0

const OUTLINE_COLOR: Color = Color(0.07, 0.07, 0.09, 1.0)
const OUTLINE_WIDTH: float = 2.0
const GOLD: Color = Color(1.0, 0.8, 0.18, 1.0)
const RUBY: Color = Color(0.9, 0.15, 0.2, 1.0)
const SILK: Color = Color(0.13, 0.13, 0.16, 1.0)
const WOOL: Color = Color(0.95, 0.95, 0.95, 1.0)
const HORN: Color = Color(0.96, 0.9, 0.74, 1.0)
const STEEL: Color = Color(0.62, 0.64, 0.7, 1.0)
const STEEL_DARK: Color = Color(0.42, 0.44, 0.5, 1.0)
const RIVET: Color = Color(0.85, 0.86, 0.9, 1.0)
const STEM: Color = Color(0.25, 0.25, 0.28, 1.0)
## Stand-ins for the wearer's own colour in `parts()`, resolved at draw time.
const TINT: String = "tint"
const TINT_DARK: String = "tint_dark"
## Propeller turns per second, in radians.
const PROPELLER_SPIN: float = 18.0

var hat_id: String = NONE
## The wearer's identity colour: caps, beanies and the like come in it.
var tint: Color = Color.WHITE
var _spin: float = 0.0

func _ready() -> void:
	name = "Hat"
	set_process(hat_id == "propeller")

## Wear `id`; anything not in IDS means no hat.
func set_hat(id: String) -> void:
	hat_id = id if IDS.has(id) else NONE
	set_process(hat_id == "propeller")
	queue_redraw()

func set_tint(colour: Color) -> void:
	tint = colour
	queue_redraw()

static func height_of(id: String) -> float:
	return float(HEIGHTS.get(id, 0.0))

func _process(delta: float) -> void:
	_spin = fmod(_spin + delta * PROPELLER_SPIN, TAU)
	queue_redraw()

func _draw() -> void:
	for part: Dictionary in parts(hat_id, _spin):
		var fill: Color = _resolve(part["fill"])
		match str(part["kind"]):
			"poly":
				var pts: PackedVector2Array = part["pts"]
				draw_colored_polygon(pts, fill)
				if part.get("outline", true):
					var closed: PackedVector2Array = pts.duplicate()
					closed.append(pts[0])
					draw_polyline(closed, OUTLINE_COLOR, OUTLINE_WIDTH, true)
			"circle":
				draw_circle(part["c"], part["r"], fill)
				if part.get("outline", true):
					draw_arc(part["c"], part["r"], 0.0, TAU, 20, OUTLINE_COLOR, OUTLINE_WIDTH * 0.75, true)
			"ring":
				var ring: PackedVector2Array = _ellipse(part["c"], part["rx"], part["ry"], 24)
				ring.append(ring[0])
				draw_polyline(ring, OUTLINE_COLOR, float(part["width"]) + OUTLINE_WIDTH * 1.5, true)
				draw_polyline(ring, fill, part["width"], true)

func _resolve(fill: Variant) -> Color:
	if fill is Color:
		return fill
	return tint.darkened(0.35) if str(fill) == TINT_DARK else tint

## What hat `id` is made of, back to front: each part a Dictionary with a
## "kind" -- "poly" (`pts`), "circle" (`c`, `r`) or "ring" (an unfilled
## ellipse: `c`, `rx`, `ry`, `width`) -- a "fill" that is a Color or TINT /
## TINT_DARK, and "outline" (default true). `spin` turns the propeller.
static func parts(id: String, spin: float = 0.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match id:
		"crown":
			out.append(_poly([Vector2(-17, 0), Vector2(17, 0), Vector2(19, -18), Vector2(9, -9),
				Vector2(0, -22), Vector2(-9, -9), Vector2(-19, -18)], GOLD))
			for tip: Vector2 in [Vector2(-19, -18), Vector2(0, -22), Vector2(19, -18)]:
				out.append(_circle(tip, 2.5, GOLD))
			out.append(_circle(Vector2(0, -5), 3.0, RUBY))
			out.append(_circle(Vector2(-10, -4), 2.2, TINT))
			out.append(_circle(Vector2(10, -4), 2.2, TINT))
		"top_hat":
			out.append(_poly([Vector2(-22, 0), Vector2(22, 0), Vector2(22, -5), Vector2(-22, -5)], SILK))
			out.append(_poly([Vector2(-14, -5), Vector2(14, -5), Vector2(15, -34), Vector2(-15, -34)], SILK))
			out.append(_poly([Vector2(-14.1, -6), Vector2(14.1, -6), Vector2(14.3, -12), Vector2(-14.3, -12)], TINT, false))
		"cap":
			out.append(_poly(_dome(Vector2.ZERO, 17.0), TINT))
			out.append(_poly([Vector2(10, 0), Vector2(32, 0), Vector2(30, -4), Vector2(12, -5)], TINT_DARK))
			out.append(_circle(Vector2(0, -17), 2.5, TINT_DARK))
		"beanie":
			out.append(_poly(_dome(Vector2(0, -4), 18.0), TINT))
			out.append(_poly([Vector2(-20, 0), Vector2(20, 0), Vector2(20, -8), Vector2(-20, -8)], TINT_DARK))
			out.append(_circle(Vector2(0, -23), 5.0, WOOL))
		"viking":
			var horn: Array[Vector2] = [Vector2(-12, -10), Vector2(-20, -12), Vector2(-27, -19), Vector2(-30, -30),
				Vector2(-26, -33), Vector2(-24, -24), Vector2(-19, -18), Vector2(-11, -16)]
			out.append(_poly(horn, HORN))
			var mirrored: Array[Vector2] = []
			for i in range(horn.size() - 1, -1, -1):
				mirrored.append(Vector2(-horn[i].x, horn[i].y))
			out.append(_poly(mirrored, HORN))
			out.append(_poly(_dome(Vector2.ZERO, 17.0), STEEL))
			out.append(_poly([Vector2(-19, 0), Vector2(19, 0), Vector2(19, -5), Vector2(-19, -5)], STEEL_DARK))
			for x: float in [-10.0, 0.0, 10.0]:
				out.append(_circle(Vector2(x, -2.5), 1.5, RIVET, false))
		"party":
			out.append(_poly([Vector2(-14, 0), Vector2(14, 0), Vector2(0, -34)], TINT))
			for band: Vector2 in [Vector2(8, 13), Vector2(19, 23)]:
				out.append(_poly(_cone_band(14.0, 34.0, band.x, band.y), WOOL, false))
			out.append(_circle(Vector2(0, -35), 4.5, GOLD))
		"halo":
			out.append({"kind": "ring", "c": Vector2(0, -13), "rx": 16.0, "ry": 5.0, "width": 4.0, "fill": GOLD})
		"propeller":
			out.append(_poly(_dome(Vector2.ZERO, 16.0), TINT))
			out.append(_poly([Vector2(-1.5, -16), Vector2(1.5, -16), Vector2(1.5, -23), Vector2(-1.5, -23)], STEM, false))
			# A blade seen edge-on as it turns: its length follows cos(spin),
			# and the two swap sides past a half turn.
			var reach: float = 3.0 + 14.0 * absf(cos(spin))
			var left_red: bool = cos(spin) >= 0.0
			out.append(_poly(_ellipse(Vector2(-reach * 0.5, -24), reach * 0.5, 2.8, 12), RUBY if left_red else GOLD))
			out.append(_poly(_ellipse(Vector2(reach * 0.5, -24), reach * 0.5, 2.8, 12), GOLD if left_red else RUBY))
			out.append(_circle(Vector2(0, -24), 2.5, STEM))
	return out

## `parts()` for every hat, for the phone's picker: JSON-safe, points as flat
## [x, y, ...] lists, colours as "#rrggbb" or "tint" / "tint_dark".
static func art_for_phone() -> Dictionary:
	var art: Dictionary = {}
	for id: String in IDS:
		var list: Array = []
		for part: Dictionary in parts(id):
			var entry: Dictionary = {"kind": part["kind"], "outline": part.get("outline", true)}
			var fill: Variant = part["fill"]
			entry["fill"] = "#" + (fill as Color).to_html(false) if fill is Color else str(fill)
			match str(part["kind"]):
				"poly":
					var flat: Array = []
					for p: Vector2 in part["pts"]:
						flat.append(snappedf(p.x, 0.01))
						flat.append(snappedf(p.y, 0.01))
					entry["pts"] = flat
				"circle":
					entry["x"] = part["c"].x
					entry["y"] = part["c"].y
					entry["r"] = part["r"]
				"ring":
					entry["x"] = part["c"].x
					entry["y"] = part["c"].y
					entry["rx"] = part["rx"]
					entry["ry"] = part["ry"]
					entry["width"] = part["width"]
			list.append(entry)
		art[id] = list
	return art

static func _poly(pts: Array, fill: Variant, outline: bool = true) -> Dictionary:
	return {"kind": "poly", "pts": PackedVector2Array(pts), "fill": fill, "outline": outline}

static func _circle(c: Vector2, r: float, fill: Variant, outline: bool = true) -> Dictionary:
	return {"kind": "circle", "c": c, "r": r, "fill": fill, "outline": outline}

## The upper half of a circle, flat side down on `centre`.
static func _dome(centre: Vector2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 13:
		var angle: float = PI + PI * float(i) / 12.0
		pts.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return pts

static func _ellipse(centre: Vector2, rx: float, ry: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps:
		var angle: float = TAU * float(i) / float(steps)
		pts.append(centre + Vector2(cos(angle) * rx, sin(angle) * ry))
	return pts

## A stripe across a cone of base half-width `half` and height `tall`,
## between heights `from` and `to` above its base.
static func _cone_band(half: float, tall: float, from: float, to: float) -> PackedVector2Array:
	var w_from: float = half * (1.0 - from / tall)
	var w_to: float = half * (1.0 - to / tall)
	return PackedVector2Array([Vector2(-w_from, -from), Vector2(w_from, -from), Vector2(w_to, -to), Vector2(-w_to, -to)])
