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
## head's share of it is only half. `_find_head_crossing` handles the
## pair instead: one correction, by one of the two heads, computed from both
## heads' motion over the step. See `_owns_pair` for which one, and why that
## has to be answerable the same way from either side.

## Floor under the sweep gate, so a degenerate head shape cannot make the
## sweep run against every tick of ordinary contact.
##
## It can bind on an ordinary weapon and not only a degenerate one, and
## wherever it does, the argument `_sweep_gate()` makes -- a step shorter than
## the cluster is wide cannot have left the cluster -- no longer covers the
## difference. On the roster as it stands the dagger is that case: 3.84 px
## across, so it is gated at this 4.00 and the last 0.16 px goes uncovered.
## Keeping a plant's settle out of a limit cycle is worth that much.
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
## Head against head is handled by `_find_head_crossing` instead, which
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

## Sound hooks (issue #75, ADR-0016); nothing in the physics reads them.
## `struck_world`: the world sweep stopped this head against `collider` --
## terrain, or a player's body -- heading into it at `speed` px/s.
## `clashed`: this head's pair correction took `speed` px/s of closing speed
## out against another head. Only the head that owns the pair corrects it,
## so one clash is one `clashed`.
signal struck_world(collider: Object, speed: float, point: Vector2)
signal clashed(speed: float, point: Vector2)

var _previous_position: Vector2 = Vector2.ZERO
## The facing that goes with `_previous_position`. Both sweeps reconstruct the
## pose the head held when the step began, and a pose is a position *and* a
## facing: taking the position from the step's start and the facing from its
## end describes an instant that never happened. Harmless while a head was one
## circle centred on its anchor, because that circle sits at the anchor at
## every facing. Since ADR-0010 a cluster's circles sit well off it -- the axe
## crescent reaches about 50 px -- so a head that turned during the step has
## its starting circles reconstructed wherever the facing it ended on puts
## them, and the sweep then looks for a crossing along a path the head did not
## take.
var _previous_rotation: float = 0.0
## Where each swept circle sat, in this head's own frame, when the step began.
##
## The body is `lock_rotation = true`, so the facing does not live in its
## transform at all -- `Player._update_weapon_visual` rewrites every circle's
## local `position` and `rotation` from the aim once a tick. Reading those
## nodes during `_integrate_forces` therefore gets *this* tick's facing, and
## pairing it with last tick's anchor describes a pose the head never held.
##
## Under one circle centred on the anchor that was invisible: the circle sits
## in the same place at every facing. Since ADR-0010 the axe's crescent reaches
## about 50 px off its anchor, so a head that swung 0.4 rad during the step had
## those circles some 20 px from where this reconstructs them -- comparable to
## the whole 16 px at which two heads touch. The sweep then looks for a
## crossing along a path the head did not take, and a genuine crossing can fall
## outside it entirely.
var _previous_shape_xforms: Array[Transform2D] = []
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
var _step_shape_xforms: Array[Transform2D] = []
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
	_turn_ready = false

# --- The turn ----------------------------------------------------------------

## Issue #48. Everything above sweeps the head's *body*, and the body only
## translates: it is rotation-locked, and the facing lives on the circles,
## which `Player._update_weapon_visual` re-places around the anchor once a
## tick. That re-placement is a teleport. Nothing in the engine sees it as
## motion -- not the solver, which only finds the circles already wherever
## they were put, not continuous detection, which works from the body's
## velocity, and not `_find_world_contact`, which casts a translation.
##
## While every head was compact that was a few pixels a tick and harmless.
## The sword's blade (since #45) lies along the haft and reaches 56 px past
## the anchor, and at its 24 rad/s drive the facing turns 0.4 rad a tick, so
## its tip circles -- 3.9 px across -- were teleported about 22 px a tick
## through a 24 px slab. Put past the slab's middle, a circle is pushed out
## of the far side by the solver, which is the "clips thru platforms" the
## owner saw: measured, 50 of 720 slam variants over the arena's thin slab
## left the sword's tip under it, and every one was one of the blade's last
## three circles.
##
## `guard_turn` is called by `Player` right after the circles are turned and
## before the step runs. It traces each circle's *centre* along the arc the
## turn carried it through, and if a centre would have entered terrain, it
## moves the head back along that circle's path until the centre sits just
## outside the surface. A circle whose centre is outside terrain can overlap
## it by at most its own radius, which on the roster is under half of the
## thinnest slab, so the solver then resolves it out of the side it came in
## -- the same outcome as the head having hit the surface, from a correction
## that is never larger than the tip's own travel.
##
## The centre, not the whole circle, because a blade pressed on a platform
## starts the next turn already touching it, and a whole-circle cast ignores
## whatever it starts out touching. The centre is still a radius clear of the
## surface, so the next turn is guarded as well as the first -- which is what
## keeps a blade the player keeps driving into the floor on top of it.
##
## Terrain only, not other players' bodies. A body is a 48 px disc that no
## one tick of turn crosses the middle of, and a head meeting a body is a
## strike, which `Player` scores from the contact the solver reports. Guarding
## it here would move where strikes land for no tunnelling it closes.
##
## **A one-sided head's flip is not guarded this way; it is held.** When the
## axe changes sides its bit jumps across the haft, every circle by twice its
## own distance from it, and moving the head back far enough to stop the bit
## that meets a slab first jams the circles nearer the haft into that slab.
## Measured: the axe standing on the slab with its bit hooked under the end
## and swung over, which the move above put straight through. So `Player`
## guards the turn on the side the head already has, then asks
## `turn_is_clear` about the flip and simply keeps that side while the bit
## would cross terrain to change it. Nothing is lost: which side the bit is on
## is presentation (see `Player._update_head_mirror`), and it changes as soon
## as the way is clear.
##
## A flip is a jump across the haft, not a swing, so it is traced as the
## straight line each circle jumps along, not as an arc about the anchor. The
## arc would run out along the haft, which with the axe pointed at the floor
## is into the floor, and would hold a flip that crosses nothing.

## Most of a turn one straight ray stands in for. The circle actually moves
## along an arc about the anchor; tracing it as chords of at most this angle
## keeps the chord within 0.5 px of the arc for the sword's furthest circle.
const TURN_ARC_STEP: float = 0.25
## How far short of the surface a guarded centre is left, along its own path,
## so that the next trace starts outside the terrain rather than on it.
const TURN_SEAT_BACKOFF: float = 0.5
## Colliders a single trace steps past before giving up: other players'
## bodies share the terrain layer and are not what this guards against.
const TURN_MAX_SKIPS: int = 4

## Whether the circles have been turned from a facing this head actually held.
## The first turn after the rig is built is from the circles' authored,
## unturned offsets, which is not a pose the head was ever in.
var _turn_ready: bool = false

## See the block comment above. `previous_offsets` is where each circle of
## `sweep_shapes` sat relative to the anchor before this tick's turn; the
## circles themselves already hold the new facing.
func guard_turn(previous_offsets: PackedVector2Array) -> void:
	if not _turn_ready:
		_turn_ready = true
		return
	var now := PackedVector2Array()
	for node: CollisionShape2D in sweep_shapes:
		now.append(node.position if node != null else Vector2.ZERO)
	var hit: Dictionary = _first_turn_contact(previous_offsets, now, true)
	if hit.is_empty():
		return
	global_position = hit["anchor"] + hit["shift"]
	# The anchor's own velocity into the surface is taken out, as for a world
	# contact; the turn itself is the haft's and is resisted through the
	# groove joint once the circle is resting on the surface.
	var normal: Vector2 = hit["normal"]
	var into: float = linear_velocity.dot(normal)
	if into < 0.0:
		linear_velocity -= normal * into

## Whether jumping the circles straight from `from_offsets` to `to_offsets`
## would carry no circle's centre into terrain. Asked by `Player` before a
## flip (see the block comment above).
func turn_is_clear(from_offsets: PackedVector2Array, to_offsets: PackedVector2Array) -> bool:
	if not _turn_ready:
		return true
	return _first_turn_contact(from_offsets, to_offsets, false).is_empty()

## The earliest point in a re-placement of the circles at which a centre
## enters terrain: `{anchor, shift, normal}`, where `shift` moves the head to
## leave that centre just short of the surface, or empty. With `along_arc`,
## each circle is traced along the arc about the anchor from where it was to
## where it is going, in chords of at most TURN_ARC_STEP (a circle whose
## distance from the anchor changed is traced straight). Without it, every
## circle is traced straight: a flip.
func _first_turn_contact(from_offsets: PackedVector2Array, to_offsets: PackedVector2Array,
		along_arc: bool) -> Dictionary:
	if from_offsets.size() != sweep_shapes.size() or to_offsets.size() != sweep_shapes.size():
		return {}
	if not is_inside_tree():
		return {}
	var anchor: Vector2 = PhysicsServer2D.body_get_state(
		get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM).origin
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.new()
	query.collision_mask = sweep_mask
	query.collide_with_areas = false
	query.hit_from_inside = false

	var soonest: float = INF
	var shift: Vector2 = Vector2.ZERO
	var normal: Vector2 = Vector2.ZERO
	for i in sweep_shapes.size():
		var from_offset: Vector2 = from_offsets[i]
		var to_offset: Vector2 = to_offsets[i]
		if from_offset.is_equal_approx(to_offset):
			continue
		var turn: float = 0.0
		var steps: int = 1
		if along_arc and absf(from_offset.length() - to_offset.length()) < 0.01:
			turn = from_offset.angle_to(to_offset)
			steps = maxi(1, ceili(absf(turn) / TURN_ARC_STEP))
		var previous: Vector2 = anchor + from_offset
		for step in steps:
			var next: Vector2 = anchor + to_offset
			if step < steps - 1:
				next = anchor + from_offset.rotated(turn * float(step + 1) / float(steps))
			var hit: Dictionary = _trace_terrain(space, query, previous, next)
			if not hit.is_empty():
				var chord: Vector2 = next - previous
				var reached: float = (Vector2(hit["position"]) - previous).length()
				var fraction: float = (float(step) + reached / chord.length()) / float(steps)
				if fraction < soonest:
					soonest = fraction
					var seat: Vector2 = Vector2(hit["position"]) \
						- chord.normalized() * minf(TURN_SEAT_BACKOFF, reached)
					shift = seat - (anchor + to_offset)
					normal = hit["normal"]
				break
			previous = next
	if soonest == INF:
		return {}
	return {"anchor": anchor, "shift": shift, "normal": normal}


## The first thing on `sweep_mask` the straight line `from` -> `to` enters, or
## empty: what the world sweep asks of a circle's centre. Unlike
## `_trace_terrain` it counts players' bodies, as the world sweep always has.
func _trace_centre(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, to, sweep_mask, sweep_exclude)
	query.collide_with_areas = false
	query.hit_from_inside = false
	return space.intersect_ray(query)

## The first terrain the straight line `from` -> `to` enters, or empty. Steps
## past other players' bodies, which share the layer (see the block comment).
func _trace_terrain(
		space: PhysicsDirectSpaceState2D,
		query: PhysicsRayQueryParameters2D,
		from: Vector2,
		to: Vector2) -> Dictionary:
	var exclude: Array[RID] = sweep_exclude.duplicate()
	query.from = from
	query.to = to
	for _i in TURN_MAX_SKIPS:
		query.exclude = exclude
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return {}
		if hit["collider"] is RigidBody2D:
			exclude.append(hit["rid"])
			continue
		return hit
	return {}

## The shortest step worth sweeping: the head's own narrowest width, or
## SWEEP_GATE_FLOOR where that is larger.
##
## Below that width, a step cannot have carried the head deeper into something
## than the head is wide, so the end-of-step contact check sees the overlap
## and pushes it out of the side it came in. Above it, the head can finish a
## step past the middle of thin geometry, and the shortest way out is then
## through the far side -- which is the failure this class exists for. The
## arena's thinnest platform is 24 px, above every head the rig carries:
## measured on the roster as it stands, narrowest widths run from the dagger's
## 3.84 px to the axe's 19.29 px, with the pickaxe at 15.36, the sword at 6.66
## and the staff at 5.86.
##
## This gate is load-bearing in the other direction too. Sweeping on every
## step instead cost a plant its settle: landing on another player was
## measured bouncing the head 4-11 px a tick for a while, and correcting each
## of those turned an ordinary settle into a limit cycle the player never came
## to rest out of. Small overlaps are the solver's, and it resolves them
## correctly. That 4-11 px is what one plant was measured doing, not a bound
## on anything: no head width and no forward extent is constrained anywhere in
## this project, and no scenario checks either.
##
## For a cluster it is the **whole head's** narrowest width, not its smallest
## circle's. The head is one rigid body: a step shorter than the cluster is
## wide cannot have left the cluster past the middle of anything, whichever
## circle is deepest, because the rest of the cluster is still on the side it
## came in from and the solver pushes the body out that way. Gating on the
## smallest circle instead would fire the sweep on steps the solver settles
## perfectly well -- the pickaxe's horn circles are 7.4 px across, well inside
## the range that plant was measured bouncing through -- and buy back the
## limit cycle.
##
## That argument is about the cluster's width, though, and not about the
## number this function returns. Where SWEEP_GATE_FLOOR is the larger of the
## two it is the floor that gates, and over the difference the invariant does
## not hold: the head sweeps a hair later than its own geometry would ask. On
## the roster as it stands the dagger is that case, 3.84 px wide and gated at
## 4.00. See SWEEP_GATE_FLOOR for why the trade is taken.
##
## Being a single circle settles nothing about the width either way: the staff
## is a single circle and measures 5.86 px. (The 16 px this comment used to
## quote was the diameter of the 8 px nub every weapon carried before
## ADR-0010, not something that followed from having one circle.)
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
	# At most one correction a tick, and it is whichever contact came *first*
	# in the step: the world (terrain, other bodies) or another head.
	#
	# Not "the world first, heads only if the world found nothing", which is
	# what this used to do (issue #27). The world sweep's mask deliberately
	# leaves heads out, so a fast head that crossed a blocking head and then
	# reached the blocker's body -- or anything else -- later in the same step
	# was stopped at that later contact, on the far side of the head it had
	# already gone through, and the head check never ran. A blocking head sits
	# right in front of its own body, so that was the common case, and it is
	# why the tunnelling only showed at the highest charge speeds. Both sweeps
	# measure the same step as a fraction of it, so the earlier one is simply
	# the smaller fraction.
	#
	# **Except that a world contact changes the step the head check measured
	# (issue #38).** The head sweep assumes this head travelled its whole
	# step, but a world contact stops it partway and holds it there -- while
	# the other head keeps going. So a pair that the full-step sweep saw meet
	# *after* the world contact, and so rightly deferred to it, can still end
	# the step with the other head straight through this one: this head is
	# seated back at the world contact, and the other runs on through the
	# place it now holds. Measured on the dagger's 45 deg charge at 1800 px/s:
	# the attacker's head touched the blocker's body 0.7% of the way into the
	# step, the heads would have met at 14.8%, the attacker was seated at
	# 0.7%, and the blocker's head -- which sits almost on its own body and
	# passes through it freely -- went 29 px on and out the far side of the
	# attacker's. Nothing ever caught it, because the one correction the tick
	# had was spent. Which charge lands that close to a body is set by
	# sub-pixel timing, which is why it came and went with test history and
	# platform. So after a world contact the pair is asked again, over the
	# rest of the step, with this head held where the world stopped it.
	if _has_previous:
		var world: Dictionary = _find_world_contact(state)
		var head: Dictionary = _find_head_crossing()
		if not head.is_empty() and (world.is_empty() or head["fraction"] <= world["fraction"]):
			_apply_head_crossing(state, head)
		elif not world.is_empty():
			# Applied first, and kept: the head did reach the world, and a
			# strike on a body is recorded here or nowhere (see `swept_into`).
			# The head correction then only re-seats it against the head that
			# arrived on it afterwards.
			_apply_world_contact(state, world)
			var onto: Dictionary = _find_head_crossing(world["fraction"])
			if not onto.is_empty():
				_apply_head_crossing(state, onto)
	_previous_position = state.transform.origin
	_previous_rotation = state.transform.get_rotation()
	_previous_shape_xforms.clear()
	for node: CollisionShape2D in sweep_shapes:
		_previous_shape_xforms.append(node.transform)
	_has_previous = true

## Whether the step carried the head through something in the world, and if
## so where it first touched: `{fraction, contact, normal, collider}`, or
## empty. Finds only; `_apply_world_contact` moves the head, so the caller can
## weigh this against a head crossing earlier in the same step.
func _find_world_contact(state: PhysicsDirectBodyState2D) -> Dictionary:
	if sweep_shapes.is_empty():
		return {}

	var motion: Vector2 = state.transform.origin - _previous_position
	var distance: float = motion.length()
	if distance < _sweep_gate():
		return {}

	# Each circle is swept where it actually sits, not at the body's origin:
	# the body is rotation-locked, so the cluster carries its facing on the
	# shape nodes rather than on the body. Those offsets are constant across a
	# pure translation, so a safe fraction found for a circle is the same safe
	# fraction for the body's origin -- which is what lets the earliest of
	# them stand for the whole head.
	#
	# The *live* offsets, deliberately, and not the step-start snapshot that
	# `_find_head_crossing` uses. Neither is exact for a head that swung
	# during the step, because `cast_motion` translates and cannot rotate, so
	# the choice is which end of the step to get right. Here it is the end:
	# the question this asks is whether the step carried the head past
	# something, and casting from the live offsets lands on the pose the head
	# actually holds now, which is the pose the answer reseats it from.
	# Casting from the snapshot instead ends on a pose the head never reached
	# and stops swings short of targets they did in fact reach -- measured, it
	# cost `head_strike_damage_scales` its 0.90 rad swing outright.
	#
	# The pair sweep is the other way round for the opposite reason: there the
	# question is where two heads first *met*, so the start is what has to be
	# right. See `_previous_shape_xforms`.
	var start := Transform2D(_previous_rotation, _previous_position)
	var params := PhysicsShapeQueryParameters2D.new()
	params.motion = motion
	params.collision_mask = sweep_mask
	params.exclude = sweep_exclude
	params.margin = 0.0

	var space: PhysicsDirectSpaceState2D = state.get_space_state()
	var safe: float = 1.0
	var stopped_by: CollisionShape2D = null
	var centre_hit: Dictionary = {}
	for node: CollisionShape2D in sweep_shapes:
		if node == null or node.shape == null:
			continue
		params.shape = node.shape
		params.transform = start * node.transform
		var fractions: PackedFloat32Array = space.cast_motion(params)
		if fractions.size() < 2:
			continue
		# 1.0 means this circle's path was clear -- or that it began the step
		# already touching whatever is there: `cast_motion` ignores anything
		# a shape starts out overlapping. That is how a head skimming along a
		# surface or pressed on it is left to the solver, which is right for
		# those: snapping it back to where it started would pin it to that
		# surface, which would cost the moveset far more than the tunnelling
		# does. 0.0 means it could not move at all, and is the solver's too.
		if fractions[0] > 0.0 and fractions[0] < safe:
			safe = fractions[0]
			stopped_by = node
			centre_hit = {}
		# **But a head that began the step touching can still be carried
		# through (issue #48).** A head resting on a slab is still pulled by
		# the joints, and measured on the staff's slam, one step dragged a
		# head that began it resting on the arena's thin slab 40 px down and
		# out of the far side, where the cast above saw nothing at all. The
		# circle's centre is a radius clear of the surface even while the
		# circle rests on it, so its path is asked as well. Skimming and
		# pressing leave the centre outside and pass untouched; only a centre
		# carried into the terrain is stopped, and it is stopped at the
		# surface, from where the solver pushes the circle back out of the
		# side it came in. For a circle that began clear, the cast above has
		# already found the same surface earlier, so this changes nothing.
		var origin: Vector2 = params.transform.origin
		var hit: Dictionary = _trace_centre(space, origin, origin + motion)
		if not hit.is_empty():
			var reached: float = maxf(0.0,
				(Vector2(hit["position"]) - origin).length() - TURN_SEAT_BACKOFF)
			if reached / distance < safe:
				safe = reached / distance
				stopped_by = node
				centre_hit = hit
	if stopped_by == null:
		return {}
	if not centre_hit.is_empty():
		var along: Vector2 = motion / distance
		return {
			"fraction": safe,
			"contact": _previous_position + motion * safe,
			"normal": _surface_normal(centre_hit, along),
			"collider": centre_hit["collider"],
		}

	var contact: Vector2 = _previous_position + motion * safe
	var travel: Vector2 = motion / distance
	params.shape = stopped_by.shape
	params.transform = start * stopped_by.transform
	var rest: Dictionary = _contact_rest_info(space, params, contact, travel)
	return {
		"fraction": safe,
		"contact": contact,
		"normal": _surface_normal(rest, travel),
		"collider": instance_from_id(rest["collider_id"]) if rest.has("collider_id") else null,
	}

## Seat the head where the world sweep found it first touched, and take out
## the part of its velocity heading into the surface.
func _apply_world_contact(state: PhysicsDirectBodyState2D, hit: Dictionary) -> void:
	state.transform = Transform2D(state.transform.get_rotation(), hit["contact"])
	var normal: Vector2 = hit["normal"]
	var into: float = state.linear_velocity.dot(normal)
	if into < 0.0:
		state.linear_velocity -= normal * into
		swept_into = hit["collider"]
		swept_speed = -into
		struck_world.emit(hit["collider"], -into, Vector2(hit["contact"]))

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
	_step_rotation = _previous_rotation
	_step_velocity = velocity
	_step_shape_xforms = _previous_shape_xforms.duplicate()
	# A weapon swapped mid-step leaves a snapshot that no longer describes the
	# cluster now on the head. Nothing to sweep from, so the step is skipped
	# rather than swept against the wrong shapes; the next one is whole.
	_step_usable = _has_previous and _step_shape_xforms.size() == sweep_shapes.size()

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
		"shapes": _step_shape_xforms,
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
##
## Finds only, returning `{fraction, origin, normal, partner_velocity}` or
## empty; `_apply_head_crossing` moves the head. The caller weighs it against
## a world contact earlier in the same step (issue #27).
##
## `held_from`, when given, is the fraction of the step at which a world
## contact stopped this head (issue #38). Only the rest of the step is swept
## then, with this head standing still at the point it was stopped and the
## other head carrying on along its own path -- which is what actually
## happened, and not what the full-step sweep assumed. The fraction returned
## is still a fraction of the whole step.
func _find_head_crossing(held_from: float = -1.0) -> Dictionary:
	if sweep_shapes.is_empty() or not _step_usable:
		return {}
	var tree: SceneTree = get_tree()
	if tree == null or is_queued_for_deletion():
		return {}

	var my_from: Vector2 = _step_from
	var my_motion: Vector2 = _step_to - _step_from
	var window: float = 0.0
	if held_from >= 0.0:
		window = held_from
		my_from = _step_from + my_motion * held_from
		my_motion = Vector2.ZERO
	var mine := Transform2D(_step_rotation, my_from)

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

		var their_start: Vector2 = theirs["from"]
		var their_step: Vector2 = Vector2(theirs["to"]) - their_start
		var their_from: Vector2 = their_start + their_step * window
		var their_motion: Vector2 = their_step * (1.0 - window)
		var closed: float = (my_motion - their_motion).length()
		if closed <= 0.0:
			continue
		# Nowhere near each other at any point in the step: no pair of circles
		# can have met, and saying so from the two heads' own reach costs one
		# test instead of a pass over the whole of both clusters.
		if _closest_approach(my_from - their_from, my_motion - their_motion) \
				> _head_reach() + other._head_reach():
			continue
		var theirs_at_start := Transform2D(theirs["rotation"], their_from)

		var met: Dictionary = _first_circle_contact(
			mine, my_motion, _step_shape_xforms,
			their_shapes, theirs_at_start, their_motion, theirs["shapes"])
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
		offset = (my_from + my_motion * fraction) - (their_from + their_motion * fraction)
		partner_origin = theirs["to"]
		partner_velocity = theirs["velocity"]

	# Three separate ways there is nothing to do, and with clustered heads no
	# one of them implies the others:
	#
	#   * `soonest > 1.0` -- no pair of circles met inside the step at all.
	#   * a zero `normal` -- nothing to take the closing speed out along, so
	#     the velocity correction below would be a no-op at best and the
	#     contact was not resolvable anyway.
	#   * a zero `offset` -- the two heads' *anchors* coincided at the contact
	#     fraction. Seating this head at `partner_origin + offset` would then
	#     put its anchor exactly on the partner's and stack the two bodies,
	#     which is worse than the crossing being corrected.
	#
	# The last two used to be interchangeable and only one guard was needed:
	# when a head was a single circle centred on its anchor, the normal was
	# the line between the anchors, so it vanished exactly when the offset
	# did. Since ADR-0010 it is the line of centres between the two circles
	# that actually met (see `_first_circle_contact`), and those sit off their
	# heads' anchors -- so two anchors can coincide while the circles meeting
	# off to one side hand back a perfectly good non-zero normal. Both
	# conditions are load-bearing now.
	if soonest > 1.0 or normal.length_squared() == 0.0 or offset.length_squared() == 0.0:
		return {}
	return {
		"fraction": window + soonest * (1.0 - window),
		"origin": partner_origin + offset,
		"normal": normal,
		"partner_velocity": partner_velocity,
	}

## Seat the head back where it first met the other head, carried to wherever
## that head actually ended the step, and take out the closing speed between
## the two.
func _apply_head_crossing(state: PhysicsDirectBodyState2D, hit: Dictionary) -> void:
	state.transform = Transform2D(state.transform.get_rotation(), hit["origin"])
	# The other head is moving too, so what is taken out is the part of the
	# closing speed *between the two of them* -- a head being carried along by
	# the head it is braced against is not still driving into it. Deliberately
	# not recorded in `swept_into`: this is a block, not a strike.
	var normal: Vector2 = hit["normal"]
	var closing: float = (state.linear_velocity - Vector2(hit["partner_velocity"])).dot(normal)
	if closing < 0.0:
		state.linear_velocity -= normal * closing
		clashed.emit(-closing, Vector2(hit["origin"]))

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
		my_locals: Array[Transform2D],
		their_shapes: Array[CollisionShape2D],
		theirs: Transform2D,
		their_motion: Vector2,
		their_locals: Array[Transform2D]) -> Dictionary:
	# Both callers gate on their snapshot matching their cluster, so a
	# mismatched length here is a head whose weapon changed between the two
	# checks. Sweeping it against stale offsets is worse than not sweeping it.
	if my_locals.size() != sweep_shapes.size() \
			or their_locals.size() != their_shapes.size():
		return {}
	var soonest: float = INF
	var normal: Vector2 = Vector2.ZERO
	for my_index: int in sweep_shapes.size():
		var my_node: CollisionShape2D = sweep_shapes[my_index]
		if my_node == null or my_node.shape == null:
			continue
		# The snapshot, not `my_node.transform`: see `_previous_shape_xforms`.
		var my_at_start: Transform2D = mine * my_locals[my_index]
		for their_index: int in their_shapes.size():
			var their_node: CollisionShape2D = their_shapes[their_index]
			if their_node == null or their_node.shape == null:
				continue
			var their_at_start: Transform2D = theirs * their_locals[their_index]
			# Already touching when the step began. Ordinarily that is a
			# settled clash and the solver's -- except when the step then
			# carried the two clean through each other, which the solver
			# cannot stop for circles a few pixels wide closing tens of pixels
			# a tick: it is exactly what happens the tick after a correction
			# seats this head against one whose body is still driving in
			# (issue #27). Told apart by the line of centres: a settled clash
			# jitters a fraction of a pixel and keeps its side, while a pair
			# driven through ends the step on the other side of it. That
			# counts as crossing at the very start of the step.
			if my_node.shape.collide(my_at_start, their_node.shape, their_at_start):
				var start_line: Vector2 = my_at_start.origin - their_at_start.origin
				var end_line: Vector2 = (my_at_start.origin + my_motion) - (their_at_start.origin + their_motion)
				if start_line.length_squared() > 0.0 and end_line.dot(start_line) < 0.0 and 0.0 < soonest:
					soonest = 0.0
					normal = start_line.normalized()
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
