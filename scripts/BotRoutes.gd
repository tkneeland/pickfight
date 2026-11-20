extends RefCounted

## Issue #1299: a bot's map of a stage, for getting between its levels.
##
## Built once a stage read (`Bot._read_stage`) from the stage's fixed terrain:
## every unrotated rectangle collision shape on a `StaticBody2D` that is not one
## of `SKIP_SCRIPTS` (parts that move, turn, break or give way) gives its top
## edge as a **surface**. Tops at the same height that touch or overlap merge
## into one; a top with no open space just above it (buried under other
## terrain) is left out. Bounce pads are not surfaces; they are where a launch
## link starts.
##
## Links between surfaces, each with the point the bot heads for to take it
## (`start`) and where it arrives (`land`); a link whose landing point is inside
## terrain is left out:
## - **DROP**: walk off an end of A and land on B below, the body falling no more
##   than the bot's MAX_DROP, when no bounce pad is in the way of the landing (a
##   pad throws the bot back up).
## - **LEAP**: from an end of A across a gap of up to LEAP_GAP to a ledge B no
##   more than LEAP_DROP lower (Summit's tower to its steps: the gap between is
##   over a pad, so only a jump across gets down).
## - **CLIMB**: from an end of A up to a ledge B at most CLIMB_RISE higher whose
##   near end is within CLIMB_GAP. Kept short: Summit's 60-70 px climbs across
##   50-70 px gaps failed too often to route through.
## - **PAD**: from a level pad set in A, a launch up to any surface B whose near
##   end is within PAD_REACH of the launch column and within the launch height.
##
## `next_hop` runs a cheapest-path search (the walk to each link, a cost per link,
## and the last walk to the goal itself) and returns the first link of the route.
## The bot steers to it with the moves it already has; with no route it uses its
## own rules.
##
## Preloaded by path (`Bot.gd`), never referenced by `class_name` (CLAUDE.md).

const DROP: int = 0
const LEAP: int = 1
const CLIMB: int = 2
const PAD: int = 3

## Parts that are no fixed terrain to plan on.
const SKIP_SCRIPTS: Array[Script] = [
	preload("res://scripts/MovingPlatform.gd"), preload("res://scripts/RotatingPlatform.gd"),
	preload("res://scripts/BreakableWall.gd"), preload("res://scripts/FallingRock.gd"),
	preload("res://scripts/CrumblingLedge.gd"), preload("res://scripts/CollapsingFloor.gd"),
]
const PAD_SCRIPT: Script = preload("res://scripts/BouncePad.gd")

## Gaps and heights a bot can manage (px).
const LEAP_GAP: float = 90.0
const LEAP_DROP: float = 130.0
const CLIMB_RISE: float = 50.0
const CLIMB_GAP: float = 60.0
const PAD_REACH: float = 60.0
## A pad is set in the surface whose top is within this of the pad's top.
const PAD_IN_SURFACE: float = 40.0
## A pad counts as under a landing when its centre is no more than this below it.
const PAD_UNDER_LANDING: float = 20.0
## The body's radius, and how far past an end the bot aims to be off it.
const BODY_RADIUS: float = 24.0
const PAST_END: float = 10.0
## Tops this close in height, touching or overlapping along x, are one surface.
const SAME_LEVEL: float = 4.0
## A point counts as on a surface when its ground is this close to the top.
const ON_SURFACE: float = 8.0
## How far above a top the open-space check looks (a body's width, less a little).
const OPEN_ABOVE: float = 20.0
## What a link costs over and above the walk to it, in px of walking.
const COST: Dictionary = {DROP: 60.0, LEAP: 220.0, CLIMB: 260.0, PAD: 180.0}

## Each surface: {"x0", "x1", "y"}.
var surfaces: Array[Dictionary] = []
## Each link: {"kind", "from", "to", "start": Vector2, "land": Vector2, "pad": Node2D or null}.
var links: Array[Dictionary] = []

var _space: PhysicsDirectSpaceState2D = null
var _exclude: Array[RID] = []

## Forgets the map (a stage with nothing to read).
func clear() -> void:
	surfaces.clear()
	links.clear()

## Reads `stage` in `space` (`exclude`: the players' bodies). `pads` are the
## stage's bounce pads; `launch_x` gives the clear launch x for one
## (Callable(pad) -> float) and `launch_height` how high it throws
## (Callable(pad) -> float). `max_drop`: the furthest the bot's body may fall.
func build(stage: Node, space: PhysicsDirectSpaceState2D, exclude: Array[RID], pads: Array[Node2D],
		launch_x: Callable, launch_height: Callable, max_drop: float) -> void:
	clear()
	if stage == null or space == null:
		return
	_space = space
	_exclude = exclude
	var tops: Array[Dictionary] = []
	for node: Node in stage.find_children("*", "StaticBody2D", true, false):
		var script: Script = node.get_script()
		if script == PAD_SCRIPT or script in SKIP_SCRIPTS:
			continue
		for child: Node in node.get_children():
			if not (child is CollisionShape2D) or not ((child as CollisionShape2D).shape is RectangleShape2D):
				continue
			var shape := child as CollisionShape2D
			if shape.disabled or not is_zero_approx(shape.global_rotation):
				continue
			var size: Vector2 = (shape.shape as RectangleShape2D).size * shape.global_scale.abs()
			var at: Vector2 = shape.global_position
			tops.append({"x0": at.x - size.x * 0.5, "x1": at.x + size.x * 0.5, "y": at.y - size.y * 0.5})
	for top: Dictionary in tops:
		surfaces.append(top.duplicate())
	_merge()
	surfaces = surfaces.filter(func(s: Dictionary) -> bool: return _open_above(s))
	surfaces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["y"] < b["y"] or (a["y"] == b["y"] and a["x0"] < b["x0"]))
	_link_ends(pads, max_drop)
	_link_pads(pads, launch_x, launch_height)
	links = links.filter(func(l: Dictionary) -> bool: return _free(l["land"]))

## The surface a point stands over: the one whose top is at `ground_y` (the
## ground the caller found straight below the point) and spans its x, or -1.
func surface_at(x: float, ground_y: float) -> int:
	for i in surfaces.size():
		var s: Dictionary = surfaces[i]
		if absf(s["y"] - ground_y) <= ON_SURFACE and x >= s["x0"] - 1.0 and x <= s["x1"] + 1.0:
			return i
	return -1

## The first link of the cheapest route from surface `from` (the bot at x
## `from_x`) to the goal at x `goal_x` on surface `to`, or an empty Dictionary
## when there is none or the two are the same surface.
func next_hop(from: int, from_x: float, to: int, goal_x: float) -> Dictionary:
	if from < 0 or to < 0 or from == to:
		return {}
	var best: Dictionary = {from: 0.0}
	var at_x: Dictionary = {from: from_x}
	var first: Dictionary = {}
	var open: Array[int] = [from]
	var done: Dictionary = {}
	while not open.is_empty():
		var cur: int = open[0]
		for o: int in open:
			if float(best[o]) < float(best[cur]):
				cur = o
		open.erase(cur)
		if cur == to:
			return first.get(cur, {})
		done[cur] = true
		for link: Dictionary in links:
			if link["from"] != cur or done.has(link["to"]):
				continue
			var nxt: int = link["to"]
			var land_x: float = (link["land"] as Vector2).x
			var cost: float = float(best[cur]) + absf((link["start"] as Vector2).x - float(at_x[cur])) + float(COST[link["kind"]])
			if nxt == to:
				cost += absf(goal_x - land_x)   # and the walk on to the goal
			if not best.has(nxt) or cost < float(best[nxt]):
				best[nxt] = cost
				at_x[nxt] = land_x
				first[nxt] = first[cur] if first.has(cur) else link
				if not open.has(nxt):
					open.append(nxt)
	return {}

## Merges tops at the same height that touch or overlap, until none do.
func _merge() -> void:
	var changed: bool = true
	while changed:
		changed = false
		for i in surfaces.size():
			for j in range(i + 1, surfaces.size()):
				var a: Dictionary = surfaces[i]
				var b: Dictionary = surfaces[j]
				if absf(a["y"] - b["y"]) <= SAME_LEVEL and b["x0"] <= a["x1"] and b["x1"] >= a["x0"]:
					a["x0"] = minf(a["x0"], b["x0"])
					a["x1"] = maxf(a["x1"], b["x1"])
					a["y"] = minf(a["y"], b["y"])
					surfaces.remove_at(j)
					changed = true
					break
			if changed:
				break

## Whether a top has open space just above it somewhere along it (its middle or
## near either end): a top buried under other terrain is no surface.
func _open_above(s: Dictionary) -> bool:
	var inset: float = minf(BODY_RADIUS, (s["x1"] - s["x0"]) * 0.5)
	for x: float in [s["x0"] + inset, (s["x0"] + s["x1"]) * 0.5, s["x1"] - inset]:
		if _free(Vector2(x, s["y"] - OPEN_ABOVE)):
			return true
	return false

## Whether `point` is outside all terrain.
func _free(point: Vector2) -> bool:
	if _space == null:
		return true
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = 1
	query.exclude = _exclude
	return _space.intersect_point(query, 1).is_empty()

func _link_ends(pads: Array[Node2D], max_drop: float) -> void:
	# Between surface tops: the body falls from its centre, BODY_RADIUS above.
	var top_drop: float = max_drop - BODY_RADIUS
	for i in surfaces.size():
		var a: Dictionary = surfaces[i]
		for d: float in [-1.0, 1.0]:
			var end: float = a["x1"] if d > 0.0 else a["x0"]
			var off := Vector2(end + d * (BODY_RADIUS + PAST_END), a["y"] - BODY_RADIUS)
			# DROP: the highest surface under the column just past the end.
			var landing: int = -1
			for j in surfaces.size():
				var b: Dictionary = surfaces[j]
				if j == i or b["y"] <= a["y"] or b["y"] - a["y"] > top_drop:
					continue
				if off.x < b["x0"] or off.x > b["x1"]:
					continue
				if landing < 0 or b["y"] < surfaces[landing]["y"]:
					landing = j
			if landing >= 0 and not _pad_between(pads, off.x, a["y"], surfaces[landing]["y"]):
				links.append({"kind": DROP, "from": i, "to": landing, "start": off,
						"land": Vector2(off.x, surfaces[landing]["y"] - BODY_RADIUS), "pad": null})
			for j in surfaces.size():
				if j == i:
					continue
				var b: Dictionary = surfaces[j]
				var near: float = b["x0"] if d > 0.0 else b["x1"]
				var gap: float = (near - end) * d
				var onto := Vector2(near + d * (BODY_RADIUS + PAST_END), b["y"] - BODY_RADIUS)
				var start := Vector2(end - d * BODY_RADIUS, a["y"] - BODY_RADIUS)
				# LEAP: across a gap to a ledge a little lower.
				if gap > 0.0 and gap <= LEAP_GAP and b["y"] > a["y"] and b["y"] - a["y"] <= LEAP_DROP:
					links.append({"kind": LEAP, "from": i, "to": j, "start": start, "land": onto, "pad": null})
				# CLIMB: up to a ledge whose near end is close.
				elif gap >= -BODY_RADIUS and gap <= CLIMB_GAP and b["y"] < a["y"] and a["y"] - b["y"] <= CLIMB_RISE:
					links.append({"kind": CLIMB, "from": i, "to": j, "start": start, "land": onto, "pad": null})

func _link_pads(pads: Array[Node2D], launch_x: Callable, launch_height: Callable) -> void:
	for pad: Node2D in pads:
		if not is_instance_valid(pad) or not is_zero_approx(pad.global_rotation):
			continue
		var top: float = pad.global_position.y - _pad_half(pad).y
		var lx: float = launch_x.call(pad)
		# The surface the pad is set in: the nearest top to the pad's that spans its column.
		var under: int = -1
		for i in surfaces.size():
			var s: Dictionary = surfaces[i]
			if absf(s["y"] - top) > PAD_IN_SURFACE or lx < s["x0"] - PAD_REACH or lx > s["x1"] + PAD_REACH:
				continue
			if under < 0 or absf(s["y"] - top) < absf(surfaces[under]["y"] - top):
				under = i
		if under < 0:
			continue
		var height: float = launch_height.call(pad)
		for j in surfaces.size():
			if j == under:
				continue
			var b: Dictionary = surfaces[j]
			if b["y"] >= top or top - b["y"] > height:
				continue
			var near: float = b["x1"] if b["x1"] < lx else (b["x0"] if b["x0"] > lx else lx)
			if absf(near - lx) > PAD_REACH or (b["x0"] <= lx and b["x1"] >= lx):
				continue
			var side: float = signf(near - lx)
			links.append({"kind": PAD, "from": under, "to": j, "start": Vector2(lx, pad.global_position.y),
					"land": Vector2(near + side * (BODY_RADIUS + PAST_END), b["y"] - BODY_RADIUS), "pad": pad})

## Whether a bounce pad lies under x between heights `above` and `below`.
func _pad_between(pads: Array[Node2D], x: float, above: float, below: float) -> bool:
	for pad: Node2D in pads:
		if not is_instance_valid(pad):
			continue
		if absf(x - pad.global_position.x) <= _pad_half(pad).x + BODY_RADIUS \
				and pad.global_position.y > above and pad.global_position.y <= below + PAD_UNDER_LANDING:
			return true
	return false

## Half a pad's size (its `size` export, scaled), or a body's radius without one.
func _pad_half(pad: Node2D) -> Vector2:
	var size: Variant = pad.get("size")
	return (size as Vector2) * pad.global_scale.abs() * 0.5 if size is Vector2 else Vector2(BODY_RADIUS, 0.0)
