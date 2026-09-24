extends GutTest

## AC1, from several angles, plus the replay guarantee in AC7.

const REFERENCE_MISSION := "insertion"


func _mission() -> Mission:
	var m := MissionDB.get_mission(REFERENCE_MISSION)
	assert_not_null(m, "the determinism suite needs the '%s' mission" % REFERENCE_MISSION)
	return m


func _fly(seed: int = 0) -> RunResult:
	var m := _mission()
	var ship := MissionDB.ship_for(m)
	var program := Assembler.assemble(_reference_source())
	var world := MissionDB.world_for(m)
	var runner := SimRunner.new()
	runner.setup(m, world, ship.to_profile(), program, ship.content_hash(), seed)
	return runner.run()


func _reference_source() -> String:
	var d: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://missions/04_insertion.json")
	)
	return String((d as Dictionary).get("reference", {}).get("solution", ""))


func test_the_same_inputs_produce_the_same_bits() -> void:
	var a := _fly()
	var b := _fly()
	assert_eq(a.state_hash, b.state_hash)
	assert_eq(a.ticks, b.ticks)
	assert_eq(a.fuel_used, b.fuel_used, "exact equality, not almost")
	assert_eq(a.instructions_executed, b.instructions_executed)


func test_a_fresh_world_does_not_inherit_anything() -> void:
	# Bodies memoise their positions; a stale memo would leak between runs.
	var first := _fly()
	for _i in 3:
		var other := MissionDB.get_mission("reaching_lyra")
		if other != null:
			var w := MissionDB.world_for(other)
			w.bodies[0].pos_x(12345.678)
	var again := _fly()
	assert_eq(
		first.state_hash,
		again.state_hash,
		"running other missions in between must not change the answer"
	)


func test_the_simulation_draws_no_random_numbers() -> void:
	# If anything in the sim consulted the global RNG, seeding it differently
	# would change the outcome. Nothing should.
	seed(1)
	var a := _fly()
	seed(999999)
	randomize()
	var b := _fly()
	assert_eq(
		a.state_hash,
		b.state_hash,
		"the simulation must not depend on the global random number generator"
	)


func test_the_state_hash_notices_a_difference() -> void:
	# A hash that never changes would pass every test above and prove nothing.
	var m := _mission()
	var ship := MissionDB.ship_for(m)
	var world := MissionDB.world_for(m)

	var normal := SimRunner.new()
	normal.setup(m, world, ship.to_profile(), Assembler.assemble(_reference_source()))
	var a := normal.run()

	var nudged_world := MissionDB.world_for(m)
	var nudged := SimRunner.new()
	nudged.setup(
		m,
		nudged_world,
		ship.to_profile(),
		Assembler.assemble(_reference_source().replace("BURN    0.25", "BURN    0.26"))
	)
	var b := nudged.run()

	assert_ne(a.state_hash, b.state_hash, "a different program must produce a different hash")


func test_a_solution_file_round_trips_and_reproduces_the_run() -> void:
	# AC7: a solution file re-imports and reproduces the run.
	var m := _mission()
	var ship := MissionDB.ship_for(m)
	var program := Assembler.assemble(_reference_source())
	var world := MissionDB.world_for(m)
	var runner := SimRunner.new()
	runner.setup(m, world, ship.to_profile(), program, ship.content_hash(), 4242)
	var original := runner.run()

	var solution := SolutionFile.from_run(m, ship, program, original, "a test flight")
	var text := solution.to_json()

	var errors: Array[String] = []
	var reloaded := SolutionFile.from_json(text, errors)
	assert_eq(errors.size(), 0, ", ".join(errors))
	assert_not_null(reloaded)
	assert_eq(reloaded.mission_id, m.id)
	assert_eq(reloaded.seed, 4242)

	var replay := reloaded.replay(errors)
	assert_eq(errors.size(), 0, ", ".join(errors))
	assert_true(
		replay["ok"],
		"a re-imported solution must reproduce the run exactly: " + ", ".join(replay["differences"])
	)

	var replayed: RunResult = replay["result"]
	assert_eq(replayed.state_hash, original.state_hash)
	assert_eq(replayed.fuel_used, original.fuel_used)
	assert_eq(replayed.stars, original.stars)


func test_a_tampered_solution_file_is_reported_rather_than_believed() -> void:
	var m := _mission()
	var ship := MissionDB.ship_for(m)
	var program := Assembler.assemble(_reference_source())
	var world := MissionDB.world_for(m)
	var runner := SimRunner.new()
	runner.setup(m, world, ship.to_profile(), program, ship.content_hash(), 0)
	var original := runner.run()

	var solution := SolutionFile.from_run(m, ship, program, original)
	solution.recorded["fuel_used"] = 1.0  # claim an impossible flight
	solution.recorded["state_hash"] = "deadbeefdeadbeef"

	var errors: Array[String] = []
	var replay := solution.replay(errors)
	assert_false(replay["ok"], "the claim should not survive a replay")
	assert_gt(replay["differences"].size(), 0)
	var joined := ", ".join(replay["differences"])
	assert_string_contains(joined, "fuel used", "and the report should name what did not match")


func test_a_solution_file_from_the_future_is_refused_politely() -> void:
	var errors: Array[String] = []
	var bogus := (
		JSON
		. stringify(
			{
				"magic": SolutionFile.MAGIC,
				"format_version": SolutionFile.FORMAT_VERSION + 99,
				"mission_id": "insertion",
			}
		)
	)
	assert_null(SolutionFile.from_json(bogus, errors))
	assert_gt(errors.size(), 0)
	assert_string_contains(String(errors[0]).to_lower(), "newer")


func test_something_that_is_not_a_solution_file_is_refused() -> void:
	var errors: Array[String] = []
	assert_null(SolutionFile.from_json('{"hello": 1}', errors))
	assert_null(SolutionFile.from_json("not json at all", errors))
	assert_gt(errors.size(), 0)
