class_name Orbital
extends RefCounted

## Closed-form two-body orbital mathematics.
##
## Nothing in here integrates anything — these are the instantaneous conic
## elements of a state vector, used for sensors, the map view and mission
## predicates. The trajectory itself always comes from the integrator, so that
## thrust, drag and a second body's gravity are all accounted for.
##
## All angles are radians; all distances metres; all times seconds.

## Keys returned by elements().
const K_RADIUS := "radius"
const K_SPEED := "speed"
const K_SMA := "sma"
const K_ECC := "ecc"
const K_APOAPSIS := "apoapsis"     ## radius, not altitude
const K_PERIAPSIS := "periapsis"   ## radius, not altitude
const K_PERIOD := "period"
const K_ENERGY := "energy"
const K_ANG_MOMENTUM := "h"
const K_TRUE_ANOMALY := "nu"
const K_TIME_TO_APO := "t_apo"
const K_TIME_TO_PERI := "t_peri"
const K_RADIAL_SPEED := "v_radial"
const K_TANGENTIAL_SPEED := "v_tangential"


## Speed of a circular orbit at radius r.
static func circular_speed(mu: float, r: float) -> float:
	if r <= 0.0 or mu <= 0.0:
		return 0.0
	return sqrt(mu / r)


## Escape speed at radius r.
static func escape_speed(mu: float, r: float) -> float:
	if r <= 0.0 or mu <= 0.0:
		return 0.0
	return sqrt(2.0 * mu / r)


## Vis-viva: speed at radius r on an orbit of semi-major axis a.
static func vis_viva(mu: float, r: float, a: float) -> float:
	if r <= 0.0 or a == 0.0:
		return 0.0
	var v2 := mu * (2.0 / r - 1.0 / a)
	if v2 <= 0.0:
		return 0.0
	return sqrt(v2)


## Orbital period of a closed orbit; INF if the orbit is not closed.
static func period(mu: float, a: float) -> float:
	if a <= 0.0 or mu <= 0.0:
		return INF
	return DetMath.TAU_D * sqrt(a * a * a / mu)


## Total delta-v of a two-burn Hohmann transfer between circular orbits.
## Returns [burn1, burn2, transfer_time].
static func hohmann(mu: float, r1: float, r2: float) -> Array:
	if r1 <= 0.0 or r2 <= 0.0 or mu <= 0.0:
		return [0.0, 0.0, 0.0]
	var a_t := 0.5 * (r1 + r2)
	var v1 := sqrt(mu / r1)
	var v2 := sqrt(mu / r2)
	var vt1 := vis_viva(mu, r1, a_t)
	var vt2 := vis_viva(mu, r2, a_t)
	return [vt1 - v1, v2 - vt2, DetMath.PI_D * sqrt(a_t * a_t * a_t / mu)]


## Full conic elements of a relative state vector.
##
## `rx, ry` and `vx, vy` are measured *relative to the attracting body*, so a
## ship inside a moon's sphere of influence is described by its orbit about the
## moon rather than a wildly eccentric orbit about the primary.
##
## Apoapsis is INF for parabolic and hyperbolic orbits; times to apsis are INF
## when the ship will never come back round.
static func elements(mu: float, rx: float, ry: float, vx: float, vy: float) -> Dictionary:
	var r := DetMath.hypot(rx, ry)
	var v2 := vx * vx + vy * vy
	var v := sqrt(v2)

	var out := {
		K_RADIUS: r,
		K_SPEED: v,
		K_SMA: 0.0,
		K_ECC: 0.0,
		K_APOAPSIS: INF,
		K_PERIAPSIS: 0.0,
		K_PERIOD: INF,
		K_ENERGY: 0.0,
		K_ANG_MOMENTUM: 0.0,
		K_TRUE_ANOMALY: 0.0,
		K_TIME_TO_APO: INF,
		K_TIME_TO_PERI: INF,
		K_RADIAL_SPEED: 0.0,
		K_TANGENTIAL_SPEED: 0.0,
	}
	if r <= 0.0 or mu <= 0.0:
		return out

	# Specific angular momentum. In 2D this is the scalar z-component; its sign
	# tells us whether the ship travels counter-clockwise (positive) or
	# clockwise, which matters for working out which apsis comes next.
	var h := rx * vy - ry * vx
	var rv := rx * vx + ry * vy  # r . v, positive when climbing away

	out[K_ANG_MOMENTUM] = h
	out[K_RADIAL_SPEED] = rv / r
	out[K_TANGENTIAL_SPEED] = h / r

	var energy := 0.5 * v2 - mu / r
	out[K_ENERGY] = energy

	# Eccentricity vector, pointing at periapsis.
	var c1 := v2 / mu - 1.0 / r
	var c2 := rv / mu
	var ex := c1 * rx - c2 * vx
	var ey := c1 * ry - c2 * vy
	var ecc := DetMath.hypot(ex, ey)
	out[K_ECC] = ecc

	if absf(energy) < 1.0e-12:
		# Parabolic to within double precision: no semi-major axis to speak of.
		out[K_SMA] = INF
		out[K_PERIAPSIS] = h * h / mu * 0.5
		return out

	var a := -mu / (2.0 * energy)
	out[K_SMA] = a

	if ecc < 1.0:
		out[K_APOAPSIS] = a * (1.0 + ecc)
		out[K_PERIAPSIS] = a * (1.0 - ecc)
		out[K_PERIOD] = period(mu, a)
	else:
		out[K_APOAPSIS] = INF
		out[K_PERIAPSIS] = a * (1.0 - ecc)  # a is negative here, so this is positive

	# True anomaly, measured from periapsis in the direction of travel.
	var nu := 0.0
	if ecc > 1.0e-10:
		var cos_nu := (ex * rx + ey * ry) / (ecc * r)
		nu = DetMath.acos(clampf(cos_nu, -1.0, 1.0))
		if rv < 0.0:
			nu = DetMath.TAU_D - nu
	out[K_TRUE_ANOMALY] = nu

	if ecc < 1.0 and a > 0.0:
		var n := sqrt(mu / (a * a * a))
		if n > 0.0:
			# Kepler: true anomaly -> eccentric anomaly -> mean anomaly -> time.
			var half := nu * 0.5
			var sq1 := sqrt(maxf(0.0, 1.0 - ecc))
			var sq2 := sqrt(maxf(0.0, 1.0 + ecc))
			var ea := 2.0 * DetMath.atan2(sq1 * DetMath.sin(half), sq2 * DetMath.cos(half))
			var m := DetMath.wrap_tau(ea - ecc * DetMath.sin(ea))
			out[K_TIME_TO_PERI] = (DetMath.TAU_D - m) / n if m > 0.0 else 0.0
			out[K_TIME_TO_APO] = DetMath.wrap_tau(DetMath.PI_D - m) / n

	return out


## Orbital period from a raw state vector, without computing the full element
## set. The step-size chooser needs only this, and calling it on every coasting
## tick makes the Kepler machinery in elements() a measurable cost.
static func period_of_state(mu: float, rx: float, ry: float, vx: float, vy: float) -> float:
	var r := DetMath.hypot(rx, ry)
	if r <= 0.0 or mu <= 0.0:
		return INF
	var energy := 0.5 * (vx * vx + vy * vy) - mu / r
	if energy >= 0.0:
		return INF
	var a := -mu / (2.0 * energy)
	return period(mu, a)


## Altitude of apoapsis above a body's surface; INF for an escape trajectory.
static func apoapsis_altitude(elems: Dictionary, body_radius: float) -> float:
	var ap: float = elems.get(K_APOAPSIS, INF)
	return INF if is_inf(ap) else ap - body_radius


## Altitude of periapsis above a body's surface. Goes negative when the orbit
## intersects the ground — which is exactly what makes it a useful warning.
static func periapsis_altitude(elems: Dictionary, body_radius: float) -> float:
	return float(elems.get(K_PERIAPSIS, 0.0)) - body_radius
