class_name Proposal
extends RefCounted

## What Mission Control came back with: a list of instructions it suggests, the
## assumptions it had to make to produce them, and whatever it wants to say
## about it.
##
## A proposal is never executed. It goes into the editor as text the player can
## read, change, or throw away. That is the whole point of the feature — the
## co-pilot is fallible on purpose, and the only defence against a fallible
## co-pilot is reading what it wrote.

## Raw instruction lines, in the game's own assembly language.
var ops: PackedStringArray = PackedStringArray()

## Things the model had to decide for itself because the order did not say.
## These are the teaching moment: an imprecise intent produces a long list here,
## and the manoeuvre that follows is wrong in exactly the way the list predicts.
var assumptions: PackedStringArray = PackedStringArray()

## A sentence of commentary, if it offered one.
var note: String = ""

## The intent the player typed, kept so the history panel can show both halves.
var intent: String = ""

## Provider and model that produced it.
var provider: String = ""
var model: String = ""

## Set when the reply could not be understood.
var parse_error: String = ""

## Assembly diagnostics for `ops`, filled in by `validate()`.
var program: Program = null


func ok() -> bool:
	return parse_error.is_empty() and not ops.is_empty()


func to_source() -> String:
	return "\n".join(ops)


## Assembles the proposed ops so the panel can show the player whether the
## suggestion even compiles *before* they accept it. A co-pilot that produces
## invalid instructions should be visibly wrong, not mysteriously wrong.
func validate() -> Program:
	program = Assembler.assemble(to_source())
	return program


func assembles() -> bool:
	if program == null:
		validate()
	return program.ok()


## One line for the history list.
func summary() -> String:
	if not parse_error.is_empty():
		return "could not be read: %s" % parse_error
	return (
		"%d instruction%s, %d assumption%s"
		% [
			ops.size(),
			"" if ops.size() == 1 else "s",
			assumptions.size(),
			"" if assumptions.size() == 1 else "s"
		]
	)


## Parses a provider reply.
##
## Models are asked for JSON and mostly return it, sometimes wrapped in a code
## fence or with a sentence in front. Rather than fail on that, the parser
## finds the outermost JSON object and reads it; if there is none, it falls
## back to treating the reply as bare assembly, since a model that ignores the
## format instruction and simply writes the program is still being useful.
static func from_reply(
	text: String, intent_: String, provider_: String, model_: String
) -> Proposal:
	var p := Proposal.new()
	p.intent = intent_
	p.provider = provider_
	p.model = model_

	var json_text := _extract_json_object(text)
	if not json_text.is_empty():
		# A model can reply with anything at all, so parse through an instance:
		# JSON.parse_string() would push an engine error for every malformed
		# reply, which is noise, not a fault in the game.
		var json := JSON.new()
		if json.parse(json_text) == OK and typeof(json.data) == TYPE_DICTIONARY:
			var d: Dictionary = json.data
			for line in d.get("ops", []):
				var s := String(line).strip_edges()
				if not s.is_empty():
					p.ops.append(s)
			for a in d.get("assumptions", []):
				var sa := String(a).strip_edges()
				if not sa.is_empty():
					p.assumptions.append(sa)
			p.note = String(d.get("note", "")).strip_edges()
			if p.ops.is_empty():
				p.parse_error = "The reply had no instructions in it."
			return p

	# No JSON. Take any lines that look like instructions.
	var salvaged := _salvage_assembly(text)
	if salvaged.is_empty():
		p.parse_error = "The reply was not in the expected format."
		p.note = text.substr(0, 400)
		return p
	p.ops = salvaged
	p.note = "The reply was not JSON, so these lines were read out of it directly."
	return p


## Finds the outermost {...} in a blob of text, tolerating code fences and
## prose either side of it.
static func _extract_json_object(text: String) -> String:
	var start := text.find("{")
	if start < 0:
		return ""
	var depth := 0
	var in_string := false
	var escaped := false
	for i in range(start, text.length()):
		var c := text[i]
		if in_string:
			if escaped:
				escaped = false
			elif c == "\\":
				escaped = true
			elif c == '"':
				in_string = false
			continue
		if c == '"':
			in_string = true
		elif c == "{":
			depth += 1
		elif c == "}":
			depth -= 1
			if depth == 0:
				return text.substr(start, i - start + 1)
	return ""


## Pulls plausible instruction lines out of an unstructured reply.
static func _salvage_assembly(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var known := {}
	for name in ISA.op_names_ordered():
		known[name] = true
	for raw in text.split("\n"):
		var line := String(raw).strip_edges()
		if line.is_empty() or line.begins_with("```"):
			continue
		var head := line.split(" ", false)
		if head.is_empty():
			continue
		var first := String(head[0]).to_upper().trim_suffix(":")
		if known.has(first) or line.ends_with(":") or line.begins_with(";"):
			out.append(line)
	return out
