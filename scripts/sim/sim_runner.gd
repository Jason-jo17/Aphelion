class_name SimRunner
extends RefCounted

## Drives one flight: flight computer, integrator, mission predicates, metrics.
##
## Order within a step
## -------------------
## 1. sample the world for the flight computer;
## 2. run the flight computer, which sets throttle and torque for the step;
## 3. choose a step size, integrate;
## 4. if a watched event happened during the step, roll back and try again with
##    a smaller one;
## 5. re-sample, record, and check whether the mission is over.
##
## Event refinement (step 4) is what lets long coasts run at 128x or more
## without losing precision. A `WAIT UNTIL TAPO < 20` parked over a half-orbit
## coast would otherwise either force full-rate stepping for twenty minutes of
## mission time, or overshoot the moment it was waiting for by a whole coarse
## step. Instead the runner takes the big step, notices the condition flipped,
## restores the state it saved, and halves until the crossing is pinned to
## within one 1/64 s tick. Rolling back is cheap because the state is a value
## object and the flight computer does not run during an integration.
##
## The same refinement catches ground contact, which is what makes a touchdown
## speed accurate enough to judge a landing by.

## Ceiling on recorded trajectory samples. Beyond this the record is decimated
## rather than grown, so a four-hour flight costs the same memory as a two-minute
## one.
const MAX_TRAJECTORY_SAMPLES := 4096

## Hard stop, whatever the mission says. A run that reaches this has gone wrong
## in a way the time limit did not catch.
const MAX_STEPS := 4_000_000

var world: SimWorld = null
var profile: ShipProfile = null
var mission: Mission = null
var state: ShipState = null
var vm: ControllerVM = null
var bus: SensorBus = null
var ctrl := ControlInput.new()
var integrator := Integrator.new()

var result: RunResult = null
var finished: bool = false

var _snapshot := ShipState.new()
var _last_throttle: float = 0.0
var _steps: int = 0
var _sample_stride: int = 1
var _sustain_slack: float = INF
var _escape_distance: float = INF


## Prepares a run. `ship_hash` identifies the assembly that produced `profile`.
func setup(mission_: Mission, world_: SimWorld, profile_: ShipProfile,
		program: Program, ship_hash: String = "", seed: int = 0) -> void:
	mission = mission_
	world = world_
	profile = profile_
	world.seed = seed

	state = mission.initial_state(world, profile)
	vm = ControllerVM.new(program)
	bus = SensorBus.new(world, profile)
	bus.target_index = mission.active_target_index(world)

	mission.reset_predicates()

	result = RunResult.new()
	result.mission_id = mission.id
	result.seed = seed
	result.ship_hash = ship_hash
	result.program_hash = program.content_hash() if program != null else ""
	result.mission_hash = mission_hash()
	result.instruction_count = program.instruction_count() if program != null else 0

	finished = false
	_steps = 0
	_sample_stride = 1
	_last_throttle = 0.0
	ctrl.clear()

	# Never fast-forward past a quarter of the tightest "hold this" window, so
	# a sustained objective cannot be satisfied by one enormous step.
	var ms := mission.min_sustain_seconds()
	_sustain_slack = INF if is_inf(ms) else maxf(SimWorld.DT_BASE, ms * 0.25)

	# Far enough out that the mission is plainly over.
	_escape_distance = world.primary.radius * 100.0
	for b in world.bodies:
		if b.orbit_radius > 0.0:
			_escape_distance = maxf(_escape_distance, b.orbit_radius * 5.0)

	if program != null and not program.ok():
		_fail("The program did not assemble.", program.first_error_text())

	_record_sample(true)


## Advances one step. Returns false once the run is over.
func step() -> bool:
	if finished:
		return false

	# --- 1 & 2: the flight computer decides this step's controls ---
	bus.begin_tick(state, _last_throttle)
	vm.tick(bus, state, profile, ctrl, SimWorld.DT_BASE)

	# --- 3: choose a step size and integrate ---
	var t := SimWorld.time_for_tick(state.tick)
	var slack := minf(vm.vm_slack(state.tick), _sustain_slack)
	var scale := world.step_scale_for(t, state, ctrl, profile, slack)

	_snapshot.copy_from(state)
	integrator.step(world, state, ctrl, profile, scale)

	# --- 4: refine if something we are watching happened mid-step ---
	while scale > 1 and _event_fired():
		state.copy_from(_snapshot)
		@warning_ignore("integer_division")
		scale = scale / 2
		integrator.step(world, state, ctrl, profile, scale)

	var dt := SimWorld.DT_BASE * float(scale)
	_steps += 1
	_last_throttle = ctrl.throttle

	# --- 5: look at where we ended up ---
	bus.begin_tick(state, ctrl.throttle)
	_observe()
	_record_sample(false)
	_check_surface()
	_check_limits()
	if not finished:
		_check_mission(dt)
	if _steps >= MAX_STEPS and not finished:
		_fail("The flight ran too long to finish.",
			"This usually means the program never reached a HALT and the ship "
			+ "never reached the objective.")
	return not finished


## Runs to completion. `step_limit` guards against a mission with no time limit.
func run(step_limit: int = MAX_STEPS) -> RunResult:
	var n := 0
	while not finished and n < step_limit:
		step()
		n += 1
	if not finished:
		_fail("The flight was cut short.", "Step limit reached.")
	return result


## Has an event we are watching for happened during the step just taken?
## Must not mutate anything the run depends on.
func _event_fired() -> bool:
	bus.begin_tick(state, ctrl.throttle)
	if vm.has_watched_condition() and vm.watched_condition_holds(bus):
		return true
	if bus.altitude() <= 0.0:
		return true
	return false


# --- outcomes --------------------------------------------------------------


func _check_surface() -> void:
	if finished or state.crashed or state.landed:
		return
	if bus.altitude() > 0.0:
		return

	var body := bus.body()
	var t := SimWorld.time_for_tick(state.tick)
	var rx := state.px - body.pos_x(t)
	var ry := state.py - body.pos_y(t)
	var r := DetMath.hypot(rx, ry)
	if r <= 0.0:
		r = body.radius

	# Speed relative to the ground, which is moving with the body.
	var gvx := body.vel_x(t) + body.surface_vel_x(rx, ry)
	var gvy := body.vel_y(t) + body.surface_vel_y(rx, ry)
	var impact := DetMath.hypot(state.vx - gvx, state.vy - gvy)
	result.touchdown_speed = impact

	# Legs only help if they are pointing down. Forty-five degrees is generous,
	# but landing sideways at speed is still landing sideways at speed.
	var sc := DetMath.sincos(state.angle)
	var upright := (sc[1] * rx + sc[0] * ry) / r   # cos of the angle from vertical

	var gear := profile.max_landing_speed
	if gear > 0.0 and impact <= gear and upright >= 0.7071:
		state.landed = true
		# Settle exactly onto the surface, moving with it.
		var k := body.radius / r
		state.px = body.pos_x(t) + rx * k
		state.py = body.pos_y(t) + ry * k
		state.vx = gvx
		state.vy = gvy
		state.ang_vel = 0.0
		bus.begin_tick(state, ctrl.throttle)
		return

	state.crashed = true
	var why := "Touchdown at %s." % Fmt.speed(impact)
	if gear <= 0.0:
		why = "%s This ship has no landing legs, so any contact is fatal." % why
	elif impact > gear:
		why = "%s The legs are rated for %s." % [why, Fmt.speed(gear)]
	else:
		why = "%s The ship was not upright." % why
	_fail("Destroyed on contact with %s." % body.display_name, why)


func _check_limits() -> void:
	if finished:
		return
	if vm.status == ControllerVM.Status.FAULTED:
		_fail(vm.fault_message, vm.fault_hint)
		return
	var elapsed := SimWorld.time_for_tick(state.tick)
	if elapsed > mission.time_limit:
		_fail("Out of time.",
			"The mission window is %s and the flight is still going."
			% Fmt.duration(mission.time_limit))
		return
	if DetMath.hypot(state.px, state.py) > _escape_distance:
		_fail("Lost.", "The ship is %s from %s and is not coming back."
			% [Fmt.distance(DetMath.hypot(state.px, state.py)), world.primary.display_name])


func _check_mission(dt: float) -> void:
	for f in mission.failures:
		if f["predicate"].check(bus, state, vm, dt):
			_fail(String(f["message"]), "")
			return
	if mission.success != null and mission.success.check(bus, state, vm, dt):
		_succeed()


func _succeed() -> void:
	_finalise()
	result.success = true
	result.outcome = "Objective complete."
	result.outcome_detail = ""
	Scoring.apply(mission, result)
	finished = true


func _fail(outcome: String, detail: String) -> void:
	if finished:
		return
	_finalise()
	result.success = false
	result.outcome = outcome
	result.outcome_detail = detail
	Scoring.apply(mission, result)
	finished = true


func _finalise() -> void:
	result.ticks = state.tick
	result.elapsed = SimWorld.time_for_tick(state.tick)
	result.fuel_remaining = state.fuel
	result.fuel_used = maxf(0.0, profile.fuel_capacity * mission.start_fuel_fraction - state.fuel)
	result.delta_v_used = profile.delta_v(profile.fuel_capacity * mission.start_fuel_fraction) \
		- profile.delta_v(state.fuel)
	result.instructions_executed = vm.instructions_executed
	result.spin_ticks = vm.spin_ticks
	result.vm_ticks = vm.total_ticks
	result.vm_status = vm.status_text()
	result.fault_code = vm.fault_code
	result.fault_message = vm.fault_message
	result.fault_hint = vm.fault_hint
	result.fault_line = vm.fault_line
	result.log_entries = vm.log_entries.duplicate()
	result.state_hash = state_hash()
	_record_sample(true)


# --- observation -----------------------------------------------------------


func _observe() -> void:
	result.max_altitude = maxf(result.max_altitude, bus.altitude())
	result.max_dynamic_pressure = maxf(result.max_dynamic_pressure, bus.dynamic_pressure())


func _record_sample(force: bool) -> void:
	if not force and (_steps % _sample_stride) != 0:
		return
	result.trajectory.append_array(PackedFloat64Array([
		SimWorld.time_for_tick(state.tick),
		state.px, state.py, state.vx, state.vy,
		state.fuel, state.angle, ctrl.throttle,
	]))
	if result.sample_count() > MAX_TRAJECTORY_SAMPLES:
		_decimate()


## Halves the sample count by dropping every other sample, and doubles the
## stride so the record keeps covering the whole flight at a coarser rate.
func _decimate() -> void:
	var stride := RunResult.TRAJECTORY_STRIDE
	var kept := PackedFloat64Array()
	var n := result.sample_count()
	kept.resize(0)
	for i in range(0, n, 2):
		var o := i * stride
		kept.append_array(result.trajectory.slice(o, o + stride))
	result.trajectory = kept
	_sample_stride *= 2


## Bit-exact hash of the final state. Two runs of identical inputs must produce
## the same string; CI compares it across Windows, macOS and Linux.
func state_hash() -> String:
	var nums := PackedFloat64Array([
		state.px, state.py, state.vx, state.vy,
		state.angle, state.ang_vel, state.fuel,
	])
	var bytes := nums.to_byte_array()
	bytes.append_array(PackedInt64Array([state.tick]).to_byte_array())
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode().substr(0, 16)


## Identity of the mission's rules, so a recorded run can prove it was scored
## against the same mission file.
func mission_hash() -> String:
	var parts := PackedStringArray([
		mission.id,
		str(mission.star_fuel), str(mission.star_time), str(mission.star_instructions),
		mission.success.describe() if mission.success != null else "",
		str(mission.time_limit),
	])
	return String("|").join(parts).sha256_text().substr(0, 16)
