class_name FixtureLoader
extends RefCounted

## Reads tests/fixtures/*.json, the golden values produced by tools/refsim.
##
## Floats are stored as the shortest string that round-trips exactly, so
## `to_float()` gives back the identical double and the tests can compare with
## `==` rather than a tolerance. That is the point: these fixtures exist to
## prove the shipped GDScript and the Python reference agree *bit for bit*, and
## a tolerance would hide exactly the drift they are there to catch.

const DIR := "res://tests/fixtures/"


static func load_json(name: String) -> Variant:
	var text := FileAccess.get_file_as_string(DIR + name)
	if text.is_empty():
		push_error("FixtureLoader: could not read %s%s" % [DIR, name])
		return null
	return JSON.parse_string(text)


## Parses a fixture float, including the infinities JSON cannot express.
static func num(v: Variant) -> float:
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return float(v)
	var s := String(v).strip_edges()
	match s:
		"inf", "+inf", "Infinity": return INF
		"-inf", "-Infinity": return -INF
		"nan": return NAN
	return s.to_float()
