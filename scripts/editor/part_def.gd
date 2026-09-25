class_name PartDef
extends RefCounted

## A catalogue entry: what a kind of part *is*, independent of any ship.
## Loaded once from data/parts.json and shared by every ship.

const CAT_COMMAND := "command"
const CAT_FUEL := "fuel"
const CAT_ENGINE := "engine"
const CAT_CONTROL := "control"
const CAT_STRUCTURE := "structure"

var id: String = ""
var display_name: String = ""
var category: String = CAT_STRUCTURE
var description: String = ""

## Footprint in grid cells, [width, height].
var size_w: int = 1
var size_h: int = 1

## Dry mass, kg.
var mass: float = 0.0

## Propellant this part carries when full, kg.
var fuel_capacity: float = 0.0

## Thrust at full throttle (N) and specific impulse (s).
var thrust: float = 0.0
var isp: float = 0.0

## Reaction-wheel authority, N*m.
var torque: float = 0.0

## Drag area this part adds *on top of* the hull frontal area, m^2. Only parts
## whose whole point is drag (a heat shield) carry this.
var extra_drag_area: float = 0.0

## Touchdown speed this part survives, m/s. Zero means it provides no gear.
var max_landing_speed: float = 0.0

## True for parts that can host the flight computer.
var is_command: bool = false

## Which silhouette the assembly bay draws this part with.
##
## Shape carries the meaning that colour cannot: every part used to be the same
## rectangle, so a capsule, a tank, an engine bell and a reaction wheel differed
## only by hue and two initials, and the three structural parts — a strut, an
## ablative shield and a set of landing legs — did not differ at all. A ship is
## something you look at to understand, so it has to look like the thing it is.
##
## Defaults from the category, which is right for command, fuel, engine and
## control. `structure` holds three unrelated objects, so those name a shape of
## their own in data/parts.json.
var shape: String = SHAPE_BEAM

const SHAPE_CAPSULE := "capsule"
const SHAPE_PROBE := "probe"
const SHAPE_TANK := "tank"
const SHAPE_ENGINE := "engine"
const SHAPE_WHEEL := "wheel"
const SHAPE_BEAM := "beam"
const SHAPE_SHIELD := "shield"
const SHAPE_LEGS := "legs"

const SHAPE_FOR_CATEGORY := {
	CAT_COMMAND: SHAPE_CAPSULE,
	CAT_FUEL: SHAPE_TANK,
	CAT_ENGINE: SHAPE_ENGINE,
	CAT_CONTROL: SHAPE_WHEEL,
	CAT_STRUCTURE: SHAPE_BEAM,
}


func cell_count() -> int:
	return size_w * size_h


func is_engine() -> bool:
	return thrust > 0.0


func is_tank() -> bool:
	return fuel_capacity > 0.0


static func from_dict(d: Dictionary) -> PartDef:
	var p := PartDef.new()
	p.id = String(d.get("id", ""))
	p.display_name = String(d.get("name", p.id))
	p.category = String(d.get("category", CAT_STRUCTURE))
	p.description = String(d.get("description", ""))
	var sz: Array = d.get("size", [1, 1])
	p.size_w = maxi(1, int(sz[0]))
	p.size_h = maxi(1, int(sz[1]) if sz.size() > 1 else 1)
	p.mass = float(d.get("mass", 0.0))
	p.fuel_capacity = float(d.get("fuel_capacity", 0.0))
	p.thrust = float(d.get("thrust", 0.0))
	p.isp = float(d.get("isp", 0.0))
	p.torque = float(d.get("torque", 0.0))
	p.extra_drag_area = float(d.get("extra_drag_area", 0.0))
	p.max_landing_speed = float(d.get("max_landing_speed", 0.0))
	p.is_command = bool(d.get("command", false))
	p.shape = String(d.get("shape", SHAPE_FOR_CATEGORY.get(p.category, SHAPE_BEAM)))
	return p
