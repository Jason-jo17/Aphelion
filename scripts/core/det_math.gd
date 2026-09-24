class_name DetMath
extends RefCounted

## Bit-deterministic replacements for libm's transcendental functions.
##
## Why this exists
## ---------------
## Aphelion's headline promise is that the same ship + program + seed produces
## the *identical* trajectory on every machine, so that local leaderboards and
## exported solution files mean something. IEEE-754 guarantees correctly-rounded
## results for `+ - * /` and `sqrt` — those are bit-identical everywhere. It
## guarantees nothing at all for `sin`, `cos`, `exp`, `atan`, `log` or `pow`:
## each platform ships its own libm, and glibc, Apple's libm and MSVC's CRT
## disagree in the last couple of ULPs. A 1-ULP difference in the sine used for
## a thrust vector compounds over a 200 000-tick flight into a visibly different
## orbit.
##
## So the simulation never calls the engine's trig. It calls these, which are
## built exclusively from correctly-rounded primitives (`+ - * / sqrt`, exact
## comparisons and exact powers of two) and therefore produce identical bits on
## every platform Godot targets.
##
## The polynomial kernels and argument-reduction constants are the classic
## fdlibm ones (Sun Microsystems, freely redistributable), which are accurate to
## well under 1 ULP over the reduced ranges. We reuse the constants, not the C.
##
## Cost: roughly 3-6x a native libm call. The integrator makes a handful of these
## per tick, so at 50 Hz this is far from the bottleneck — see tests/unit/test_det_math.gd
## for the accuracy assertions and docs/DETERMINISM.md for the full rule set.

# --- Constants, written so that no float parser can get them wrong. ---------
# Each one is an exact 53-bit integer over an exact power of two, because
# Godot's float literal parser is not correctly rounded. Written as plain
# decimals, four of the coefficients below landed up to 4 ULP away from the
# double Python reads out of the same digits, which was enough to make sin()
# and cos() disagree between the two implementations above a few hundred
# radians. The same digits *without* a decimal point come back exact — they go
# through the int64 reader instead — and dividing by a power of two is exact in
# IEEE-754, so the folded constant carries the intended bits on every platform
# and, just as importantly, on every future Godot. That second part is what
# makes recorded solutions safe to keep: a parser change would otherwise move
# every trajectory in the game. The plain decimal in each comment is for
# reading only. tools/refsim/det_math.py carries the same table, and
# tests/unit/test_det_math.gd asserts the two agree bit for bit.

const _TWO_POW_26 := 67108864.0  # 2**26
const _TWO_POW_52 := _TWO_POW_26 * _TWO_POW_26  # 2**52

const PI_2 := 884279719003555 / _TWO_POW_26 / 8388608.0  # 1.5707963267948966 — pi/2
const PI_D := 884279719003555 / _TWO_POW_26 / 4194304.0  # 3.141592653589793 — pi
const TAU_D := 884279719003555 / _TWO_POW_26 / 2097152.0  # 6.283185307179586 — 2*pi
const PI_4 := 884279719003555 / _TWO_POW_26 / 16777216.0  # 0.7853981633974483 — pi/4

# --- Argument reduction for sin/cos: 2/pi and pi/2 split into exact parts. ---
const _TWO_OVER_PI := 5734161139222659 / _TWO_POW_52 / 2.0  # 0.6366197723675814 — 2/pi
const _PIO2_1 := 1686629713 / _TWO_POW_26 / 16.0  # 1.5707963267341256 — the first 33 bits of pi/2
const _PIO2_1T := 4701928774853425 / _TWO_POW_52 / _TWO_POW_26 / 256.0  # 6.077100506506192e-11
const _PIO2_2 := 2242054355 / _TWO_POW_52 / 8192.0  # 6.077100506303966e-11 — the next 33 bits
const _PIO2_2T := 5376105825661043 / _TWO_POW_52 / _TWO_POW_52 / 131072.0  # 2.0222662487959506e-21
const _REDUCE_TINY := 3022314549036573 / _TWO_POW_52 / _TWO_POW_26  # 1e-08

# --- sin kernel on [-pi/4, pi/4] ---
const _S1 := -6004799503160649 / _TWO_POW_52 / 8.0  # -0.16666666666666632
const _S2 := 2401919801261139 / _TWO_POW_52 / 64.0  # 0.00833333333332249
const _S3 := -7320136532976085 / _TWO_POW_52 / 8192.0  # -0.0001984126982985795
const _S4 := 6506786730409597 / _TWO_POW_52 / 524288.0  # 2.7557313707070068e-06
const _S5 := -7571127717829867 / _TWO_POW_52 / _TWO_POW_26  # -2.5050760253406863e-08
const _S6 := 1537454791456095 / _TWO_POW_52 / _TWO_POW_26 / 32.0  # 1.58969099521155e-10

# --- cos kernel on [-pi/4, pi/4] ---
const _C1 := 1501199875790163 / _TWO_POW_52 / 8.0  # 0.0416666666666666
const _C2 := -6405119470031223 / _TWO_POW_52 / 1024.0  # -0.001388888888887411
const _C3 := 457508533350745 / _TWO_POW_52 / 4096.0  # 2.480158728947673e-05
const _C4 := -5205429506036397 / _TWO_POW_52 / 4194304.0  # -2.7557314351390663e-07
const _C5 := 1261860039765105 / _TWO_POW_52 / _TWO_POW_26 / 2.0  # 2.087572321298175e-09
const _C6 := -1757820317994549 / _TWO_POW_52 / _TWO_POW_26 / 512.0  # -1.1359647557788195e-11

# --- exp kernel ---
const _LN2_HI := 2977044471 / _TWO_POW_26 / 64.0  # 0.6931471803691238
const _LN2_LO := 3691024475790907 / _TWO_POW_52 / _TWO_POW_26 / 64.0  # 1.9082149292705877e-10
const _INV_LN2 := 3248660424278399 / _TWO_POW_26 / 33554432.0  # 1.4426950408889634
const _P1 := 3002399751580319 / _TWO_POW_52 / 4.0  # 0.16666666666666602
const _P2 := -6405119469862291 / _TWO_POW_52 / 512.0  # -0.0027777777777015593
const _P3 := 1220022702274443 / _TWO_POW_52 / 4096.0  # 6.613756321437934e-05
const _P4 := -7807914560613361 / _TWO_POW_52 / 1048576.0  # -1.6533902205465252e-06
const _P5 := 390835970239053 / _TWO_POW_52 / 2097152.0  # 4.1381367970572385e-08
const _EXP_MAX := 6243314768165359 / _TWO_POW_26 / 131072.0  # 709.782712893384
const _EXP_MIN := -6554261109157969 / _TWO_POW_26 / 131072.0  # -745.1332191019411

const _ATAN_HI := [
	8352332796509007 / _TWO_POW_52 / 4.0,  # 0.4636476090008061 — atan(0.5)
	PI_4,  # 0.7853981633974483 — atan(1.0)
	8852218891597467 / _TWO_POW_52 / 2.0,  # 0.982793723247329 — atan(1.5)
	PI_2,  # 1.5707963267948966 — atan(inf)
]

const _ATAN_LO := [
	3683087214424817 / _TWO_POW_52 / _TWO_POW_52 / 8.0,  # 2.2698777452961687e-17
	4967757600021511 / _TWO_POW_52 / _TWO_POW_52 / 8.0,  # 3.061616997868383e-17
	4511882386918333 / _TWO_POW_52 / _TWO_POW_52 / 16.0,  # 1.3903311031230998e-17
	4967757600021511 / _TWO_POW_52 / _TWO_POW_52 / 4.0,  # 6.123233995736766e-17
]

const _AT := [
	6004799503160589 / _TWO_POW_52 / 4.0,  # 0.3333333333333293
	-1801439850937073 / _TWO_POW_52 / 2.0,  # -0.19999999999876483
	5146970997949439 / _TWO_POW_52 / 8.0,  # 0.14285714272503466
	-8006398829074033 / _TWO_POW_52 / 16.0,  # -0.11111110405462356
	3275337272528951 / _TWO_POW_52 / 8.0,  # 0.09090887133436507
	-5542580929731181 / _TWO_POW_52 / 16.0,  # -0.0769187620504483
	4799809039908177 / _TWO_POW_52 / 16.0,  # 0.06661073137387531
	-4203530284924621 / _TWO_POW_52 / 16.0,  # -0.058335701337905735
	7172437082246635 / _TWO_POW_52 / 32.0,  # 0.049768779946159324
	-5264754476739631 / _TWO_POW_52 / 32.0,  # -0.036531572744216916
	4694068057790993 / _TWO_POW_52 / 64.0,  # 0.016285820115365782
]

# --- log kernel ---
const _LG1 := 6004799503160723 / _TWO_POW_52 / 2.0  # 0.6666666666666735
const _LG2 := 1801439850921601 / _TWO_POW_52  # 0.3999999999940942
const _LG3 := 5146971033736025 / _TWO_POW_52 / 4.0  # 0.2857142874366239
const _LG4 := 8006390766270639 / _TWO_POW_52 / 8.0  # 0.22222198432149784
const _LG5 := 3275661152453103 / _TWO_POW_52 / 4.0  # 0.1818357216161805
const _LG6 := 5517391500461727 / _TWO_POW_52 / 8.0  # 0.15313837699209373
const _LG7 := 1332903234475153 / _TWO_POW_52 / 2.0  # 0.14798198605116586
const _SQRT2 := 6369051672525773 / _TWO_POW_52  # 1.4142135623730951 — sqrt(2)

# --- exact powers of two used as thresholds and scale factors ---
const _TWO_POW_66 := _TWO_POW_52 * 16384.0  # 7.378697629483821e+19
const _TWO_POW_M30 := 1 / _TWO_POW_26 / 16.0  # 9.313225746154785e-10


## sin(x), accurate to <1 ULP, identical bits on every platform.
static func sin(x: float) -> float:
	if is_nan(x) or is_inf(x):
		return NAN
	var q := _reduce_half_pi(x)
	var r: float = q[0]
	var n: int = q[1] & 3
	match n:
		0:
			return _kernel_sin(r)
		1:
			return _kernel_cos(r)
		2:
			return -_kernel_sin(r)
		_:
			return -_kernel_cos(r)


## cos(x), accurate to <1 ULP, identical bits on every platform.
static func cos(x: float) -> float:
	if is_nan(x) or is_inf(x):
		return NAN
	var q := _reduce_half_pi(x)
	var r: float = q[0]
	var n: int = q[1] & 3
	match n:
		0:
			return _kernel_cos(r)
		1:
			return -_kernel_sin(r)
		2:
			return -_kernel_cos(r)
		_:
			return _kernel_sin(r)


## Returns [sin(x), cos(x)] sharing one argument reduction.
##
## The integrator needs both for every thrust vector, so this halves the cost.
## Typed as a PackedFloat64Array rather than an Array so that indexing it yields
## a `float`: an untyped Array would make every caller's `var s := sc[0]` a
## Variant, which defeats static typing all the way down to the integrator — and
## costs a boxed allocation per element in the hottest loop in the game.
static func sincos(x: float) -> PackedFloat64Array:
	if is_nan(x) or is_inf(x):
		return PackedFloat64Array([NAN, NAN])
	var q := _reduce_half_pi(x)
	var r: float = q[0]
	var n: int = q[1] & 3
	var s := _kernel_sin(r)
	var c := _kernel_cos(r)
	match n:
		0:
			return PackedFloat64Array([s, c])
		1:
			return PackedFloat64Array([c, -s])
		2:
			return PackedFloat64Array([-s, -c])
		_:
			return PackedFloat64Array([-c, s])


## e**x. Overflows to INF above ~709.78, underflows to 0 below ~-745.
static func exp(x: float) -> float:
	if is_nan(x):
		return NAN
	if x > _EXP_MAX:
		return INF
	if x < _EXP_MIN:
		return 0.0

	# x = k*ln2 + r, with |r| <= ln2/2. The two-part ln2 keeps r exact.
	var k := _round_to_int(x * _INV_LN2)
	var kf := float(k)
	var r := (x - kf * _LN2_HI) - kf * _LN2_LO

	var rr := r * r
	var c := r - rr * (_P1 + rr * (_P2 + rr * (_P3 + rr * (_P4 + rr * _P5))))
	var y := 1.0 + (r * c / (2.0 - c) + r)
	return _scale_pow2(y, k)


## Natural log. Returns NAN for x < 0 and -INF for x == 0.
static func log(x: float) -> float:
	if is_nan(x) or x < 0.0:
		return NAN
	if x == 0.0:
		return -INF
	if is_inf(x):
		return INF

	# Split x into m * 2**e with m in [sqrt(2)/2, sqrt(2)), where the series
	# converges fastest. Both loops use exact powers of two, so no bits are lost.
	var e := 0
	var m := x
	while m >= 2.0:
		m *= 0.5
		e += 1
	while m < 1.0:
		m *= 2.0
		e -= 1
	if m >= _SQRT2:
		m *= 0.5
		e += 1

	var f := m - 1.0
	var s := f / (2.0 + f)
	var z := s * s
	var w := z * z
	var t1 := w * (_LG2 + w * (_LG4 + w * _LG6))
	var t2 := z * (_LG1 + w * (_LG3 + w * (_LG5 + w * _LG7)))
	var rr := t1 + t2
	var hfsq := 0.5 * f * f
	var ef := float(e)
	return ef * _LN2_HI - ((hfsq - (s * (hfsq + rr) + ef * _LN2_LO)) - f)


## x**y, via exp(y*log(x)). Handles the integer-exponent and sign cases exactly.
static func pow(x: float, y: float) -> float:
	if y == 0.0:
		return 1.0
	if y == 1.0:
		return x
	if y == 2.0:
		return x * x
	if x == 0.0:
		return 0.0 if y > 0.0 else INF
	if x > 0.0:
		return exp(y * log(x))
	# Negative base is only defined for integer exponents.
	var yi := _round_to_int(y)
	if float(yi) != y:
		return NAN
	var mag := exp(y * log(-x))
	return -mag if (yi & 1) == 1 else mag


## atan(x) in [-pi/2, pi/2].
static func atan(x: float) -> float:
	if is_nan(x):
		return NAN
	var neg := x < 0.0
	var ax := -x if neg else x
	if is_inf(ax) or ax > _TWO_POW_66:
		return -PI_2 if neg else PI_2

	var id := -1
	var t := ax
	if ax < 0.4375:
		id = -1
	elif ax < 1.1875:
		if ax < 0.6875:
			id = 0
			t = (2.0 * ax - 1.0) / (2.0 + ax)
		else:
			id = 1
			t = (ax - 1.0) / (ax + 1.0)
	elif ax < 2.4375:
		id = 2
		t = (ax - 1.5) / (1.0 + 1.5 * ax)
	else:
		id = 3
		t = -1.0 / ax

	var z := t * t
	var w := z * z
	var s1: float = (
		z * (_AT[0] + w * (_AT[2] + w * (_AT[4] + w * (_AT[6] + w * (_AT[8] + w * _AT[10])))))
	)
	var s2: float = w * (_AT[1] + w * (_AT[3] + w * (_AT[5] + w * (_AT[7] + w * _AT[9]))))

	var res: float
	if id < 0:
		res = t - t * (s1 + s2)
	else:
		res = _ATAN_HI[id] - ((t * (s1 + s2) - _ATAN_LO[id]) - t)
	return -res if neg else res


## atan2(y, x) in (-pi, pi]. Quadrant-correct, including the axis cases.
static func atan2(y: float, x: float) -> float:
	if is_nan(y) or is_nan(x):
		return NAN
	if x == 0.0:
		if y > 0.0:
			return PI_2
		if y < 0.0:
			return -PI_2
		return 0.0
	if y == 0.0:
		return 0.0 if x > 0.0 else PI_D
	if is_inf(x) and is_inf(y):
		# Ratio is meaningless; fall back on the 45-degree diagonals.
		var qx := 1.0 if x > 0.0 else -1.0
		var qy := 1.0 if y > 0.0 else -1.0
		return qy * (PI_D * 0.25 if qx > 0.0 else PI_D * 0.75)

	var a := atan(y / x)
	if x > 0.0:
		return a
	return a + PI_D if y > 0.0 else a - PI_D


## asin(x) in [-pi/2, pi/2]. Returns NAN outside [-1, 1].
static func asin(x: float) -> float:
	if x > 1.0 or x < -1.0:
		return NAN
	if x == 1.0:
		return PI_2
	if x == -1.0:
		return -PI_2
	return atan2(x, sqrt(1.0 - x * x))


## acos(x) in [0, pi]. Returns NAN outside [-1, 1].
static func acos(x: float) -> float:
	if x > 1.0 or x < -1.0:
		return NAN
	return atan2(sqrt(1.0 - x * x), x)


## Wraps an angle into [-pi, pi) using only exact operations.
static func wrap_angle(a: float) -> float:
	# floorf(), not floor(): the untyped global returns a Variant, which would
	# make `w` a Variant and break inference in every caller.
	var w := a - floorf((a + PI_D) / TAU_D) * TAU_D
	# The floor is exact, but the multiply can land exactly on the boundary.
	if w >= PI_D:
		w -= TAU_D
	elif w < -PI_D:
		w += TAU_D
	return w


## Wraps an angle into [0, 2*pi).
static func wrap_tau(a: float) -> float:
	var w := a - floorf(a / TAU_D) * TAU_D
	if w < 0.0:
		w += TAU_D
	elif w >= TAU_D:
		w -= TAU_D
	return w


## Smallest signed rotation from `from` to `to`, in [-pi, pi).
static func angle_delta(from: float, to: float) -> float:
	return wrap_angle(to - from)


## Floating-point remainder, x - trunc(x/y)*y.
##
## Unlike the transcendentals above, `fmod` needs no reimplementation: it is an
## *exact* operation — the result is always representable and no rounding
## occurs — so every conforming platform returns identical bits. It is wrapped
## here anyway so that the "no libm in the simulation" rule stays a clean grep,
## and so this reasoning lives somewhere rather than in a reviewer's memory.
static func fmod_exact(x: float, y: float) -> float:
	return fmod(x, y)


## Hypotenuse without the intermediate overflow of sqrt(x*x + y*y).
static func hypot(x: float, y: float) -> float:
	var ax := absf(x)
	var ay := absf(y)
	if ax < ay:
		var tmp := ax
		ax = ay
		ay = tmp
	if ax == 0.0:
		return 0.0
	var r := ay / ax
	return ax * sqrt(1.0 + r * r)


# --- internals -------------------------------------------------------------


## Reduces x to [-pi/4, pi/4] plus a quadrant count. Returns [r, n] — an
## untyped Array because the pair is mixed (a float and an int); callers
## annotate both explicitly. Returns [r, n] where
## x == n*(pi/2) + r. Uses Cody-Waite subtraction so that no precision is lost
## for the arguments the simulation produces (angles stay well under 2**20 rad
## because everything is wrapped before use).
static func _reduce_half_pi(x: float) -> Array:
	var ax := absf(x)
	if ax <= PI_4:  # already reduced
		return [x, 0]

	var n := _round_to_int(ax * _TWO_OVER_PI)
	var fn := float(n)
	var r := ax - fn * _PIO2_1
	var w := fn * _PIO2_1T
	var y := r - w

	# For large n the first split is not enough; peel off a second term.
	if absf(y) < _REDUCE_TINY or n > 33554432:  # 2**25
		var t := r
		w = fn * _PIO2_2
		r = t - w
		w = fn * _PIO2_2T - ((t - r) - w)
		y = r - w

	if x < 0.0:
		return [-y, (-n) & 3]
	return [y, n & 3]


static func _kernel_sin(x: float) -> float:
	var z := x * x
	return x + x * z * (_S1 + z * (_S2 + z * (_S3 + z * (_S4 + z * (_S5 + z * _S6)))))


static func _kernel_cos(x: float) -> float:
	var z := x * x
	var r := z * (_C1 + z * (_C2 + z * (_C3 + z * (_C4 + z * (_C5 + z * _C6)))))
	return 1.0 - (0.5 * z - z * r)


## Round-half-away-from-zero to an int, without calling round().
## Adding and subtracting the "rounding magic" 2**52 forces the fractional bits
## out of a double exactly, which is the same trick libm uses.
static func _round_to_int(x: float) -> int:
	if x >= 0.0:
		return int(x + 0.5)
	return -int(-x + 0.5)


## y * 2**k, computed with exact power-of-two multiplies only.
static func _scale_pow2(y: float, k: int) -> float:
	var result := y
	var n := k
	# Step in chunks of 2**30 so the scale factor itself is always exact and
	# finite, which keeps very large/small k from flushing to inf/0 early.
	while n > 30:
		result *= 1073741824.0  # 2**30
		n -= 30
	while n < -30:
		result *= _TWO_POW_M30
		n += 30
	if n > 0:
		result *= float(1 << n)
	elif n < 0:
		result /= float(1 << (-n))
	return result
