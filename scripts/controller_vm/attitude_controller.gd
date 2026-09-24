class_name AttitudeController
extends RefCounted

## Drives the reaction wheels toward an attitude goal.
##
## The goal is held continuously, on every tick, whatever else the program is
## doing — `ORIENT` and `POINT` differ only in whether the program waits for the
## goal to be reached. A goal of PROGRADE keeps tracking prograde as prograde
## moves, which is what makes a long burn hold its heading.
##
## The law is time-optimal bang-bang with a rate-nulling endgame:
##
## * far from the goal, apply full torque in whichever direction reduces the
##   error *after* accounting for the angle it will take to stop again;
## * inside the tolerance band, apply exactly the torque that brings the
##   angular rate to zero this tick.
##
## The endgame matters. Under constant torque the rotational dynamics have an
## exact closed form, so `-w / (alpha * dt)` nulls the rate precisely rather than
## asymptotically, and the ship settles instead of hunting. Residual pointing
## error is bounded by `alpha * dt^2 / 2` — about 0.004 degrees for the stock
## ships, far inside the 0.5 degree default tolerance.

const DEFAULT_TOLERANCE_DEG := 0.5

## An ORIENT that has not converged in this long is not going to. Bounded so a
## goal that cannot be reached surfaces as a fault instead of hanging the run.
const CONVERGENCE_TIMEOUT := 300.0

## Rate below which the ship counts as stopped, rad/s.
const RATE_EPSILON := 1.0e-6

var goal_kind: int = ISA.Goal.ABSOLUTE
var goal_angle: float = 0.0          ## radians, used when goal_kind is ABSOLUTE
var tolerance: float = DEFAULT_TOLERANCE_DEG * SensorBus.DEG_TO_RAD

## True once a goal has been set; before that the wheels stay idle.
var active: bool = false


func set_goal(kind: int, angle_rad: float = 0.0) -> void:
	goal_kind = kind
	goal_angle = angle_rad
	active = true


func set_tolerance_deg(deg: float) -> void:
	tolerance = maxf(0.01, absf(deg)) * SensorBus.DEG_TO_RAD


## Where the wheels are currently trying to point, in radians.
func desired_heading(bus: SensorBus) -> float:
	match goal_kind:
		ISA.Goal.PROGRADE:
			return bus.prograde_rad()
		ISA.Goal.RETROGRADE:
			return bus.prograde_rad() + DetMath.PI_D
		ISA.Goal.RADIAL:
			return bus.radial_rad()
		ISA.Goal.ANTIRADIAL:
			return bus.radial_rad() + DetMath.PI_D
		ISA.Goal.TARGET:
			return bus.target_rad()
		_:
			return goal_angle


## Signed error from where the ship points to where it should, in radians.
func error(state: ShipState, bus: SensorBus) -> float:
	return DetMath.angle_delta(state.angle, desired_heading(bus))


## Torque command in [-1, 1] for the coming step.
func torque_for(state: ShipState, profile: ShipProfile, bus: SensorBus, dt: float) -> float:
	if not active:
		return 0.0
	var alpha := angular_authority(profile)
	if alpha <= 0.0 or dt <= 0.0:
		return 0.0

	var err := error(state, bus)
	var w := state.ang_vel

	if absf(err) <= tolerance:
		# Endgame: null the rate exactly. If one tick of full torque is not
		# enough, give it full torque and finish next tick.
		return clampf(-w / (alpha * dt), -1.0, 1.0)

	# The angle it will take to stop if we start braking now.
	var stop := (w * w) / (2.0 * alpha)
	var residual := err
	if w > 0.0:
		residual = err - stop
	elif w < 0.0:
		residual = err + stop

	if residual > 0.0:
		return 1.0
	if residual < 0.0:
		return -1.0
	return 0.0


func at_goal(state: ShipState, bus: SensorBus) -> bool:
	if not active:
		return true
	return absf(error(state, bus)) <= tolerance and absf(state.ang_vel) <= RATE_EPSILON


## Peak angular acceleration the ship can produce, rad/s^2.
static func angular_authority(profile: ShipProfile) -> float:
	if profile.inertia <= 0.0:
		return 0.0
	return profile.max_torque / profile.inertia


## Seconds to slew through `angle_rad` under bang-bang control, ignoring the
## starting rate. Used by the UI to preview a turn, not by the controller.
static func slew_time(profile: ShipProfile, angle_rad: float) -> float:
	var alpha := angular_authority(profile)
	if alpha <= 0.0:
		return INF
	return 2.0 * sqrt(absf(angle_rad) / alpha)


func reset() -> void:
	active = false
	goal_kind = ISA.Goal.ABSOLUTE
	goal_angle = 0.0
	tolerance = DEFAULT_TOLERANCE_DEG * SensorBus.DEG_TO_RAD
