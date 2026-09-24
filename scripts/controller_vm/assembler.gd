class_name Assembler
extends RefCounted

## Turns flight-computer source text into a Program.
##
## Error messages are part of the game's teaching, not an afterthought. Every
## diagnostic carries the line, the text that caused it, a specific explanation,
## and — where one exists — a suggestion. "Syntax error on line 12" would tell a
## player nothing about orbital mechanics or about their program.

const MAX_LINE_LENGTH := 400

## Characters that end a bare token.
const _BREAKERS := " \t,;"
const _TWO_CHAR_OPS := ["<=", ">=", "==", "!=", "<>"]
const _ONE_CHAR_OPS := ["<", ">", "="]


## Assembles `source` into a Program. The Program is returned whether or not it
## assembled cleanly; check `program.ok()`.
static func assemble(source: String) -> Program:
	var prog := Program.new()
	prog.source = source
	prog.source_kind = Program.SOURCE_ISA

	var lines := source.split("\n")
	var pending_labels: Array[String] = []

	for li in lines.size():
		var line_no := li + 1
		var raw: String = lines[li]
		if raw.length() > MAX_LINE_LENGTH:
			prog.add_error(line_no, raw.substr(0, 40),
				"Line is longer than %d characters." % MAX_LINE_LENGTH,
				"Break it into several instructions.")
			continue

		var tokens := _tokenize(raw)
		if tokens.is_empty():
			continue

		# Leading labels: "loop:" alone, or "loop: SET R0, 1".
		while not tokens.is_empty() and tokens[0].ends_with(":"):
			var name: String = tokens[0].substr(0, tokens[0].length() - 1)
			if name.is_empty():
				prog.add_error(line_no, tokens[0], "A label needs a name before the colon.",
					"Write something like `loop:`.")
			elif not _is_identifier(name):
				prog.add_error(line_no, tokens[0],
					"'%s' is not a valid label name." % name,
					"Labels start with a letter and contain letters, digits or underscores.")
			elif prog.labels.has(name.to_upper()):
				prog.add_error(line_no, tokens[0],
					"Label '%s' is already defined." % name,
					"Every label must be unique.")
			else:
				pending_labels.append(name.to_upper())
			tokens.remove_at(0)

		if tokens.is_empty():
			continue

		var ins := _parse_instruction(prog, line_no, raw.strip_edges(), tokens)
		if ins == null:
			continue
		for lbl in pending_labels:
			prog.labels[lbl] = prog.instructions.size()
		pending_labels.clear()
		prog.instructions.append(ins)

	# Labels may sit at the very end of the file, pointing one past the last
	# instruction — a perfectly good place to jump to in order to fall off.
	for lbl in pending_labels:
		prog.labels[lbl] = prog.instructions.size()

	_resolve_jumps(prog)
	return prog


# --- tokenising ------------------------------------------------------------


## Splits a line into tokens. Comparison operators are recognised whether or not
## they are surrounded by spaces, so `IF ALT>70000` and `IF ALT > 70000` both
## work — players type both.
static func _tokenize(line: String) -> Array[String]:
	var out: Array[String] = []
	var i := 0
	var n := line.length()
	while i < n:
		var ch := line[i]
		if ch == ";":
			break
		if ch == " " or ch == "\t" or ch == "," or ch == "\r":
			i += 1
			continue
		var two := line.substr(i, 2)
		if two in _TWO_CHAR_OPS:
			out.append(two)
			i += 2
			continue
		if ch in _ONE_CHAR_OPS:
			out.append(ch)
			i += 1
			continue
		var start := i
		while i < n:
			var c := line[i]
			if c in _BREAKERS or c == "\r" or c in _ONE_CHAR_OPS:
				break
			# A colon terminates a label, but is included in the token.
			if c == ":":
				i += 1
				break
			i += 1
		if i > start:
			out.append(line.substr(start, i - start))
		else:
			i += 1
	return out


static func _is_identifier(s: String) -> bool:
	if s.is_empty():
		return false
	var first := s[0]
	if not (first.is_valid_identifier() or first == "_" or _is_alpha(first)):
		return false
	for c in s:
		if not (_is_alpha(c) or c.is_valid_int() or c == "_"):
			return false
	return true


static func _is_alpha(c: String) -> bool:
	var u := c.to_upper()
	return u >= "A" and u <= "Z"


# --- instruction parsing ---------------------------------------------------


static func _parse_instruction(prog: Program, line_no: int, raw: String, tokens: Array[String]) -> Instruction:
	var mnemonic: String = tokens[0].to_upper()
	if not ISA.OPS.has(mnemonic):
		prog.add_error(line_no, tokens[0],
			"Unknown instruction '%s'." % tokens[0],
			_suggest(mnemonic, ISA.op_names_ordered(), "instruction"))
		return null

	var spec: Dictionary = ISA.OPS[mnemonic]
	var args := tokens.slice(1)
	var ins := Instruction.new()
	ins.op = spec["op"]
	ins.line = line_no
	ins.source_text = raw

	# BURN and WAIT each have a timed form and an UNTIL form.
	if (mnemonic == "BURN" or mnemonic == "WAIT") and not args.is_empty() and args[0].to_upper() == "UNTIL":
		ins.op = ISA.Op.BURN_UNTIL if mnemonic == "BURN" else ISA.Op.WAIT_UNTIL
		if not _parse_condition(prog, ins, line_no, args.slice(1), mnemonic + " UNTIL"):
			return null
		return ins

	match spec["form"]:
		ISA.Form.NONE:
			if not args.is_empty():
				prog.add_error(line_no, raw,
					"%s takes no operands." % mnemonic,
					"Remove '%s'." % " ".join(args))
				return null
		ISA.Form.REG:
			if args.size() != 1:
				prog.add_error(line_no, raw,
					"%s takes exactly one register." % mnemonic,
					"Write `%s R0`." % mnemonic)
				return null
			ins.a = _parse_operand(prog, line_no, args[0], false)
			if ins.a == null:
				return null
			if not ins.a.is_writable():
				prog.add_error(line_no, args[0],
					"%s can only be applied to a register." % mnemonic,
					"R0 to R7 are the writable registers.")
				return null
		ISA.Form.REG_VALUE:
			if args.size() != 2:
				prog.add_error(line_no, raw,
					"%s takes a register and a value." % mnemonic,
					"Write `%s R0, 100` or `%s R0, ALT`." % [mnemonic, mnemonic])
				return null
			ins.a = _parse_operand(prog, line_no, args[0], false)
			ins.b = _parse_operand(prog, line_no, args[1], false)
			if ins.a == null or ins.b == null:
				return null
			if not ins.a.is_writable():
				prog.add_error(line_no, args[0],
					"'%s' cannot be written to." % args[0],
					"The first operand of %s must be R0 to R7." % mnemonic)
				return null
			if mnemonic == "SENSE" and ins.b.kind != Operand.Kind.SENSOR:
				prog.add_error(line_no, args[1],
					"SENSE reads a sensor, and '%s' is not one." % args[1],
					_suggest(args[1].to_upper(), ISA.sensor_names_ordered(), "sensor"))
				return null
		ISA.Form.LABEL:
			if args.size() != 1:
				prog.add_error(line_no, raw, "%s takes one label." % mnemonic,
					"Write `%s loop`, where `loop:` appears somewhere in the program." % mnemonic)
				return null
			ins.label_name = args[0]
		ISA.Form.CONDITION:
			if not _parse_condition(prog, ins, line_no, args, mnemonic):
				return null
		ISA.Form.VALUE:
			if args.size() != 1:
				prog.add_error(line_no, raw, "%s takes one value." % mnemonic,
					_value_hint(mnemonic))
				return null
			ins.a = _parse_operand(prog, line_no, args[0], mnemonic in ["ORIENT", "POINT"])
			if ins.a == null:
				return null
		ISA.Form.VALUE_OPT:
			if args.size() < 1 or args.size() > 2:
				prog.add_error(line_no, raw,
					"%s takes a target and an optional tolerance in degrees." % mnemonic,
					"Write `ORIENT PROGRADE` or `ORIENT 90, 2`.")
				return null
			ins.a = _parse_operand(prog, line_no, args[0], true)
			if ins.a == null:
				return null
			if args.size() == 2:
				ins.b = _parse_operand(prog, line_no, args[1], false)
				if ins.b == null:
					return null
	return ins


static func _parse_condition(prog: Program, ins: Instruction, line_no: int, args: Array, what: String) -> bool:
	if args.size() != 3:
		prog.add_error(line_no, what + " " + " ".join(args),
			"%s needs a comparison: a value, an operator, and another value." % what,
			"For example `%s APO > 100000`." % what)
		return false
	var op_text: String = args[1]
	if not ISA.CMP_FROM_TEXT.has(op_text):
		prog.add_error(line_no, op_text,
			"'%s' is not a comparison operator." % op_text,
			"Use one of <  <=  >  >=  ==  !=")
		return false
	ins.cmp = ISA.CMP_FROM_TEXT[op_text]
	ins.a = _parse_operand(prog, line_no, args[0], false)
	ins.b = _parse_operand(prog, line_no, args[2], false)
	return ins.a != null and ins.b != null


## Parses one value token. `allow_goal` enables the attitude keywords, which are
## only meaningful to ORIENT and POINT.
static func _parse_operand(prog: Program, line_no: int, token: String, allow_goal: bool) -> Operand:
	var up := token.to_upper()

	if allow_goal and ISA.GOAL_FROM_TEXT.has(up):
		return Operand.from_goal(ISA.GOAL_FROM_TEXT[up], up)

	if up.length() >= 2 and up[0] == "R" and up.substr(1).is_valid_int():
		var idx := int(up.substr(1))
		if idx < 0 or idx >= ISA.REGISTER_COUNT:
			prog.add_error(line_no, token,
				"There is no register %s." % token,
				"The flight computer has R0 to R%d." % (ISA.REGISTER_COUNT - 1))
			return null
		return Operand.register(idx, up)

	if ISA.SENSORS.has(up):
		return Operand.from_sensor(ISA.SENSORS[up]["id"], up)

	if ISA.CONSTANTS.has(up):
		return Operand.literal(ISA.CONSTANTS[up], up)

	if token.is_valid_float():
		return Operand.literal(token.to_float(), token)
	if token.is_valid_int():
		return Operand.literal(float(token.to_int()), token)

	# Nothing matched. Work out which vocabulary the player was probably reaching
	# for, so the suggestion is useful rather than generic.
	var candidates := PackedStringArray()
	candidates.append_array(ISA.sensor_names_ordered())
	if allow_goal:
		for g in ISA.GOAL_FROM_TEXT:
			candidates.append(g)
	for c in ISA.CONSTANTS:
		candidates.append(c)
	prog.add_error(line_no, token,
		"'%s' is not a number, a register or a sensor." % token,
		_suggest(up, candidates, "value"))
	return null


static func _value_hint(mnemonic: String) -> String:
	match mnemonic:
		"THROTTLE": return "Write `THROTTLE 1` for full thrust or `THROTTLE 0.5` for half."
		"BURN": return "Write `BURN 30` for thirty seconds, or `BURN UNTIL APO > 100000`."
		"WAIT": return "Write `WAIT 60`, or `WAIT UNTIL TAPO < 20`."
		"POINT": return "Write `POINT PROGRADE` or `POINT 90`."
		"LOG": return "Write `LOG ALT` or `LOG R0`."
		_: return "Give it a single value."


## Closest match by edit distance, phrased as a suggestion. Returns a generic
## pointer when nothing is close enough to be worth guessing at.
static func _suggest(word: String, candidates: PackedStringArray, kind: String) -> String:
	var best := ""
	var best_d := 1 << 30
	for c in candidates:
		var d := _edit_distance(word, c)
		if d < best_d:
			best_d = d
			best = c
	# Only offer a guess when it is genuinely close: at most a third of the word.
	if not best.is_empty() and best_d <= maxi(1, word.length() / 3):
		return "Did you mean %s?" % best
	return "See the %s reference (F1) for the full list." % kind


static func _edit_distance(a: String, b: String) -> int:
	var n := a.length()
	var m := b.length()
	if n == 0:
		return m
	if m == 0:
		return n
	var prev := PackedInt32Array()
	prev.resize(m + 1)
	var cur := PackedInt32Array()
	cur.resize(m + 1)
	for j in m + 1:
		prev[j] = j
	for i in range(1, n + 1):
		cur[0] = i
		for j in range(1, m + 1):
			var cost := 0 if a[i - 1] == b[j - 1] else 1
			cur[j] = mini(mini(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost)
		for j in m + 1:
			prev[j] = cur[j]
	return prev[m]


static func _resolve_jumps(prog: Program) -> void:
	for ins in prog.instructions:
		if ins.op != ISA.Op.JMP:
			continue
		var key := ins.label_name.to_upper()
		if not prog.labels.has(key):
			var names := PackedStringArray()
			for k in prog.labels:
				names.append(k)
			prog.add_error(ins.line, ins.label_name,
				"No label called '%s'." % ins.label_name,
				_suggest(key, names, "label") if names.size() > 0
					else "Define it by writing `%s:` on a line of its own." % ins.label_name)
			continue
		ins.target = prog.labels[key]
