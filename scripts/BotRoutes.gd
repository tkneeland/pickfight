extends RefCounted

## Issue #1299: a bot's map of a stage, for getting between its levels.
##
## Built once a stage read (`Bot._read_stage`) from the stage's fixed terrain:
## every unrotated rectangle collision shape on a `StaticBody2D` that is not a
## moving, rotating, breakable or hazard part gives its top edge as a
## **surface** (overlapping tops at the same height merge). Bounce pads are not
## surfaces; they are where a launch link starts.
##
## Links between surfaces, each with the point the bot heads for to take it:
## - **DROP**: walk off an end of A and land on B below (within MAX_DROP), when
##   no bounce pad is in the way of the landing (a pad throws the bot back up).
## - **LEAP**: from an end of A across a gap of up to LEAP_GAP to a ledge B no
##   more than LEAP_DROP lower (Summit's tower to its steps: the gap between is
##   over a pad, so only a jump across gets down).
## - **CLIMB**: from an end of A up to a ledge B at most CLIMB_RISE higher whose
##   near end is within CLIMB_GAP.
## - **PAD**: from a level pad set in A, a launch up to any surface B whose near
##   end is within PAD_REACH of the launch column and within the launch height.
##
## `next_hop` runs a cheapest-path search (walking distance plus a cost per
## link) and returns the first link of the route. The bot steers to it with the
## moves it already has; with no route, the bot's own rules apply as before.
##
## Preloaded by path (`Bot.gd`), never referenced by `class_name` (CLAUDE.md).

const DROP: int = 0
const LEAP: int = 1
const CLIMB: int = 2
const PAD: int = 3

## Heights and gaps a bot can manage (px). MAX_DROP matches Bot.MAX_DROP.
const MAX_DROP: float = 240.0
const LEAP_GAP: float = 90.0
const LEAP_DROP: float = 130.0
const CLIMB_RISE: float = 50.0
const CLIMB_GAP: float = 60.0
const PAD_REACH: float = 60.0
## The body's radius, and how far past an end the bot aims to be off it.
const BODY_RADIUS: float = 24.0
const PAST_END: float = 10.0
## Tops this close in height, touching or overlapping along x, are one surface.
const SAME_LEVEL: float = 4.0
## A point counts as on a surface when its ground is this close to the top.
const ON_SURFACE: float = 8.0
## What a link costs over and above the walk to it, in px of walking.
const COST: Dictionary = {DROP: 60.0, LEAP: 220.0, CLIMB: 260.0, PAD: 180.0}

## Each surface: {"x0", "x1", "y"}.
var surfaces: Array[Dictionary] = []
## Each link: {"kind", "from", "to", "start": Vector2 (where on `from` the bot
## heads to take it), "land": Vector2 (where on `to` it arrives), "pad": Node2D or null}.
var links: Array[Dictionary] = []

## Reads `stage`. `skip` holds the scripts of parts that are no fixed terrain;
## `pads` the stage's bounce pads; `launch_x` the bot's clear launch x for a pad
## (Callable(pad) -> float); `launch_height` how high a pad throws (Callable(pad) -> float).
func build(stage: Node, skip: Array, pad_script: Script, pads: Array[Node2D], launch_x: Callable, launch_height: Callable) -> void:
	surfaces.clear()
	links.clear()
	if stage == null:
		return
	var tops: Array[Dictionary] = []
	for node: Node in stage.find_children("*", "StaticBody2D", true, false):
		var script: Script = node.get_script()
		if script == pad_script or script in skip:
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
	tops.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["y"] < b["y"] or (a["y"] == b["y"] and a["x0"] < b["x0"]))
	for top: Dictionary in tops:
		var merged: bool = false
		for s: Dictionary in surfaces:
			if absf(s["y"] - top["y"]) <= SAME_LEVEL and top["x0"] <= s["x1"] and top["x1"] >= s["x0"]:
				s["x0"] = minf(s["x0"], top["x0"])
				s["x1"] = maxf(s["x1"], top["x1"])
				merged = true
				break
		if not merged:
			surfaces.append(top.duplicate())
	_link_ends(pads)
	_link_pads(pads, launch_x, launch_height)

## The surface a point stands over: the first whose top is at `ground_y` (the
## ground the caller found straight below the point) and spans its x, or -1.
func surface_at(x: float, ground_y: float) -> int:
	for i in surfaces.size():
		var s: Dictionary = surfaces[i]
		if absf(s["y"] - ground_y) <= ON_SURFACE and x >= s["x0"] - 1.0 and x <= s["x1"] + 1.0:
			return i
	return -1

## The first link of the cheapest route from surface `from` (the bot at x
## `from_x`) to surface `to`, or an empty Dictionary when there is none or the
## two are the same surface.
func next_hop(from: int, from_x: float, to: int) -> Dictionary:
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
			var cost: float = float(best[cur]) + absf((link["start"] as Vector2).x - float(at_x[cur])) + float(COST[link["kind"]])
			var nxt: int = link["to"]
			if not best.has(nxt) or cost < float(best[nxt]):
				best[nxt] = cost
				at_x[nxt] = (link["land"] as Vector2).x
				first[nxt] = first[cur] if first.has(cur) else link
				if not open.has(nxt):
					open.append(nxt)
	return {}

func _link_ends(pads: Array[Node2D]) -> void:
	for i in surfaces.size():
		var a: Dictionary = surfaces[i]
		for d: float in [-1.0, 1.0]:
			var end: float = a["x1"] if d > 0.0 else a["x0"]
			var off := Vector2(end + d * (BODY_RADIUS + PAST_END), a["y"] - BODY_RADIUS)
			# DROP: the highest surface under the column just past the end.
			var landing: int = -1
			for j in surfaces.size():
				var b: Dictionary = surfaces[j]
				if j == i or b["y"] <= a["y"] or b["y"] - a["y"] > MAX_DROP:
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
		var size: Variant = pad.get("size")
		var top: float = pad.global_position.y - ((size as Vector2).y * absf(pad.global_scale.y) * 0.5 if size is Vector2 else 0.0)
		var lx: float = launch_x.call(pad)
		var under: int = -1
		for i in surfaces.size():
			var s: Dictionary = surfaces[i]
			if absf(s["y"] - top) <= 40.0 and lx >= s["x0"] - 60.0 and lx <= s["x1"] + 60.0:
				under = i
				break
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
			links.append({"kind": PAD, "from": under, "to": j, "start": Vector2(lx, top - BODY_RADIUS),
					"land": Vector2(near + side * (BODY_RADIUS + PAST_END), b["y"] - BODY_RADIUS), "pad": pad})

## Whether a bounce pad lies under x between heights `above` and `below`.
func _pad_between(pads: Array[Node2D], x: float, above: float, below: float) -> bool:
	for pad: Node2D in pads:
		if not is_instance_valid(pad):
			continue
		var size: Variant = pad.get("size")
		var half: float = ((size as Vector2).x * absf(pad.global_scale.x) * 0.5) if size is Vector2 else BODY_RADIUS
		var y: float = pad.global_position.y
		if absf(x - pad.global_position.x) <= half + BODY_RADIUS and y > above and y <= below + 20.0:
			return true
	return false
