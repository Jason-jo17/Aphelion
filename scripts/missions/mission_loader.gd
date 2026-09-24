class_name MissionLoader
extends RefCounted

## Loading missions, the universe and the stock ships from disk.
##
## Static, and separate from the MissionDB autoload, because headless tools need
## exactly this and get no autoloads: `godot --headless --script` replaces the
## main loop, so nothing in [autoload] is ever instantiated. Keeping the loading
## here means the cross-platform determinism check in CI exercises the same code
## path the game does rather than a copy of it that can drift.

const UNIVERSE_PATH := "res://data/universe.json"
const SHIPS_PATH := "res://data/ships.json"
const MISSIONS_DIR := "res://missions"


static func read_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


static func load_universe() -> Dictionary:
	return read_json(UNIVERSE_PATH)


## id -> the raw ship dictionary from data/ships.json.
static func load_stock_ships() -> Dictionary:
	var out := {}
	for s in read_json(SHIPS_PATH).get("ships", []):
		out[String(s.get("id", ""))] = s
	return out


## Mission files, sorted so the order is the same on every platform —
## DirAccess.get_files() does not promise an order, and an unstable one would
## make the determinism check flaky for reasons that have nothing to do with
## determinism.
static func mission_files() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(MISSIONS_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		var name := f.trim_suffix(".remap")
		if name.ends_with(".json"):
			out.append("%s/%s" % [MISSIONS_DIR, name])
	out.sort()
	return out


## Loads every mission, in play order. `errors` collects anything wrong.
static func load_missions(errors: Array[String] = []) -> Array[Mission]:
	var out: Array[Mission] = []
	for path in mission_files():
		var d := read_json(path)
		if d.is_empty():
			errors.append("Could not read %s." % path)
			continue
		var m := Mission.from_dict(d)
		if m.id.is_empty():
			errors.append("%s has no id." % path)
			continue
		out.append(m)
		for e in m.errors:
			errors.append("%s: %s" % [m.id, e])
	out.sort_custom(func(a: Mission, b: Mission) -> bool:
		if a.order != b.order:
			return a.order < b.order
		return a.id < b.id)
	return out


## The `reference` block from a mission file: the program that solved it and the
## numbers that flight achieved.
static func reference_for(mission_id: String) -> Dictionary:
	for path in mission_files():
		var d := read_json(path)
		if String(d.get("id", "")) == mission_id:
			return d.get("reference", {})
	return {}
