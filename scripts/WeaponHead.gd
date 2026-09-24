class_name WeaponHead
extends RigidBody2D

## The weapon's head: the only part of the weapon that collides, and so the
## part that plants, strikes and blocks (ADR-0005, ADR-0006). `Player` builds
## it as part of the weapon rig; this script exists for one job the engine
## will not do for us.
##
## **Why it is here.** The head is small, and a swing moves it fast: measured
## peak head speed in clear air is 2724 px/s, and the largest single-tick
## displacement measured is 45.4 px, against arena platforms that are 24 px
## thick. A single step can therefore finish with the head past the middle of a
## slab, and the shortest way out of that overlap is through the far side. That
## is
## the tunnelling ADR-0006 warned the spike would have to survive, and the
## operator hit it in real play: swinging straight down to boost upward
## occasionally put the head under a platform instead of planted on it.
##
## **Why `continuous_cd` does not cover it.** The head already runs
## `CCD_MODE_CAST_SHAPE`. Godot's 2D continuous detection estimates a step's
## motion from the body's velocity at the time the collision pair is set up,
## which is before the constraint solver runs. The head is not only integrated
## -- it is also dragged by the joints that tie it to the haft and the body,
## and that part of its motion is produced inside the solve. Measured on the
## boost move: the worst single tick displaced the head 36.2 px while its
## pre-step velocity accounted for only 21.0 px. The remaining 15.2 px, 42% of
## the motion, never appeared in the estimate CCD was working from. No CCD
## setting closes that, because there is nothing wrong with the CCD.
##
## **Why not the other two levers.** Raising `physics_ticks_per_second`
## shrinks the window without closing it, and re-times every tick-counted
## thing in the project. Clamping the head's per-tick displacement would close
## it, but guaranteeing safety against 24 px geometry at 60 Hz means capping
## the head near 720 px/s -- about a quarter of the speed the moveset actually
## reaches, which would cost the fast swing the operator says feels right.
##
## **What it does instead.** Each tick the head sweeps its own collision shape
## along the displacement the previous step actually produced -- whatever
## produced it, integration or solver. If that path crossed something solid,
## the head is placed at the contact point and the part of its velocity
## heading into the surface is removed. That is the same outcome the step
## would have had if the solver had seen the contact, and it is applied
## against the motion that really happened rather than against a prediction.
##
## **And the same thing happens head against head.** Blocking is one of the
## three jobs the weapon exists for (CONTEXT.md), and two heads charged into
## each other went clean through: measured, two heads 26.2 px apart ended one
## step 26.2 px apart on the other side, with no tick at which they were ever
## in contact. The world sweep above cannot be pointed at it -- see
## `sweep_mask` for why each head correcting itself against the other is the
## wrong shape -- and neither can either head's own motion, because at 1200
## px/s each it is the *relative* motion that crosses the gap and either
## head's share of it is only half. `_undo_any_head_crossing` handles the
## pair instead: one correction, by one of the two heads, computed from both
## heads' motion over the step. See `_owns_pair` for which one, and why that
## has to be answerable the same way from either side.

## Floor under the sweep gate, so a degenerate head shape cannot make the
## sweep run against every tick of ordinary contact.
const SWEEP_GATE_FLOOR: float = 4.0
## Directions the head's width is measured along to find its narrowest, half
## a turn's worth. A head is a cluster of circles (ADR-0010) whose facing
## turns every tick, so the narrowest width has to be a property of the
## cluster rather than of the frame it happens to be drawn in; sampling
## directions is what makes it one. Sixteen resolves it to 11.25 degrees,
## which on the shapes this rig carries is a fraction of a pixel.
const GATE_DIRECTIONS: int = 16
## How far past the contact point the surface is probed for its normal. Just
## enough overlap to get an answer.
const NORMAL_PROBE_DEPTH: float = 1.0
## Every live head is in this group, which is how one head finds the other.
## Membership tracks being in the tree, so a rig torn down mid-frame stops
## being a candidate as soon as it leaves.
const HEAD_GROUP: StringName = &"weapon_heads"
## Halvings spent finding the moment in the step at which two heads first
## touched. Ten resolves the largest relative step this rig produces -- 60 px,
## two heads charged at 1800 px/s each -- to 0.06 px, which is finer than the
## solver's own give, and it lands the head a hair inside contact rather than
## a hair short of it. That matters: seated just inside, the step that
## follows generates a real contact and the solver takes the clash from
## there, which is where a clash belongs.
const PAIR_CONTACT_STEPS: int = 10
## How far a step may carry one head past the moment it met another before
## the pair is corrected rather than left to the solver. Measured against
## what this rig actually produces: a settled clash holds at 0.3 px of give
## and an ordinary walked approach leaves 1.2 px, neither of which is visible
## or worth touching, while a head sent in at full extension leaves 5.5 px --
## a third of the head, and plainly wrong for a block.
const PAIR_OVERLAP_ALLOWANCE: float = 2.0

## The collision shape nodes whose shapes are swept: every circle in the
## head's cluster (ADR-0010). Set by `Player` when it builds the rig. Each is
## read for its local transform as well as its shape, because the cluster is
## turned to face along the haft each tick while the body itself stays
## rotation-locked -- so a circle's offset from the head's anchor is where
## the facing actually lives.
##
## Everything below works per circle and takes the earliest answer across the
## cluster. That is not an approximation of the single-shape version it
## replaces: each circle sweeps and each pair of circles meets on exactly the
## maths that was there before, and a head is stopped by whichever of its
## circles got somewhere first, which is what being one rigid cluster means.
var sweep_shapes: Array[CollisionShape2D] = []

## Layers the sweep treats as solid, and bodies it ignores.
##
## Deliberately not the head's own `collision_mask`, which also contains other
## weapon heads: a clash is two driven heads contesting, and two heads each
## snapping the other back out of the contact would fight rather than resolve.
## Head against head is handled by `_undo_any_head_crossing` instead, which
## corrects the pair once rather than each head separately.
## The exclusion list carries the head's own player, whose body the head is
## allowed to pass through.
var sweep_mask: int = 1
var sweep_exclude: Array[RID] = []

## The force ceiling of the weapon driving this head, copied here by `Player`
## when it builds the rig. The head never drives with it; it is here for one
## purpose, which is deciding which of two heads owns their shared
## correction. See `_owns_pair`.
var drive_force: float = 0.0

## What the last sweep correction stopped the head against, and how fast the
## head was heading into it when it did. Read and cleared by `Player`.
##
## The sweep turns out not to be only a safety net. A head arriving at swing
## speed is stopped *here* rather than by the solver: the sweep runs first,
## puts the head at the surface and takes the closing velocity out of it, so
## the step that follows generates no contact worth the name. Measured on a
## 2468 px/s strike, the only `body_entered` the owner ever saw carried 18
## px/s -- everything that made it a strike had already been resolved. So
## anything that wants to know a hard hit happened has to be told from in
## here; there is nowhere else it is visible.
##
## Only the world sweep writes these. A head stopped against another head
## leaves them alone on purpose: a head meeting a head is a block, not a
## strike (CONTEXT.md's Clash), and `Player._score_swept_strike` is the code
## that would have to be told otherwise.
var swept_into: Object = null
var swept_speed: float = 0.0

var _previous_position: Vector2 = Vector2.ZERO
var _has_previous: bool = false
## Cached per cluster: the sweep gate, and how far the cluster reaches from
## the head's own origin. Both are fixed by the weapon, so they are recomputed
## when `Player` hands over a different set of shapes and not otherwise.
var _gate_shapes: Array[CollisionShape2D] = []
var _gate_distance: float = 0.0
var _cluster_radius: float = 0.0

## The step that just finished, snapshotted before anything this tick has had
## a chance to correct it: where this head started, where it ended, how it was
## facing and how fast it was going. Stamped with the physics frame it belongs
## to.
##
## A pair correction is computed from both heads' snapshots rather than from
## whatever the two bodies happen to hold at the moment it runs, because the
## engine integrates the two in some order and the second of them would
## otherwise be reading a partner that has already moved this tick. Taken from
## `_integrate_forces` when this head's own turn comes first, and pulled
## straight off the physics server by whichever head asks first when it does
## not -- either way it is the same numbers, and the pair agrees on the
## encounter however the engine ordered them.
var _step_frame: int = -1
var _step_from: Vector2 = Vector2.ZERO
var _step_to: Vector2 = Vector2.ZERO
var _step_rotation: float = 0.0
var _step_velocity: Vector2 = Vector2.ZERO
var _step_usable: bool = false

func _enter_tree() -> void:
	add_to_group(HEAD_GROUP)

func _exit_tree() -> void:
	remove_from_group(HEAD_GROUP)

## Called by `Player` whenever the head is moved by something other than the
## simulation -- a scenario placing a player via `Player.teleport_to()`. (A
## new round's spawn builds a fresh head instead.) Without it the next
## sweep would run along the teleport itself and snap the head back to the
## place it was teleported away from.
func forget_previous_position() -> void:
	_has_previous = false

## The shortest step worth sweeping: the head's own narrowest width.
##
## Below that, a step cannot have carried the head deeper into something than
## the head is wide, so the end-of-step contact check sees the overlap and
## pushes it out of the side it came in. Above it, the head can finish a step
## past the middle of thin geometry, and the shortest way out is then through
## the far side -- which is the failure this class exists for. The arena's
## thinnest platform is 24 px, comfortably above the pickaxe's 16 px head.
##
## This gate is load-bearing in the other direction too. Sweeping on every
## step instead cost a plant its settle: landing on another player bounces the
## head 4-11 px a tick for a while, and correcting each of those turned an
## ordinary settle into a limit cycle the player never came to rest out of.
## Small overlaps are the solver's, and it resolves them correctly.
##
## For a cluster it is the **whole head's** narrowest width, not its smallest
## circle's. The head is one rigid body: a step shorter than the cluster is
## wide cannot have left the cluster past the middle of anything, whichever
## circle is deepest, because the rest of the cluster is still on the side it
## came in from and the solver pushes the body out that way. Gating on the
## smallest circle instead would fire the sweep on steps the solver settles
## perfectly well -- the pickaxe's horn circles are 7.4 px across, inside the
## 4-11 px a plant bounces through -- and buy back the limit cycle. A single
## circle, which is what every weapon was until ADR-0010, measures the same
## 16 px it always did.
func _sweep_gate() -> float:
	_refresh_cluster_metrics()
	return _gate_distance

## How far the cluster reaches from the head's origin: the pair correction's
## early-out, so two heads nowhere near each other cost one distance test
## rather than a pass over every circle against every circle.
func _head_reach() -> float:
	_refresh_cluster_metrics()
	return _cluster_radius

func _refresh_cluster_metrics() -> void:
	if _gate_shapes == sweep_shapes:
		return
	_gate_shapes = sweep_shapes.duplicate()
	_gate_distance = maxf(SWEEP_GATE_FLOOR, _narrowest_width())
	_cluster_radius = _furthest_reach()

## The narrowest the head is, measured across the cluster in every sampled
## direction. Circles only, per ADR-0010; a shape that is not a circle is left
## out, which can only make the gate smaller and so the sweep more willing to
## run.
func _narrowest_width() -> float:
	var narrowest: float = INF
	for i in GATE_DIRECTIONS:
		var axis: Vector2 = Vector2.RIGHT.rotated(PI * float(i) / float(GATE_DIRECTIONS))
		var low: float = INF
		var high: float = -INF
		for node: CollisionShape2D in sweep_shapes:
			var circle := node.shape as CircleShape2D
			if circle == null:
				continue
			var along: float = node.transform.origin.dot(axis)
			low = minf(low, along - circle.radius)
			high = maxf(high, along + circle.radius)
		if low > high:
			continue
		narrowest = minf(narrowest, high - low)
	return 0.0 if narrowest == INF else narrowest

func _furthest_reach() -> float:
	var reach: float = 0.0
	for node: CollisionShape2D in sweep_shapes:
		var circle := node.shape as CircleShape2D
		if circle == null:
			continue
		reach = maxf(reach, node.transform.origin.length() + circle.radius)
	return reach

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	_snapshot_step(state.transform, state.linear_velocity)
	# At most one correction a tick, and the world goes first: terrain is not
	# negotiable, and a head the world sweep has already stopped and taken the
	# closing velocity out of is not still arriving anywhere.
	if _has_previous and not _undo_any_tunnelling(state):
		_undo_any_head_crossing(state)
	_previous_position = state.transform.origin
	_has_previous = true

## Returns whether it moved the head.
func _undo_any_tunnelling(state: PhysicsDirectBodyState2D) -> bool:
	if sweep_shapes.is_empty():
		return false

	var motion: Vector2 = state.transform.origin - _previous_position
	var distance: float = motion.length()
	if distance < _sweep_gate():
		return false

	# Each circle is swept where it actually sits, not at the body's origin:
	# the body is rotation-locked, so the cluster carries its facing on the
	# shape nodes rather than on the body. Those offsets are constant across a
	# pure translation, so a safe fraction found for a circle is the same safe
	# fraction for the body's origin -- which is what lets the earliest of
	# them stand for the whole head.
	var start := Transform2D(state.transform.get_rotation(), _previous_position)
	var params := PhysicsShapeQueryParameters2D.new()
	params.motion = motion
	params.collision_mask = sweep_mask
	params.exclude = sweep_exclude
	params.margin = 0.0

	var space: PhysicsDirectSpaceState2D = state.get_space_state()
	var safe: float = 1.0
	var stopped_by: CollisionShape2D = null
	for node: CollisionShape2D in sweep_shapes:
		if node.shape == null:
			continue
		params.shape = node.shape
		params.transform = start * node.transform
		var fractions: PackedFloat32Array = space.cast_motion(params)
		if fractions.size() < 2:
			continue
		# 1.0 means this circle's path was clear. 0.0 means it could not move
		# at all from where the step began -- it was already touching -- so it
		# crossed nothing this step and the contact is the solver's to
		# resolve. Snapping a head that is skimming along a surface back to
		# where it started would pin it to that surface, which would cost the
		# moveset far more than the tunnelling does.
		if fractions[0] <= 0.0 or fractions[0] >= safe:
			continue
		safe = fractions[0]
		stopped_by = node
	if stopped_by == null:
		return false

	var contact: Vector2 = _previous_position + motion * safe
	state.transform = Transform2D(state.transform.get_rotation(), contact)

	var travel: Vector2 = motion / distance
	params.shape = stopped_by.shape
	params.transform = start * stopped_by.transform
	var rest: Dictionary = _contact_rest_info(space, params, contact, travel)
	var normal: Vector2 = _surface_normal(rest, travel)
	var into: float = state.linear_velocity.dot(normal)
	if into < 0.0:
		state.linear_velocity -= normal * into
		swept_into = instance_from_id(rest["collider_id"]) if rest.has("collider_id") else null
		swept_speed = -into
	return true

## Whatever the sweep stopped against: its normal, and which body it was.
## Probed just past the contact point, the shallowest overlap that still
## gets an answer. `params` arrives carrying the circle that stopped first,
## sitting where it sat at the start of the step -- that circle is the one
## touching the surface, so it is the one the surface is asked about.
func _contact_rest_info(
		space: PhysicsDirectSpaceState2D,
		params: PhysicsShapeQueryParameters2D,
		contact: Vector2,
		travel: Vector2) -> Dictionary:
	params.motion = Vector2.ZERO
	params.transform = params.transform.translated(
		contact - _previous_position + travel * NORMAL_PROBE_DEPTH)
	return space.get_rest_info(params)

## The surface's normal, so that what is taken out of the velocity is the part
## driving the head through the surface and not the part sliding it along.
## Oriented against the direction of travel rather than trusted to arrive that
## way, and falling back to the direction of travel itself, which can be
## over-eager but can never be the wrong sign.
func _surface_normal(rest: Dictionary, travel: Vector2) -> Vector2:
	if rest.has("normal"):
		var normal: Vector2 = rest["normal"]
		if normal.length_squared() > 0.0:
			return -normal if normal.dot(travel) > 0.0 else normal
	return -travel

# --- Head against head ------------------------------------------------------

## Snapshot the step that just finished, once a tick, before anything has
## corrected it. Safe to call twice: the second call is the one that finds the
## frame already stamped, and the two would have produced identical numbers
## anyway.
func _snapshot_step(xform: Transform2D, velocity: Vector2) -> void:
	var frame: int = Engine.get_physics_frames()
	if _step_frame == frame:
		return
	_step_frame = frame
	_step_from = _previous_position
	_step_to = xform.origin
	_step_rotation = xform.get_rotation()
	_step_velocity = velocity
	_step_usable = _has_previous

## This head's snapshot of the step that just finished, taken now if this
## tick's has not been taken yet.
##
## Read by the other head of a pair, which may well get here before this head
## has been integrated at all -- so the fallback reads the physics server
## rather than the node, whose transform is only synced as each body's turn
## comes round and would otherwise be a whole step stale.
func pair_step_snapshot() -> Dictionary:
	if _step_frame != Engine.get_physics_frames():
		var rid: RID = get_rid()
		_snapshot_step(
			PhysicsServer2D.body_get_state(rid, PhysicsServer2D.BODY_STATE_TRANSFORM),
			PhysicsServer2D.body_get_state(rid, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY))
	return {
		"usable": _step_usable,
		"from": _step_from,
		"to": _step_to,
		"rotation": _step_rotation,
		"velocity": _step_velocity,
	}

## Which of two heads does the pair's one correction.
##
## It has to be one of them and the same one from either side, or the whole
## point is lost: two heads each snapping the other out of the contact is the
## fight `sweep_mask` excludes head-vs-head to avoid, and no head at all doing
## it is the tunnelling this exists to close.
##
## The weaker weapon owns it, so that the correction agrees with the clash
## rule rather than competing with it: the head that gives way is the one
## whose drive would have lost the contest anyway. `max_drive_force` is the
## number that decides a clash (ADR-0006), and it is what `drive_force`
## carries.
##
## **The tie is the case that actually exists.** Every player holds the same
## pickaxe today, so two heads meeting have identical force ceilings and the
## weaker-weapon rule says nothing at all. The tie-break is instance id:
## unique, never equal between two live objects, and -- the property that
## matters -- the same comparison from either side, so it cannot depend on
## which head the engine integrates first, on group order, or on where either
## player sits in the scene. With identical weapons the two answers are
## physically interchangeable anyway; what is needed is that there is exactly
## one of them.
func _owns_pair(other: Variant) -> bool:
	var theirs: float = other.drive_force
	if drive_force != theirs:
		return drive_force < theirs
	return get_instance_id() < other.get_instance_id()

## Undo a head having gone through, or deep into, another head this step.
##
## Worked in the relative frame, which is the only frame the crossing is
## visible in: at 1200 px/s each the two heads close 40 px in a tick against
## the 16 px at which they touch, but neither head's own 20 px reaches the
## other's starting position, so nothing cast along one head's motion alone
## ever sees it.
##
## It fires on one thing: a pair that began the step clear of each other, met
## during it, and was carried more than `PAIR_OVERLAP_ALLOWANCE` past the
## moment of meeting. That is a head arriving faster than the step can
## resolve, and the owner is put back where the two shapes first touched with
## its closing speed taken out of it.
##
## **Why the gate is depth and not speed.** The world sweep gates on how far
## the head moved, because against terrain the question is whether the step
## could have carried it past the middle of a slab. Here the question is
## simply how far into another head the step left this one, so that is what is
## measured. It also makes the gate self-limiting in the way the world
## sweep's is: a corrected pair sits a hundredth of a pixel inside each other,
## far under the allowance, so the correction cannot re-trigger on its own
## output. Measured, an ordinary walked approach at 2.7 px a tick leaves 1.2
## px and a settled clash holds at 0.3 px -- both below the allowance, both
## left to the solver, which resolves them correctly. A head sent in at
## 22.6 px a tick leaves 5.5 px, a third of the head, which is the visible
## interpenetration this closes.
##
## Sustained contact is cheap and does nothing: every pair of circles that
## starts the step touching is passed over as the solver's, and a settled
## clash is nothing but those. Two heads that are nowhere near each other are
## cheaper still -- they never reach the circles at all, see `_head_reach()`.
func _undo_any_head_crossing(state: PhysicsDirectBodyState2D) -> void:
	if sweep_shapes.is_empty() or not _step_usable:
		return
	var tree: SceneTree = get_tree()
	if tree == null or is_queued_for_deletion():
		return

	var my_motion: Vector2 = _step_to - _step_from
	var mine := Transform2D(_step_rotation, _step_from)

	var soonest: float = INF
	var normal: Vector2 = Vector2.ZERO
	var offset: Vector2 = Vector2.ZERO
	var partner_origin: Vector2 = Vector2.ZERO
	var partner_velocity: Vector2 = Vector2.ZERO

	for node: Node in tree.get_nodes_in_group(HEAD_GROUP):
		# Deliberately untyped. Declaring a `class_name` is harmless;
		# *resolving* one needs Godot's global class cache, which lives in
		# the gitignored `.godot/` and is only built by an editor run, so a
		# fresh clone cannot parse a reference to it. Same reason as
		# `Player`'s preloads.
		var other: Variant = node
		if node == self or node.is_queued_for_deletion() or not node.is_inside_tree():
			continue
		if node.get_script() != get_script():
			continue
		# The other head answers for its own half of the encounter, and only
		# one of the two of us acts on the answer.
		if not _owns_pair(other):
			continue
		var their_shapes: Array[CollisionShape2D] = other.sweep_shapes
		if their_shapes.is_empty():
			continue
		var theirs: Dictionary = other.pair_step_snapshot()
		if not theirs["usable"]:
			continue

		var their_from: Vector2 = theirs["from"]
		var their_motion: Vector2 = Vector2(theirs["to"]) - their_from
		var closed: float = (my_motion - their_motion).length()
		if closed <= 0.0:
			continue
		# Nowhere near each other at any point in the step: no pair of circles
		# can have met, and saying so from the two heads' own reach costs one
		# test instead of a pass over the whole of both clusters.
		if _closest_approach(_step_from - their_from, my_motion - their_motion) \
				> _head_reach() + other._head_reach():
			continue
		var theirs_at_start := Transform2D(theirs["rotation"], their_from)

		var met: Dictionary = _first_circle_contact(
			mine, my_motion, their_shapes, theirs_at_start, their_motion)
		if met.is_empty():
			continue
		var fraction: float = met["fraction"]
		# How far past meeting the step carried them. Below the allowance the
		# overlap is the kind the solver pushes out invisibly.
		if (1.0 - fraction) * closed <= PAIR_OVERLAP_ALLOWANCE:
			continue
		if fraction >= soonest:
			continue
		soonest = fraction
		normal = met["normal"]
		# How the two bodies sat relative to one another at the moment they
		# first touched. Carried over to wherever the other head actually
		# ended the step, so the correction leaves the pair in contact rather
		# than in contact with where the other head used to be.
		offset = (_step_from + my_motion * fraction) - (their_from + their_motion * fraction)
		partner_origin = theirs["to"]
		partner_velocity = theirs["velocity"]

	if soonest > 1.0 or normal.length_squared() == 0.0:
		return

	state.transform = Transform2D(state.transform.get_rotation(), partner_origin + offset)
	# The other head is moving too, so what is taken out is the part of the
	# closing speed *between the two of them* -- a head being carried along by
	# the head it is braced against is not still driving into it. Deliberately
	# not recorded in `swept_into`: this is a block, not a strike.
	var closing: float = (state.linear_velocity - partner_velocity).dot(normal)
	if closing < 0.0:
		state.linear_velocity -= normal * closing

## The earliest moment in the step at which any circle of this head met any
## circle of another, and the normal along which they met there.
##
## Empty when no pair of circles met that had not already been touching when
## the step began.
##
## **Contact is excluded per pair of circles, not per pair of heads.** Two
## clusters are not one shape: a horn resting against a horn is sustained
## contact and the solver's, and a belly crossing the other head in the same
## step is not -- and a head with a hundredth of a pixel of resting contact
## somewhere on it must not be blind to a head arriving into it elsewhere.
## Measured on the charge sweep, where the two answers are plainly different:
## excluding the whole pair let charged heads finish steps 5 px between
## anchors, where excluding only the touching circles holds them at the 18 px
## the crescents meet at.
##
## It cannot re-trigger on its own output for the same reason the head-level
## version could not: the pair this correction seats together is touching at
## the start of the next step, so it is the pair excluded next time, and
## anything else that comes into contact behind it has PAIR_OVERLAP_ALLOWANCE
## to cross before it counts.
##
## The normal comes from the two circles that met rather than from the two
## body origins the single-shape version could use interchangeably: between
## two circles it is exactly the line of centres, and with the cluster's
## circles sitting off their heads' anchors that is no longer the line
## between the anchors.
func _first_circle_contact(
		mine: Transform2D,
		my_motion: Vector2,
		their_shapes: Array[CollisionShape2D],
		theirs: Transform2D,
		their_motion: Vector2) -> Dictionary:
	var soonest: float = INF
	var normal: Vector2 = Vector2.ZERO
	for my_node: CollisionShape2D in sweep_shapes:
		if my_node.shape == null:
			continue
		var my_at_start: Transform2D = mine * my_node.transform
		for their_node: CollisionShape2D in their_shapes:
			if their_node == null or their_node.shape == null:
				continue
			var their_at_start: Transform2D = theirs * their_node.transform
			# These two were already touching when the step began: they
			# crossed nothing, and their contact belongs to the solver.
			if my_node.shape.collide(my_at_start, their_node.shape, their_at_start):
				continue
			if not my_node.shape.collide_with_motion(
					my_at_start, my_motion, their_node.shape, their_at_start, their_motion):
				continue
			var fraction: float = _first_contact_fraction(
				my_node.shape, my_at_start, my_motion,
				their_node.shape, their_at_start, their_motion)
			if fraction >= soonest:
				continue
			soonest = fraction
			normal = ((my_at_start.origin + my_motion * fraction) \
				- (their_at_start.origin + their_motion * fraction)).normalized()
	if soonest > 1.0:
		return {}
	return {"fraction": soonest, "normal": normal}

## How close two bodies got over one step, given where one started relative
## to the other and how their motions differed. Closed form: the relative
## motion is a straight line, so the nearest point on it is the foot of the
## perpendicular, clamped to the step.
func _closest_approach(relative_from: Vector2, relative_motion: Vector2) -> float:
	var length_squared: float = relative_motion.length_squared()
	if length_squared == 0.0:
		return relative_from.length()
	var along: float = clampf(-relative_from.dot(relative_motion) / length_squared, 0.0, 1.0)
	return (relative_from + relative_motion * along).length()

## Where in the step the two shapes first touched, as a fraction of it.
##
## Bisected on the engine's own swept shape-versus-shape test, which answers
## "did these two meet anywhere along these two motions" rather than when, so
## halving the pair of motions together narrows the interval that contains
## the answer. Returns the near end of the interval that still collides, which
## is inside contact by at most the resolution -- see PAIR_CONTACT_STEPS.
func _first_contact_fraction(
		shape: Shape2D,
		from: Transform2D,
		motion: Vector2,
		other_shape: Shape2D,
		other_from: Transform2D,
		other_motion: Vector2) -> float:
	var clear: float = 0.0
	var met: float = 1.0
	for _i in PAIR_CONTACT_STEPS:
		var mid: float = (clear + met) * 0.5
		if shape.collide_with_motion(from, motion * mid, other_shape, other_from, other_motion * mid):
			met = mid
		else:
			clear = mid
	return met
