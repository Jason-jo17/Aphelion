extends GutTest

## Conic element maths: against the Python reference, and against closed-form
## answers that can be worked out by hand.

const MU := 3.6864e12       ## Halcyon
const R := 640000.0

var _fixture: Array


func before_all() -> void:
	_fixture = FixtureLoader.load_json("orbital.json")


func test_elements_match_the_reference_exactly() -> void:
	for case in _fixture:
		var el := Orbital.elements(
			FixtureLoader.num(case["mu"]),
			FixtureLoader.num(case["rx"]), FixtureLoader.num(case["ry"]),
			FixtureLoader.num(case["vx"]), FixtureLoader.num(case["vy"]))
		var name := String(case["name"])
		for key in ["sma", "ecc", "apoapsis", "periapsis", "period", "nu",
				"t_apo", "t_peri", "v_radial", "v_tangential"]:
			var expected := FixtureLoader.num(case[key])
			var got := float(el[_element_key(key)])
			if is_inf(expected):
				assert_true(is_inf(got) and signf(got) == signf(expected),
					"%s.%s should be %s" % [name, key, case[key]])
			else:
				assert_eq(got, expected, "%s.%s" % [name, key])


func _element_key(fixture_key: String) -> String:
	match fixture_key:
		"sma": return Orbital.K_SMA
		"ecc": return Orbital.K_ECC
		"apoapsis": return Orbital.K_APOAPSIS
		"periapsis": return Orbital.K_PERIAPSIS
		"period": return Orbital.K_PERIOD
		"nu": return Orbital.K_TRUE_ANOMALY
		"t_apo": return Orbital.K_TIME_TO_APO
		"t_peri": return Orbital.K_TIME_TO_PERI
		"v_radial": return Orbital.K_RADIAL_SPEED
		"v_tangential": return Orbital.K_TANGENTIAL_SPEED
	return fixture_key


# --- closed-form checks ----------------------------------------------------

func test_a_circular_orbit_has_zero_eccentricity() -> void:
	var r := R + 100000.0
	var v := Orbital.circular_speed(MU, r)
	var el := Orbital.elements(MU, r, 0.0, 0.0, v)
	assert_almost_eq(float(el[Orbital.K_ECC]), 0.0, 1.0e-12)
	assert_almost_eq(float(el[Orbital.K_APOAPSIS]), r, 1.0e-6)
	assert_almost_eq(float(el[Orbital.K_PERIAPSIS]), r, 1.0e-6)


func test_circular_speed_matches_vis_viva() -> void:
	var r := R + 150000.0
	assert_almost_eq(Orbital.vis_viva(MU, r, r), Orbital.circular_speed(MU, r), 1.0e-9)


func test_escape_speed_is_root_two_times_circular() -> void:
	var r := R + 100000.0
	assert_almost_eq(Orbital.escape_speed(MU, r),
		Orbital.circular_speed(MU, r) * sqrt(2.0), 1.0e-9)


func test_apsides_from_a_known_transfer() -> void:
	# Burn at 100 km to an 800 km apoapsis, and check the element maths agrees.
	var rp := R + 100000.0
	var ra := R + 800000.0
	var a := 0.5 * (rp + ra)
	var el := Orbital.elements(MU, rp, 0.0, 0.0, Orbital.vis_viva(MU, rp, a))
	assert_almost_eq(float(el[Orbital.K_APOAPSIS]), ra, 1.0e-3)
	assert_almost_eq(float(el[Orbital.K_PERIAPSIS]), rp, 1.0e-3)
	assert_almost_eq(float(el[Orbital.K_SMA]), a, 1.0e-3)


func test_time_to_apoapsis_from_periapsis_is_half_a_period() -> void:
	var rp := R + 100000.0
	var ra := R + 900000.0
	var a := 0.5 * (rp + ra)
	var el := Orbital.elements(MU, rp, 0.0, 0.0, Orbital.vis_viva(MU, rp, a))
	assert_almost_eq(float(el[Orbital.K_TIME_TO_APO]),
		float(el[Orbital.K_PERIOD]) * 0.5, 1.0e-6)


func test_hyperbolic_orbit_has_no_apoapsis_but_does_have_a_periapsis_time() -> void:
	# This is the case that used to return INF and broke every capture burn.
	var mu_moon := 6.5e10
	var el := Orbital.elements(mu_moon, -1198571.429, -1844837.806, 279.1541, 266.7656)
	assert_gt(float(el[Orbital.K_ECC]), 1.0, "this state is hyperbolic")
	assert_true(is_inf(float(el[Orbital.K_APOAPSIS])), "a hyperbola has no apoapsis")
	assert_true(is_inf(float(el[Orbital.K_TIME_TO_APO])), "nor a time to one")
	var tp := float(el[Orbital.K_TIME_TO_PERI])
	assert_false(is_inf(tp), "but it does have a periapsis, and a time to reach it")
	assert_gt(tp, 0.0)
	assert_lt(tp, 10000.0)


func test_receding_hyperbola_never_reaches_periapsis_again() -> void:
	var mu_moon := 6.5e10
	# Same orbit, but heading outward: periapsis is behind us.
	var el := Orbital.elements(mu_moon, -1198571.429, -1844837.806, -279.1541, -266.7656)
	assert_true(is_inf(float(el[Orbital.K_TIME_TO_PERI])),
		"once past periapsis on an escape trajectory it never comes round again")


func test_direction_of_travel_shows_in_angular_momentum() -> void:
	var r := R + 100000.0
	var v := Orbital.circular_speed(MU, r)
	var pro := Orbital.elements(MU, r, 0.0, 0.0, v)
	var retro := Orbital.elements(MU, r, 0.0, 0.0, -v)
	assert_gt(float(pro[Orbital.K_ANG_MOMENTUM]), 0.0)
	assert_lt(float(retro[Orbital.K_ANG_MOMENTUM]), 0.0)
	# The shape is identical either way round.
	assert_almost_eq(float(pro[Orbital.K_ECC]), float(retro[Orbital.K_ECC]), 1.0e-12)


func test_hohmann_matches_the_two_burn_arithmetic() -> void:
	var r1 := R + 150000.0
	var r2 := R + 500000.0
	var h := Orbital.hohmann(MU, r1, r2)
	var a_t := 0.5 * (r1 + r2)
	assert_almost_eq(float(h[0]),
		Orbital.vis_viva(MU, r1, a_t) - Orbital.circular_speed(MU, r1), 1.0e-9)
	assert_almost_eq(float(h[1]),
		Orbital.circular_speed(MU, r2) - Orbital.vis_viva(MU, r2, a_t), 1.0e-9)
	assert_almost_eq(float(h[2]), Orbital.period(MU, a_t) * 0.5, 1.0e-6)


func test_apsis_altitudes_go_negative_when_the_orbit_hits_the_ground() -> void:
	# A suborbital lob: periapsis is underground, and saying so is the point.
	var el := Orbital.elements(MU, R + 50000.0, 0.0, 0.0, 1500.0)
	assert_lt(Orbital.periapsis_altitude(el, R), 0.0)


func test_period_of_state_agrees_with_full_elements() -> void:
	var r := R + 300000.0
	var v := Orbital.circular_speed(MU, r) * 1.1
	var el := Orbital.elements(MU, r, 0.0, 0.0, v)
	assert_eq(Orbital.period_of_state(MU, r, 0.0, 0.0, v), float(el[Orbital.K_PERIOD]),
		"the cheap path used by the step chooser must agree with the full one")
