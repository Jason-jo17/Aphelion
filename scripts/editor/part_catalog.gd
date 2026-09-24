class_name PartCatalog
extends RefCounted

## The loaded contents of data/parts.json.

const DATA_PATH := "res://data/parts.json"

var grid_width: int = 9
var grid_height: int = 14
var cell_size: float = 1.0

var parts: Array[PartDef] = []
var _by_id: Dictionary = {}

static var _shared: PartCatalog = null


## The process-wide catalogue, loaded on first use.
static func shared() -> PartCatalog:
	if _shared == null:
		_shared = PartCatalog.new()
		var err := _shared.load_from(DATA_PATH)
		if err != OK:
			push_error("PartCatalog: could not load %s (error %d)" % [DATA_PATH, err])
	return _shared


func load_from(path: String) -> int:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return ERR_FILE_CANT_OPEN
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return ERR_PARSE_ERROR
	return load_from_dict(parsed)


func load_from_dict(d: Dictionary) -> int:
	parts.clear()
	_by_id.clear()
	var g: Dictionary = d.get("grid", {})
	grid_width = int(g.get("width", 9))
	grid_height = int(g.get("height", 14))
	cell_size = float(g.get("cell_size", 1.0))
	for entry in d.get("parts", []):
		var p := PartDef.from_dict(entry)
		if p.id.is_empty():
			continue
		parts.append(p)
		_by_id[p.id] = p
	return OK


func get_part(id: String) -> PartDef:
	return _by_id.get(id, null)


func has_part(id: String) -> bool:
	return _by_id.has(id)


func by_category(category: String) -> Array[PartDef]:
	var out: Array[PartDef] = []
	for p in parts:
		if p.category == category:
			out.append(p)
	return out


func categories() -> PackedStringArray:
	# Fixed order so the editor palette never reshuffles itself between runs.
	return PackedStringArray(
		[
			PartDef.CAT_COMMAND,
			PartDef.CAT_ENGINE,
			PartDef.CAT_FUEL,
			PartDef.CAT_CONTROL,
			PartDef.CAT_STRUCTURE,
		]
	)
