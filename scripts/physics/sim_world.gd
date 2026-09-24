class_name SimWorld
extends RefCounted

## The universe a mission is flown in: one primary, any number of moons, and any
## number of rendezvous targets.
##
## Timekeeping
## -----------
## Time is stored as an integer tick count and converted with a multiplication:
## `t = tick * DT_BASE`. It is never accumulated, because `t += dt` drifts by a
## few ULPs per step and a 200 000-step flight would end up at a measurably
## different clock than a replay that stepped in a different pattern.
##
## DT_BASE is 1/64 s, which is exactly representable in binary floating point.
## Every permitted step size is DT_BASE times a power of two, so every step
## boundary lands on an exactly representable instant. That is what lets the
## simulation speed up over a long coast and still produce the same numbers as a
## run that crawled through at full rate — see `step_scale_for()`.

## Base tick, 1/64 s. Exactly representable; do not change this to a decimal.
const DT_BASE := 0.015625

## Largest permitted step scale, as a power of two. 2^12 * DT_BASE = 64 s.
const MAX_STEP_SCALE := 4096

## An orbit is never stepped more coarsely than this many steps per revolution.
## RK4's local error goes as (dt/T)^5, so 512 steps per orbit keeps a full
## revolution accurate to far better than a millimetre.
const MIN_STEPS_PER_ORBIT := 512.0

var primary: CelestialBody = null

## All gravitating bodies. Index 0 is always the primary.
var bodies: Array[CelestialBody] = []

## Rendezvous targets, in declaration order.
var targets: Array[OrbitTarget] = []

## Seed for any stochastic flavour (currently only cosmetic starfields). The
## simulation itself draws no random numbers at all.
var seed: int = 0


static func time_for_tick(tick: int) -> float:
	return float(tick) * DT_BASE


func add_body(b: CelestialBody) -> int:
	bodies.append(b)
	if b.is_primary() and primary == null:
		primary = b
	return bodies.size() - 1


func body_by_id(id: String) -> CelestialBody:
	for b in bodies:
		if b.id == id:
			return b
	return null


func body_index_by_id(id: String) -> int:
	for i in bodies.size():
		if bodies[i].id == id:
			return i
	return -1


func target_by_id(id: String) -> OrbitTarget:
	for tg in targets:
		if tg.id == id:
			return tg
	return null


## Which body currently owns the ship, by sphere of influence.
##
## Smaller spheres win, so a ship deep inside a moon's SOI is described by its
## orbit about the moon. The primary's SOI is infinite and is the fallback.
func dominant_body_index(t: float, px: float, py: float) -> int:
	var best := 0
	var best_soi := INF
	for i in bodies.size():
		var b := bodies[i]
		if is_inf(b.soi_radius):
			continue
		var dx := px - b.pos_x(t)
		var dy := py - b.pos_y(t)
		if DetMath.hypot(dx, dy) <= b.soi_radius and b.soi_radius < best_soi:
			best = i
			best_soi = b.soi_radius
	return best


## Altitude above a given body's surface. Negative means underground.
func altitude_above(body_index: int, t: float, px: float, py: float) -> float:
	var b := bodies[body_index]
	var dx := px - b.pos_x(t)
	var dy := py - b.pos_y(t)
	return DetMath.hypot(dx, dy) - b.radius


## Conic elements of the ship about whichever body currently owns it.
func elements_for(body_index: int, t: float, st: ShipState) -> Dictionary:
	var b := bodies[body_index]
	var rx := st.px - b.pos_x(t)
	var ry := st.py - b.pos_y(t)
	var vx := st.vx - b.vel_x(t)
	var vy := st.vy - b.vel_y(t)
	return Orbital.elements(b.mu, rx, ry, vx, vy)


## Chooses the step scale for the coming step: a power of two in [1, MAX_STEP_SCALE].
##
## This is *deterministic* adaptive stepping. An ordinary adaptive integrator
## picks its step from an error estimate, which makes the result depend on
## rounding and therefore unreproducible. Here the scale is a pure function of
## the state at the start of the step and of what the flight computer is waiting
## for, so two runs from the same state always choose the same scale — while
## still letting a long, quiet coast run hundreds of times faster than a burn.
##
## `vm_slack` is how many seconds the flight computer is certain it does not
## need to be consulted for; pass 0.0 whenever it must run every tick.
func step_scale_for(t: float, st: ShipState, ctrl: ControlInput, prof: ShipProfile, vm_slack: float) -> int:
	# Anything actively happening: full rate, no exceptions.
	if ctrl.throttle > 0.0 or st.landed or st.crashed:
		return 1
	if absf(ctrl.torque) > 0.0 or absf(st.ang_vel) > 1.0e-6:
		return 1

	var soi := dominant_body_index(t, st.px, st.py)
	var body := bodies[soi]
	var alt := altitude_above(soi, t, st.px, st.py)

	# Inside (or just above) an atmosphere the forces change quickly.
	if body.has_atmosphere() and alt < body.atmo_height * 1.25:
		return 1
	# Close to any surface, a coarse step could step straight through the ground.
	if alt < body.radius * 0.05:
		return 1

	var limit := float(MAX_STEP_SCALE)

	# Never coarser than MIN_STEPS_PER_ORBIT per revolution.
	var per := Orbital.period_of_state(
		body.mu,
		st.px - body.pos_x(t), st.py - body.pos_y(t),
		st.vx - body.vel_x(t), st.vy - body.vel_y(t)
	)
	if not is_inf(per) and per > 0.0:
		limit = minf(limit, per / (MIN_STEPS_PER_ORBIT * DT_BASE))

	# Never step past the moment the flight computer asked to be woken.
	if vm_slack < INF:
		limit = minf(limit, maxf(1.0, vm_slack / DT_BASE))

	# Never step further than a fraction of the distance to the nearest surface,
	# so that an approach cannot skip over a body.
	var closing := st.speed()
	if closing > 0.0 and alt > 0.0:
		limit = minf(limit, (alt * 0.05) / (closing * DT_BASE))

	if limit <= 1.0:
		return 1

	# Snap down to a power of two: exact step boundaries, and a scale that only
	# ever halves or doubles as conditions change.
	var scale := 1
	while scale * 2 <= MAX_STEP_SCALE and float(scale * 2) <= limit:
		scale *= 2
	return scale


func to_dict() -> Dictionary:
	var bl: Array = []
	for b in bodies:
		bl.append(b.id)
	return {"bodies": bl, "targets": targets.size(), "seed": seed}
