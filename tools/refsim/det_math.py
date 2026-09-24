"""Python port of scripts/core/det_math.gd.

This module exists to keep two jobs honest:

1.  It is the *parity reference*.  Every routine here is a line-by-line port of
    the GDScript in ``scripts/core/det_math.gd``.  Because both languages use
    IEEE-754 doubles and only correctly-rounded primitives, the two must agree
    bit for bit.  ``tools/refsim/generate_fixtures.py`` uses that to bake golden
    values which the GUT suite then asserts against, so a drift between the
    Python reference and the shipped GDScript fails CI.

2.  It lets us tune mission thresholds without a Godot install in the loop.

If you change one file, change the other.  ``tests/unit/test_det_math.gd`` and
``tools/refsim/test_det_math.py`` cover the same cases from both sides.
"""

import math

PI_2 = 1.57079632679489661923
TAU_D = 6.28318530717958647692
PI_D = 3.14159265358979323846

_TWO_OVER_PI = 0.63661977236758134308
_PIO2_1 = 1.57079632673412561417
_PIO2_1T = 6.07710050650619224932e-11
_PIO2_2 = 6.07710050630396597660e-11
_PIO2_2T = 2.02226624879595063154e-21

_S1 = -1.66666666666666324348e-01
_S2 = 8.33333333332248946124e-03
_S3 = -1.98412698298579493134e-04
_S4 = 2.75573137070700676789e-06
_S5 = -2.50507602534068634195e-08
_S6 = 1.58969099521155010221e-10

_C1 = 4.16666666666666019037e-02
_C2 = -1.38888888888741095749e-03
_C3 = 2.48015872894767294178e-05
_C4 = -2.75573143513906633035e-07
_C5 = 2.08757232129817482790e-09
_C6 = -1.13596475577881948265e-11

_LN2_HI = 6.93147180369123816490e-01
_LN2_LO = 1.90821492927058770002e-10
_INV_LN2 = 1.44269504088896338700e+00
_P1 = 1.66666666666666019037e-01
_P2 = -2.77777777770155933842e-03
_P3 = 6.61375632143793436117e-05
_P4 = -1.65339022054652515390e-06
_P5 = 4.13813679705723846039e-08

_ATAN_HI = [
    4.63647609000806093515e-01,
    7.85398163397448278999e-01,
    9.82793723247329054082e-01,
    1.57079632679489655800e+00,
]
_ATAN_LO = [
    2.26987774529616870924e-17,
    3.06161699786838301793e-17,
    1.39033110312309984516e-17,
    6.12323399573676603587e-17,
]
_AT = [
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

_LG1 = 6.666666666666735130e-01
_LG2 = 3.999999999940941908e-01
_LG3 = 2.857142874366239149e-01
_LG4 = 2.222219843214978396e-01
_LG5 = 1.818357216161805012e-01
_LG6 = 1.531383769920937332e-01
_LG7 = 1.479819860511658591e-01
_SQRT2 = 1.41421356237309504880


def _round_to_int(x):
    if x >= 0.0:
        return int(x + 0.5)
    return -int(-x + 0.5)


def _scale_pow2(y, k):
    result = y
    n = k
    while n > 30:
        result *= 1073741824.0
        n -= 30
    while n < -30:
        result *= 9.31322574615478515625e-10
        n += 30
    if n > 0:
        result *= float(1 << n)
    elif n < 0:
        result /= float(1 << (-n))
    return result


def _reduce_half_pi(x):
    ax = abs(x)
    if ax <= 0.7853981633974483:
        return (x, 0)
    n = _round_to_int(ax * _TWO_OVER_PI)
    fn = float(n)
    r = ax - fn * _PIO2_1
    w = fn * _PIO2_1T
    y = r - w
    if abs(y) < 1.0e-8 or n > 33554432:
        t = r
        w = fn * _PIO2_2
        r = t - w
        w = fn * _PIO2_2T - ((t - r) - w)
        y = r - w
    if x < 0.0:
        return (-y, (-n) & 3)
    return (y, n & 3)


def _kernel_sin(x):
    z = x * x
    return x + x * z * (_S1 + z * (_S2 + z * (_S3 + z * (_S4 + z * (_S5 + z * _S6)))))


def _kernel_cos(x):
    z = x * x
    r = z * (_C1 + z * (_C2 + z * (_C3 + z * (_C4 + z * (_C5 + z * _C6)))))
    return 1.0 - (0.5 * z - z * r)


def sin(x):
    if math.isnan(x) or math.isinf(x):
        return math.nan
    r, n = _reduce_half_pi(x)
    n &= 3
    if n == 0:
        return _kernel_sin(r)
    if n == 1:
        return _kernel_cos(r)
    if n == 2:
        return -_kernel_sin(r)
    return -_kernel_cos(r)


def cos(x):
    if math.isnan(x) or math.isinf(x):
        return math.nan
    r, n = _reduce_half_pi(x)
    n &= 3
    if n == 0:
        return _kernel_cos(r)
    if n == 1:
        return -_kernel_sin(r)
    if n == 2:
        return -_kernel_cos(r)
    return _kernel_sin(r)


def sincos(x):
    if math.isnan(x) or math.isinf(x):
        return (math.nan, math.nan)
    r, n = _reduce_half_pi(x)
    n &= 3
    s = _kernel_sin(r)
    c = _kernel_cos(r)
    if n == 0:
        return (s, c)
    if n == 1:
        return (c, -s)
    if n == 2:
        return (-s, -c)
    return (-c, s)


def exp(x):
    if math.isnan(x):
        return math.nan
    if x > 709.782712893383973096:
        return math.inf
    if x < -745.133219101941108420:
        return 0.0
    if -1.0e-300 < x < 1.0e-300:
        return 1.0 + x
    k = _round_to_int(x * _INV_LN2)
    kf = float(k)
    r = (x - kf * _LN2_HI) - kf * _LN2_LO
    rr = r * r
    c = r - rr * (_P1 + rr * (_P2 + rr * (_P3 + rr * (_P4 + rr * _P5))))
    y = 1.0 + (r * c / (2.0 - c) + r)
    return _scale_pow2(y, k)


def log(x):
    if math.isnan(x) or x < 0.0:
        return math.nan
    if x == 0.0:
        return -math.inf
    if math.isinf(x):
        return math.inf
    e = 0
    m = x
    while m >= 2.0:
        m *= 0.5
        e += 1
    while m < 1.0:
        m *= 2.0
        e -= 1
    if m >= _SQRT2:
        m *= 0.5
        e += 1
    f = m - 1.0
    s = f / (2.0 + f)
    z = s * s
    w = z * z
    t1 = w * (_LG2 + w * (_LG4 + w * _LG6))
    t2 = z * (_LG1 + w * (_LG3 + w * (_LG5 + w * _LG7)))
    rr = t1 + t2
    hfsq = 0.5 * f * f
    ef = float(e)
    return ef * _LN2_HI - ((hfsq - (s * (hfsq + rr) + ef * _LN2_LO)) - f)


def pow(x, y):
    if y == 0.0:
        return 1.0
    if y == 1.0:
        return x
    if y == 2.0:
        return x * x
    if x == 0.0:
        return 0.0 if y > 0.0 else math.inf
    if x > 0.0:
        return exp(y * log(x))
    yi = _round_to_int(y)
    if float(yi) != y:
        return math.nan
    mag = exp(y * log(-x))
    return -mag if (yi & 1) == 1 else mag


def atan(x):
    if math.isnan(x):
        return math.nan
    neg = x < 0.0
    ax = -x if neg else x
    if math.isinf(ax) or ax > 7.3786976294838206464e19:
        return -PI_2 if neg else PI_2
    if ax < 0.4375:
        idx = -1
        t = ax
    elif ax < 1.1875:
        if ax < 0.6875:
            idx = 0
            t = (2.0 * ax - 1.0) / (2.0 + ax)
        else:
            idx = 1
            t = (ax - 1.0) / (ax + 1.0)
    elif ax < 2.4375:
        idx = 2
        t = (ax - 1.5) / (1.0 + 1.5 * ax)
    else:
        idx = 3
        t = -1.0 / ax
    z = t * t
    w = z * z
    s1 = z * (_AT[0] + w * (_AT[2] + w * (_AT[4] + w * (_AT[6] + w * (_AT[8] + w * _AT[10])))))
    s2 = w * (_AT[1] + w * (_AT[3] + w * (_AT[5] + w * (_AT[7] + w * _AT[9]))))
    if idx < 0:
        res = t - t * (s1 + s2)
    else:
        res = _ATAN_HI[idx] - ((t * (s1 + s2) - _ATAN_LO[idx]) - t)
    return -res if neg else res


def atan2(y, x):
    if math.isnan(y) or math.isnan(x):
        return math.nan
    if x == 0.0:
        if y > 0.0:
            return PI_2
        if y < 0.0:
            return -PI_2
        return 0.0
    if y == 0.0:
        return 0.0 if x > 0.0 else PI_D
    if math.isinf(x) and math.isinf(y):
        qx = 1.0 if x > 0.0 else -1.0
        qy = 1.0 if y > 0.0 else -1.0
        return qy * (PI_D * 0.25 if qx > 0.0 else PI_D * 0.75)
    a = atan(y / x)
    if x > 0.0:
        return a
    return a + PI_D if y > 0.0 else a - PI_D


def asin(x):
    if x > 1.0 or x < -1.0:
        return math.nan
    if x == 1.0:
        return PI_2
    if x == -1.0:
        return -PI_2
    return atan2(x, math.sqrt(1.0 - x * x))


def acos(x):
    if x > 1.0 or x < -1.0:
        return math.nan
    return atan2(math.sqrt(1.0 - x * x), x)


def wrap_angle(a):
    w = a - math.floor((a + PI_D) / TAU_D) * TAU_D
    if w >= PI_D:
        w -= TAU_D
    elif w < -PI_D:
        w += TAU_D
    return w


def wrap_tau(a):
    w = a - math.floor(a / TAU_D) * TAU_D
    if w < 0.0:
        w += TAU_D
    elif w >= TAU_D:
        w -= TAU_D
    return w


def angle_delta(frm, to):
    return wrap_angle(to - frm)


def fmod_exact(x, y):
    return math.fmod(x, y)


def hypot(x, y):
    ax = abs(x)
    ay = abs(y)
    if ax < ay:
        ax, ay = ay, ax
    if ax == 0.0:
        return 0.0
    r = ay / ax
    return ax * math.sqrt(1.0 + r * r)
