extends SceneTree

## Flies every mission's reference solution and prints a machine-readable report
## of what each one produced.
##
## Run headless on Windows, macOS and Linux, and compare the output. If the
## three agree bit for bit, AC1 holds across operating systems; if they do not,
## the diff names the mission and the field that moved.
##
##     godot --headless --script res://tools/determinism_check.gd
##     godot --headless --script res://tools/determinism_check.gd -- --json out.json
##
## This runs as the main loop, which means no autoloads: everything it needs
## comes from MissionLoader, the same code the game uses.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var json_path := ""
	for i in args.size():
		if args[i] == "--json" and i + 1 < args.size():
			json_path = args[i + 1]

	var universe := MissionLoader.load_universe()
	if universe.is_empty():
		push_error("Could not read the universe definition.")
		quit(2)
		return

	var stock := MissionLoader.load_stock_ships()
	var errors: Array[String] = []
	var missions := MissionLoader.load_missions(errors)
	for e in errors:
		push_error(e)
	if missions.is_empty():
		push_error("No missions found.")
		quit(2)
		return

	var report := {
		"platform": OS.get_name(),
		"godot": Engine.get_version_info()["string"],
		"missions": [],
	}
	var failures := 0

	print("# Aphelion determinism report")
	print("# platform: %s   godot: %s" % [report["platform"], report["godot"]])
	print("# mission                 ticks       fuel_used  instr  stars  state_hash")

	for m in missions:
		var ref := MissionLoader.reference_for(m.id)
		if ref.is_empty() or String(ref.get("solution", "")).is_empty():
			printerr("%s: no reference solution" % m.id)
			failures += 1
			continue

		var ship_dict: Dictionary = stock.get(m.stock_ship_id, {})
		if ship_dict.is_empty():
			printerr("%s: unknown stock ship '%s'" % [m.id, m.stock_ship_id])
			failures += 1
			continue
		var ship := Ship.from_dict(ship_dict, PartCatalog.shared())

		var program := Assembler.assemble(String(ref["solution"]))
		if not program.ok():
			printerr("%s: reference solution does not assemble: %s"
				% [m.id, program.first_error_text()])
			failures += 1
			continue

		var world := m.build_world(universe)
		var runner := SimRunner.new()
		runner.setup(m, world, ship.to_profile(), program, ship.content_hash(), 0)
		var result := runner.run()

		# %.17g round-trips a double exactly, so a one-ULP difference between
		# platforms is visible in the text rather than rounded away.
		var row := {
			"id": m.id,
			"success": result.success,
			"ticks": result.ticks,
			"fuel_used": "%.17g" % result.fuel_used,
			"instructions": result.instruction_count,
			"stars": result.stars,
			"state_hash": result.state_hash,
			"outcome": result.outcome,
		}
		report["missions"].append(row)

		print("%-24s %8d  %18s  %5d  %5d  %s" % [
			m.id, result.ticks, row["fuel_used"],
			result.instruction_count, result.stars, result.state_hash])

		if not result.success:
			printerr("%s FAILED: %s %s" % [m.id, result.outcome, result.outcome_detail])
			failures += 1
		elif result.stars < 3:
			printerr("%s only scored %d stars; the reference should score three"
				% [m.id, result.stars])
			failures += 1
		elif result.state_hash != String(ref.get("state_hash", "")):
			printerr("%s state hash %s does not match the recorded %s"
				% [m.id, result.state_hash, ref.get("state_hash", "")])
			failures += 1

	if not json_path.is_empty():
		var f := FileAccess.open(json_path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(report, "  "))
			f.close()
			print("# wrote %s" % json_path)

	if failures > 0:
		printerr("%d of %d missions did not reproduce" % [failures, missions.size()])
	else:
		print("# all %d missions reproduced exactly" % missions.size())
	quit(1 if failures > 0 else 0)
