class_name Predicate
extends RefCounted

## A mission condition: what counts as success, and what counts as failure.
##
## Predicates describe themselves. The objectives panel renders `describe()`
## rather than a hand-written string in the mission file, so what the player is
## told to do and what the game actually checks cannot drift apart — a mistake
## that is very easy to make and very annoying to find.

enum Kind { ALL, ANY, NOT, COMPARE, BETWEEN, FLAG, SUSTAIN, ALWAYS, NEVER }

const FLAGS := ["landed", "crashed", "out_of_fuel", "program_done", "escaped"]

var kind: int = Kind.ALWAYS
var children: Array[Predicate] = []

## COMPARE / BETWEEN
var sensor: int = ISA.Sensor.NONE
var cmp: int = ISA.Cmp.GE
var value: float = 0.0
var lo: float = 0.0
var hi: float = 0.0

## FLAG
var flag: String = ""

## SUSTAIN: the inner predicate must hold continuously for this long.
var sustain_seconds: float = 0.0
var _held: float = 0.0


func reset() -> void:
	_held = 0.0
	for c in children:
		c.reset()


## Evaluates against the current step. `dt` is the duration of the step just
## taken, which only SUSTAIN uses.
func check(bus: SensorBus, state: ShipState, vm: ControllerVM, dt: float) -> bool:
	match kind:
		Kind.ALWAYS:
			return true
		Kind.NEVER:
			return false
		Kind.ALL:
			for c in children:
				if not c.check(bus, state, vm, dt):
					return false
			return true
		Kind.ANY:
			for c in children:
				if c.check(bus, state, vm, dt):
					return true
			return false
		Kind.NOT:
			return not (children.is_empty() or children[0].check(bus, state, vm, dt))
		Kind.COMPARE:
			return ControllerVM._compare(bus.read(sensor), cmp, value)
		Kind.BETWEEN:
			var v := bus.read(sensor)
			return v >= lo and v <= hi
		Kind.FLAG:
			return _flag_value(bus, state, vm)
		Kind.SUSTAIN:
			var inner := not children.is_empty() and children[0].check(bus, state, vm, dt)
			if inner:
				_held += dt
			else:
				_held = 0.0
			return _held >= sustain_seconds
	return false


## How far through a SUSTAIN we are, 0..1. The objectives panel shows this as a
## little progress bar, because "hold this for ten seconds" is much less
## stressful when you can see the ten seconds.
func sustain_progress() -> float:
	if kind != Kind.SUSTAIN or sustain_seconds <= 0.0:
		return 0.0
	return clampf(_held / sustain_seconds, 0.0, 1.0)


func _flag_value(bus: SensorBus, state: ShipState, vm: ControllerVM) -> bool:
	match flag:
		"landed":
			return state.landed
		"crashed":
			return state.crashed
		"out_of_fuel":
			return state.fuel <= 0.0
		"program_done":
			return vm != null and vm.is_finished()
		"escaped":
			return is_inf(bus.read(ISA.Sensor.APO))
	return false


## A human sentence for the objectives list.
func describe() -> String:
	match kind:
		Kind.ALWAYS:
			return "no condition"
		Kind.NEVER:
			return "impossible"
		Kind.ALL:
			var parts := PackedStringArray()
			for c in children:
				parts.append(c.describe())
			return " and ".join(parts)
		Kind.ANY:
			var any_parts := PackedStringArray()
			for c in children:
				any_parts.append(c.describe())
			return " or ".join(any_parts)
		Kind.NOT:
			return "not (%s)" % (children[0].describe() if not children.is_empty() else "")
		Kind.COMPARE:
			return "%s %s %s" % [_sensor_label(), _cmp_word(), _format(value)]
		Kind.BETWEEN:
			return "%s between %s and %s" % [_sensor_label(), _format(lo), _format(hi)]
		Kind.FLAG:
			return _flag_label()
		Kind.SUSTAIN:
			var inner := children[0].describe() if not children.is_empty() else ""
			return "%s, held for %s" % [inner, Fmt.duration(sustain_seconds)]
	return "?"


func _sensor_label() -> String:
	match sensor:
		ISA.Sensor.APO:
			return "apoapsis"
		ISA.Sensor.PERI:
			return "periapsis"
		ISA.Sensor.ALT:
			return "altitude"
		ISA.Sensor.ECC:
			return "eccentricity"
		ISA.Sensor.VEL:
			return "speed"
		ISA.Sensor.VVEL:
			return "vertical speed"
		ISA.Sensor.HVEL:
			return "horizontal speed"
		ISA.Sensor.FUEL:
			return "fuel"
		ISA.Sensor.TGTD:
			return "distance to target"
		ISA.Sensor.TGTV:
			return "speed relative to target"
		ISA.Sensor.SOI:
			return "sphere of influence"
		ISA.Sensor.T:
			return "mission time"
		_:
			return ISA.sensor_name(sensor).to_lower()


func _cmp_word() -> String:
	match cmp:
		ISA.Cmp.LT:
			return "below"
		ISA.Cmp.LE:
			return "at most"
		ISA.Cmp.GT:
			return "above"
		ISA.Cmp.GE:
			return "at least"
		ISA.Cmp.EQ:
			return "exactly"
		ISA.Cmp.NE:
			return "not"
	return "?"


func _flag_label() -> String:
	match flag:
		"landed":
			return "touched down safely"
		"crashed":
			return "destroyed"
		"out_of_fuel":
			return "tanks empty"
		"program_done":
			return "program finished"
		"escaped":
			return "on an escape trajectory"
	return flag


func _format(v: float) -> String:
	return Fmt.sensor_value(sensor, v)


# --- parsing ---------------------------------------------------------------


## Builds a predicate from mission JSON. Unrecognised shapes become NEVER and
## are reported through `errors`, so a malformed mission fails loudly at load
## rather than quietly becoming unwinnable.
static func from_dict(d: Variant, errors: Array[String] = []) -> Predicate:
	var p := Predicate.new()
	if typeof(d) != TYPE_DICTIONARY:
		errors.append("Predicate must be an object, found %s." % type_string(typeof(d)))
		p.kind = Kind.NEVER
		return p
	var dict: Dictionary = d

	for key in ["all", "any"]:
		if dict.has(key):
			p.kind = Kind.ALL if key == "all" else Kind.ANY
			for sub in dict[key]:
				p.children.append(from_dict(sub, errors))
			return p

	if dict.has("not"):
		p.kind = Kind.NOT
		p.children.append(from_dict(dict["not"], errors))
		return p

	if dict.has("sustain"):
		p.kind = Kind.SUSTAIN
		p.sustain_seconds = float(dict["sustain"])
		if not dict.has("of"):
			errors.append("A `sustain` predicate needs an `of` to sustain.")
			p.children.append(never())
		else:
			p.children.append(from_dict(dict["of"], errors))
		return p

	if dict.has("flag"):
		p.kind = Kind.FLAG
		p.flag = String(dict["flag"])
		if not FLAGS.has(p.flag):
			errors.append("Unknown flag '%s'. Known flags: %s." % [p.flag, ", ".join(FLAGS)])
			p.kind = Kind.NEVER
		return p

	if dict.has("sensor"):
		var name := String(dict["sensor"]).to_upper()
		if not ISA.SENSORS.has(name):
			errors.append("Unknown sensor '%s' in a predicate." % name)
			p.kind = Kind.NEVER
			return p
		p.sensor = ISA.SENSORS[name]["id"]
		if dict.has("between"):
			var r: Array = dict["between"]
			if r.size() != 2:
				errors.append("`between` takes exactly two values.")
				p.kind = Kind.NEVER
				return p
			p.kind = Kind.BETWEEN
			p.lo = _num(r[0])
			p.hi = _num(r[1])
			return p
		p.kind = Kind.COMPARE
		var op_text := String(dict.get("op", ">="))
		if not ISA.CMP_FROM_TEXT.has(op_text):
			errors.append("'%s' is not a comparison operator." % op_text)
			p.kind = Kind.NEVER
			return p
		p.cmp = ISA.CMP_FROM_TEXT[op_text]
		p.value = _num(dict.get("value", 0.0))
		return p

	errors.append("Predicate has none of: all, any, not, sustain, flag, sensor.")
	p.kind = Kind.NEVER
	return p


## Accepts numbers and the string "inf"/"-inf", which JSON cannot express.
static func _num(v: Variant) -> float:
	if typeof(v) == TYPE_STRING:
		var s := String(v).strip_edges().to_lower()
		if s == "inf" or s == "+inf" or s == "infinity":
			return INF
		if s == "-inf" or s == "-infinity":
			return -INF
		return s.to_float()
	return float(v)


static func always() -> Predicate:
	return Predicate.new()


static func never() -> Predicate:
	var p := Predicate.new()
	p.kind = Kind.NEVER
	return p


## Flattens an ALL predicate into its parts, so the objectives panel can tick
## them off one at a time instead of showing one long sentence.
func parts() -> Array[Predicate]:
	if kind == Kind.ALL:
		return children
	return [self] as Array[Predicate]
