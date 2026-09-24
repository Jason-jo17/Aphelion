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

const PI_2 := 1.57079632679489661923   # pi/2
const TAU_D := 6.28318530717958647692  # 2*pi
const PI_D := 3.14159265358979323846

# --- Argument reduction for sin/cos: 2/pi and pi/2 split into exact parts. ---
# pi/2 is written as three doubles whose sum carries ~160 bits of the true value.
# Subtracting them one at a time (Cody-Waite) keeps the reduced argument accurate
# even when the input is large, because each partial subtraction is exact.
const _TWO_OVER_PI := 0.63661977236758134308
const _PIO2_1 := 1.57079632673412561417    # first 33 bits of pi/2
const _PIO2_1T := 6.07710050650619224932e-11
const _PIO2_2 := 6.07710050630396597660e-11
const _PIO2_2T := 2.02226624879595063154e-21

# --- sin kernel on [-pi/4, pi/4] ---
const _S1 := -1.66666666666666324348e-01
const _S2 := 8.33333333332248946124e-03
const _S3 := -1.98412698298579493134e-04
const _S4 := 2.75573137070700676789e-06
const _S5 := -2.50507602534068634195e-08
const _S6 := 1.58969099521155010221e-10

# --- cos kernel on [-pi/4, pi/4] ---
const _C1 := 4.16666666666666019037e-02
const _C2 := -1.38888888888741095749e-03
const _C3 := 2.48015872894767294178e-05
const _C4 := -2.75573143513906633035e-07
const _C5 := 2.08757232129817482790e-09
const _C6 := -1.13596475577881948265e-11

# --- exp kernel ---
const _LN2_HI := 6.93147180369123816490e-01
const _LN2_LO := 1.90821492927058770002e-10
const _INV_LN2 := 1.44269504088896338700e+00
const _P1 := 1.66666666666666019037e-01
const _P2 := -2.77777777770155933842e-03
const _P3 := 6.61375632143793436117e-05
const _P4 := -1.65339022054652515390e-06
const _P5 := 4.13813679705723846039e-08

# --- atan kernel ---
const _ATAN_HI := [
	4.63647609000806093515e-01,  # atan(0.5)
	7.85398163397448278999e-01,  # atan(1.0)
	9.82793723247329054082e-01,  # atan(1.5)
	1.57079632679489655800e+00,  # atan(inf)
]
const _ATAN_LO := [
	2.26987774529616870924e-17,
	3.06161699786838301793e-17,
	1.39033110312309984516e-17,
	6.12323399573676603587e-17,
]
const _AT := [
	3.33333333333329318027e-01,
	-1.99999999998764832476e-01,
	1.42857142725034663711e-01,
	-1.11111104054623557880e-01,
	9.09088713343650656196e-02,
	-7.69187620504482999495e-02,
	6.66107313738753120669e-02,
	-5.83357013379057348645e-02,
	4.97687799461593236017e-02,
	-3.65315727442169155270e-02,
	1.62858201153657823623e-02,
]

# --- log kernel ---
const _LG1 := 6.666666666666735130e-01
const _LG2 := 3.999999999940941908e-01
const _LG3 := 2.857142874366239149e-01
const _LG4 := 2.222219843214978396e-01
const _LG5 := 1.818357216161805012e-01
const _LG6 := 1.531383769920937332e-01
const _LG7 := 1.479819860511658591e-01
const _SQRT2 := 1.41421356237309504880


## sin(x), accurate to <1 ULP, identical bits on every platform.
static func sin(x: float) -> float:
	if is_nan(x) or is_inf(x):
		return NAN
	var q := _reduce_half_pi(x)
	var r: float = q[0]
	var n: int = q[1] & 3
	match n:
		0: return _kernel_sin(r)
		1: return _kernel_cos(r)
		2: return -_kernel_sin(r)
		_: return -_kernel_cos(r)


## cos(x), accurate to <1 ULP, identical bits on every platform.
static func cos(x: float) -> float:
	if is_nan(x) or is_inf(x):
		return NAN
	var q := _reduce_half_pi(x)
	var r: float = q[0]
	var n: int = q[1] & 3
	match n:
		0: return _kernel_cos(r)
		1: return -_kernel_sin(r)
		2: return -_kernel_cos(r)
		_: return _kernel_sin(r)


## Returns [sin(x), cos(x)] sharing one argument reduction.
## The integrator needs both for every thrust vector, so this halves the cost.
static func sincos(x: float) -> Array:
	if is_nan(x) or is_inf(x):
		return [NAN, NAN]
	var q := _reduce_half_pi(x)
	var r: float = q[0]
	var n: int = q[1] & 3
	var s := _kernel_sin(r)
	var c := _kernel_cos(r)
	match n:
		0: return [s, c]
		1: return [c, -s]
		2: return [-s, -c]
		_: return [-c, s]


## e**x. Overflows to INF above ~709.78, underflows to 0 below ~-745.
static func exp(x: float) -> float:
	if is_nan(x):
		return NAN
	if x > 709.782712893383973096:
		return INF
	if x < -745.133219101941108420:
		return 0.0
	if x > -1.0e-300 and x < 1.0e-300:
		return 1.0 + x

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
	if is_inf(ax) or ax > 7.3786976294838206464e19:  # 2**66
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
	var s1: float = z * (_AT[0] + w * (_AT[2] + w * (_AT[4] + w * (_AT[6] + w * (_AT[8] + w * _AT[10])))))
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
	var w := a - floor((a + PI_D) / TAU_D) * TAU_D
	# floor() is exact, but the multiply can land exactly on the boundary.
	if w >= PI_D:
		w -= TAU_D
	elif w < -PI_D:
		w += TAU_D
	return w


## Wraps an angle into [0, 2*pi).
static func wrap_tau(a: float) -> float:
	var w := a - floor(a / TAU_D) * TAU_D
	if w < 0.0:
		w += TAU_D
	elif w >= TAU_D:
		w -= TAU_D
	return w


## Smallest signed rotation from `from` to `to`, in [-pi, pi).
static func angle_delta(from: float, to: float) -> float:
	return wrap_angle(to - from)


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


## Reduces x to [-pi/4, pi/4] plus a quadrant count. Returns [r, n] where
## x == n*(pi/2) + r. Uses Cody-Waite subtraction so that no precision is lost
## for the arguments the simulation produces (angles stay well under 2**20 rad
## because everything is wrapped before use).
static func _reduce_half_pi(x: float) -> Array:
	var ax := absf(x)
	if ax <= 0.7853981633974483:  # pi/4 — already reduced
		return [x, 0]

	var n := _round_to_int(ax * _TWO_OVER_PI)
	var fn := float(n)
	var r := ax - fn * _PIO2_1
	var w := fn * _PIO2_1T
	var y := r - w

	# For large n the first split is not enough; peel off a second term.
	if absf(y) < 1.0e-8 or n > 33554432:  # 2**25
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
		result *= 9.31322574615478515625e-10  # 2**-30
		n += 30
	if n > 0:
		result *= float(1 << n)
	elif n < 0:
		result /= float(1 << (-n))
	return result
