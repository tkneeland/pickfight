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

## What the Camera2D in scenes/Main.tscn shows of a normal stage (1600x900,
## no zoom), plus a margin all round so a parallax shift or a drifting cloud
## never shows an edge. A large stage (issue #144) passes its own, bigger view
## to `configure()`, since the camera zooms out to show all of it; the
## backdrop is still built at this size and then scaled up by the same factor
## the camera zooms out by, so its skyline fills a large stage's screen
## exactly as it fills a normal one's instead of shrinking into a strip.
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
## Far and mid hill colours from the stage's palette mood (#255); when
## `use_hill_colours` is set the terrain layers blend far to near between them
## instead of from the sky towards `silhouette`.
var far_hill: Color = Color.BLACK
var mid_hill: Color = Color.BLACK
var use_hill_colours: bool = false
var layer_kinds: PackedStringArray = ["clouds", "mountains", "hills"]
var rng_seed: int = 0
## The world area the camera shows while this backdrop's stage plays. 16:9,
## as `Stage.get_view_rect()` gives it, so one factor scales both axes.
var view_size: Vector2 = VIEW_SIZE
var _scale: float = 1.0

## The layer nodes, far to near, and each one's parallax factor and drift.
var _layers: Array[Node2D] = []
var _parallax: PackedFloat32Array = []
var _drift: PackedFloat32Array = []
var _time: float = 0.0
var _sky: Polygon2D

## Flat parallax dressing (#257): a sky layer (clouds, or stars on Dusk) and a
## far and a mid silhouette, all plain Polygon2Ds with no collision, coloured
## from the mood's dress_* keys and shaped from `dressing_index`. Off unless
## `Stage` turns it on. Kept apart from `_layers` so the 2-3 layer count of
## the original backdrop holds.
const DRESS_PARALLAX: Array[float] = [0.04, 0.07, 0.12]
const DRESS_CLOUD_DRIFT: float = 4.0
const DRESS_KINDS: PackedStringArray = ["hills", "blocks", "peaks"]
var dressing_enabled: bool = false
var dressing_index: int = 0
var dressing_stars: bool = false
var dress_sky: Color = Color.WHITE
var dress_far: Color = Color.WHITE
var dress_mid: Color = Color.WHITE
var _dress_layers: Array[Node2D] = []
var _dress_drift: PackedFloat32Array = []

func configure(top: Color, bottom: Color, tint: Color, kinds: PackedStringArray, seed_value: int,
		view: Vector2 = VIEW_SIZE) -> void:
	view_size = view
	sky_top = top
	sky_bottom = bottom
	silhouette = tint
	layer_kinds = kinds
	rng_seed = seed_value

func _ready() -> void:
	z_as_relative = false
	z_index = Z
	# Moved in _process, off the physics tick, so it must not be physics
	# interpolated (#108 turned that on project-wide); the layers inherit this.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_scale = maxf(view_size.x / VIEW_SIZE.x, view_size.y / VIEW_SIZE.y)
	scale = Vector2(_scale, _scale)
	_build()
	_follow_view(0.0)

func _process(delta: float) -> void:
	_follow_view(delta)

## The sky, in global coordinates -- what the scenario checks covers the view.
func get_sky_rect() -> Rect2:
	var half: Vector2 = (VIEW_SIZE * 0.5 + Vector2(MARGIN, MARGIN)) * _scale
	return Rect2(global_position - half, half * 2.0)

## Every colour this backdrop draws with, for the contrast check.
func get_colours() -> Array[Color]:
	var colours: Array[Color] = [sky_top, sky_bottom]
	for layer: Node2D in _layers:
		for child: Node in layer.get_children():
			if child is Polygon2D:
				colours.append((child as Polygon2D).color)
	for layer: Node2D in _dress_layers:
		for child: Node in layer.get_children():
			colours.append((child as Polygon2D).color)
	return colours

## Sets up the dressing from a palette mood and the stage's rotation index.
func configure_dressing(mood: Dictionary, stage_index: int) -> void:
	dressing_enabled = true
	dressing_index = maxi(stage_index, 0)
	dressing_stars = mood.get("name", "") == "dusk"
	dress_sky = mood["dress_sky"]
	dress_far = mood["dress_far"]
	dress_mid = mood["dress_mid"]

func get_dressing_layers() -> Array[Node2D]:
	return _dress_layers

## A number that changes whenever any dressing shape does; equal for equal
## layouts. Hashes every polygon's points.
func get_dressing_signature() -> int:
	var h: int = 17
	for layer: Node2D in _dress_layers:
		for child: Node in layer.get_children():
			h = hash([h, (child as Polygon2D).polygon])
	return h

func get_layer_count() -> int:
	return _layers.size()

## Centres the backdrop on what the camera sees and shifts each layer by its
## share of how far that is from the stage's own origin. The camera in Main
## only moves between rounds, to centre on each stage's view (issue #144), so
## in play this only ever moves the clouds; it is here so a stage viewed
## off-centre (or a camera that moves later) still gets depth.
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
		# In the backdrop's own (scaled) units, so a camera move shifts each
		# layer by the same share of the screen on a large stage as on a
		# normal one.
		var shift: Vector2 = -offset * _parallax[i] / _scale
		if _drift[i] != 0.0:
			shift.x += fposmod(_time * _drift[i], wrap) - wrap
		_layers[i].position = shift
	for i in _dress_layers.size():
		var dress_shift: Vector2 = -offset * DRESS_PARALLAX[i] / _scale
		if _dress_drift[i] != 0.0:
			dress_shift.x += fposmod(_time * _dress_drift[i], wrap) - wrap
		_dress_layers[i].position = dress_shift

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
	if dressing_enabled:
		_build_dressing(half)

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
		if use_hill_colours:
			colour = far_hill.lerp(mid_hill, t)
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

## The dressing: three flat layers, far to near, built once. Shapes come from
## a generator seeded by the stage index, so a stage always looks the same and
## the 24 differ. The far/mid silhouette kinds step with the rotation lap.
func _build_dressing(half: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = dressing_index * 7919 + 101
	var lap: int = dressing_index / 3
	var far_kind: String = DRESS_KINDS[lap % 3]
	var mid_kind: String = DRESS_KINDS[(lap + 1 + (lap / 3) % 2) % 3]
	var wrap: float = half.x * 2.0

	var sky_layer := Node2D.new()
	sky_layer.name = "DressSky"
	add_child(sky_layer)
	if dressing_stars:
		for s in 28:
			var side: float = rng.randf_range(5.0, 11.0)
			var at := Vector2(rng.randf_range(-half.x, half.x), rng.randf_range(-half.y, -60.0))
			_add_polygon(sky_layer, _rect(at, Vector2(side, side)), dress_sky)
	else:
		for c in 5:
			var at := Vector2(-half.x + (float(c) + rng.randf_range(0.1, 0.9)) * wrap / 5.0,
				rng.randf_range(-half.y + MARGIN, -140.0))
			var width: float = rng.randf_range(110.0, 220.0)
			var height: float = rng.randf_range(26.0, 44.0)
			for copy: float in [0.0, wrap]:
				_add_polygon(sky_layer, _rect(at + Vector2(copy, 0.0), Vector2(width, height)), dress_sky)
				_add_polygon(sky_layer, _rect(at + Vector2(copy + width * 0.2, -height * 0.7),
					Vector2(width * 0.5, height)), dress_sky)
	_dress_layers.append(sky_layer)
	_dress_drift.append(0.0 if dressing_stars else DRESS_CLOUD_DRIFT)

	var far := Node2D.new()
	far.name = "DressFar_" + far_kind
	add_child(far)
	_dress_silhouette(far, rng, half, dress_far, far_kind, -20.0, 130.0)
	_dress_layers.append(far)
	_dress_drift.append(0.0)

	var mid := Node2D.new()
	mid.name = "DressMid_" + mid_kind
	add_child(mid)
	_dress_silhouette(mid, rng, half, dress_mid, mid_kind, 140.0, 90.0)
	_dress_layers.append(mid)
	_dress_drift.append(0.0)

func _rect(top_left: Vector2, size: Vector2) -> PackedVector2Array:
	return PackedVector2Array([top_left, top_left + Vector2(size.x, 0.0),
		top_left + size, top_left + Vector2(0.0, size.y)])

## A flat silhouette across the view: rolling hills, square-topped blocks or
## sharp peaks, filled down past the bottom edge.
func _dress_silhouette(layer: Node2D, rng: RandomNumberGenerator, half: Vector2, colour: Color,
		kind: String, base_y: float, amplitude: float) -> void:
	var left: float = -half.x - MARGIN
	var right: float = half.x + MARGIN
	var points := PackedVector2Array()
	match kind:
		"hills":
			var phase_a: float = rng.randf() * TAU
			var phase_b: float = rng.randf() * TAU
			var x: float = left
			while x <= right:
				points.append(Vector2(x, base_y + amplitude * (0.6 * sin(x * 0.005 + phase_a) + 0.4 * sin(x * 0.013 + phase_b))))
				x += 80.0
		"blocks":
			var x: float = left
			points.append(Vector2(x, half.y))
			while x < right:
				var width: float = rng.randf_range(70.0, 160.0)
				var top: float = base_y - rng.randf_range(0.0, amplitude * 1.6)
				points.append(Vector2(x, top))
				points.append(Vector2(x + width, top))
				x += width
		_:
			var x: float = left
			while x <= right:
				points.append(Vector2(x, base_y - rng.randf_range(0.1, 1.0) * amplitude))
				x += rng.randf_range(120.0, 260.0)
	points.append(Vector2(right, half.y))
	points.append(Vector2(left, half.y))
	_add_polygon(layer, points, colour)
