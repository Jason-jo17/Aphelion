class_name ISA
extends RefCounted

## The instruction set, the sensor set, and the tables that describe both.
##
## Everything the assembler, the VM, the editor's autocomplete, the in-game
## reference panel and the Mission Control prompt know about the language comes
## from here, so there is exactly one place to change when the language changes.
##
## See docs/ISA.md for the language as the player meets it.

# --- opcodes ---------------------------------------------------------------

enum Op {
	NOP,
	# data
	SET,
	ADD,
	SUB,
	MUL,
	DIV,
	MOD,
	MIN,
	MAX,
	ABS,
	NEG,
	SENSE,
	# flow
	JMP,
	IF,
	HALT,
	# attitude
	ORIENT,
	POINT,
	# thrust
	THROTTLE,
	BURN,
	BURN_UNTIL,
	WAIT,
	WAIT_UNTIL,
	# output
	LOG,
}

# --- comparisons -----------------------------------------------------------

enum Cmp { LT, LE, GT, GE, EQ, NE }

const CMP_TEXT := {
	Cmp.LT: "<",
	Cmp.LE: "<=",
	Cmp.GT: ">",
	Cmp.GE: ">=",
	Cmp.EQ: "==",
	Cmp.NE: "!=",
}

const CMP_FROM_TEXT := {
	"<": Cmp.LT,
	"<=": Cmp.LE,
	">": Cmp.GT,
	">=": Cmp.GE,
	"==": Cmp.EQ,
	"!=": Cmp.NE,
	"=": Cmp.EQ,
	"<>": Cmp.NE,
}

# --- attitude goals --------------------------------------------------------

enum Goal { ABSOLUTE, PROGRADE, RETROGRADE, RADIAL, ANTIRADIAL, TARGET }

const GOAL_FROM_TEXT := {
	"PROGRADE": Goal.PROGRADE,
	"RETROGRADE": Goal.RETROGRADE,
	"RADIAL": Goal.RADIAL,
	"ANTIRADIAL": Goal.ANTIRADIAL,
	"TARGET": Goal.TARGET,
	# friendly aliases
	"PRO": Goal.PROGRADE,
	"RETRO": Goal.RETROGRADE,
	"UP": Goal.RADIAL,
	"DOWN": Goal.ANTIRADIAL,
}

# --- sensors ---------------------------------------------------------------

enum Sensor {
	NONE,
	ALT,
	VEL,
	VVEL,
	HVEL,
	APO,
	PERI,
	ECC,
	SMA,
	TAPO,
	TPERI,
	HDG,
	PRO,
	RETRO,
	RAD,
	ANTIRAD,
	PITCH,
	FUEL,
	MASS,
	DV,
	TWR,
	THR,
	GRAV,
	DENS,
	Q,
	T,
	SOI,
	LANDED,
	TGTD,
	TGTV,
	TGTA,
}

## Sensor metadata: name -> {id, unit, angle, summary}.
## `angle` marks values the VM must convert between radians and degrees.
const SENSORS := {
	"ALT":
	{
		"id": Sensor.ALT,
		"unit": "m",
		"angle": false,
		"summary": "Altitude above the surface of the body you are bound to."
	},
	"VEL":
	{"id": Sensor.VEL, "unit": "m/s", "angle": false, "summary": "Speed relative to that body."},
	"VVEL":
	{
		"id": Sensor.VVEL,
		"unit": "m/s",
		"angle": false,
		"summary": "Vertical speed. Positive is climbing."
	},
	"HVEL": {"id": Sensor.HVEL, "unit": "m/s", "angle": false, "summary": "Horizontal speed."},
	"APO":
	{
		"id": Sensor.APO,
		"unit": "m",
		"angle": false,
		"summary": "Apoapsis altitude. INF on an escape trajectory."
	},
	"PERI":
	{
		"id": Sensor.PERI,
		"unit": "m",
		"angle": false,
		"summary": "Periapsis altitude. Negative when your orbit hits the ground."
	},
	"ECC":
	{"id": Sensor.ECC, "unit": "", "angle": false, "summary": "Eccentricity. Zero is a circle."},
	"SMA":
	{
		"id": Sensor.SMA,
		"unit": "m",
		"angle": false,
		"summary": "Semi-major axis, as a radius rather than an altitude."
	},
	"TAPO": {"id": Sensor.TAPO, "unit": "s", "angle": false, "summary": "Seconds until apoapsis."},
	"TPERI":
	{"id": Sensor.TPERI, "unit": "s", "angle": false, "summary": "Seconds until periapsis."},
	"HDG":
	{
		"id": Sensor.HDG,
		"unit": "deg",
		"angle": true,
		"summary": "Where the ship is pointing, 0-360."
	},
	"PRO": {"id": Sensor.PRO, "unit": "deg", "angle": true, "summary": "Prograde heading."},
	"RETRO": {"id": Sensor.RETRO, "unit": "deg", "angle": true, "summary": "Retrograde heading."},
	"RAD":
	{"id": Sensor.RAD, "unit": "deg", "angle": true, "summary": "Straight up, away from the body."},
	"ANTIRAD":
	{
		"id": Sensor.ANTIRAD,
		"unit": "deg",
		"angle": true,
		"summary": "Straight down, toward the body."
	},
	"PITCH":
	{
		"id": Sensor.PITCH,
		"unit": "deg",
		"angle": true,
		"summary": "Signed angle from your heading to prograde, -180 to 180."
	},
	"FUEL": {"id": Sensor.FUEL, "unit": "kg", "angle": false, "summary": "Propellant remaining."},
	"MASS": {"id": Sensor.MASS, "unit": "kg", "angle": false, "summary": "Current total mass."},
	"DV": {"id": Sensor.DV, "unit": "m/s", "angle": false, "summary": "Delta-v remaining."},
	"TWR":
	{
		"id": Sensor.TWR,
		"unit": "",
		"angle": false,
		"summary": "Thrust-to-weight against local gravity."
	},
	"THR":
	{"id": Sensor.THR, "unit": "", "angle": false, "summary": "Current throttle setting, 0-1."},
	"GRAV":
	{
		"id": Sensor.GRAV,
		"unit": "m/s^2",
		"angle": false,
		"summary": "Local gravitational acceleration."
	},
	"DENS":
	{"id": Sensor.DENS, "unit": "kg/m^3", "angle": false, "summary": "Atmospheric density here."},
	"Q": {"id": Sensor.Q, "unit": "Pa", "angle": false, "summary": "Dynamic pressure."},
	"T": {"id": Sensor.T, "unit": "s", "angle": false, "summary": "Mission elapsed time."},
	"SOI":
	{
		"id": Sensor.SOI,
		"unit": "",
		"angle": false,
		"summary": "0 for the primary, 1 or more for a moon."
	},
	"LANDED":
	{
		"id": Sensor.LANDED,
		"unit": "",
		"angle": false,
		"summary": "1 when on the surface, otherwise 0."
	},
	"TGTD":
	{"id": Sensor.TGTD, "unit": "m", "angle": false, "summary": "Distance to the active target."},
	"TGTV":
	{"id": Sensor.TGTV, "unit": "m/s", "angle": false, "summary": "Speed relative to the target."},
	"TGTA":
	{"id": Sensor.TGTA, "unit": "deg", "angle": true, "summary": "Heading toward the target."},
}

## Named literals usable anywhere a number is.
const CONSTANTS := {
	"INF": INF,
	"PI": DetMath.PI_D,
	"TAU": DetMath.TAU_D,
	"TRUE": 1.0,
	"FALSE": 0.0,
}

# --- opcode table ----------------------------------------------------------

## Operand shapes, used by the assembler to parse and by the UI to describe.
enum Form {
	NONE,  ## no operands                      HALT, NOP
	VALUE,  ## one value                        THROTTLE, LOG, BURN, WAIT, ORIENT, POINT
	REG_VALUE,  ## register, value                  SET, ADD, ...
	REG,  ## register only                    ABS, NEG
	LABEL,  ## a label name                     JMP
	CONDITION,  ## value cmp value                  IF, BURN UNTIL, WAIT UNTIL
	VALUE_OPT,  ## value, optional second value     ORIENT tol
}

const OPS := {
	"NOP": {"op": Op.NOP, "form": Form.NONE, "blocking": false, "summary": "Do nothing."},
	"SET": {"op": Op.SET, "form": Form.REG_VALUE, "blocking": false, "summary": "Rd = value."},
	"ADD": {"op": Op.ADD, "form": Form.REG_VALUE, "blocking": false, "summary": "Rd += value."},
	"SUB": {"op": Op.SUB, "form": Form.REG_VALUE, "blocking": false, "summary": "Rd -= value."},
	"MUL": {"op": Op.MUL, "form": Form.REG_VALUE, "blocking": false, "summary": "Rd *= value."},
	"DIV":
	{
		"op": Op.DIV,
		"form": Form.REG_VALUE,
		"blocking": false,
		"summary": "Rd /= value. Faults on zero."
	},
	"MOD":
	{
		"op": Op.MOD,
		"form": Form.REG_VALUE,
		"blocking": false,
		"summary": "Rd = Rd mod value. Faults on zero."
	},
	"MIN":
	{
		"op": Op.MIN,
		"form": Form.REG_VALUE,
		"blocking": false,
		"summary": "Rd = smaller of Rd and value."
	},
	"MAX":
	{
		"op": Op.MAX,
		"form": Form.REG_VALUE,
		"blocking": false,
		"summary": "Rd = larger of Rd and value."
	},
	"ABS": {"op": Op.ABS, "form": Form.REG, "blocking": false, "summary": "Rd = |Rd|."},
	"NEG": {"op": Op.NEG, "form": Form.REG, "blocking": false, "summary": "Rd = -Rd."},
	"SENSE":
	{"op": Op.SENSE, "form": Form.REG_VALUE, "blocking": false, "summary": "Rd = sensor reading."},
	"JMP": {"op": Op.JMP, "form": Form.LABEL, "blocking": false, "summary": "Jump to a label."},
	"IF":
	{
		"op": Op.IF,
		"form": Form.CONDITION,
		"blocking": false,
		"summary": "Skip the next instruction unless the condition holds."
	},
	"HALT":
	{
		"op": Op.HALT,
		"form": Form.NONE,
		"blocking": true,
		"summary": "Stop the program. The flight continues."
	},
	"ORIENT":
	{
		"op": Op.ORIENT,
		"form": Form.VALUE_OPT,
		"blocking": true,
		"summary": "Turn to face a target and wait until you are there."
	},
	"POINT":
	{
		"op": Op.POINT,
		"form": Form.VALUE,
		"blocking": false,
		"summary": "Set the attitude goal and carry on."
	},
	"THROTTLE":
	{
		"op": Op.THROTTLE,
		"form": Form.VALUE,
		"blocking": false,
		"summary": "Set the throttle a later BURN will use, 0-1."
	},
	"BURN":
	{
		"op": Op.BURN,
		"form": Form.VALUE,
		"blocking": true,
		"summary": "Burn for this many seconds, or UNTIL a condition."
	},
	"WAIT":
	{
		"op": Op.WAIT,
		"form": Form.VALUE,
		"blocking": true,
		"summary": "Coast for this many seconds, or UNTIL a condition."
	},
	"LOG":
	{
		"op": Op.LOG,
		"form": Form.VALUE,
		"blocking": false,
		"summary": "Record a value in the flight log."
	},
	"STAGE":
	{
		"op": Op.NOP,
		"form": Form.NONE,
		"blocking": false,
		"summary": "Reserved. Does nothing in this version."
	},
}


## Opcodes that block, keyed by Op. Derived once rather than restated.
static func is_blocking(op: int) -> bool:
	return op in [Op.HALT, Op.ORIENT, Op.BURN, Op.BURN_UNTIL, Op.WAIT, Op.WAIT_UNTIL]


static func op_name(op: int) -> String:
	match op:
		Op.BURN_UNTIL:
			return "BURN UNTIL"
		Op.WAIT_UNTIL:
			return "WAIT UNTIL"
		_:
			for key in OPS:
				if OPS[key]["op"] == op and key != "STAGE":
					return key
	return "?"


static func sensor_name(sensor: int) -> String:
	for key in SENSORS:
		if SENSORS[key]["id"] == sensor:
			return key
	return "?"


static func sensor_is_angle(sensor: int) -> bool:
	var n := sensor_name(sensor)
	return SENSORS.has(n) and SENSORS[n]["angle"]


## Sensor names in a stable, documented order for the reference panel.
static func sensor_names_ordered() -> PackedStringArray:
	return PackedStringArray(
		[
			"ALT",
			"VEL",
			"VVEL",
			"HVEL",
			"APO",
			"PERI",
			"ECC",
			"SMA",
			"TAPO",
			"TPERI",
			"HDG",
			"PRO",
			"RETRO",
			"RAD",
			"ANTIRAD",
			"PITCH",
			"FUEL",
			"MASS",
			"DV",
			"TWR",
			"THR",
			"GRAV",
			"DENS",
			"Q",
			"T",
			"SOI",
			"LANDED",
			"TGTD",
			"TGTV",
			"TGTA",
		]
	)


static func op_names_ordered() -> PackedStringArray:
	return PackedStringArray(
		[
			"SET",
			"ADD",
			"SUB",
			"MUL",
			"DIV",
			"MOD",
			"MIN",
			"MAX",
			"ABS",
			"NEG",
			"SENSE",
			"JMP",
			"IF",
			"HALT",
			"NOP",
			"ORIENT",
			"POINT",
			"THROTTLE",
			"BURN",
			"WAIT",
			"LOG",
		]
	)


const REGISTER_COUNT := 8
