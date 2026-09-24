extends GutTest

## The integrator: conservation, accuracy, and byte-for-byte reproducibility.

const MU := 3.6864e12
const R := 640000.0

var _world: SimWorld
var _profile: ShipProfile
var _integrator: Integrator


func before_each() -> void:
	_world = _build_world()
	_profile = ShipProfile.new()
	_profile.dry_mass = 1300.0
	_profile.fuel_capacity = 0.0
	_profile.max_thrust = 0.0
	_profile.isp = 290.0
	_profile.inertia = 8000.0
	_profile.drag_area = 1.0
	_integrator = Integrator.new()


func _build_world(with_atmosphere: bool = false) -> SimWorld:
	var w := SimWorld.new()
	var b := CelestialBody.new()
	b.id = "halcyon"
	b.display_name = "Halcyon"
	b.mu = MU
	b.radius = R
	b.rotation_rate = 0.0002908882086657216
	if with_atmosphere:
		b.atmo_height = 70000.0
		b.atmo_sea_level_density = 0.8
		b.atmo_scale_height = 6000.0
	w.add_body(b)
	return w


func _circular(altitude: float) -> ShipState:
	var s := ShipState.new()
	s.px = R + altitude
	s.py = 0.0
	s.vx = 0.0
	s.vy = Orbital.circular_speed(MU, s.px)
	return s


func _energy(s: ShipState) -> float:
	var r := DetMath.hypot(s.px, s.py)
	return 0.5 * (s.vx * s.vx + s.vy * s.vy) - MU / r


func _run(state: ShipState, ticks: int, ctrl: ControlInput, scale: int = 1) -> void:
	var n := 0
	while n < ticks:
		_integrator.step(_world, state, ctrl, _profile, scale)
		n += scale


func test_energy_is_conserved_over_ten_orbits() -> void:
	var st := _circular(100000.0)
	var e0 := _energy(st)
	var period := Orbital.period(MU, st.px)
	_run(st, int(10.0 * period / SimWorld.DT_BASE), ControlInput.new())
	var drift := absf((_energy(st) - e0) / e0)
	assert_lt(drift, 1.0e-11,
		"RK4 at 1/64 s should hold energy to far better than a part in 1e11")


func test_a_circular_orbit_stays_circular() -> void:
	var st := _circular(100000.0)
	var r0 := st.px
	var period := Orbital.period(MU, r0)
	_run(st, int(10.0 * period / SimWorld.DT_BASE), ControlInput.new())
	var el := Orbital.elements(MU, st.px, st.py, st.vx, st.vy)
	assert_lt(float(el[Orbital.K_ECC]), 1.0e-9, "eccentricity must not creep")
	assert_almost_eq(float(el[Orbital.K_APOAPSIS]), r0, 0.001,
		"apoapsis should hold to within a millimetre")


func test_identical_inputs_give_identical_bits() -> void:
	# This is AC1 in one assertion.
	var a := _circular(100000.0)
	var b := _circular(100000.0)
	_run(a, 60000, ControlInput.new())
	var integrator_b := Integrator.new()
	var n := 0
	while n < 60000:
		integrator_b.step(_world, b, ControlInput.new(), _profile, 1)
		n += 1
	assert_eq(a.px, b.px)
	assert_eq(a.py, b.py)
	assert_eq(a.vx, b.vx)
	assert_eq(a.vy, b.vy)
	assert_eq(a.tick, b.tick)


func test_time_is_derived_not_accumulated() -> void:
	# t = tick * DT_BASE must be exact for every tick, which is why DT_BASE is
	# a power of two. Accumulating would drift.
	for tick in [1, 63, 64, 1000, 123456, 10000000]:
		var t := SimWorld.time_for_tick(tick)
		assert_eq(t * 64.0, float(tick),
			"tick %d should convert to a time that is exact" % tick)


func test_step_scale_is_a_pure_function_of_state() -> void:
	var st := _circular(400000.0)
	var ctrl := ControlInput.new()
	var first := _world.step_scale_for(0.0, st, ctrl, _profile, INF)
	var second := _world.step_scale_for(0.0, st, ctrl, _profile, INF)
	assert_eq(first, second, "asking twice must give the same answer")
	assert_gt(first, 1, "a quiet vacuum coast should be allowed to fast-forward")


func test_step_scale_drops_to_one_when_anything_is_happening() -> void:
	var st := _circular(400000.0)
	var burning := ControlInput.new()
	burning.throttle = 1.0
	assert_eq(_world.step_scale_for(0.0, st, burning, _profile, INF), 1,
		"a burn must be integrated at full rate")

	var turning := ControlInput.new()
	turning.torque = 0.5
	assert_eq(_world.step_scale_for(0.0, st, turning, _profile, INF), 1,
		"so must a slew")

	var low := _circular(5000.0)
	assert_eq(_world.step_scale_for(0.0, low, ControlInput.new(), _profile, INF), 1,
		"and so must anything close to the ground")


func test_step_scale_never_outruns_the_flight_computer() -> void:
	var st := _circular(400000.0)
	var ctrl := ControlInput.new()
	# The VM says it needs to be consulted in a tenth of a second.
	var scale := _world.step_scale_for(0.0, st, ctrl, _profile, 0.1)
	assert_le(float(scale) * SimWorld.DT_BASE, 0.1 + 1.0e-12,
		"a pending WAIT must not be stepped over")


func test_fast_forwarding_agrees_with_full_rate() -> void:
	var fine := _circular(400000.0)
	var warped := _circular(400000.0)
	var ctrl := ControlInput.new()
	var period := Orbital.period(MU, fine.px)
	var ticks := int(3.0 * period / SimWorld.DT_BASE)

	_run(fine, ticks, ctrl, 1)

	var integ := Integrator.new()
	var n := 0
	while n < ticks:
		var scale: int = _world.step_scale_for(
			SimWorld.time_for_tick(warped.tick), warped, ctrl, _profile, INF)
		scale = mini(scale, ticks - n)
		var p := 1
		while p * 2 <= scale:
			p *= 2
		integ.step(_world, warped, ctrl, _profile, p)
		n += p

	var apart := DetMath.hypot(fine.px - warped.px, fine.py - warped.py)
	assert_lt(apart, 1.0,
		"three orbits of fast-forwarding should land within a metre of full rate")


func test_thrust_burns_propellant_at_the_rocket_equation_rate() -> void:
	_profile.max_thrust = 40000.0
	_profile.fuel_capacity = 1100.0
	var st := _circular(200000.0)
	st.fuel = 1100.0
	var m0 := _profile.dry_mass + st.fuel
	var v0 := st.speed()

	var ctrl := ControlInput.new()
	ctrl.throttle = 1.0
	_run(st, 640, ctrl)   # ten seconds

	var expected_flow := _profile.max_thrust / _profile.exhaust_velocity()
	assert_almost_eq(1100.0 - st.fuel, expected_flow * 10.0, 1.0e-6,
		"propellant spent must equal mass flow times burn time")

	var m1 := _profile.dry_mass + st.fuel
	var ideal := _profile.exhaust_velocity() * DetMath.log(m0 / m1)
	# Gravity and the changing direction eat into it, so the achieved speed
	# change is a little under ideal; it must not exceed it.
	assert_lt(st.speed() - v0, ideal)
	assert_gt(st.speed() - v0, ideal * 0.9)


func test_a_burn_stops_exactly_when_the_tanks_run_dry() -> void:
	_profile.max_thrust = 40000.0
	_profile.fuel_capacity = 10.0
	var st := _circular(200000.0)
	st.fuel = 10.0
	var ctrl := ControlInput.new()
	ctrl.throttle = 1.0
	# Far more ticks than there is propellant for.
	_run(st, 6400, ctrl)
	assert_eq(st.fuel, 0.0, "fuel must not go negative")


func test_burning_with_no_fuel_does_nothing() -> void:
	_profile.max_thrust = 40000.0
	var st := _circular(200000.0)
	st.fuel = 0.0
	var before := st.speed()
	var ctrl := ControlInput.new()
	ctrl.throttle = 1.0
	_run(st, 64, ctrl)
	var el := Orbital.elements(MU, st.px, st.py, st.vx, st.vy)
	assert_almost_eq(float(el[Orbital.K_ECC]), 0.0, 1.0e-9,
		"an empty ship coasts; the orbit must not change shape")


func test_attitude_integrates_exactly_under_constant_torque() -> void:
	_profile.max_torque = 4000.0
	_profile.inertia = 8000.0
	var st := _circular(200000.0)
	st.angle = 0.0
	st.ang_vel = 0.0
	var ctrl := ControlInput.new()
	ctrl.torque = 1.0

	var ticks := 64
	_run(st, ticks, ctrl)

	var alpha := _profile.max_torque / _profile.inertia
	var t := float(ticks) * SimWorld.DT_BASE
	# Integrated one tick at a time, so compare against the same recurrence
	# rather than the closed form over the whole interval.
	assert_almost_eq(st.ang_vel, alpha * t, 1.0e-12)


func test_drag_removes_energy_and_only_inside_the_atmosphere() -> void:
	_world = _build_world(true)
	_profile.drag_area = 6.0
	_profile.drag_coefficient = 0.35

	var high := _circular(200000.0)
	var e_high := _energy(high)
	_run(high, 64000, ControlInput.new())
	assert_almost_eq(_energy(high) / e_high, 1.0, 1.0e-11,
		"there is no air at 200 km, so nothing should change")

	var low := _circular(62000.0)
	var e_low := _energy(low)
	_run(low, 64000, ControlInput.new())
	assert_lt(_energy(low), e_low, "inside the atmosphere, drag must take energy out")


func test_gravity_inside_a_body_does_not_diverge() -> void:
	# A ship that clips the ground should be reported as a crash by the runner,
	# not flung to infinity by a singular point mass first.
	var st := ShipState.new()
	st.px = R * 0.5
	st.py = 0.0
	st.vx = 0.0
	st.vy = 100.0
	_run(st, 64, ControlInput.new())
	assert_false(is_nan(st.px) or is_inf(st.px), "position must stay finite")
	assert_false(is_nan(st.vx) or is_inf(st.vx), "velocity must stay finite")


func test_trajectory_fixtures_match_the_reference_exactly() -> void:
	var fixtures: Array = FixtureLoader.load_json("trajectory.json")
	var catalog := PartCatalog.shared()
	for case in fixtures:
		var world := _fixture_world()
		var ship := MissionDB.stock_ship(String(case["ship"]))
		assert_not_null(ship, "fixture ship '%s' must exist" % case["ship"])
		var profile := ship.to_profile()

		var start: Dictionary = case["start"]
		var st := ShipState.new()
		st.px = FixtureLoader.num(start["px"])
		st.py = FixtureLoader.num(start["py"])
		st.vx = FixtureLoader.num(start["vx"])
		st.vy = FixtureLoader.num(start["vy"])
		st.angle = FixtureLoader.num(start["angle"])
		st.ang_vel = FixtureLoader.num(start["ang_vel"])
		st.fuel = FixtureLoader.num(start["fuel"])

		var ctrl := ControlInput.new()
		ctrl.throttle = FixtureLoader.num(case["throttle"])
		ctrl.torque = FixtureLoader.num(case["torque"])
		var fixed_scale := int(case["scale"])

		var integ := Integrator.new()
		var samples: Array = case["samples"]
		var target_tick := int(samples[samples.size() - 1]["tick"])
		var by_tick := {}
		for s in samples:
			by_tick[int(s["tick"])] = s

		while st.tick < target_tick:
			var scale := fixed_scale
			if fixed_scale < 0:
				scale = world.step_scale_for(SimWorld.time_for_tick(st.tick), st,
					ctrl, profile, INF)
				scale = mini(scale, target_tick - st.tick)
				var p := 1
				while p * 2 <= scale:
					p *= 2
				scale = p
			integ.step(world, st, ctrl, profile, scale)
			if by_tick.has(st.tick):
				var want: Dictionary = by_tick[st.tick]
				var where := "%s @ tick %d" % [case["name"], st.tick]
				assert_eq(st.px, FixtureLoader.num(want["px"]), where + " px")
				assert_eq(st.py, FixtureLoader.num(want["py"]), where + " py")
				assert_eq(st.vx, FixtureLoader.num(want["vx"]), where + " vx")
				assert_eq(st.vy, FixtureLoader.num(want["vy"]), where + " vy")
				assert_eq(st.angle, FixtureLoader.num(want["angle"]), where + " angle")
				assert_eq(st.fuel, FixtureLoader.num(want["fuel"]), where + " fuel")


func _fixture_world() -> SimWorld:
	# The fixtures were generated against the real universe, moon included.
	var mission := MissionDB.get_mission("reaching_lyra")
	assert_not_null(mission, "reaching_lyra is needed for its two-body world")
	return MissionDB.world_for(mission)
