extends Node

## Autoload. The player's record: which missions are solved, the best run of
## each, and the history behind those bests.
##
## Persisted as JSON under user://. CLAUDE.md allows SQLite or JSON for v1, and
## JSON wins here: the leaderboard is local and single-player, the whole file is
## a few hundred kilobytes, and it costs no native dependency — which keeps the
## headless CI build and the three-platform export matrix simple. The storage
## boundary is this file alone, so moving to SQLite later touches nothing else.

signal record_saved(mission_id: String, result: RunResult, is_new_best: bool)
signal progress_changed()

const PATH := "user://profile.json"
const BACKUP_PATH := "user://profile.backup.json"
const SCHEMA_VERSION := 1

## How many past runs to keep per mission, newest first.
const HISTORY_LIMIT := 25

## mission_id -> {best: Dictionary, history: Array[Dictionary], attempts: int,
##                best_fuel: Dictionary, best_time: Dictionary, best_instructions: Dictionary}
var records: Dictionary = {}

## mission_id -> the last program the player ran, so returning to a mission
## picks up where they left off.
var drafts: Dictionary = {}

var _dirty := false


func _ready() -> void:
	load_profile()


# --- queries ---------------------------------------------------------------


func has_solved(mission_id: String) -> bool:
	var r := best_for(mission_id)
	return r != null and r.success


func stars_for(mission_id: String) -> int:
	var r := best_for(mission_id)
	return r.stars if r != null else 0


func total_stars() -> int:
	var n := 0
	for id in records:
		n += int(records[id].get("best", {}).get("stars", 0))
	return n


func attempts_for(mission_id: String) -> int:
	return int(records.get(mission_id, {}).get("attempts", 0))


func best_for(mission_id: String) -> RunResult:
	var rec: Dictionary = records.get(mission_id, {})
	if rec.is_empty() or not rec.has("best"):
		return null
	return RunResult.from_dict(rec["best"])


## The best run for one metric specifically — the leaderboard shows all three,
## because a fuel record and a speed record are rarely the same flight.
func best_for_metric(mission_id: String, metric: String) -> RunResult:
	var rec: Dictionary = records.get(mission_id, {})
	var key := "best_" + metric
	if not rec.has(key):
		return null
	return RunResult.from_dict(rec[key])


func history_for(mission_id: String) -> Array[RunResult]:
	var out: Array[RunResult] = []
	for d in records.get(mission_id, {}).get("history", []):
		out.append(RunResult.from_dict(d))
	return out


## Is a mission unlocked? The first two are always open; after that, a mission
## opens once the one before it has been solved. Players who get stuck can turn
## this off in the settings — a puzzle you cannot reach is not a puzzle.
func is_unlocked(mission_id: String) -> bool:
	var idx := MissionDB.mission_index(mission_id)
	if idx <= 1:
		return true
	var prev: Mission = MissionDB.missions[idx - 1]
	return has_solved(prev.id)


# --- recording -------------------------------------------------------------


## Files a completed run. Returns true if it became the overall personal best.
func record(mission_id: String, result: RunResult) -> bool:
	var rec: Dictionary = records.get(mission_id, {
		"attempts": 0, "history": [],
	})
	rec["attempts"] = int(rec.get("attempts", 0)) + 1

	var history: Array = rec.get("history", [])
	history.push_front(result.to_dict())
	while history.size() > HISTORY_LIMIT:
		history.pop_back()
	rec["history"] = history

	var is_best := false
	if result.success:
		var incumbent := best_for(mission_id)
		if Scoring.is_better(result, incumbent):
			rec["best"] = result.to_dict(true)   # keep the trajectory, for replay
			is_best = true
		for metric in [Scoring.METRIC_FUEL, Scoring.METRIC_TIME, Scoring.METRIC_INSTRUCTIONS]:
			var key := "best_" + metric
			var current: RunResult = null
			if rec.has(key):
				current = RunResult.from_dict(rec[key])
			if Scoring.is_better(result, current, metric):
				rec[key] = result.to_dict(true)

	records[mission_id] = rec
	_dirty = true
	save_profile()
	record_saved.emit(mission_id, result, is_best)
	progress_changed.emit()
	return is_best


func save_draft(mission_id: String, program: Program, ship: Ship) -> void:
	drafts[mission_id] = {
		"program": program.to_dict(),
		"ship": ship.to_dict() if ship != null else {},
	}
	_dirty = true
	save_profile()


func load_draft(mission_id: String) -> Dictionary:
	return drafts.get(mission_id, {})


func clear_mission(mission_id: String) -> void:
	records.erase(mission_id)
	drafts.erase(mission_id)
	_dirty = true
	save_profile()
	progress_changed.emit()


func clear_all() -> void:
	records.clear()
	drafts.clear()
	_dirty = true
	save_profile()
	progress_changed.emit()


# --- persistence -----------------------------------------------------------


func load_profile() -> void:
	var text := FileAccess.get_file_as_string(PATH)
	if text.is_empty():
		text = FileAccess.get_file_as_string(BACKUP_PATH)
		if not text.is_empty():
			push_warning("Profile: main file unreadable, recovered from backup.")
	if text.is_empty():
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Profile: %s is not valid JSON; leaving it alone and starting fresh." % PATH)
		return
	var d: Dictionary = parsed
	if int(d.get("schema_version", 0)) > SCHEMA_VERSION:
		push_warning("Profile was written by a newer version of Aphelion; "
			+ "loading what is recognisable.")
	records = d.get("records", {})
	drafts = d.get("drafts", {})


func save_profile() -> void:
	if not _dirty:
		return
	# Write the backup before the main file, so a crash mid-write can never
	# leave both unreadable.
	var existing := FileAccess.get_file_as_string(PATH)
	if not existing.is_empty():
		var b := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
		if b != null:
			b.store_string(existing)
			b.close()

	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("Profile: cannot write %s" % PATH)
		return
	f.store_string(JSON.stringify({
		"schema_version": SCHEMA_VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"records": records,
		"drafts": drafts,
	}, "  "))
	f.close()
	_dirty = false


## Campaign summary for the menu.
func summary() -> Dictionary:
	var solved := 0
	var total := 0
	for m in MissionDB.playable_missions():
		total += 1
		if has_solved(m.id):
			solved += 1
	return {
		"solved": solved,
		"total": total,
		"stars": total_stars(),
		"max_stars": total * 3,
	}
