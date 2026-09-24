class_name Operand
extends RefCounted

## One value slot in an instruction.
##
## Operands are resolved at run time rather than at assembly time, because a
## sensor's value changes every tick and a register's changes whenever the
## program says so. Assembly only decides *where* a value comes from.

enum Kind { LITERAL, REGISTER, SENSOR, GOAL }

var kind: int = Kind.LITERAL
var value: float = 0.0  ## LITERAL: the number. GOAL: the absolute heading, in radians.
var index: int = 0  ## REGISTER: 0-7
var sensor: int = ISA.Sensor.NONE
var goal: int = ISA.Goal.ABSOLUTE
var text: String = ""  ## as the player wrote it, for error messages and the disassembler


static func literal(v: float, src: String = "") -> Operand:
	var o := Operand.new()
	o.kind = Kind.LITERAL
	o.value = v
	o.text = src if not src.is_empty() else str(v)
	return o


static func register(i: int, src: String = "") -> Operand:
	var o := Operand.new()
	o.kind = Kind.REGISTER
	o.index = i
	o.text = src if not src.is_empty() else "R%d" % i
	return o


static func from_sensor(s: int, src: String = "") -> Operand:
	var o := Operand.new()
	o.kind = Kind.SENSOR
	o.sensor = s
	o.text = src if not src.is_empty() else ISA.sensor_name(s)
	return o


static func from_goal(g: int, src: String = "") -> Operand:
	var o := Operand.new()
	o.kind = Kind.GOAL
	o.goal = g
	o.text = src
	return o


func is_writable() -> bool:
	return kind == Kind.REGISTER


func to_text() -> String:
	return text
