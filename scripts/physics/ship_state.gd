class_name ShipState
extends RefCounted

## The complete dynamical state of the ship at one instant.
##
## Everything here is a double. Nothing here is a Vector2 — Godot's Vector2 is
## single-precision in standard builds, and 24 bits of mantissa is not enough to
## hold a position 7 000 km from the origin to sub-metre accuracy. Conversion to
## Vector2 happens at the rendering boundary and nowhere else.

## Ticks elapsed, in units of SimWorld.DT_BASE. Mission time is derived from
## this by multiplication, never by accumulation, so it cannot drift.
var tick: int = 0

var px: float = 0.0
var py: float = 0.0
var vx: float = 0.0
var vy: float = 0.0

## Heading in radians, measured counter-clockwise from +X. Thrust points along
## this direction.
var angle: float = 0.0
var ang_vel: float = 0.0

## Remaining propellant, kg.
var fuel: float = 0.0

## Terminal flags. A landed ship is frozen to the surface; a crashed one is
## simply over.
var landed: bool = false
var crashed: bool = false

## Which body the ship is currently bound to, as an index into SimWorld.bodies.
## Sensors that report orbital elements report them about this body.
var soi_index: int = 0


func mass(profile: ShipProfile) -> float:
	return profile.dry_mass + fuel


func speed() -> float:
	return DetMath.hypot(vx, vy)


func copy() -> ShipState:
	var s := ShipState.new()
	s.tick = tick
	s.px = px
	s.py = py
	s.vx = vx
	s.vy = vy
	s.angle = angle
	s.ang_vel = ang_vel
	s.fuel = fuel
	s.landed = landed
	s.crashed = crashed
	s.soi_index = soi_index
	return s


func copy_from(o: ShipState) -> void:
	tick = o.tick
	px = o.px
	py = o.py
	vx = o.vx
	vy = o.vy
	angle = o.angle
	ang_vel = o.ang_vel
	fuel = o.fuel
	landed = o.landed
	crashed = o.crashed
	soi_index = o.soi_index


func to_dict() -> Dictionary:
	return {
		"tick": tick,
		"px": px, "py": py, "vx": vx, "vy": vy,
		"angle": angle, "ang_vel": ang_vel,
		"fuel": fuel,
		"landed": landed, "crashed": crashed,
		"soi_index": soi_index,
	}


static func from_dict(d: Dictionary) -> ShipState:
	var s := ShipState.new()
	s.tick = int(d.get("tick", 0))
	s.px = float(d.get("px", 0.0))
	s.py = float(d.get("py", 0.0))
	s.vx = float(d.get("vx", 0.0))
	s.vy = float(d.get("vy", 0.0))
	s.angle = float(d.get("angle", 0.0))
	s.ang_vel = float(d.get("ang_vel", 0.0))
	s.fuel = float(d.get("fuel", 0.0))
	s.landed = bool(d.get("landed", false))
	s.crashed = bool(d.get("crashed", false))
	s.soi_index = int(d.get("soi_index", 0))
	return s
