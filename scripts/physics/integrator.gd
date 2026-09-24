class_name Integrator
extends RefCounted

## Fixed-step RK4 for the ship's translational state, with exact closed-form
## handling of the things that change *within* a step.
##
## The engine's own physics server is never involved — see docs/DETERMINISM.md.
##
## What is held constant across a step, and what is not
## ----------------------------------------------------
## Throttle and torque are held constant (zero-order hold): the flight computer
## decides once per step, so the integrator never samples a control value that
## depends on where inside the step it happened to look.
##
## Attitude and mass are *not* held constant, because both have exact closed
## forms under constant torque and constant throttle:
##
##     angle(s) = angle0 + w0*s + alpha*s^2/2
##     mass(s)  = m0 - mdot*min(s, t_cut)
##
## Evaluating those at each RK4 stage rather than freezing them at the start of
## the step is what keeps a long burn accurate while the ship is still slewing,
## and it costs nothing in determinism because both are polynomials in `s`.
##
## Propellant exhaustion is handled the same way: `t_cut` is the exact instant
## within the step at which the tanks run dry, and thrust is zero after it. A
## burn therefore ends at the same sub-tick instant no matter what step scale
## was in force, which is what stops a fast-forwarded coast from producing a
## different final mass than a real-time one.
##
## This object carries scratch state and is deliberately *not* reentrant: create
## one per simulation, and do not share it across threads.

# --- per-step constants, set up by step() ---
var _m0: float = 0.0
var _mdot: float = 0.0
var _t_cut: float = 0.0
var _thrust: float = 0.0
var _alpha: float = 0.0
var _angle0: float = 0.0
var _w0: float = 0.0

# --- acceleration output; avoids allocating a pair on every stage ---
var _ax: float = 0.0
var _ay: float = 0.0


## Advances `st` by `scale * SimWorld.DT_BASE` seconds under `ctrl`.
##
## Mutates `st` in place. `st.tick` is advanced by `scale`, so mission time
## stays an exact integer multiple of the base tick.
func step(
	world: SimWorld, st: ShipState, ctrl: ControlInput, prof: ShipProfile, scale: int = 1
) -> void:
	if st.crashed:
		return

	var h := SimWorld.DT_BASE * float(scale)
	var t0 := SimWorld.time_for_tick(st.tick)

	_m0 = prof.dry_mass + st.fuel
	_angle0 = st.angle
	_w0 = st.ang_vel

	# Angular acceleration from the reaction wheels. Constant over the step.
	_alpha = 0.0
	if prof.inertia > 0.0 and prof.max_torque > 0.0:
		_alpha = clampf(ctrl.torque, -1.0, 1.0) * prof.max_torque / prof.inertia

	# Thrust, propellant flow, and the instant the tanks run dry.
	_thrust = prof.max_thrust * clampf(ctrl.throttle, 0.0, 1.0)
	_mdot = 0.0
	_t_cut = 0.0
	if _thrust > 0.0 and st.fuel > 0.0:
		var ve := prof.exhaust_velocity()
		if ve > 0.0:
			_mdot = _thrust / ve
			_t_cut = h if _mdot <= 0.0 else minf(h, st.fuel / _mdot)
		else:
			_thrust = 0.0
	else:
		_thrust = 0.0

	# A landed ship is pinned to the surface until it can push itself off.
	if st.landed and not _can_lift_off(world, st, prof, t0):
		_advance_attitude(st, h, scale)
		return

	var px := st.px
	var py := st.py
	var vx := st.vx
	var vy := st.vy

	var h2 := h * 0.5
	var t_half := t0 + h2
	var t_end := t0 + h

	# --- RK4 over (position, velocity) ---
	_accel(world, prof, t0, 0.0, px, py, vx, vy)
	var k1px := vx
	var k1py := vy
	var k1vx := _ax
	var k1vy := _ay

	_accel(world, prof, t_half, h2, px + h2 * k1px, py + h2 * k1py, vx + h2 * k1vx, vy + h2 * k1vy)
	var k2px := vx + h2 * k1vx
	var k2py := vy + h2 * k1vy
	var k2vx := _ax
	var k2vy := _ay

	_accel(world, prof, t_half, h2, px + h2 * k2px, py + h2 * k2py, vx + h2 * k2vx, vy + h2 * k2vy)
	var k3px := vx + h2 * k2vx
	var k3py := vy + h2 * k2vy
	var k3vx := _ax
	var k3vy := _ay

	_accel(world, prof, t_end, h, px + h * k3px, py + h * k3py, vx + h * k3vx, vy + h * k3vy)
	var k4px := vx + h * k3vx
	var k4py := vy + h * k3vy
	var k4vx := _ax
	var k4vy := _ay

	var h6 := h / 6.0
	st.px = px + h6 * (k1px + 2.0 * k2px + 2.0 * k3px + k4px)
	st.py = py + h6 * (k1py + 2.0 * k2py + 2.0 * k3py + k4py)
	st.vx = vx + h6 * (k1vx + 2.0 * k2vx + 2.0 * k3vx + k4vx)
	st.vy = vy + h6 * (k1vy + 2.0 * k2vy + 2.0 * k3vy + k4vy)

	# Propellant actually spent: exactly the burn that happened, never more than
	# what was in the tanks.
	if _mdot > 0.0:
		st.fuel = maxf(0.0, st.fuel - _mdot * _t_cut)

	_advance_attitude(st, h, scale)
	if st.landed:
		st.landed = false


## Attitude integrates exactly under constant torque, so it is not part of RK4.
func _advance_attitude(st: ShipState, h: float, scale: int) -> void:
	st.angle = DetMath.wrap_angle(st.angle + st.ang_vel * h + 0.5 * _alpha * h * h)
	st.ang_vel += _alpha * h
	st.tick += scale


## Can a ship sitting on the ground push itself off it this step?
func _can_lift_off(world: SimWorld, st: ShipState, _prof: ShipProfile, t: float) -> bool:
	if _thrust <= 0.0:
		return false
	var soi := world.dominant_body_index(t, st.px, st.py)
	var body := world.bodies[soi]
	var dx := st.px - body.pos_x(t)
	var dy := st.py - body.pos_y(t)
	var r := DetMath.hypot(dx, dy)
	if r <= 0.0:
		return false
	# Vertical component of thrust must beat local weight.
	var sc := DetMath.sincos(st.angle)
	var up_component := (sc[1] * dx + sc[0] * dy) / r
	var g := body.mu / (r * r)
	return (_thrust * up_component) > (_m0 * g)


## Total acceleration at sub-step offset `s` within the current step.
## Writes into _ax/_ay rather than returning a pair, because this runs four
## times per step for the whole flight and allocation here dominates everything
## else the simulation does.
func _accel(
	world: SimWorld,
	prof: ShipProfile,
	t: float,
	s: float,
	px: float,
	py: float,
	vx: float,
	vy: float
) -> void:
	_ax = 0.0
	_ay = 0.0

	# --- gravity from every body ---
	for i in world.bodies.size():
		var b := world.bodies[i]
		var dx := b.pos_x(t) - px
		var dy := b.pos_y(t) - py
		var r2 := dx * dx + dy * dy
		if r2 <= 0.0:
			continue
		var r := sqrt(r2)
		# Inside the body the point-mass law diverges. Clamping to the surface
		# keeps a ship that clips the ground from being flung to infinity before
		# the runner has a chance to call it a crash.
		if r < b.radius:
			r = b.radius
			r2 = r * r
		var f := b.mu / (r2 * r)
		_ax += f * dx
		_ay += f * dy

	var mass := _m0
	if _mdot > 0.0:
		mass = _m0 - _mdot * minf(s, _t_cut)
	if mass <= 0.0:
		mass = 1.0e-6

	# --- atmospheric drag ---
	for i in world.bodies.size():
		var b := world.bodies[i]
		if not b.has_atmosphere():
			continue
		var rx := px - b.pos_x(t)
		var ry := py - b.pos_y(t)
		var alt := DetMath.hypot(rx, ry) - b.radius
		if alt >= b.atmo_height:
			continue
		var rho := b.density_at_altitude(alt)
		if rho <= 0.0:
			continue
		# Velocity relative to the air, which co-rotates with the body.
		var avx := b.vel_x(t) + b.surface_vel_x(rx, ry)
		var avy := b.vel_y(t) + b.surface_vel_y(rx, ry)
		var rvx := vx - avx
		var rvy := vy - avy
		var sp := DetMath.hypot(rvx, rvy)
		if sp <= 0.0:
			continue
		var k := 0.5 * rho * prof.drag_coefficient * prof.drag_area * sp / mass
		_ax -= k * rvx
		_ay -= k * rvy

	# --- thrust ---
	if _thrust > 0.0 and _t_cut > 0.0 and s <= _t_cut:
		var ang := _angle0 + _w0 * s + 0.5 * _alpha * s * s
		var sc := DetMath.sincos(ang)
		var at := _thrust / mass
		_ax += at * sc[1]
		_ay += at * sc[0]
