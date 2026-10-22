extends RefCounted
## Auto-fit for the host's Text size (#751). Each screen (and popup) that holds
## text steps its own text size down from the chosen one until its contents
## fit, so Larger is honoured wherever there is room and nothing clips. Run
## from `Sfx._process`; load with preload() by path.
##
## One entry per fit root. It measures with `TextScale.overflows` a frame after
## each change (containers settle at the end of a frame): too big, step down by
## 0.1, never below Normal; fits, and once the contents change, try one step
## up again, and fall straight back if that does not fit.

const TextScaleScript := preload("res://scripts/TextScale.gd")

const STEP: float = 0.1
## Seconds between looks at a root that fits.
const IDLE_SECONDS: float = 0.25

var _entries: Dictionary = {} # instance id -> state Dictionary


## Starts tracking a fit root at `target`.
func register(root: Control, target: float) -> void:
	if _entries.has(root.get_instance_id()):
		return
	_entries[root.get_instance_id()] = {"root": root, "factor": target, "prev": target, "probing": false, "wait": 0, "idle": 0.0, "blocked": -1}
	TextScaleScript.assign_fit(root, target, target)


## The chosen size changed: every root starts again from it.
func retarget(target: float) -> void:
	for id: int in _entries.keys():
		var state: Dictionary = _entries[id]
		var root: Variant = state["root"]
		if not is_instance_valid(root):
			_entries.erase(id)
			continue
		state["factor"] = target
		state["prev"] = target
		state["probing"] = false
		state["wait"] = 0
		state["idle"] = 0.0
		state["blocked"] = -1
		TextScaleScript.assign_fit(root, target, target)


## The factor `root` is at now, or `fallback` when it is not tracked.
func factor_of(root: Control, fallback: float) -> float:
	var state: Dictionary = _entries.get(root.get_instance_id(), {})
	return float(state.get("factor", fallback))


func tracked() -> Array[Control]:
	var out: Array[Control] = []
	for id: int in _entries:
		var root: Variant = _entries[id]["root"]
		if is_instance_valid(root):
			out.append(root)
	return out


## One frame. Does nothing at Normal.
func tick(delta: float, target: float, viewport_size: Vector2) -> void:
	if target <= 1.0 + 0.001:
		return
	for id: int in _entries.keys():
		var state: Dictionary = _entries[id]
		var root: Variant = state["root"]
		if not is_instance_valid(root):
			_entries.erase(id)
			continue
		if not root.is_visible_in_tree():
			state["blocked"] = -1 # shown again later: look for room afresh
			continue
		if int(state["wait"]) > 0:
			state["wait"] = int(state["wait"]) - 1
			continue
		state["idle"] = float(state["idle"]) - delta
		if float(state["idle"]) > 0.0:
			continue
		_step(root, state, target, viewport_size)


func _step(root: Control, state: Dictionary, target: float, viewport_size: Vector2) -> void:
	var factor: float = float(state["factor"])
	if TextScaleScript.overflows(root, viewport_size):
		if factor <= 1.0 + 0.001:
			state["probing"] = false
			state["idle"] = IDLE_SECONDS
			return
		if bool(state["probing"]):
			state["probing"] = false
			state["blocked"] = TextScaleScript.signature(root)
			_apply(root, state, float(state["prev"]), target)
		else:
			state["blocked"] = TextScaleScript.signature(root)
			_apply(root, state, maxf(1.0, factor - STEP), target)
		state["idle"] = 0.0
		return
	state["probing"] = false
	state["idle"] = IDLE_SECONDS
	if factor < target - 0.001 and _may_probe(root, state):
		state["prev"] = factor
		state["probing"] = true
		_apply(root, state, minf(target, factor + STEP), target)


## Larger is tried again after the root is shown anew or when it holds fewer controls than when it last did not fit.
func _may_probe(root: Control, state: Dictionary) -> bool:
	return int(state["blocked"]) < 0 or TextScaleScript.signature(root) < int(state["blocked"])


func _apply(root: Control, state: Dictionary, factor: float, target: float) -> void:
	state["factor"] = factor
	state["wait"] = 2 # containers and wrapped labels take a couple of frames to settle
	TextScaleScript.set_fit(root, factor, target)


## The language changed: text may be shorter now, so every root may look for room again.
func reset_blocks() -> void:
	for id: int in _entries:
		(_entries[id] as Dictionary)["blocked"] = -1
