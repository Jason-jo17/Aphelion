class_name Instruction
extends RefCounted

## One assembled instruction.

var op: int = ISA.Op.NOP
var a: Operand = null       ## first operand: destination register, value, or condition LHS
var b: Operand = null       ## second operand: value, tolerance, or condition RHS
var cmp: int = ISA.Cmp.LT   ## comparison, for IF / BURN UNTIL / WAIT UNTIL
var target: int = -1        ## resolved jump destination, for JMP
var label_name: String = "" ## unresolved jump destination, kept for error messages

var line: int = 0           ## 1-based source line
var source_text: String = ""


static func make(op_: int, a_: Operand = null, b_: Operand = null) -> Instruction:
	var ins := Instruction.new()
	ins.op = op_
	ins.a = a_
	ins.b = b_
	return ins


func is_blocking() -> bool:
	return ISA.is_blocking(op)


## Renders the instruction back to assembly. The node-graph editor uses this to
## show the text a graph compiles to, so the two views always agree.
func to_text() -> String:
	match op:
		ISA.Op.HALT, ISA.Op.NOP:
			return ISA.op_name(op)
		ISA.Op.JMP:
			return "JMP %s" % label_name
		ISA.Op.IF:
			return "IF %s %s %s" % [a.to_text(), ISA.CMP_TEXT[cmp], b.to_text()]
		ISA.Op.BURN_UNTIL:
			return "BURN UNTIL %s %s %s" % [a.to_text(), ISA.CMP_TEXT[cmp], b.to_text()]
		ISA.Op.WAIT_UNTIL:
			return "WAIT UNTIL %s %s %s" % [a.to_text(), ISA.CMP_TEXT[cmp], b.to_text()]
		ISA.Op.ORIENT:
			if b != null:
				return "ORIENT %s, %s" % [a.to_text(), b.to_text()]
			return "ORIENT %s" % a.to_text()
		ISA.Op.ABS, ISA.Op.NEG:
			return "%s %s" % [ISA.op_name(op), a.to_text()]
		ISA.Op.POINT, ISA.Op.THROTTLE, ISA.Op.BURN, ISA.Op.WAIT, ISA.Op.LOG:
			return "%s %s" % [ISA.op_name(op), a.to_text()]
		_:
			return "%s %s, %s" % [ISA.op_name(op), a.to_text(), b.to_text()]
