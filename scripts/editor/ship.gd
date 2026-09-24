class_name Ship
extends RefCounted

## A ship as the player assembles it: parts placed on a grid.
##
## The editor's job is to turn this into a ShipProfile, which is all the
## simulation ever sees. Everything derived here — mass, thrust, effective Isp,
## moment of inertia — is recomputed from scratch on every change, so the
## numbers on screen can never lag the ship in front of them.

const GRID_CELL := 1.0  ## metres per cell; overridden by the catalogue

## Drag coefficient, shared by every ship.
##
## Aphelion is two-dimensional and has no notion of nose cones or fairings, so
## modelling per-part drag shapes would be inventing detail the player cannot
## see or act on. Instead every hull gets the same blunt-body coefficient and
## the *area* carries all the meaning: a wide ship catches more air than a
## narrow one, and a heat shield adds area on purpose.
const DRAG_COEFFICIENT := 0.35

## Assumed hull depth, metres. The sim is 2D; frontal area is width * depth.
const HULL_DEPTH := 1.0

## Severity levels used by validate().
const LEVEL_ERROR := "error"  ## cannot fly
const LEVEL_WARNING := "warning"  ## will fly, probably badly
const LEVEL_INFO := "info"  ## worth knowing for some missions

var display_name: String = "Untitled"

## Placed parts, each a Dictionary {"part_id": String, "x": int, "y": int}.
## `x, y` is the top-left cell of the part's footprint.
var placements: Array[Dictionary] = []

var catalog: PartCatalog = null


func _init(cat: PartCatalog = null) -> void:
	catalog = cat if cat != null else PartCatalog.shared()


# --- assembly --------------------------------------------------------------


## Can `part_id` sit with its top-left corner at (x, y)?
## Returns "" if it can, or a human-readable reason if it cannot.
func placement_blocked_reason(part_id: String, x: int, y: int, ignore_index: int = -1) -> String:
	var def := catalog.get_part(part_id)
	if def == null:
		return "Unknown part '%s'." % part_id
	if (
		x < 0
		or y < 0
		or x + def.size_w > catalog.grid_width
		or y + def.size_h > catalog.grid_height
	):
		return "That does not fit inside the assembly bay."
	var occ := _occupancy(ignore_index)
	for dx in def.size_w:
		for dy in def.size_h:
			var key := Vector2i(x + dx, y + dy)
			if occ.has(key):
				var other: PartDef = catalog.get_part(placements[occ[key]]["part_id"])
				var other_name: String = other.display_name if other != null else "another part"
				return "Overlaps %s." % other_name
	return ""


func can_place(part_id: String, x: int, y: int, ignore_index: int = -1) -> bool:
	return placement_blocked_reason(part_id, x, y, ignore_index).is_empty()


## Adds a part. Returns its index, or -1 if it would not fit.
func place(part_id: String, x: int, y: int) -> int:
	if not can_place(part_id, x, y):
		return -1
	placements.append({"part_id": part_id, "x": x, "y": y})
	return placements.size() - 1


func remove_at_index(index: int) -> bool:
	if index < 0 or index >= placements.size():
		return false
	placements.remove_at(index)
	return true


## Index of the part covering cell (x, y), or -1.
func index_at_cell(x: int, y: int) -> int:
	return _occupancy().get(Vector2i(x, y), -1)


func move(index: int, x: int, y: int) -> bool:
	if index < 0 or index >= placements.size():
		return false
	var pid: String = placements[index]["part_id"]
	if not can_place(pid, x, y, index):
		return false
	placements[index]["x"] = x
	placements[index]["y"] = y
	return true


func clear() -> void:
	placements.clear()


func part_def_at(index: int) -> PartDef:
	if index < 0 or index >= placements.size():
		return null
	return catalog.get_part(placements[index]["part_id"])


# --- derived physical properties -------------------------------------------


## Everything the simulation needs, computed from the current assembly.
##
## A note on the moment of inertia: it is computed once, with full tanks, and
## held constant for the flight. Real propellant shifts the centre of mass as it
## drains; modelling that would make a ship's handling change mid-burn in a way
## the player has no instrument to observe, and would buy nothing for the
## puzzles. The simplification is deliberate and is documented in the manual.
func to_profile() -> ShipProfile:
	var prof := ShipProfile.new()
	prof.display_name = display_name

	var dry := 0.0
	var fuel := 0.0
	var thrust := 0.0
	var flow := 0.0  # sum of thrust_i / isp_i, for the effective Isp
	var torque := 0.0
	var extra_drag := 0.0
	var landing := 0.0

	for i in placements.size():
		var def := part_def_at(i)
		if def == null:
			continue
		dry += def.mass
		fuel += def.fuel_capacity
		if def.thrust > 0.0 and def.isp > 0.0:
			thrust += def.thrust
			flow += def.thrust / def.isp
		torque += def.torque
		extra_drag += def.extra_drag_area
		landing = maxf(landing, def.max_landing_speed)

	prof.dry_mass = dry
	prof.fuel_capacity = fuel
	prof.max_thrust = thrust
	# Mixing engines gives a thrust-weighted harmonic mean of their Isp, which
	# is what you get when they all burn from the same tanks at once.
	prof.isp = (thrust / flow) if flow > 0.0 else 0.0
	prof.max_torque = torque
	prof.drag_coefficient = DRAG_COEFFICIENT
	prof.drag_area = maxf(0.5, frontal_width() * HULL_DEPTH + extra_drag)
	prof.max_landing_speed = landing
	prof.inertia = maxf(1.0, moment_of_inertia())
	return prof


## Width of the ship's footprint in metres — the frontal area the atmosphere
## sees. Narrow rockets are draggier per kilogram but cheaper to push.
func frontal_width() -> float:
	if placements.is_empty():
		return 0.0
	var lo := 1 << 30
	var hi := -(1 << 30)
	for i in placements.size():
		var def := part_def_at(i)
		if def == null:
			continue
		var x: int = placements[i]["x"]
		lo = mini(lo, x)
		hi = maxi(hi, x + def.size_w)
	if hi <= lo:
		return 0.0
	return float(hi - lo) * catalog.cell_size


## Centre of mass with full tanks, in metres, in grid coordinates
## (+x right, +y down), as [x, y]. Empty ship gives [0, 0].
##
## Returns doubles, not a Vector2. Vector2 is single-precision in standard
## Godot builds, and this value feeds the moment of inertia, which sets how the
## ship turns, which changes where it ends up — so a 32-bit rounding here would
## put single precision directly into the trajectory. docs/DETERMINISM.md rule 5.
## The conversion to Vector2 happens in the editor's drawing code and nowhere
## else.
func centre_of_mass() -> PackedFloat64Array:
	var cell := catalog.cell_size
	var total := 0.0
	var cx := 0.0
	var cy := 0.0
	for i in placements.size():
		var def := part_def_at(i)
		if def == null:
			continue
		var m := def.mass + def.fuel_capacity
		if m <= 0.0:
			continue
		var p: Dictionary = placements[i]
		var px := (float(p["x"]) + float(def.size_w) * 0.5) * cell
		var py := (float(p["y"]) + float(def.size_h) * 0.5) * cell
		cx += m * px
		cy += m * py
		total += m
	if total <= 0.0:
		return PackedFloat64Array([0.0, 0.0])
	return PackedFloat64Array([cx / total, cy / total])


## Moment of inertia about the centre of mass, kg*m^2.
## Each part contributes its own rectangular inertia plus the parallel-axis term.
func moment_of_inertia() -> float:
	var cell := catalog.cell_size
	var com := centre_of_mass()
	var total := 0.0
	for i in placements.size():
		var def := part_def_at(i)
		if def == null:
			continue
		var m := def.mass + def.fuel_capacity
		if m <= 0.0:
			continue
		var p: Dictionary = placements[i]
		var w := float(def.size_w) * cell
		var hgt := float(def.size_h) * cell
		var px := (float(p["x"]) + float(def.size_w) * 0.5) * cell
		var py := (float(p["y"]) + float(def.size_h) * 0.5) * cell
		var own := m * (w * w + hgt * hgt) / 12.0
		var dx := px - com[0]
		var dy := py - com[1]
		total += own + m * (dx * dx + dy * dy)
	return total


## Delta-v with full tanks, m/s.
func delta_v() -> float:
	return to_profile().delta_v()


## Thrust-to-weight ratio on a given body's surface, full tanks.
func twr(surface_gravity: float) -> float:
	return to_profile().twr(surface_gravity)


func part_count() -> int:
	return placements.size()


# --- validation ------------------------------------------------------------


## Checks the assembly and returns a list of findings, most severe first.
##
## Every finding carries a hint, because "invalid ship" on its own teaches
## nothing — AC5 asks for the hint specifically.
func validate() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var prof := to_profile()

	var commands := 0
	var engines := 0
	var wheels := 0
	var legs := 0
	for i in placements.size():
		var def := part_def_at(i)
		if def == null:
			continue
		if def.is_command:
			commands += 1
		if def.is_engine():
			engines += 1
		if def.torque > 0.0:
			wheels += 1
		if def.max_landing_speed > 0.0:
			legs += 1

	if placements.is_empty():
		out.append(
			_finding(
				LEVEL_ERROR,
				"empty",
				"There is no ship yet.",
				"Start with a Corvid Mk1 Capsule, then hang a tank and an engine below it."
			)
		)
		return out

	if commands == 0:
		(
			out
			. append(
				_finding(
					LEVEL_ERROR,
					"no_command",
					"No command part.",
					"Add a Corvid Mk1 Capsule or a Wren Probe Core — something has to run the flight computer."
				)
			)
		)
	elif commands > 1:
		out.append(
			_finding(
				LEVEL_ERROR,
				"multiple_command",
				"%d command parts." % commands,
				"A ship takes exactly one flight computer. Remove the extras."
			)
		)

	if engines == 0:
		out.append(
			_finding(
				LEVEL_ERROR,
				"no_engine",
				"No engine.",
				"Without thrust this ship cannot change its own orbit. Add a Kestrel Booster."
			)
		)
	elif prof.fuel_capacity <= 0.0:
		out.append(
			_finding(
				LEVEL_ERROR,
				"no_fuel",
				"Engines, but no propellant.",
				"Add a fuel tank. Delta-v is currently zero, so BURN would do nothing."
			)
		)

	var loose := disconnected_indices()
	if not loose.is_empty():
		(
			out
			. append(
				_finding(
					LEVEL_ERROR,
					"disconnected",
					(
						"%d part%s not attached to the ship."
						% [loose.size(), "" if loose.size() == 1 else "s"]
					),
					"Every part must touch the command part through its neighbours. Drag the floating pieces back."
				)
			)
		)

	if wheels == 0 and engines > 0:
		(
			out
			. append(
				_finding(
					LEVEL_WARNING,
					"no_wheel",
					"No reaction wheel.",
					"ORIENT will have nothing to turn the ship with, so your heading is frozen wherever it starts."
				)
			)
		)

	if prof.max_thrust > 0.0:
		var t := prof.twr(9.0)
		if t < 1.0:
			(
				out
				. append(
					_finding(
						LEVEL_WARNING,
						"low_twr",
						"Thrust-to-weight on Halcyon is %.2f." % t,
						"Below 1.0 the ship cannot lift off. It is fine for a ship that starts in orbit."
					)
				)
			)

	if legs == 0:
		out.append(
			_finding(
				LEVEL_INFO,
				"no_legs",
				"No landing legs.",
				"Any surface contact counts as a crash. Landing missions will need a pair."
			)
		)

	return out


func is_flyable() -> bool:
	for f in validate():
		if f["level"] == LEVEL_ERROR:
			return false
	return true


## Indices of parts that cannot be reached from the command part by stepping
## between edge-adjacent cells.
func disconnected_indices() -> Array[int]:
	var out: Array[int] = []
	if placements.is_empty():
		return out

	var root := -1
	for i in placements.size():
		var def := part_def_at(i)
		if def != null and def.is_command:
			root = i
			break
	if root < 0:
		return out  # reported separately as no_command

	var occ := _occupancy()
	var seen := {root: true}
	var queue: Array[int] = [root]
	while not queue.is_empty():
		var idx: int = queue.pop_front()
		for neighbour in _neighbours_of(idx, occ):
			if not seen.has(neighbour):
				seen[neighbour] = true
				queue.append(neighbour)

	for i in placements.size():
		if not seen.has(i):
			out.append(i)
	return out


func _neighbours_of(index: int, occ: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var def := part_def_at(index)
	if def == null:
		return out
	var p: Dictionary = placements[index]
	var x0: int = p["x"]
	var y0: int = p["y"]
	var found := {}
	for dx in def.size_w:
		for dy in def.size_h:
			var cx := x0 + dx
			var cy := y0 + dy
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var key := Vector2i(cx + step.x, cy + step.y)
				if occ.has(key):
					var other: int = occ[key]
					if other != index and not found.has(other):
						found[other] = true
						out.append(other)
	return out


## Maps every occupied cell to the index of the part covering it.
func _occupancy(ignore_index: int = -1) -> Dictionary:
	var occ := {}
	for i in placements.size():
		if i == ignore_index:
			continue
		var def := part_def_at(i)
		if def == null:
			continue
		var p: Dictionary = placements[i]
		for dx in def.size_w:
			for dy in def.size_h:
				occ[Vector2i(int(p["x"]) + dx, int(p["y"]) + dy)] = i
	return occ


static func _finding(level: String, code: String, message: String, hint: String) -> Dictionary:
	return {"level": level, "code": code, "message": message, "hint": hint}


# --- serialisation ---------------------------------------------------------


func to_dict() -> Dictionary:
	var pl: Array = []
	for p in placements:
		pl.append({"part_id": p["part_id"], "x": int(p["x"]), "y": int(p["y"])})
	return {"name": display_name, "placements": pl}


static func from_dict(d: Dictionary, cat: PartCatalog = null) -> Ship:
	var s := Ship.new(cat)
	s.display_name = String(d.get("name", "Untitled"))
	for entry in d.get("placements", []):
		(
			s
			. placements
			. append(
				{
					"part_id": String(entry.get("part_id", "")),
					"x": int(entry.get("x", 0)),
					"y": int(entry.get("y", 0)),
				}
			)
		)
	return s


## Stable content hash, used to tell whether a replay is flying the same ship.
## Placement order must not matter, so the entries are sorted first.
func content_hash() -> String:
	var keys: Array[String] = []
	for p in placements:
		keys.append("%s@%d,%d" % [p["part_id"], int(p["x"]), int(p["y"])])
	keys.sort()
	return String("|").join(keys).sha256_text().substr(0, 16)
