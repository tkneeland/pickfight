extends Node2D

## Animated lava art (#687). Visual only: it never touches a collision shape,
## the zone's colours or its timing. Two looks, both drawn by this one node so
## `KillZone.gd` stays a rule script:
##
## - POOL: a body of lava (the rising floor). A wavy crest from a few summed
##   sines, a glowing edge line, a gradient that darkens with depth, and a
##   handful of embers drifting up. `setup_pool` gives the footprint.
## - TILE: one `Hazard.tscn` block. Stacked tiles form walls, so no crest or
##   gradient (they would stripe at every seam): drifting bright blobs only.
##
## Cheap by design: arrays are sized once in setup, `_draw` allocates nothing,
## no shader reads the screen, at most EMBERS (16) circles per pool.

const WAVE_STEP: float = 32.0
const WAVE_PAD: float = 8.0
const EMBERS: int = 16
const EMBER_SPAN: float = 2400.0
const EMBER_RISE: float = 160.0
const BLOBS: int = 3

var _pool: bool = false
var _left: float = 0.0
var _right: float = 0.0
var _top: float = 0.0
var _depth: float = 0.0
var _glow: Color = Color(1.0, 0.75, 0.2, 1.0)
var _edge: Line2D
var _crest: PackedVector2Array = PackedVector2Array()
var _seed: PackedFloat32Array = PackedFloat32Array()
var _time: float = 0.0
var _tile_size: Vector2 = Vector2.ZERO

func setup_pool(left: float, right: float, top: float, depth: float, edge: Line2D, glow: Color) -> void:
	_pool = true
	_left = left
	_right = right
	_top = top
	_depth = depth
	_edge = edge
	_glow = glow
	_crest.resize(int(ceilf((right - left) / WAVE_STEP)) + 1)
	_fill_seeds(EMBERS)
	_crest_update()

func setup_tile(size: Vector2) -> void:
	_pool = false
	_tile_size = size
	_fill_seeds(BLOBS)

func set_glow(colour: Color) -> void:
	_glow = colour

func _fill_seeds(n: int) -> void:
	_seed.resize(n * 3)
	for i in n:
		# Fixed pseudo-random values per index: independent of the gameplay RNG.
		_seed[i * 3] = fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
		_seed[i * 3 + 1] = 0.35 + fposmod(sin(float(i) * 78.233) * 24634.6345, 1.0) * 0.65
		_seed[i * 3 + 2] = fposmod(sin(float(i) * 39.346) * 11813.3197, 1.0)

func _wave(x: float) -> float:
	return sin(x * 0.021 + _time * 2.1) * 3.5 + sin(x * 0.047 - _time * 1.4) * 2.5 + sin(x * 0.113 + _time * 3.3) * 1.2

func _crest_update() -> void:
	for i in _crest.size():
		var x: float = minf(_left + float(i) * WAVE_STEP, _right)
		_crest[i] = Vector2(x, _top + _wave(x))
	if _edge != null:
		_edge.points = _crest

func _process(delta: float) -> void:
	_time += delta
	if _pool:
		_crest_update()
	queue_redraw()

func _draw() -> void:
	if _pool:
		_draw_pool()
	else:
		_draw_tile()

func _draw_pool() -> void:
	var base: Color = (get_parent() as Polygon2D).color
	var body_top: float = _top + WAVE_PAD
	# Crest columns fill the gap between the wavy top and the flat body.
	for i in _crest.size() - 1:
		var y: float = _crest[i].y
		draw_rect(Rect2(_crest[i].x, y, WAVE_STEP, body_top - y), base)
	# Gradient: clear under the crest, dark at depth.
	var mid: float = body_top + 260.0
	var deep: float = body_top + _depth
	var dark: Color = Color(0.1, 0.0, 0.0, 0.6)
	var clear: Color = Color(0.1, 0.0, 0.0, 0.0)
	draw_polygon(PackedVector2Array([Vector2(_left, body_top), Vector2(_right, body_top), Vector2(_right, mid), Vector2(_left, mid)]),
		PackedColorArray([clear, clear, dark, dark]))
	draw_rect(Rect2(_left, mid - 1.0, _right - _left, deep - mid), dark)
	# Glow just under the edge line, fading into the body.
	var hot: Color = Color(_glow, 0.55)
	var cool: Color = Color(_glow, 0.0)
	draw_polygon(PackedVector2Array([Vector2(_left, body_top), Vector2(_right, body_top), Vector2(_right, body_top + 60.0), Vector2(_left, body_top + 60.0)]),
		PackedColorArray([hot, hot, cool, cool]))
	# Embers rising off the surface.
	var centre: float = (_left + _right) * 0.5
	var span: float = minf(_right - _left, EMBER_SPAN)
	for i in EMBERS:
		var life: float = fposmod(_time * 0.22 * _seed[i * 3 + 1] + _seed[i * 3 + 2], 1.0)
		var x: float = centre + (_seed[i * 3] - 0.5) * span + sin(_time * 1.7 + float(i)) * 10.0
		var y: float = _top - 6.0 - life * EMBER_RISE * _seed[i * 3 + 1]
		draw_circle(Vector2(x, y), 3.0 + 2.5 * _seed[i * 3 + 1] * (1.0 - life), Color(1.0, 0.8, 0.3, 1.0 - life))

func _draw_tile() -> void:
	var half: Vector2 = _tile_size * 0.5
	for i in BLOBS:
		var pulse: float = 0.5 + 0.5 * sin(_time * 1.6 + _seed[i * 3 + 2] * TAU)
		var c: Vector2 = Vector2(sin(_time * 0.6 * _seed[i * 3 + 1] + _seed[i * 3] * TAU) * (half.x - 18.0), -half.y * 0.5 + _seed[i * 3 + 2] * half.y)
		draw_circle(c, 9.0 + 7.0 * pulse, Color(_glow, 0.12 + 0.18 * pulse))
		draw_circle(c, 4.0, Color(1.0, 0.9, 0.5, 0.2 + 0.25 * pulse))
