extends Node

## Autoload. Loads the universe, the mission files and the stock ships once, and
## hands them out. Missions that fail to load are kept in the list with their
## errors attached, so a broken mission file is visible in the menu rather than
## silently absent.

const UNIVERSE_PATH := "res://data/universe.json"
const SHIPS_PATH := "res://data/ships.json"
const MISSIONS_DIR := "res://missions"

var universe: Dictionary = {}
var missions: Array[Mission] = []
var stock_ships: Dictionary = {}     ## id -> Dictionary as stored in ships.json

var load_errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	reload()


func reload() -> void:
	universe = {}
	missions.clear()
	stock_ships.clear()
	load_errors = PackedStringArray()

	universe = _read_json(UNIVERSE_PATH)
	if universe.is_empty():
		load_errors.append("Could not read %s." % UNIVERSE_PATH)

	var ships_doc := _read_json(SHIPS_PATH)
	for s in ships_doc.get("ships", []):
		stock_ships[String(s.get("id", ""))] = s

	for path in _mission_files():
		var d := _read_json(path)
		if d.is_empty():
			load_errors.append("Could not read %s." % path)
			continue
		var m := Mission.from_dict(d)
		if m.id.is_empty():
			load_errors.append("%s has no id." % path)
			continue
		missions.append(m)
		for e in m.errors:
			load_errors.append("%s: %s" % [m.id, e])

	missions.sort_custom(func(a: Mission, b: Mission) -> bool:
		if a.order != b.order:
			return a.order < b.order
		return a.id < b.id)


func _mission_files() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(MISSIONS_DIR)
	if dir == null:
		load_errors.append("No missions directory at %s." % MISSIONS_DIR)
		return out
	for f in dir.get_files():
		# Exported projects rename .json to .json.remap in some configurations.
		var name := f.trim_suffix(".remap")
		if name.ends_with(".json"):
			out.append("%s/%s" % [MISSIONS_DIR, name])
	out.sort()
	return out


func get_mission(id: String) -> Mission:
	for m in missions:
		if m.id == id:
			return m
	return null


func mission_index(id: String) -> int:
	for i in missions.size():
		if missions[i].id == id:
			return i
	return -1


## The mission after `id` in play order, or null at the end of the campaign.
func next_mission(id: String) -> Mission:
	var i := mission_index(id)
	if i < 0 or i + 1 >= missions.size():
		return null
	return missions[i + 1]


func playable_missions() -> Array[Mission]:
	var out: Array[Mission] = []
	for m in missions:
		if m.ok():
			out.append(m)
	return out


## Builds the Ship a mission hands the player, or null if it wants a custom one.
func ship_for(mission: Mission) -> Ship:
	if mission.ship_policy != "stock":
		return null
	return stock_ship(mission.stock_ship_id)


func stock_ship(id: String) -> Ship:
	if not stock_ships.has(id):
		return null
	return Ship.from_dict(stock_ships[id], PartCatalog.shared())


func stock_ship_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for k in stock_ships:
		out.append(String(k))
	out.sort()
	return out


## Builds the world a mission is flown in.
func world_for(mission: Mission) -> SimWorld:
	return mission.build_world(universe)


static func _read_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed
