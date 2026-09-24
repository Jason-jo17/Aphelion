extends Node

## Autoload. Loads the universe, the mission files and the stock ships once, and
## hands them out. Missions that fail to load are kept in the list with their
## errors attached, so a broken mission file is visible in the menu rather than
## silently absent.

# Kept as literals rather than aliases of MissionLoader's: a const initialised
# from another class's const makes the parse order matter, for no benefit.
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

	universe = MissionLoader.load_universe()
	if universe.is_empty():
		load_errors.append("Could not read %s." % UNIVERSE_PATH)

	stock_ships = MissionLoader.load_stock_ships()

	var errors: Array[String] = []
	missions = MissionLoader.load_missions(errors)
	for e in errors:
		load_errors.append(e)
	if missions.is_empty():
		load_errors.append("No missions were found in %s." % MISSIONS_DIR)


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

