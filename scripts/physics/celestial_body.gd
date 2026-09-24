class_name CelestialBody
extends RefCounted

## A gravitating body: the primary the mission orbits, or a moon.
##
## Moons travel on a *prescribed analytic circular orbit* rather than being
## integrated alongside the ship. That is a deliberate determinism choice: the
## moon's position is a closed-form function of mission time, so it can never
## accumulate integration error, can never drift between one run and the next,
## and can be evaluated at any time without replaying history. The ship still
## feels the moon's real gravity — only the moon's own motion is on rails.

var id: String = ""
var display_name: String = ""

## Standard gravitational parameter G*M, in m^3/s^2.
var mu: float = 0.0

## Surface radius in metres. Altitude is measured from here.
var radius: float = 0.0

## Rotation of the surface (and the atmosphere that clings to it), in rad/s.
var rotation_rate: float = 0.0
var surface_phase0: float = 0.0

## Orbit about the primary. Zero radius marks the primary itself.
var orbit_radius: float = 0.0
var orbit_phase0: float = 0.0
var orbit_mean_motion: float = 0.0

## Sphere of influence. INF for the primary, so it always wins by default.
var soi_radius: float = INF

## Atmosphere (null for airless bodies).
var atmo_height: float = 0.0
var atmo_sea_level_density: float = 0.0
var atmo_scale_height: float = 1.0

## Display-only.
var color: Color = Color(0.45, 0.55, 0.75)

# Single-entry memo for position_at(). RK4 evaluates the midpoint twice per
# step with the identical float argument, so this is a guaranteed hit rather
# than a heuristic. Keyed on exact equality — never on a tolerance, which would
# make the result depend on evaluation order.
var _memo_t: float = NAN
var _memo_x: float = 0.0
var _memo_y: float = 0.0


func has_atmosphere() -> bool:
	return atmo_height > 0.0 and atmo_sea_level_density > 0.0


func is_primary() -> bool:
	return orbit_radius == 0.0


## Computes this body's position at mission time `t` into _memo_x/_memo_y.
func position_at(t: float) -> void:
	if t == _memo_t:
		return
	if orbit_radius == 0.0:
		_memo_x = 0.0
		_memo_y = 0.0
	else:
		var sc := DetMath.sincos(orbit_phase0 + orbit_mean_motion * t)
		_memo_x = orbit_radius * sc[1]
		_memo_y = orbit_radius * sc[0]
	_memo_t = t


func pos_x(t: float) -> float:
	position_at(t)
	return _memo_x


func pos_y(t: float) -> float:
	position_at(t)
	return _memo_y


## Orbital velocity of the body itself — needed to compute a ship's velocity
## relative to a moon when it enters the moon's sphere of influence.
func vel_x(t: float) -> float:
	if orbit_radius == 0.0:
		return 0.0
	var sc := DetMath.sincos(orbit_phase0 + orbit_mean_motion * t)
	return -orbit_radius * orbit_mean_motion * sc[0]


func vel_y(t: float) -> float:
	if orbit_radius == 0.0:
		return 0.0
	var sc := DetMath.sincos(orbit_phase0 + orbit_mean_motion * t)
	return orbit_radius * orbit_mean_motion * sc[1]


## Atmospheric density at a given altitude, via an exponential profile.
## Returns exactly zero at and above the stated atmosphere height so that the
## "am I in vacuum?" test used by the step-size chooser is a crisp boundary
## rather than an asymptote.
func density_at_altitude(altitude: float) -> float:
	if not has_atmosphere():
		return 0.0
	if altitude >= atmo_height:
		return 0.0
	if altitude <= 0.0:
		return atmo_sea_level_density
	return atmo_sea_level_density * DetMath.exp(-altitude / atmo_scale_height)


## Surface (and atmosphere) velocity at a point, from the body's rotation.
## A launch from the equator starts with this much eastward speed for free.
func surface_vel_x(_rel_x: float, rel_y: float) -> float:
	return -rotation_rate * rel_y


func surface_vel_y(rel_x: float, _rel_y: float) -> float:
	return rotation_rate * rel_x


## Builds a body from a mission/universe JSON dictionary.
static func from_dict(d: Dictionary, primary_mu: float) -> CelestialBody:
	var b := CelestialBody.new()
	b.id = String(d.get("id", ""))
	b.display_name = String(d.get("name", b.id))
	b.mu = float(d.get("mu", 0.0))
	b.radius = float(d.get("radius", 0.0))
	# Preferring a period to a rate is deliberate: a period is a round number
	# that every parser reads identically, while the rate it implies needs
	# sixteen significant digits. See docs/DETERMINISM.md rule 9.
	if d.has("rotation_period") and float(d["rotation_period"]) != 0.0:
		b.rotation_rate = DetMath.TAU_D / float(d["rotation_period"])
	else:
		b.rotation_rate = float(d.get("rotation_rate", 0.0))
	b.surface_phase0 = float(d.get("surface_phase0", 0.0))
	b.orbit_radius = float(d.get("orbit_radius", 0.0))
	b.orbit_phase0 = float(d.get("orbit_phase0", 0.0))

	if b.orbit_radius > 0.0 and primary_mu > 0.0:
		# Circular mean motion n = sqrt(mu / a^3). Direction is prograde unless
		# the data says otherwise.
		var a3 := b.orbit_radius * b.orbit_radius * b.orbit_radius
		var n := sqrt(primary_mu / a3)
		var dir := 1.0 if float(d.get("orbit_direction", 1.0)) >= 0.0 else -1.0
		b.orbit_mean_motion = n * dir
		# A tidally locked body turns once per orbit by definition, so take the
		# rate from the orbit rather than from a literal. Writing it out would
		# need 17 significant digits, which Godot's float parser rounds
		# differently than Python's — and this value moves the surface a lander
		# is aiming at.
		if bool(d.get("tidally_locked", false)):
			b.rotation_rate = b.orbit_mean_motion
		# Hill sphere: a * (m/M)^(2/5).
		b.soi_radius = b.orbit_radius * DetMath.pow(b.mu / primary_mu, 0.4)
	else:
		b.orbit_mean_motion = 0.0
		b.soi_radius = INF

	var atmo: Dictionary = d.get("atmosphere", {})
	if not atmo.is_empty():
		b.atmo_height = float(atmo.get("height", 0.0))
		b.atmo_sea_level_density = float(atmo.get("sea_level_density", 0.0))
		b.atmo_scale_height = maxf(1.0, float(atmo.get("scale_height", 1.0)))

	if d.has("color"):
		b.color = Color(String(d["color"]))
	return b
