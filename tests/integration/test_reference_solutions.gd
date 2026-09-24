extends GutTest

## Flies the reference solution for every mission.
##
## This is the test CLAUDE.md asks for by name: three-star solutions provable in
## CI. Each mission file carries the program that solved it and the fuel, time,
## instruction count and final-state hash that flight achieved. Re-flying them
## here proves three things at once:
##
## 1. every mission is still winnable;
## 2. the thresholds are still reachable, so the stars mean something;
## 3. the shipped GDScript agrees with the Python reference that produced the
##    numbers — *to the bit*, via the state hash.
##
## A change to the physics that quietly breaks a mission fails the build here
## rather than reaching a player.

const TIMEOUT_STEPS := 4_000_000


func test_every_mission_file_loads_without_complaint() -> void:
	assert_eq(
		MissionDB.load_errors.size(),
		0,
		"mission files must load cleanly: " + ", ".join(MissionDB.load_errors)
	)
	assert_gte(MissionDB.missions.size(), 12, "CLAUDE.md asks for at least twelve missions")


func test_missions_are_ordered_and_uniquely_identified() -> void:
	var seen_ids := {}
	var seen_order := {}
	for m in MissionDB.missions:
		assert_false(seen_ids.has(m.id), "duplicate mission id '%s'" % m.id)
		seen_ids[m.id] = true
		assert_false(
			seen_order.has(m.order),
			"missions '%s' and '%s' share order %d" % [m.id, seen_order.get(m.order, ""), m.order]
		)
		seen_order[m.order] = m.id


func test_every_mission_states_what_it_teaches_and_how_to_win() -> void:
	for m in MissionDB.missions:
		assert_false(m.title.is_empty(), "%s has no title" % m.id)
		assert_false(m.brief.is_empty(), "%s has no briefing" % m.id)
		assert_false(
			m.teaches.is_empty(),
			(
				"%s does not say what it teaches — if you cannot write that line, " % m.id
				+ "the mission is doing too much"
			)
		)
		assert_gt(m.objective_lines().size(), 0, "%s has no objectives" % m.id)
		assert_gt(m.hints.size(), 0, "%s offers no hints" % m.id)


func test_every_mission_carries_a_reference_solution() -> void:
	for m in MissionDB.missions:
		var ref := _reference_for(m.id)
		assert_false(
			ref.is_empty(),
			(
				"%s has no reference solution; regenerate with " % m.id
				+ "tools/refsim/author_missions.py --write"
			)
		)
		assert_false(String(ref.get("solution", "")).is_empty())


func test_every_reference_solution_wins_its_mission_with_three_stars() -> void:
	for m in MissionDB.missions:
		var ref := _reference_for(m.id)
		if ref.is_empty():
			continue
		var outcome := _fly(m, String(ref["solution"]))
		var result: RunResult = outcome["result"]

		assert_true(
			result.success,
			(
				"%s: the reference solution must still win. Got: %s %s"
				% [m.id, result.outcome, result.outcome_detail]
			)
		)
		if not result.success:
			continue

		assert_eq(
			result.stars,
			3,
			(
				(
					"%s: the reference flight is what the thresholds were derived from, "
					+ "so it must earn all three. fuel %.1f/%.1f, time %.1f/%.1f, "
					+ "instructions %d/%d"
				)
				% [
					m.id,
					result.fuel_used,
					m.star_fuel,
					result.elapsed,
					m.star_time,
					result.instruction_count,
					m.star_instructions
				]
			)
		)


func test_reference_flights_reproduce_the_recorded_numbers_exactly() -> void:
	# The recorded values were produced by tools/refsim, in Python. Matching
	# them here proves the two implementations have not drifted.
	for m in MissionDB.missions:
		var ref := _reference_for(m.id)
		if ref.is_empty():
			continue
		var outcome := _fly(m, String(ref["solution"]))
		var result: RunResult = outcome["result"]
		if not result.success:
			continue  # reported by the test above

		assert_eq(
			result.ticks,
			int(ref["ticks"]),
			"%s: tick count must match the reference implementation" % m.id
		)
		assert_almost_eq(
			result.fuel_used,
			float(ref["fuel_used"]),
			1.0e-6,
			"%s: fuel used must match the reference implementation" % m.id
		)
		assert_eq(
			result.instruction_count, int(ref["instructions"]), "%s: program size must match" % m.id
		)
		assert_eq(
			result.state_hash,
			String(ref["state_hash"]),
			(
				(
					"%s: the final state hash must match the Python reference exactly. "
					+ "A mismatch means scripts/physics/ and tools/refsim/ have drifted; "
					+ "fix both and regenerate."
				)
				% m.id
			)
		)


func test_running_a_mission_twice_gives_identical_results() -> void:
	# AC1, end to end, through the whole stack rather than the integrator alone.
	for m in MissionDB.missions:
		var ref := _reference_for(m.id)
		if ref.is_empty():
			continue
		var first: RunResult = _fly(m, String(ref["solution"]))["result"]
		var second: RunResult = _fly(m, String(ref["solution"]))["result"]
		assert_eq(first.state_hash, second.state_hash, "%s: state hash" % m.id)
		assert_eq(first.ticks, second.ticks, "%s: ticks" % m.id)
		assert_eq(first.fuel_used, second.fuel_used, "%s: fuel" % m.id)
		assert_eq(first.stars, second.stars, "%s: stars" % m.id)


func test_an_empty_program_never_wins() -> void:
	# Cheap sanity check that the missions are not trivially satisfied at T+0.
	for m in MissionDB.missions:
		var outcome := _fly(m, "HALT")
		var result: RunResult = outcome["result"]
		assert_false(
			result.success, "%s is satisfied by doing nothing, which makes it not a puzzle" % m.id
		)


func test_star_thresholds_are_set_and_plausible() -> void:
	for m in MissionDB.missions:
		assert_false(is_inf(m.star_fuel), "%s has no fuel threshold" % m.id)
		assert_false(is_inf(m.star_time), "%s has no time threshold" % m.id)
		assert_lt(m.star_instructions, 1000, "%s has no instruction threshold" % m.id)
		assert_gt(m.star_instructions, 0)


# --- helpers ---------------------------------------------------------------


func _reference_for(mission_id: String) -> Dictionary:
	# The reference block lives in the mission file beside the thresholds it
	# produced, so the answer key cannot go missing.
	var path := ""
	var dir := DirAccess.open(MissionDB.MISSIONS_DIR)
	if dir == null:
		return {}
	for f in dir.get_files():
		var name := f.trim_suffix(".remap")
		if not name.ends_with(".json"):
			continue
		var d: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("%s/%s" % [MissionDB.MISSIONS_DIR, name])
		)
		if typeof(d) == TYPE_DICTIONARY and String(d.get("id", "")) == mission_id:
			return d.get("reference", {})
	return {}


func _fly(mission: Mission, source: String) -> Dictionary:
	var ship := MissionDB.ship_for(mission)
	assert_not_null(ship, "%s names a stock ship this build does not have" % mission.id)
	var program := Assembler.assemble(source)
	assert_true(
		program.ok(),
		"%s: the reference solution must assemble: %s" % [mission.id, program.first_error_text()]
	)

	var world := MissionDB.world_for(mission)
	var runner := SimRunner.new()
	runner.setup(mission, world, ship.to_profile(), program, ship.content_hash(), 0)
	return {"result": runner.run(TIMEOUT_STEPS), "runner": runner}
