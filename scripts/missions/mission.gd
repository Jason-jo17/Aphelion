class_name Mission
extends RefCounted

## One handcrafted puzzle: a world, a starting state, what counts as winning,
## what counts as losing, and what a three-star solution looks like.

const DEFAULT_TIME_LIMIT := 14400.0  ## four hours of mission time

var id: String = ""
var title: String = ""
var order: int = 0
var brief: String = ""
var teaches: String = ""
var hints: PackedStringArray = PackedStringArray()

var primary_id: String = "halcyon"
var body_ids: PackedStringArray = PackedStringArray(["halcyon"])

## "stock" hands the player a ship; "custom" sends them to the editor first.
var ship_policy: String = "stock"
var stock_ship_id: String = "sparrow"

## Starting condition; see `initial_state()`.
var start: Dictionary = {}

var target_defs: Array = []
var active_target_id: String = ""

var time_limit: float = DEFAULT_TIME_LIMIT

var success: Predicate = null
var failures: Array[Dictionary] = []  ## {predicate: Predicate, message: String}

## Thresholds for the three stars. A metric at or below its threshold earns one.
var star_fuel: float = INF
var star_time: float = INF
var star_instructions: int = 1 << 30

## Populated at load time; a mission with errors is listed but not playable.
var errors: Array[String] = []

## Starting propellant as a fraction of capacity, for missions that begin
## mid-flight with partly empty tanks.
var start_fuel_fraction: float = 1.0


func ok() -> bool:
	return errors.is_empty() and success != null


## The smallest `sustain` window anywhere in the success predicate, or INF.
## The runner uses this to cap how far it may fast-forward, so a "hold this for
## ten seconds" objective cannot be satisfied by one enormous step.
func min_sustain_seconds() -> float:
	return _min_sustain(success)


static func _min_sustain(p: Predicate) -> float:
	if p == null:
		return INF
	var best := INF
	if p.kind == Predicate.Kind.SUSTAIN and p.sustain_seconds > 0.0:
		best = p.sustain_seconds
	for c in p.children:
		best = minf(best, _min_sustain(c))
	return best


## Builds this mission's world from the shared universe definition.
func build_world(universe: Dictionary) -> SimWorld:
	var world := SimWorld.new()
	var templates := {}
	for b in universe.get("bodies", []):
		templates[String(b.get("id", ""))] = b

	# The primary must be index 0: everything else orbits it, and SOI fallback
	# assumes it.
	var primary_dict: Dictionary = templates.get(primary_id, {})
	if primary_dict.is_empty():
		errors.append("Mission '%s' names an unknown primary body '%s'." % [id, primary_id])
		return world
	var primary := CelestialBody.from_dict(primary_dict, 0.0)
	world.add_body(primary)

	for bid in body_ids:
		if bid == primary_id:
			continue
		if not templates.has(bid):
			errors.append("Mission '%s' names an unknown body '%s'." % [id, bid])
			continue
		world.add_body(CelestialBody.from_dict(templates[bid], primary.mu))

	for td in target_defs:
		var parent_id := String(td.get("body", primary_id))
		var pi := world.body_index_by_id(parent_id)
		if pi < 0:
			errors.append(
				(
					"Target '%s' orbits '%s', which this mission does not include."
					% [String(td.get("id", "?")), parent_id]
				)
			)
			continue
		world.targets.append(OrbitTarget.from_dict(td, world.bodies[pi], pi))

	return world


## Index into `world.targets` of the target this mission's TGT* sensors read,
## or -1 when the mission has no target.
func active_target_index(world: SimWorld) -> int:
	if active_target_id.is_empty():
		return 0 if world.targets.size() == 1 else -1
	for i in world.targets.size():
		if world.targets[i].id == active_target_id:
			return i
	return -1


## The ship's state at T+0.
##
## Three shapes of start are supported. `surface` puts the ship on the pad,
## already turning with the body. `orbit` places it on a conic given by its
## apsides and where along that conic it is. `state` takes raw numbers, for
## fixtures and for missions that want something awkward.
func initial_state(world: SimWorld, profile: ShipProfile) -> ShipState:
	var st := ShipState.new()
	st.fuel = profile.fuel_capacity * clampf(start_fuel_fraction, 0.0, 1.0)

	var kind := String(start.get("kind", "surface"))
	var body_id := String(start.get("body", primary_id))
	var bi := world.body_index_by_id(body_id)
	if bi < 0:
		bi = 0
	var body := world.bodies[bi]
	var bx := body.pos_x(0.0)
	var by := body.pos_y(0.0)

	match kind:
		"state":
			st.px = float(start.get("px", 0.0))
			st.py = float(start.get("py", 0.0))
			st.vx = float(start.get("vx", 0.0))
			st.vy = float(start.get("vy", 0.0))
			st.angle = float(start.get("angle", 0.0))
			st.landed = bool(start.get("landed", false))

		"orbit":
			var peri_alt := float(start.get("periapsis", start.get("altitude", 100000.0)))
			var apo_alt := float(start.get("apoapsis", peri_alt))
			var nu := float(start.get("true_anomaly", 0.0)) * SensorBus.DEG_TO_RAD
			var arg := float(start.get("argument", 0.0)) * SensorBus.DEG_TO_RAD
			var dir := 1.0 if float(start.get("direction", 1.0)) >= 0.0 else -1.0

			var rp := body.radius + minf(peri_alt, apo_alt)
			var ra := body.radius + maxf(peri_alt, apo_alt)
			var a := 0.5 * (rp + ra)
			var e := 0.0 if ra + rp <= 0.0 else (ra - rp) / (ra + rp)
			var p := a * (1.0 - e * e)
			var r := p / (1.0 + e * DetMath.cos(nu))
			var theta := arg + nu

			var sc := DetMath.sincos(theta)
			var ux := sc[1]  # radial unit vector
			var uy := sc[0]
			var tx := -sc[0] * dir  # tangential unit vector, in the direction of travel
			var ty := sc[1] * dir

			var sqrt_mu_p := sqrt(body.mu / p) if p > 0.0 else 0.0
			var v_radial := sqrt_mu_p * e * DetMath.sin(nu)
			var v_tangential := sqrt_mu_p * (1.0 + e * DetMath.cos(nu))

			st.px = bx + r * ux
			st.py = by + r * uy
			st.vx = body.vel_x(0.0) + v_radial * ux + v_tangential * tx
			st.vy = body.vel_y(0.0) + v_radial * uy + v_tangential * ty
			# Start pointing prograde, which is where most programs want to be.
			st.angle = DetMath.atan2(st.vy - body.vel_y(0.0), st.vx - body.vel_x(0.0))

		_:  # "surface"
			var ang := float(start.get("surface_angle", 0.0)) * SensorBus.DEG_TO_RAD
			var sc2 := DetMath.sincos(ang)
			st.px = bx + body.radius * sc2[1]
			st.py = by + body.radius * sc2[0]
			# Standing on a rotating body means already moving with it.
			st.vx = body.vel_x(0.0) + body.surface_vel_x(body.radius * sc2[1], body.radius * sc2[0])
			st.vy = body.vel_y(0.0) + body.surface_vel_y(body.radius * sc2[1], body.radius * sc2[0])
			st.angle = ang  # nose up
			st.landed = true

	st.soi_index = world.dominant_body_index(0.0, st.px, st.py)
	return st


# --- loading ---------------------------------------------------------------


static func from_dict(d: Dictionary) -> Mission:
	var m := Mission.new()
	m.id = String(d.get("id", ""))
	m.title = String(d.get("title", m.id))
	m.order = int(d.get("order", 0))
	m.brief = String(d.get("brief", ""))
	m.teaches = String(d.get("teaches", ""))
	for h in d.get("hints", []):
		m.hints.append(String(h))

	m.primary_id = String(d.get("primary", "halcyon"))
	var bodies: Array = d.get("bodies", [m.primary_id])
	m.body_ids = PackedStringArray()
	for b in bodies:
		m.body_ids.append(String(b))
	if not m.body_ids.has(m.primary_id):
		m.body_ids.append(m.primary_id)

	var ship: Dictionary = d.get("ship", {})
	m.ship_policy = String(ship.get("policy", "stock"))
	m.stock_ship_id = String(ship.get("id", "sparrow"))
	m.start_fuel_fraction = float(ship.get("fuel_fraction", 1.0))

	m.start = d.get("start", {})
	m.target_defs = d.get("targets", [])
	m.active_target_id = String(d.get("active_target", ""))
	m.time_limit = float(d.get("time_limit", DEFAULT_TIME_LIMIT))

	if d.has("success"):
		m.success = Predicate.from_dict(d["success"], m.errors)
	else:
		m.errors.append("Mission '%s' has no success predicate." % m.id)

	for f in d.get("failure", []):
		var fd: Dictionary = f
		(
			m
			. failures
			. append(
				{
					"predicate": Predicate.from_dict(fd.get("when", {}), m.errors),
					"message": String(fd.get("message", "Mission failed.")),
				}
			)
		)

	var stars: Dictionary = d.get("stars", {})
	m.star_fuel = float(stars.get("fuel", INF))
	m.star_time = float(stars.get("time", INF))
	m.star_instructions = int(stars.get("instructions", 1 << 30))

	if m.id.is_empty():
		m.errors.append("A mission has no id.")
	return m


## Resets every stateful predicate. Must be called before each run.
func reset_predicates() -> void:
	if success != null:
		success.reset()
	for f in failures:
		f["predicate"].reset()


## Objective lines for the briefing and the in-flight panel, derived from the
## predicate rather than written twice.
func objective_lines() -> PackedStringArray:
	var out := PackedStringArray()
	if success == null:
		return out
	for part in success.parts():
		out.append(part.describe())
	return out
