class_name ShipProfile
extends RefCounted

## The physical summary of a ship: everything the integrator needs, and nothing
## about how the ship was assembled.
##
## The ship editor turns a grid of parts into one of these. Keeping the boundary
## here means the physics has no opinion about parts, and the editor has no
## opinion about integration — and it lets tests fly a bare profile without
## constructing a plausible ship.

const G0 := 9.80665  ## Standard gravity, only ever used to convert Isp to exhaust velocity.

var display_name: String = "Unnamed"

## Mass of everything that is not propellant, in kg.
var dry_mass: float = 1000.0

## Propellant capacity, in kg.
var fuel_capacity: float = 0.0

## Combined thrust of all engines at full throttle, in newtons.
var max_thrust: float = 0.0

## Specific impulse in seconds; sets propellant efficiency.
var isp: float = 1.0

## Peak torque the reaction wheels can produce, in N*m.
var max_torque: float = 0.0

## Moment of inertia about the centre of mass, in kg*m^2.
var inertia: float = 1.0

## Drag coefficient and reference area, for the atmosphere model.
var drag_coefficient: float = 0.8
var drag_area: float = 4.0

## Touchdown speed the landing gear survives, in m/s. Zero means no gear.
var max_landing_speed: float = 0.0


func wet_mass() -> float:
	return dry_mass + fuel_capacity


## Exhaust velocity, m/s.
func exhaust_velocity() -> float:
	return isp * G0


## Propellant mass flow at full throttle, kg/s. Zero for an unpowered ship.
func mass_flow() -> float:
	var ve := exhaust_velocity()
	if ve <= 0.0 or max_thrust <= 0.0:
		return 0.0
	return max_thrust / ve


## Tsiolkovsky delta-v for a given propellant load, m/s.
func delta_v(fuel: float = -1.0) -> float:
	var f := fuel_capacity if fuel < 0.0 else fuel
	if f <= 0.0 or max_thrust <= 0.0:
		return 0.0
	var m0 := dry_mass + f
	if dry_mass <= 0.0 or m0 <= dry_mass:
		return 0.0
	return exhaust_velocity() * DetMath.log(m0 / dry_mass)


## Burn time available at full throttle, in seconds.
func burn_time(fuel: float = -1.0) -> float:
	var f := fuel_capacity if fuel < 0.0 else fuel
	var mdot := mass_flow()
	if mdot <= 0.0:
		return 0.0
	return f / mdot


## Thrust-to-weight ratio against a given surface gravity.
func twr(surface_gravity: float, fuel: float = -1.0) -> float:
	var f := fuel_capacity if fuel < 0.0 else fuel
	var w := (dry_mass + f) * surface_gravity
	if w <= 0.0:
		return 0.0
	return max_thrust / w


func duplicate_profile() -> ShipProfile:
	var p := ShipProfile.new()
	p.display_name = display_name
	p.dry_mass = dry_mass
	p.fuel_capacity = fuel_capacity
	p.max_thrust = max_thrust
	p.isp = isp
	p.max_torque = max_torque
	p.inertia = inertia
	p.drag_coefficient = drag_coefficient
	p.drag_area = drag_area
	p.max_landing_speed = max_landing_speed
	return p


func to_dict() -> Dictionary:
	return {
		"display_name": display_name,
		"dry_mass": dry_mass,
		"fuel_capacity": fuel_capacity,
		"max_thrust": max_thrust,
		"isp": isp,
		"max_torque": max_torque,
		"inertia": inertia,
		"drag_coefficient": drag_coefficient,
		"drag_area": drag_area,
		"max_landing_speed": max_landing_speed,
	}


static func from_dict(d: Dictionary) -> ShipProfile:
	var p := ShipProfile.new()
	p.display_name = String(d.get("display_name", "Unnamed"))
	p.dry_mass = float(d.get("dry_mass", 1000.0))
	p.fuel_capacity = float(d.get("fuel_capacity", 0.0))
	p.max_thrust = float(d.get("max_thrust", 0.0))
	p.isp = float(d.get("isp", 1.0))
	p.max_torque = float(d.get("max_torque", 0.0))
	p.inertia = maxf(0.001, float(d.get("inertia", 1.0)))
	p.drag_coefficient = float(d.get("drag_coefficient", 0.8))
	p.drag_area = float(d.get("drag_area", 4.0))
	p.max_landing_speed = float(d.get("max_landing_speed", 0.0))
	return p
