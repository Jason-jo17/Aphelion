class_name NodeGraph
extends RefCounted

## Compiles the visual node editor's graph into flight-computer assembly.
##
## The node graph is not a second execution engine. It emits text, that text
## goes through the ordinary Assembler, and only the resulting Program runs. So
## a graph and its text form cannot disagree, the player can flip between the
## two views at any time, and every assembly diagnostic works unchanged.
##
## Graph format (see docs/MISSIONS.md for the full schema):
##
##     {
##       "entry": "n1",
##       "nodes": [
##         {"id": "n1", "type": "throttle", "value": 1, "next": "n2"},
##         {"id": "n2", "type": "point", "target": "RADIAL", "next": "n3"},
##         {"id": "n3", "type": "burn_until",
##          "lhs": "ALT", "cmp": ">", "rhs": 800, "next": "n4"},
##         {"id": "n4", "type": "branch",
##          "lhs": "APO", "cmp": "<", "rhs": 100000, "true": "n3", "false": "n5"},
##         {"id": "n5", "type": "halt"}
##       ]
##     }

## Node types that take `lhs`, `cmp` and `rhs`.
const CONDITION_TYPES := ["branch", "burn_until", "wait_until"]

## Node type -> the mnemonic it emits, for the straightforward arithmetic cases.
const ARITH_TYPES := {
	"set": "SET", "add": "ADD", "sub": "SUB", "mul": "MUL", "div": "DIV",
	"mod": "MOD", "min": "MIN", "max": "MAX", "sense": "SENSE",
}


## Compiles a graph dictionary into a Program. Compilation errors surface as
## Program errors, with the offending node id in place of a line number.
static func compile(graph: Dictionary) -> Program:
	var emitted := emit_source(graph)
	var prog := Assembler.assemble(emitted["source"])
	prog.source_kind = Program.SOURCE_NODES
	prog.node_graph = graph
	for e in emitted["errors"]:
		prog.add_error(0, String(e["node"]), String(e["message"]), String(e["hint"]))
	return prog


## Produces the assembly text for a graph, plus any structural complaints.
## Exposed separately so the editor can show the player what their graph
## compiles to, live, beside the graph itself.
static func emit_source(graph: Dictionary) -> Dictionary:
	var errors: Array[Dictionary] = []
	var by_id := {}
	var order: Array[String] = []

	for n in graph.get("nodes", []):
		var id := String(n.get("id", ""))
		if id.is_empty():
			errors.append({"node": "?", "message": "A node has no id.",
				"hint": "Every node needs a unique id."})
			continue
		if by_id.has(id):
			errors.append({"node": id, "message": "Duplicate node id '%s'." % id,
				"hint": "Node ids must be unique."})
			continue
		by_id[id] = n
		order.append(id)

	if by_id.is_empty():
		return {"source": "", "errors": errors}

	var entry := String(graph.get("entry", order[0]))
	if not by_id.has(entry):
		errors.append({"node": entry,
			"message": "The entry node '%s' does not exist." % entry,
			"hint": "Point the start marker at a node that is in the graph."})
		entry = order[0]

	# Depth-first from the entry, so the emitted order follows the flow the
	# player drew and most edges become fall-through rather than a JMP.
	var layout: Array[String] = []
	var seen := {}
	var stack: Array[String] = [entry]
	while not stack.is_empty():
		var id: String = stack.pop_back()
		if seen.has(id) or not by_id.has(id):
			continue
		seen[id] = true
		layout.append(id)
		# Push successors in reverse so the primary path is visited first.
		var succ := _successors(by_id[id])
		for i in range(succ.size() - 1, -1, -1):
			if by_id.has(succ[i]) and not seen.has(succ[i]):
				stack.append(succ[i])

	for id in order:
		if not seen.has(id):
			errors.append({"node": id,
				"message": "Node '%s' cannot be reached from the start." % id,
				"hint": "Connect it, or delete it. Unreachable nodes are not compiled."})

	# Node ids are whatever the player typed; labels have to be unique and
	# valid. Derive them from position so neither can collide.
	var label_of := {}
	for i in order.size():
		label_of[order[i]] = "n%d" % i

	var lines := PackedStringArray()
	lines.append("; Compiled from the node editor. Edits here will be replaced")
	lines.append("; the next time the graph is changed.")
	lines.append("")

	for i in layout.size():
		var id: String = layout[i]
		var node: Dictionary = by_id[id]
		var next_in_layout := layout[i + 1] if i + 1 < layout.size() else ""
		lines.append("%s:" % String(label_of[id]))
		var body := _emit_node(id, node, next_in_layout, label_of, errors)
		for b in body:
			lines.append("        " + b)

	# Every dangling edge lands here, so a graph can always be compiled even
	# while the player is still wiring it up.
	lines.append("__end:")
	lines.append("        HALT")

	return {"source": "\n".join(lines), "errors": errors}


static func _successors(node: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if String(node.get("type", "")) == "branch":
		out.append(String(node.get("true", "")))
		out.append(String(node.get("false", "")))
	else:
		out.append(String(node.get("next", "")))
	return out


static func _emit_node(
	id: String, node: Dictionary, next_in_layout: String,
	label_of: Dictionary, errors: Array[Dictionary]
) -> PackedStringArray:
	var out := PackedStringArray()
	var type := String(node.get("type", "")).to_lower()
	var nxt := String(node.get("next", ""))

	match type:
		"start":
			pass
		"halt":
			out.append("HALT")
			return out
		"throttle":
			out.append("THROTTLE %s" % _value(node, "value", "1"))
		"point":
			out.append("POINT %s" % _value(node, "target", "PROGRADE"))
		"orient":
			if node.has("tolerance"):
				out.append("ORIENT %s, %s" % [_value(node, "target", "PROGRADE"),
					_value(node, "tolerance", "0.5")])
			else:
				out.append("ORIENT %s" % _value(node, "target", "PROGRADE"))
		"burn":
			out.append("BURN %s" % _value(node, "seconds", "1"))
		"wait":
			out.append("WAIT %s" % _value(node, "seconds", "1"))
		"burn_until":
			out.append("BURN UNTIL %s" % _condition(id, node, errors))
		"wait_until":
			out.append("WAIT UNTIL %s" % _condition(id, node, errors))
		"log":
			out.append("LOG %s" % _value(node, "value", "T"))
		"abs", "neg":
			out.append("%s %s" % [type.to_upper(), _value(node, "register", "R0")])
		"branch":
			var t := String(node.get("true", ""))
			var f := String(node.get("false", ""))
			out.append("IF %s" % _condition(id, node, errors))
			out.append("JMP %s" % _label_or_end(t, label_of))
			# The false edge falls through when it is the next node laid out,
			# which saves an instruction on the common if/else shape.
			if f != next_in_layout:
				out.append("JMP %s" % _label_or_end(f, label_of))
			return out
		_:
			if ARITH_TYPES.has(type):
				out.append("%s %s, %s" % [ARITH_TYPES[type],
					_value(node, "register", "R0"), _value(node, "value", "0")])
			else:
				errors.append({"node": id,
					"message": "Unknown node type '%s'." % type,
					"hint": "Delete the node and place it again from the palette."})
				return out

	if nxt.is_empty():
		# A node with nothing after it ends the program.
		out.append("HALT")
	elif nxt != next_in_layout:
		out.append("JMP %s" % _label_or_end(nxt, label_of))
	return out


static func _condition(id: String, node: Dictionary, errors: Array[Dictionary]) -> String:
	var cmp := String(node.get("cmp", ">"))
	if not ISA.CMP_FROM_TEXT.has(cmp):
		errors.append({"node": id,
			"message": "'%s' is not a comparison." % cmp,
			"hint": "Use one of <  <=  >  >=  ==  !="})
		cmp = ">"
	return "%s %s %s" % [_value(node, "lhs", "ALT"), cmp, _value(node, "rhs", "0")]


static func _value(node: Dictionary, key: String, fallback: String) -> String:
	if not node.has(key):
		return fallback
	var v: Variant = node[key]
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return str(v)
	var s := String(v).strip_edges()
	return fallback if s.is_empty() else s


static func _label_or_end(id: String, label_of: Dictionary) -> String:
	if id.is_empty() or not label_of.has(id):
		return "__end"
	return String(label_of[id])


## Builds a graph from a linear list of assembly-ish steps. Used by Mission
## Control to hand the player a graph they can edit rather than raw text.
static func linear_graph(steps: Array) -> Dictionary:
	var nodes: Array = []
	for i in steps.size():
		var step: Dictionary = steps[i].duplicate()
		step["id"] = "n%d" % (i + 1)
		if i + 1 < steps.size():
			step["next"] = "n%d" % (i + 2)
		nodes.append(step)
	return {"entry": "n1", "nodes": nodes}
