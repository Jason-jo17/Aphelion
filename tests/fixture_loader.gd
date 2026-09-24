class_name FixtureLoader
extends RefCounted

## Reads tests/fixtures/*.json, the golden values produced by tools/refsim.
##
## Floats arrive as "<decimal>|<hex of the 8 bytes>" and are decoded from the
## bytes, never from the decimal. Godot's float parser is not correctly rounded
## — it lands up to 4 ULP away on some 16-digit values — so reading the decimal
## would let a parser difference masquerade as a physics difference. These
## fixtures exist to prove the shipped GDScript and the Python reference agree
## *bit for bit*; the decimal is only there so a human can read a diff.

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
		"inf", "+inf", "Infinity":
			return INF
		"-inf", "-Infinity":
			return -INF
		"nan":
			return NAN
	var bar := s.find("|")
	if bar == -1:
		push_error("FixtureLoader: %s carries no bit pattern; regenerate the fixtures" % s)
		return NAN
	return from_bits(s.substr(bar + 1))


## Decodes 16 hex digits — the eight little-endian bytes of a double — back
## into the exact value Python wrote out.
static func from_bits(hex: String) -> float:
	var bytes := hex.hex_decode()
	if bytes.size() != 8:
		push_error("FixtureLoader: %s is not eight bytes" % hex)
		return NAN
	return bytes.decode_double(0)
