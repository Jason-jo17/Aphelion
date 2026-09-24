class_name SensorBus
extends RefCounted

## Presents the simulation to the flight computer.
##
## The VM never touches ShipState or SimWorld directly. Everything it can know
## comes through here, in the units the ISA documents — which means **degrees**
## for every angle, because writing a gravity turn in radians is nobody's idea
## of a good time.
##
## Values are computed once per tick and cached. A program that reads APO five
## times in one tick reads the same number five times, which is both faster and
## less surprising than re-deriving it mid-instruction.

const RAD_TO_DEG := 57.295779513082320876798154814105
const DEG_TO_RAD := 0.01745329251994329576923690768489

var world: SimWorld = null
var profile: ShipProfile = null

## Index into world.targets of the rendezvous target this mission cares about,
## or -1 when there is none.
var target_index: int = -1

var _state: ShipState = null
var _t: float = 0.0
var _soi: int = 0
var _body: CelestialBody = null
var _elems: Dictionary = {}
var _rx: float = 0.0
var _ry: float = 0.0
var _rvx: float = 0.0
var _rvy: float = 0.0
var _radius: float = 0.0
var _throttle: float = 0.0


func _init(w: SimWorld = null, p: ShipProfile = null) -> void:
	world = w
	profile = p


## Recomputes the cached view. Called once per simulation step, before the VM.
func begin_tick(state: ShipState, throttle: float) -> void:
	_state = state
	_throttle = throttle
	_t = SimWorld.time_for_tick(state.tick)
	_soi = world.dominant_body_index(_t, state.px, state.py)
	_body = world.bodies[_soi]
	state.soi_index = _soi

	_rx = state.px - _body.pos_x(_t)
	_ry = state.py - _body.pos_y(_t)
	_rvx = state.vx - _body.vel_x(_t)
	_rvy = state.vy - _body.vel_y(_t)
	_radius = DetMath.hypot(_rx, _ry)
	_elems = Orbital.elements(_body.mu, _rx, _ry, _rvx, _rvy)


func body() -> CelestialBody:
	return _body


func soi_index() -> int:
	return _soi


func elements() -> Dictionary:
	return _elems


func altitude() -> float:
	return _radius - _body.radius


## Heading of the prograde vector, in radians. The attitude controller works in
## radians; only `read()` converts to degrees.
func prograde_rad() -> float:
	if _rvx == 0.0 and _rvy == 0.0:
		return _state.angle
	return DetMath.atan2(_rvy, _rvx)


func radial_rad() -> float:
	if _rx == 0.0 and _ry == 0.0:
		return _state.angle
	return DetMath.atan2(_ry, _rx)


func target_rad() -> float:
	if target_index < 0 or target_index >= world.targets.size():
		return _state.angle
	var tg := world.targets[target_index]
	var parent := world.bodies[tg.parent_index]
	var tx := parent.pos_x(_t) + tg.rel_x(_t)
	var ty := parent.pos_y(_t) + tg.rel_y(_t)
	var dx := tx - _state.px
	var dy := ty - _state.py
	if dx == 0.0 and dy == 0.0:
		return _state.angle
	return DetMath.atan2(dy, dx)


## Distance and relative speed to the active target.
func target_distance() -> float:
	if target_index < 0 or target_index >= world.targets.size():
		return INF
	var tg := world.targets[target_index]
	var parent := world.bodies[tg.parent_index]
	var dx := parent.pos_x(_t) + tg.rel_x(_t) - _state.px
	var dy := parent.pos_y(_t) + tg.rel_y(_t) - _state.py
	return DetMath.hypot(dx, dy)


func target_relative_speed() -> float:
	if target_index < 0 or target_index >= world.targets.size():
		return INF
	var tg := world.targets[target_index]
	var parent := world.bodies[tg.parent_index]
	var dvx := parent.vel_x(_t) + tg.rel_vx(_t) - _state.vx
	var dvy := parent.vel_y(_t) + tg.rel_vy(_t) - _state.vy
	return DetMath.hypot(dvx, dvy)


## Reads a sensor, in the units docs/ISA.md documents.
func read(sensor: int) -> float:
	match sensor:
		ISA.Sensor.ALT:
			return altitude()
		ISA.Sensor.VEL:
			return DetMath.hypot(_rvx, _rvy)
		ISA.Sensor.VVEL:
			return float(_elems.get(Orbital.K_RADIAL_SPEED, 0.0))
		ISA.Sensor.HVEL:
			return absf(float(_elems.get(Orbital.K_TANGENTIAL_SPEED, 0.0)))
		ISA.Sensor.APO:
			var ap: float = _elems.get(Orbital.K_APOAPSIS, INF)
			return INF if is_inf(ap) else ap - _body.radius
		ISA.Sensor.PERI:
			return float(_elems.get(Orbital.K_PERIAPSIS, 0.0)) - _body.radius
		ISA.Sensor.ECC:
			return float(_elems.get(Orbital.K_ECC, 0.0))
		ISA.Sensor.SMA:
			return float(_elems.get(Orbital.K_SMA, 0.0))
		ISA.Sensor.TAPO:
			return float(_elems.get(Orbital.K_TIME_TO_APO, INF))
		ISA.Sensor.TPERI:
			return float(_elems.get(Orbital.K_TIME_TO_PERI, INF))
		ISA.Sensor.HDG:
			return _to_compass(_state.angle)
		ISA.Sensor.PRO:
			return _to_compass(prograde_rad())
		ISA.Sensor.RETRO:
			return _to_compass(prograde_rad() + DetMath.PI_D)
		ISA.Sensor.RAD:
			return _to_compass(radial_rad())
		ISA.Sensor.ANTIRAD:
			return _to_compass(radial_rad() + DetMath.PI_D)
		ISA.Sensor.PITCH:
			return DetMath.angle_delta(_state.angle, prograde_rad()) * RAD_TO_DEG
		ISA.Sensor.FUEL:
			return _state.fuel
		ISA.Sensor.MASS:
			return profile.dry_mass + _state.fuel
		ISA.Sensor.DV:
			return profile.delta_v(_state.fuel)
		ISA.Sensor.TWR:
			var g := local_gravity()
			var m := profile.dry_mass + _state.fuel
			return 0.0 if (g <= 0.0 or m <= 0.0) else profile.max_thrust / (m * g)
		ISA.Sensor.THR:
			return _throttle
		ISA.Sensor.GRAV:
			return local_gravity()
		ISA.Sensor.DENS:
			return _body.density_at_altitude(altitude())
		ISA.Sensor.Q:
			return dynamic_pressure()
		ISA.Sensor.T:
			return _t
		ISA.Sensor.SOI:
			return float(_soi)
		ISA.Sensor.LANDED:
			return 1.0 if _state.landed else 0.0
		ISA.Sensor.TGTD:
			return target_distance()
		ISA.Sensor.TGTV:
			return target_relative_speed()
		ISA.Sensor.TGTA:
			return _to_compass(target_rad())
	return 0.0


func local_gravity() -> float:
	if _radius <= 0.0:
		return 0.0
	return _body.mu / (_radius * _radius)


func dynamic_pressure() -> float:
	var rho := _body.density_at_altitude(altitude())
	if rho <= 0.0:
		return 0.0
	var avx := _body.vel_x(_t) + _body.surface_vel_x(_rx, _ry)
	var avy := _body.vel_y(_t) + _body.surface_vel_y(_rx, _ry)
	var sp := DetMath.hypot(_state.vx - avx, _state.vy - avy)
	return 0.5 * rho * sp * sp


## Radians in (-pi, pi] -> degrees in [0, 360).
static func _to_compass(rad: float) -> float:
	return DetMath.wrap_tau(rad) * RAD_TO_DEG
