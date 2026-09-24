extends GutTest

## DetMath must produce bit-identical results to the Python reference, and stay
## within 1 ULP of libm.
##
## The first is the load-bearing claim: it is what makes AC1 true across
## operating systems, because the numbers come from arithmetic Godot guarantees
## rather than from whichever libm the platform shipped.

var _fixture: Dictionary
var _constants: Dictionary


func before_all() -> void:
	_fixture = FixtureLoader.load_json("det_math.json")
	assert_not_null(_fixture, "det_math.json must load")
	_constants = FixtureLoader.load_json("det_math_constants.json")
	assert_not_null(_constants, "det_math_constants.json must load")


## Returns the raw IEEE-754 bits of a double, as lowercase hex.
static func _bits(v: float) -> String:
	return PackedFloat64Array([v]).to_byte_array().hex_encode()


func test_every_constant_parses_to_the_same_bits_as_the_reference() -> void:
	# This test exists because of a real bug. The kernel coefficients were
	# written as plain decimal literals, and Godot's float parser — which is not
	# correctly rounded — landed up to 4 ULP away from Python's on three of
	# them. sin() and cos() then disagreed between the two implementations for
	# every argument above a few hundred radians, silently, while everything
	# else passed.
	#
	# The fix was to stop trusting any parser: every constant in DetMath is now
	# written as a mantissa under 2**53 over a power of two, which reads back
	# exactly in both languages. This test is what keeps it that way — including
	# if a future Godot changes how it reads decimals, which would otherwise
	# invalidate every solution file players have recorded.
	var scalars: Dictionary = _constants["scalars"]
	var checked := 0
	for name in scalars:
		var entry: Dictionary = scalars[name]
		var expected := String(entry["bits"])
		var actual := _bits(_constant(String(name)))
		assert_eq(
			actual,
			expected,
			(
				"DetMath.%s parses to different bits than the Python reference. " % name
				+ "Write it as an exact ratio, not a decimal literal."
			)
		)
		checked += 1
	assert_gt(checked, 25, "the fixture should cover every constant")

	var arrays: Dictionary = _constants["arrays"]
	for name in arrays:
		var values: Array = arrays[name]
		var actual_array: Array = _constant_array(String(name))
		assert_eq(actual_array.size(), values.size(), "%s length" % name)
		for i in mini(actual_array.size(), values.size()):
			assert_eq(
				_bits(float(actual_array[i])),
				String(values[i]["bits"]),
				"DetMath.%s[%d] parses to different bits" % [name, i]
			)


func _constant(name: String) -> float:
	match name:
		"_TWO_POW_26":
			return DetMath._TWO_POW_26
		"_TWO_POW_52":
			return DetMath._TWO_POW_52
		"PI_2":
			return DetMath.PI_2
		"PI_D":
			return DetMath.PI_D
		"TAU_D":
			return DetMath.TAU_D
		"PI_4":
			return DetMath.PI_4
		"_TWO_OVER_PI":
			return DetMath._TWO_OVER_PI
		"_PIO2_1":
			return DetMath._PIO2_1
		"_PIO2_1T":
			return DetMath._PIO2_1T
		"_PIO2_2":
			return DetMath._PIO2_2
		"_PIO2_2T":
			return DetMath._PIO2_2T
		"_REDUCE_TINY":
			return DetMath._REDUCE_TINY
		"_S1":
			return DetMath._S1
		"_S2":
			return DetMath._S2
		"_S3":
			return DetMath._S3
		"_S4":
			return DetMath._S4
		"_S5":
			return DetMath._S5
		"_S6":
			return DetMath._S6
		"_C1":
			return DetMath._C1
		"_C2":
			return DetMath._C2
		"_C3":
			return DetMath._C3
		"_C4":
			return DetMath._C4
		"_C5":
			return DetMath._C5
		"_C6":
			return DetMath._C6
		"_LN2_HI":
			return DetMath._LN2_HI
		"_LN2_LO":
			return DetMath._LN2_LO
		"_INV_LN2":
			return DetMath._INV_LN2
		"_P1":
			return DetMath._P1
		"_P2":
			return DetMath._P2
		"_P3":
			return DetMath._P3
		"_P4":
			return DetMath._P4
		"_P5":
			return DetMath._P5
		"_EXP_MAX":
			return DetMath._EXP_MAX
		"_EXP_MIN":
			return DetMath._EXP_MIN
		"_LG1":
			return DetMath._LG1
		"_LG2":
			return DetMath._LG2
		"_LG3":
			return DetMath._LG3
		"_LG4":
			return DetMath._LG4
		"_LG5":
			return DetMath._LG5
		"_LG6":
			return DetMath._LG6
		"_LG7":
			return DetMath._LG7
		"_SQRT2":
			return DetMath._SQRT2
		"_TWO_POW_66":
			return DetMath._TWO_POW_66
		"_TWO_POW_M30":
			return DetMath._TWO_POW_M30
	fail_test("unknown constant '%s' — add it to _constant()" % name)
	return NAN


func _constant_array(name: String) -> Array:
	match name:
		"_ATAN_HI":
			return DetMath._ATAN_HI
		"_ATAN_LO":
			return DetMath._ATAN_LO
		"_AT":
			return DetMath._AT
	fail_test("unknown constant array '%s'" % name)
	return []


func test_unary_kernels_match_the_reference_exactly() -> void:
	var checked := 0
	for case in _fixture["unary"]:
		var fn := String(case["fn"])
		var x := FixtureLoader.num(case["x"])
		var expected := FixtureLoader.num(case["y"])
		var got := _apply_unary(fn, x)
		assert_eq(
			got,
			expected,
			"%s(%s): GDScript and the Python reference must agree bit for bit" % [fn, case["x"]]
		)
		checked += 1
	assert_gt(checked, 100, "the fixture should cover a good spread of arguments")


func test_binary_kernels_match_the_reference_exactly() -> void:
	for case in _fixture["binary"]:
		var fn := String(case["fn"])
		var x := FixtureLoader.num(case["x"])
		var y := FixtureLoader.num(case["y"])
		var expected := FixtureLoader.num(case["r"])
		var got := 0.0
		match fn:
			"atan2":
				got = DetMath.atan2(y, x)
			"hypot":
				got = DetMath.hypot(x, y)
			"pow":
				got = DetMath.pow(x, y)
		assert_eq(got, expected, "%s(%s, %s)" % [fn, case["x"], case["y"]])


func _apply_unary(fn: String, x: float) -> float:
	match fn:
		"sin":
			return DetMath.sin(x)
		"cos":
			return DetMath.cos(x)
		"sincos_s":
			return DetMath.sincos(x)[0]
		"sincos_c":
			return DetMath.sincos(x)[1]
		"exp":
			return DetMath.exp(x)
		"log":
			return DetMath.log(x)
		"atan":
			return DetMath.atan(x)
		"acos":
			return DetMath.acos(x)
		"asin":
			return DetMath.asin(x)
		"wrap_angle":
			return DetMath.wrap_angle(x)
		"wrap_tau":
			return DetMath.wrap_tau(x)
	fail_test("unknown fixture function '%s'" % fn)
	return NAN


# --- accuracy against the engine's own libm --------------------------------
#
# Bit-identical to the reference is necessary but not sufficient: both could be
# identically wrong. These check the kernels are also *correct*, to within the
# 1 ULP the polynomial approximations promise.


func test_sin_and_cos_track_libm() -> void:
	var x := -40.0
	while x <= 40.0:
		assert_almost_eq(DetMath.sin(x), sin(x), 1.0e-15, "sin(%f)" % x)
		assert_almost_eq(DetMath.cos(x), cos(x), 1.0e-15, "cos(%f)" % x)
		x += 0.37


func test_large_argument_reduction_holds_up() -> void:
	# Cody-Waite reduction is where naive implementations lose all their digits.
	# The simulation never passes an argument this large — headings are wrapped,
	# and the largest raw argument is a moon phase of about 12 radians — but a
	# reduction that falls apart here is a reduction that is one refactor away
	# from falling apart at 12.
	for x in [1.0e4, 5.0e4, -7.7e4, 123456.789]:
		assert_almost_eq(DetMath.sin(x), sin(x), 1.0e-14, "sin(%f)" % x)
		assert_almost_eq(DetMath.cos(x), cos(x), 1.0e-14, "cos(%f)" % x)


func test_exp_and_log_track_libm() -> void:
	for x in [-30.0, -5.0, -0.5, 0.0, 0.5, 5.0, 30.0, 300.0]:
		assert_almost_eq(DetMath.exp(x), exp(x), absf(exp(x)) * 1.0e-15, "exp(%f)" % x)
	for x in [1.0e-6, 0.5, 1.0, 2.0, 1000.0, 3.6864e12]:
		assert_almost_eq(DetMath.log(x), log(x), absf(log(x)) * 1.0e-15 + 1.0e-15, "log(%f)" % x)


func test_exp_of_log_round_trips() -> void:
	for x in [1.0e-3, 1.0, 7.5, 1000.0, 1.0e9]:
		assert_almost_eq(DetMath.exp(DetMath.log(x)), x, x * 1.0e-14)


func test_atan2_quadrants() -> void:
	assert_almost_eq(DetMath.atan2(0.0, 1.0), 0.0, 1.0e-15)
	assert_almost_eq(DetMath.atan2(1.0, 0.0), DetMath.PI_2, 1.0e-15)
	assert_almost_eq(DetMath.atan2(0.0, -1.0), DetMath.PI_D, 1.0e-15)
	assert_almost_eq(DetMath.atan2(-1.0, 0.0), -DetMath.PI_2, 1.0e-15)
	assert_almost_eq(DetMath.atan2(1.0, 1.0), DetMath.PI_D / 4.0, 1.0e-15)
	assert_almost_eq(DetMath.atan2(-1.0, -1.0), -3.0 * DetMath.PI_D / 4.0, 1.0e-15)


func test_atan2_of_both_zero_is_zero_not_nan() -> void:
	# A ship at rest at the origin should not produce NaN headings.
	assert_eq(DetMath.atan2(0.0, 0.0), 0.0)


func test_wrap_angle_stays_in_range() -> void:
	var x := -20.0
	while x <= 20.0:
		var w := DetMath.wrap_angle(x)
		assert_true(
			w >= -DetMath.PI_D and w < DetMath.PI_D,
			"wrap_angle(%f) = %f must be in [-pi, pi)" % [x, w]
		)
		# Wrapping must preserve the angle modulo 2*pi.
		var diff := absf(DetMath.sin(w) - DetMath.sin(x))
		assert_lt(diff, 1.0e-12, "wrap_angle(%f) changed the angle" % x)
		x += 0.31


func test_wrap_tau_stays_in_range() -> void:
	var x := -20.0
	while x <= 20.0:
		var w := DetMath.wrap_tau(x)
		assert_true(w >= 0.0 and w < DetMath.TAU_D, "wrap_tau(%f) = %f" % [x, w])
		x += 0.31


func test_angle_delta_takes_the_short_way_round() -> void:
	assert_almost_eq(DetMath.angle_delta(0.1, 0.2), 0.1, 1.0e-15)
	# 350 degrees to 10 degrees is +20, not -340.
	var d := DetMath.angle_delta(6.1086, 0.1745)
	assert_almost_eq(d, 0.3491, 1.0e-3)


func test_hypot_does_not_overflow() -> void:
	assert_almost_eq(DetMath.hypot(3.0, 4.0), 5.0, 1.0e-15)
	# Squaring these directly would overflow to infinity.
	var big := DetMath.hypot(1.0e200, 1.0e200)
	assert_false(is_inf(big), "hypot must not overflow on large inputs")
	assert_almost_eq(big / 1.0e200, sqrt(2.0), 1.0e-12)


func test_acos_and_asin_edges() -> void:
	assert_eq(DetMath.acos(1.0), 0.0)
	assert_almost_eq(DetMath.acos(-1.0), DetMath.PI_D, 1.0e-15)
	assert_eq(DetMath.asin(1.0), DetMath.PI_2)
	assert_true(is_nan(DetMath.acos(1.5)), "acos outside [-1,1] is NAN")
	assert_true(is_nan(DetMath.asin(-2.0)), "asin outside [-1,1] is NAN")


func test_repeated_calls_are_identical() -> void:
	# Trivially true, but it is the property everything else rests on.
	for x in [0.1, 1.7, -3.3, 1000.5]:
		assert_eq(DetMath.sin(x), DetMath.sin(x))
		assert_eq(DetMath.exp(x), DetMath.exp(x))
