class_name SolutionFile
extends RefCounted

## Export and import of a single solution: the mission it was flown against, the
## ship, the program, the seed, and what the run achieved.
##
## The point of the format is AC7: re-importing a file must reproduce the run.
## That means it has to carry enough identity to *detect* when it cannot —
## because a solution flown against an older mission file, or an older build of
## the simulation, is not the same solution any more. Rather than silently
## replaying to a different answer, `verify()` says exactly which part moved.

const EXTENSION := "aphelion"
const MAGIC := "aphelion.solution"
const FORMAT_VERSION := 1

## Bumped whenever a change to the physics, the VM or the scoring could alter
## the result of an existing solution. A mismatch is a warning, not a refusal:
## the run is replayed and the new numbers reported beside the old.
const SIM_VERSION := 1

var mission_id: String = ""
var mission_hash: String = ""
var ship: Dictionary = {}
var program: Dictionary = {}
var seed: int = 0
var recorded: Dictionary = {}  ## RunResult.to_dict() as it was when exported
var author_note: String = ""
var created_at: String = ""
var sim_version: int = SIM_VERSION


static func from_run(
	mission: Mission, ship_: Ship, program_: Program, result: RunResult, note: String = ""
) -> SolutionFile:
	var s := SolutionFile.new()
	s.mission_id = mission.id
	s.mission_hash = result.mission_hash
	s.ship = ship_.to_dict() if ship_ != null else {}
	s.program = program_.to_dict()
	s.seed = result.seed
	s.recorded = result.to_dict(false)
	s.author_note = note
	s.created_at = Time.get_datetime_string_from_system(true)
	return s


func to_json() -> String:
	return (
		JSON
		. stringify(
			{
				"magic": MAGIC,
				"format_version": FORMAT_VERSION,
				"sim_version": sim_version,
				"mission_id": mission_id,
				"mission_hash": mission_hash,
				"seed": seed,
				"ship": ship,
				"program": program,
				"recorded": recorded,
				"note": author_note,
				"created_at": created_at,
			},
			"  "
		)
	)


## Parses a solution file. Returns null and fills `error` when it cannot.
static func from_json(text: String, error: Array[String]) -> SolutionFile:
	# JSON.new().parse() rather than JSON.parse_string(): the static helper
	# pushes an engine error for malformed input, and a player opening the wrong
	# file is not an engine error — it is a message we want to phrase ourselves.
	var json := JSON.new()
	if json.parse(text) != OK:
		error.append(
			(
				"This is not a solution file — it is not valid JSON (line %d: %s)."
				% [json.get_error_line(), json.get_error_message()]
			)
		)
		return null
	if typeof(json.data) != TYPE_DICTIONARY:
		error.append("This is not a solution file — the top level is not an object.")
		return null
	var d: Dictionary = json.data
	if String(d.get("magic", "")) != MAGIC:
		error.append("This is not an Aphelion solution file.")
		return null
	if int(d.get("format_version", 0)) > FORMAT_VERSION:
		error.append(
			(
				"This solution was written by a newer version of Aphelion "
				+ (
					"(format %d, this build reads %d)."
					% [int(d.get("format_version", 0)), FORMAT_VERSION]
				)
			)
		)
		return null

	var s := SolutionFile.new()
	s.mission_id = String(d.get("mission_id", ""))
	s.mission_hash = String(d.get("mission_hash", ""))
	s.seed = int(d.get("seed", 0))
	s.ship = d.get("ship", {})
	s.program = d.get("program", {})
	s.recorded = d.get("recorded", {})
	s.author_note = String(d.get("note", ""))
	s.created_at = String(d.get("created_at", ""))
	s.sim_version = int(d.get("sim_version", 0))
	if s.mission_id.is_empty():
		error.append("The file does not say which mission it is for.")
		return null
	return s


func save_to(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(to_json())
	return OK


static func load_from(path: String, error: Array[String]) -> SolutionFile:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		error.append("Could not read %s." % path)
		return null
	return from_json(text, error)


## Suggested filename: mission, metrics and a short hash, so a folder full of
## them is readable without opening any.
func suggested_filename() -> String:
	var fuel := int(float(recorded.get("fuel_used", 0.0)))
	var secs := int(float(recorded.get("elapsed", 0.0)))
	var instr := int(recorded.get("instruction_count", 0))
	return "%s_%dkg_%ds_%di.%s" % [mission_id, fuel, secs, instr, EXTENSION]


# --- replay ----------------------------------------------------------------


## Re-flies the solution and compares it with what the file claims.
##
## Returns a dictionary with:
##   ok          — the replay reproduced the recorded result exactly
##   result      — the RunResult from this replay
##   differences — human-readable list of anything that did not match
##   warnings    — things that are suspicious but not disqualifying
func replay(error: Array[String]) -> Dictionary:
	var out := {"ok": false, "result": null, "differences": [], "warnings": []}

	var mission := MissionDB.get_mission(mission_id)
	if mission == null:
		error.append("This build has no mission called '%s'." % mission_id)
		return out
	if not mission.ok():
		error.append("Mission '%s' failed to load in this build." % mission_id)
		return out

	var ship_obj: Ship = null
	if ship.is_empty():
		ship_obj = MissionDB.ship_for(mission)
	else:
		ship_obj = Ship.from_dict(ship, PartCatalog.shared())
	if ship_obj == null:
		error.append("The solution names a ship this build cannot build.")
		return out

	var prog := Program.from_dict(program)
	if not prog.ok():
		error.append("The program in this solution does not assemble: %s" % prog.first_error_text())
		return out

	var world := MissionDB.world_for(mission)
	var runner := SimRunner.new()
	runner.setup(mission, world, ship_obj.to_profile(), prog, ship_obj.content_hash(), seed)
	var result := runner.run()
	out["result"] = result

	if sim_version != SIM_VERSION:
		out["warnings"].append(
			(
				(
					"Flown against simulation version %d; this build is version %d. "
					% [sim_version, SIM_VERSION]
				)
				+ "The numbers below are from replaying it here."
			)
		)
	if not mission_hash.is_empty() and mission_hash != result.mission_hash:
		out["warnings"].append(
			(
				"Mission '%s' has changed since this solution was recorded — its " % mission_id
				+ "objectives or star thresholds are not the same."
			)
		)

	var diffs: Array[String] = []
	_compare(diffs, "success", str(recorded.get("success", false)), str(result.success))
	_compare(
		diffs,
		"fuel used",
		"%.6f" % float(recorded.get("fuel_used", 0.0)),
		"%.6f" % result.fuel_used
	)
	_compare(diffs, "ticks", str(int(recorded.get("ticks", 0))), str(result.ticks))
	_compare(
		diffs,
		"instructions",
		str(int(recorded.get("instruction_count", 0))),
		str(result.instruction_count)
	)
	_compare(diffs, "stars", str(int(recorded.get("stars", 0))), str(result.stars))
	var recorded_hash := String(recorded.get("state_hash", ""))
	if not recorded_hash.is_empty():
		_compare(diffs, "final state", recorded_hash, result.state_hash)

	out["differences"] = diffs
	out["ok"] = diffs.is_empty()
	return out


static func _compare(into: Array[String], label: String, was: String, now: String) -> void:
	if was != now:
		into.append("%s: recorded %s, replayed %s" % [label, was, now])
