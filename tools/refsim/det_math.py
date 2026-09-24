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

_TWO_POW_26 = 67108864.0  # 2**26
_TWO_POW_52 = _TWO_POW_26 * _TWO_POW_26  # 2**52

PI_2 = 884279719003555 / _TWO_POW_26 / 8388608.0  # 1.5707963267948966 — pi/2
PI_D = 884279719003555 / _TWO_POW_26 / 4194304.0  # 3.141592653589793 — pi
TAU_D = 884279719003555 / _TWO_POW_26 / 2097152.0  # 6.283185307179586 — 2*pi
PI_4 = 884279719003555 / _TWO_POW_26 / 16777216.0  # 0.7853981633974483 — pi/4

# --- Argument reduction for sin/cos: 2/pi and pi/2 split into exact parts. ---
_TWO_OVER_PI = 5734161139222659 / _TWO_POW_52 / 2.0  # 0.6366197723675814 — 2/pi
_PIO2_1 = 1686629713 / _TWO_POW_26 / 16.0  # 1.5707963267341256 — the first 33 bits of pi/2
_PIO2_1T = 4701928774853425 / _TWO_POW_52 / _TWO_POW_26 / 256.0  # 6.077100506506192e-11
_PIO2_2 = 2242054355 / _TWO_POW_52 / 8192.0  # 6.077100506303966e-11 — the next 33 bits
_PIO2_2T = 5376105825661043 / _TWO_POW_52 / _TWO_POW_52 / 131072.0  # 2.0222662487959506e-21
_REDUCE_TINY = 3022314549036573 / _TWO_POW_52 / _TWO_POW_26  # 1e-08

# --- sin kernel on [-pi/4, pi/4] ---
_S1 = -6004799503160649 / _TWO_POW_52 / 8.0  # -0.16666666666666632
_S2 = 2401919801261139 / _TWO_POW_52 / 64.0  # 0.00833333333332249
_S3 = -7320136532976085 / _TWO_POW_52 / 8192.0  # -0.0001984126982985795
_S4 = 6506786730409597 / _TWO_POW_52 / 524288.0  # 2.7557313707070068e-06
_S5 = -7571127717829867 / _TWO_POW_52 / _TWO_POW_26  # -2.5050760253406863e-08
_S6 = 1537454791456095 / _TWO_POW_52 / _TWO_POW_26 / 32.0  # 1.58969099521155e-10

# --- cos kernel on [-pi/4, pi/4] ---
_C1 = 1501199875790163 / _TWO_POW_52 / 8.0  # 0.0416666666666666
_C2 = -6405119470031223 / _TWO_POW_52 / 1024.0  # -0.001388888888887411
_C3 = 457508533350745 / _TWO_POW_52 / 4096.0  # 2.480158728947673e-05
_C4 = -5205429506036397 / _TWO_POW_52 / 4194304.0  # -2.7557314351390663e-07
_C5 = 1261860039765105 / _TWO_POW_52 / _TWO_POW_26 / 2.0  # 2.087572321298175e-09
_C6 = -1757820317994549 / _TWO_POW_52 / _TWO_POW_26 / 512.0  # -1.1359647557788195e-11

# --- exp kernel ---
_LN2_HI = 2977044471 / _TWO_POW_26 / 64.0  # 0.6931471803691238
_LN2_LO = 3691024475790907 / _TWO_POW_52 / _TWO_POW_26 / 64.0  # 1.9082149292705877e-10
_INV_LN2 = 3248660424278399 / _TWO_POW_26 / 33554432.0  # 1.4426950408889634
_P1 = 3002399751580319 / _TWO_POW_52 / 4.0  # 0.16666666666666602
_P2 = -6405119469862291 / _TWO_POW_52 / 512.0  # -0.0027777777777015593
_P3 = 1220022702274443 / _TWO_POW_52 / 4096.0  # 6.613756321437934e-05
_P4 = -7807914560613361 / _TWO_POW_52 / 1048576.0  # -1.6533902205465252e-06
_P5 = 390835970239053 / _TWO_POW_52 / 2097152.0  # 4.1381367970572385e-08
_EXP_MAX = 6243314768165359 / _TWO_POW_26 / 131072.0  # 709.782712893384
_EXP_MIN = -6554261109157969 / _TWO_POW_26 / 131072.0  # -745.1332191019411

_ATAN_HI = [
    8352332796509007 / _TWO_POW_52 / 4.0,  # 0.4636476090008061 — atan(0.5)
    PI_4,  # 0.7853981633974483 — atan(1.0)
    8852218891597467 / _TWO_POW_52 / 2.0,  # 0.982793723247329 — atan(1.5)
    PI_2,  # 1.5707963267948966 — atan(inf)
]

_ATAN_LO = [
    3683087214424817 / _TWO_POW_52 / _TWO_POW_52 / 8.0,  # 2.2698777452961687e-17
    4967757600021511 / _TWO_POW_52 / _TWO_POW_52 / 8.0,  # 3.061616997868383e-17
    4511882386918333 / _TWO_POW_52 / _TWO_POW_52 / 16.0,  # 1.3903311031230998e-17
    4967757600021511 / _TWO_POW_52 / _TWO_POW_52 / 4.0,  # 6.123233995736766e-17
]

_AT = [
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
_LG1 = 6004799503160723 / _TWO_POW_52 / 2.0  # 0.6666666666666735
_LG2 = 1801439850921601 / _TWO_POW_52  # 0.3999999999940942
_LG3 = 5146971033736025 / _TWO_POW_52 / 4.0  # 0.2857142874366239
_LG4 = 8006390766270639 / _TWO_POW_52 / 8.0  # 0.22222198432149784
_LG5 = 3275661152453103 / _TWO_POW_52 / 4.0  # 0.1818357216161805
_LG6 = 5517391500461727 / _TWO_POW_52 / 8.0  # 0.15313837699209373
_LG7 = 1332903234475153 / _TWO_POW_52 / 2.0  # 0.14798198605116586
_SQRT2 = 6369051672525773 / _TWO_POW_52  # 1.4142135623730951 — sqrt(2)

# --- exact powers of two used as thresholds and scale factors ---
_TWO_POW_66 = _TWO_POW_52 * 16384.0  # 7.378697629483821e+19
_TWO_POW_M30 = 1 / _TWO_POW_26 / 16.0  # 9.313225746154785e-10


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
        result *= _TWO_POW_M30
        n += 30
    if n > 0:
        result *= float(1 << n)
    elif n < 0:
        result /= float(1 << (-n))
    return result


def _reduce_half_pi(x):
    ax = abs(x)
    if ax <= PI_4:
        return (x, 0)
    n = _round_to_int(ax * _TWO_OVER_PI)
    fn = float(n)
    r = ax - fn * _PIO2_1
    w = fn * _PIO2_1T
    y = r - w
    if abs(y) < _REDUCE_TINY or n > 33554432:
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
    if x > _EXP_MAX:
        return math.inf
    if x < _EXP_MIN:
        return 0.0
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
    if math.isinf(ax) or ax > _TWO_POW_66:
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
