class_name OrbitTarget
extends RefCounted

## A rendezvous target — a station, a derelict, a supply pod.
##
## Like moons, targets ride a prescribed circular orbit rather than being
## integrated. A rendezvous mission is about flying *your* ship precisely, and a
## target whose position is a closed-form function of time is one that can never
## drift out from under a solution that used to work.

var id: String = ""
var display_name: String = ""

## Index into SimWorld.bodies of the body this target orbits.
var parent_index: int = 0

var orbit_radius: float = 0.0
var orbit_phase0: float = 0.0
var orbit_mean_motion: float = 0.0

var color: Color = Color(0.95, 0.72, 0.30)

var _memo_t: float = NAN
var _rel_x: float = 0.0
var _rel_y: float = 0.0
var _rel_vx: float = 0.0
var _rel_vy: float = 0.0


func _eval(t: float) -> void:
	if t == _memo_t:
		return
	var sc := DetMath.sincos(orbit_phase0 + orbit_mean_motion * t)
	_rel_x = orbit_radius * sc[1]
	_rel_y = orbit_radius * sc[0]
	_rel_vx = -orbit_radius * orbit_mean_motion * sc[0]
	_rel_vy = orbit_radius * orbit_mean_motion * sc[1]
	_memo_t = t


## Position relative to the parent body.
func rel_x(t: float) -> float:
	_eval(t)
	return _rel_x


func rel_y(t: float) -> float:
	_eval(t)
	return _rel_y


func rel_vx(t: float) -> float:
	_eval(t)
	return _rel_vx


func rel_vy(t: float) -> float:
	_eval(t)
	return _rel_vy


static func from_dict(d: Dictionary, parent: CelestialBody, parent_index: int) -> OrbitTarget:
	var o := OrbitTarget.new()
	o.id = String(d.get("id", "target"))
	o.display_name = String(d.get("name", o.id))
	o.parent_index = parent_index
	o.orbit_radius = float(d.get("orbit_radius", 0.0))
	o.orbit_phase0 = float(d.get("orbit_phase0", 0.0))
	if o.orbit_radius > 0.0 and parent != null and parent.mu > 0.0:
		var a3 := o.orbit_radius * o.orbit_radius * o.orbit_radius
		var dir := 1.0 if float(d.get("orbit_direction", 1.0)) >= 0.0 else -1.0
		o.orbit_mean_motion = sqrt(parent.mu / a3) * dir
	if d.has("color"):
		o.color = Color(String(d["color"]))
	return o
