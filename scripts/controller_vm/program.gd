class_name Program
extends RefCounted

## An assembled flight-computer program, plus whatever went wrong assembling it.

const SOURCE_ISA := "isa"
const SOURCE_NODES := "nodes"

var instructions: Array[Instruction] = []

## Upper-cased label name -> instruction index.
var labels: Dictionary = {}

## Assembly diagnostics: {line, text, message, hint}.
var errors: Array[Dictionary] = []

var source: String = ""
var source_kind: String = SOURCE_ISA

## Set when the program came from the node editor, so the two views stay linked.
var node_graph: Dictionary = {}


func ok() -> bool:
	return errors.is_empty() and not instructions.is_empty()


func add_error(line: int, text: String, message: String, hint: String = "") -> void:
	errors.append({"line": line, "text": text, "message": message, "hint": hint})


## The scored size of the program: instructions only. Labels, comments and blank
## lines are free, so formatting a program readably never costs a star.
func instruction_count() -> int:
	return instructions.size()


## Renders back to assembly, one instruction per line, with labels restored.
func to_text() -> String:
	var at_index := {}
	for name in labels:
		var idx: int = labels[name]
		if not at_index.has(idx):
			at_index[idx] = []
		at_index[idx].append(name)

	var out := PackedStringArray()
	for i in instructions.size():
		if at_index.has(i):
			for name in at_index[i]:
				out.append("%s:" % String(name).to_lower())
		out.append("        " + instructions[i].to_text())
	if at_index.has(instructions.size()):
		for name in at_index[instructions.size()]:
			out.append("%s:" % String(name).to_lower())
	return "\n".join(out)


## First error as a single human-readable line, for compact UI.
func first_error_text() -> String:
	if errors.is_empty():
		return ""
	var e: Dictionary = errors[0]
	var s := "Line %d: %s" % [e["line"], e["message"]]
	if not String(e["hint"]).is_empty():
		s += " " + String(e["hint"])
	return s


## Stable hash of the compiled program, so a replay can prove it is running the
## same code. Built from the disassembly rather than the raw source, so
## reformatting or recommenting a program does not invalidate a recorded run.
func content_hash() -> String:
	var parts := PackedStringArray()
	for ins in instructions:
		parts.append(ins.to_text())
	return String("\n").join(parts).sha256_text().substr(0, 16)


func to_dict() -> Dictionary:
	var d := {"kind": source_kind, "source": source}
	if not node_graph.is_empty():
		d["nodes"] = node_graph
	return d


static func from_dict(d: Dictionary) -> Program:
	var kind := String(d.get("kind", SOURCE_ISA))
	if kind == SOURCE_NODES and d.has("nodes"):
		return NodeGraph.compile(d["nodes"])
	return Assembler.assemble(String(d.get("source", "")))


static func empty() -> Program:
	return Assembler.assemble("")
