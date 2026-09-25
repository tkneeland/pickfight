extends Node2D

## A stage's backdrop (issue #117): a vertical gradient sky and a few slow
## parallax layers of code-drawn silhouettes -- clouds, mountains, hills,
## rocks, a skyline. No art assets. `Stage.gd` builds one of these from its
## `background_*` exports when it enters the tree; nothing else creates it.
## Preloaded by path, never referenced by `class_name` (see CLAUDE.md).
##
## Cheap to draw (#108 is profiling): everything is a handful of static
## Polygon2Ds, built once. Each frame only moves the layer nodes, which is a
## transform change -- nothing is redrawn and no geometry is rebuilt.
##
## Kept behind everything: the root draws at an absolute z of `Z` (not
## relative to the stage), far below the 0 that stage geometry, players and
## heads draw at, so tree order never matters.
##
## Kept low-contrast: every colour is derived from the stage's sky and
## silhouette colours, which the stages keep dark and muted, below the grey
## of stage geometry, so players, heads and platforms stay the brightest
## things on screen.

const Z: int = -1000

## What the fixed Camera2D in scenes/Main.tscn shows (1600x900, no zoom),
## plus a margin all round so a parallax shift or a drifting cloud never
## shows an edge.
const VIEW_SIZE: Vector2 = Vector2(1600.0, 900.0)
const MARGIN: float = 160.0

## Layer kinds a stage may list, far to near.
const KINDS: PackedStringArray = ["clouds", "mountains", "hills", "rocks", "city"]

## How much of a camera move the nearest and furthest layer follow. 0 would
## be painted on the sky; 1 would be fixed to the world like the stage.
const FAR_PARALLAX: float = 0.08
const NEAR_PARALLAX: float = 0.3
## Clouds drift sideways on their own, slowly, in px/s.
const CLOUD_DRIFT_SPEED: float = 6.0
## How far each layer's colour goes from the sky towards the silhouette
## colour, far layer to near layer.
const FAR_TINT: float = 0.45
const NEAR_TINT: float = 0.9
## How far clouds lift off the sky towards white.
const CLOUD_LIGHTEN: float = 0.07

var sky_top: Color = Color(0.1, 0.12, 0.2)
var sky_bottom: Color = Color(0.2, 0.22, 0.28)
var silhouette: Color = Color(0.13, 0.14, 0.19)
var layer_kinds: PackedStringArray = ["clouds", "mountains", "hills"]
var rng_seed: int = 0

## The layer nodes, far to near, and each one's parallax factor and drift.
var _layers: Array[Node2D] = []
var _parallax: PackedFloat32Array = []
var _drift: PackedFloat32Array = []
var _time: float = 0.0
var _sky: Polygon2D

func configure(top: Color, bottom: Color, tint: Color, kinds: PackedStringArray, seed_value: int) -> void:
	sky_top = top
	sky_bottom = bottom
	silhouette = tint
	layer_kinds = kinds
	rng_seed = seed_value

func _ready() -> void:
	z_as_relative = false
	z_index = Z
	_build()
	_follow_view(0.0)

func _process(delta: float) -> void:
	_follow_view(delta)

## The sky, in global coordinates -- what the scenario checks covers the view.
func get_sky_rect() -> Rect2:
	var half: Vector2 = VIEW_SIZE * 0.5 + Vector2(MARGIN, MARGIN)
	return Rect2(global_position - half, half * 2.0)

## Every colour this backdrop draws with, for the contrast check.
func get_colours() -> Array[Color]:
	var colours: Array[Color] = [sky_top, sky_bottom]
	for layer: Node2D in _layers:
		for child: Node in layer.get_children():
			if child is Polygon2D:
				colours.append((child as Polygon2D).color)
	return colours

func get_layer_count() -> int:
	return _layers.size()

## Centres the backdrop on what the camera sees and shifts each layer by its
## share of how far that is from the stage's own origin. The camera in Main is
## fixed, so in play this only ever moves the clouds; it is here so a stage
## viewed off-centre (or a camera that moves later) still gets depth.
func _follow_view(delta: float) -> void:
	_time += delta
	var stage_origin: Vector2 = get_parent().global_position if get_parent() is Node2D else Vector2.ZERO
	var centre: Vector2 = stage_origin
	var camera: Camera2D = get_viewport().get_camera_2d() if is_inside_tree() else null
	if camera != null:
		centre = camera.get_screen_center_position()
	global_position = centre
	var offset: Vector2 = centre - stage_origin
	var wrap: float = VIEW_SIZE.x + 2.0 * MARGIN
	for i in _layers.size():
		var shift: Vector2 = -offset * _parallax[i]
		if _drift[i] != 0.0:
			shift.x += fposmod(_time * _drift[i], wrap) - wrap
		_layers[i].position = shift

func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var half: Vector2 = VIEW_SIZE * 0.5 + Vector2(MARGIN, MARGIN)

	_sky = Polygon2D.new()
	_sky.name = "Sky"
	_sky.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y)])
	_sky.vertex_colors = PackedColorArray([sky_top, sky_top, sky_bottom, sky_bottom])
	add_child(_sky)

	var kinds: PackedStringArray = []
	for kind: String in layer_kinds:
		if KINDS.has(kind):
			kinds.append(kind)
		else:
			push_warning("StageBackground: unknown layer kind '%s'" % kind)
	for i in kinds.size():
		var t: float = 0.0 if kinds.size() == 1 else float(i) / float(kinds.size() - 1)
		var layer := Node2D.new()
		layer.name = "Layer%d_%s" % [i, kinds[i]]
		add_child(layer)
		var colour: Color = sky_bottom.lerp(silhouette, lerpf(FAR_TINT, NEAR_TINT, t))
		var drift: float = 0.0
		match kinds[i]:
			"clouds":
				colour = sky_top.lerp(sky_bottom, 0.5).lerp(Color.WHITE, CLOUD_LIGHTEN)
				drift = CLOUD_DRIFT_SPEED
				_add_clouds(layer, rng, half, colour)
			"mountains":
				_add_ridge(layer, rng, half, colour, 40.0, 90.0, 220.0, true)
			"hills":
				_add_ridge(layer, rng, half, colour, 190.0, 50.0, 60.0, false)
			"rocks":
				_add_rocks(layer, rng, half, colour)
			"city":
				_add_city(layer, rng, half, colour)
		_layers.append(layer)
		_parallax.append(lerpf(FAR_PARALLAX, NEAR_PARALLAX, t))
		_drift.append(drift)

func _add_polygon(layer: Node2D, points: PackedVector2Array, colour: Color) -> void:
	var poly := Polygon2D.new()
	poly.polygon = points
	poly.color = colour
	layer.add_child(poly)

## A ridge line across the whole view, filled down past its bottom edge.
## `base_y` is the ridge's mean height, `amplitude` how far it swings, and
## `step` the spacing of its points: wide and pointed for mountains, tight
## and rounded (sum of sines) for hills.
func _add_ridge(layer: Node2D, rng: RandomNumberGenerator, half: Vector2, colour: Color,
		base_y: float, amplitude: float, step: float, peaked: bool) -> void:
	var points := PackedVector2Array()
	var extra: float = MARGIN
	var x: float = -half.x - extra
	var phase_a: float = rng.randf() * TAU
	var phase_b: float = rng.randf() * TAU
	while x <= half.x + extra:
		var y: float
		if peaked:
			y = base_y - rng.randf_range(0.2, 1.0) * amplitude
		else:
			y = base_y + amplitude * (0.6 * sin(x * 0.004 + phase_a) + 0.4 * sin(x * 0.011 + phase_b))
		points.append(Vector2(x, y))
		x += step * (rng.randf_range(0.7, 1.3) if peaked else 1.0)
	points.append(Vector2(half.x + extra, half.y))
	points.append(Vector2(-half.x - extra, half.y))
	_add_polygon(layer, points, colour)

## Soft blobs in the upper sky, each a few overlapping ellipses of one
## opaque colour. Laid out twice, one view-width apart, so the drift in
## `_follow_view` can wrap without a seam.
func _add_clouds(layer: Node2D, rng: RandomNumberGenerator, half: Vector2, colour: Color) -> void:
	var wrap: float = half.x * 2.0
	var count: int = 5
	for c in count:
		var centre := Vector2(-half.x + (float(c) + rng.randf_range(0.1, 0.9)) * wrap / count,
			rng.randf_range(-half.y + MARGIN + 30.0, -120.0))
		var puffs: int = rng.randi_range(2, 4)
		for p in puffs:
			var puff_centre: Vector2 = centre + Vector2((p - puffs * 0.5) * 38.0, rng.randf_range(-14.0, 6.0))
			var radius := Vector2(rng.randf_range(40.0, 70.0), rng.randf_range(18.0, 30.0))
			for copy: float in [0.0, wrap]:
				_add_polygon(layer, _ellipse(puff_centre + Vector2(copy, 0.0), radius), colour)

func _ellipse(centre: Vector2, radius: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	var segments: int = 16
	for i in segments:
		var a: float = TAU * float(i) / float(segments)
		points.append(centre + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	return points

## Mesas and spires: a skyline of flat-topped, slope-sided outcrops.
func _add_rocks(layer: Node2D, rng: RandomNumberGenerator, half: Vector2, colour: Color) -> void:
	var points := PackedVector2Array()
	var x: float = -half.x - MARGIN
	var ground: float = 250.0
	points.append(Vector2(x, ground))
	while x < half.x + MARGIN:
		var width: float = rng.randf_range(60.0, 180.0)
		var height: float = rng.randf_range(60.0, 230.0)
		var slope: float = rng.randf_range(10.0, 40.0)
		points.append(Vector2(x + slope, ground - height))
		points.append(Vector2(x + width - slope, ground - height + rng.randf_range(-12.0, 12.0)))
		points.append(Vector2(x + width, ground))
		x += width + rng.randf_range(20.0, 120.0)
		points.append(Vector2(x, ground))
	points.append(Vector2(x, half.y))
	points.append(Vector2(-half.x - MARGIN, half.y))
	_add_polygon(layer, points, colour)

## A blocky skyline of towers of varied width and height.
func _add_city(layer: Node2D, rng: RandomNumberGenerator, half: Vector2, colour: Color) -> void:
	var points := PackedVector2Array()
	var x: float = -half.x - MARGIN
	var ground: float = 260.0
	points.append(Vector2(x, half.y))
	while x < half.x + MARGIN:
		var width: float = rng.randf_range(50.0, 130.0)
		var top: float = ground - rng.randf_range(80.0, 420.0)
		points.append(Vector2(x, top))
		points.append(Vector2(x + width, top))
		x += width
	points.append(Vector2(x, half.y))
	_add_polygon(layer, points, colour)
