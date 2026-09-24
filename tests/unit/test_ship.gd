extends GutTest

## Ship assembly: derived physics, and the validation that tells a player *why*
## a ship will not fly (AC5).

var _catalog: PartCatalog


func before_all() -> void:
	_catalog = PartCatalog.shared()


func _sparrow() -> Ship:
	return MissionDB.stock_ship("sparrow")


func test_the_catalogue_loads() -> void:
	assert_gt(_catalog.parts.size(), 8, "there should be a catalogue to build from")
	assert_not_null(_catalog.get_part("pod_mk1"))
	assert_null(_catalog.get_part("nonexistent_part"))


func test_stock_ship_profiles_match_the_reference() -> void:
	var fixtures: Array = FixtureLoader.load_json("ship_profiles.json")
	for case in fixtures:
		var ship := MissionDB.stock_ship(String(case["id"]))
		assert_not_null(ship, "stock ship '%s' must exist" % case["id"])
		var p := ship.to_profile()
		var who := String(case["id"])
		assert_eq(p.dry_mass, FixtureLoader.num(case["dry_mass"]), who + " dry mass")
		assert_eq(p.fuel_capacity, FixtureLoader.num(case["fuel_capacity"]), who + " fuel")
		assert_eq(p.max_thrust, FixtureLoader.num(case["max_thrust"]), who + " thrust")
		assert_eq(p.isp, FixtureLoader.num(case["isp"]), who + " isp")
		assert_eq(p.max_torque, FixtureLoader.num(case["max_torque"]), who + " torque")
		assert_eq(p.inertia, FixtureLoader.num(case["inertia"]), who + " inertia")
		assert_eq(p.drag_area, FixtureLoader.num(case["drag_area"]), who + " drag area")
		assert_eq(p.delta_v(), FixtureLoader.num(case["delta_v"]), who + " delta-v")


func test_every_stock_ship_is_flyable() -> void:
	for id in MissionDB.stock_ship_ids():
		var ship := MissionDB.stock_ship(id)
		var findings := ship.validate()
		var errors := PackedStringArray()
		for f in findings:
			if f["level"] == Ship.LEVEL_ERROR:
				errors.append("%s: %s" % [f["code"], f["message"]])
		assert_eq(
			errors.size(),
			0,
			(
				"stock ship '%s' must pass the same validation the editor applies: %s"
				% [id, ", ".join(errors)]
			)
		)


func test_mass_and_thrust_are_the_sum_of_the_parts() -> void:
	var ship := Ship.new(_catalog)
	ship.place("probe_core", 4, 0)
	ship.place("tank_medium", 4, 1)
	ship.place("engine_vacuum", 4, 4)
	var p := ship.to_profile()
	var expected_dry := (
		_catalog.get_part("probe_core").mass
		+ _catalog.get_part("tank_medium").mass
		+ _catalog.get_part("engine_vacuum").mass
	)
	assert_eq(p.dry_mass, expected_dry)
	assert_eq(p.fuel_capacity, _catalog.get_part("tank_medium").fuel_capacity)
	assert_eq(p.max_thrust, _catalog.get_part("engine_vacuum").thrust)


func test_mixed_engines_give_a_thrust_weighted_isp() -> void:
	var ship := Ship.new(_catalog)
	ship.place("probe_core", 4, 0)
	ship.place("tank_medium", 4, 1)
	ship.place("engine_vacuum", 4, 4)
	ship.place("engine_vernier", 5, 4)
	var p := ship.to_profile()
	var a := _catalog.get_part("engine_vacuum")
	var b := _catalog.get_part("engine_vernier")
	var expected := (a.thrust + b.thrust) / (a.thrust / a.isp + b.thrust / b.isp)
	assert_almost_eq(
		p.isp,
		expected,
		1.0e-9,
		"two engines burning from one tank give the harmonic mean, not the average"
	)
	assert_lt(p.isp, maxf(a.isp, b.isp))
	assert_gt(p.isp, minf(a.isp, b.isp))


func test_delta_v_follows_tsiolkovsky() -> void:
	var p := _sparrow().to_profile()
	var expected := (
		p.isp * ShipProfile.G0 * DetMath.log((p.dry_mass + p.fuel_capacity) / p.dry_mass)
	)
	assert_almost_eq(p.delta_v(), expected, 1.0e-9)


func test_delta_v_falls_as_the_tanks_drain() -> void:
	var p := _sparrow().to_profile()
	assert_gt(p.delta_v(p.fuel_capacity), p.delta_v(p.fuel_capacity * 0.5))
	assert_eq(p.delta_v(0.0), 0.0)


func test_inertia_grows_when_mass_moves_away_from_the_centre() -> void:
	var compact := Ship.new(_catalog)
	compact.place("probe_core", 4, 0)
	compact.place("tank_medium", 4, 1)
	compact.place("engine_vacuum", 4, 4)

	var stretched := Ship.new(_catalog)
	stretched.place("probe_core", 4, 0)
	stretched.place("structure_beam", 4, 1)
	stretched.place("structure_beam", 4, 2)
	stretched.place("structure_beam", 4, 3)
	stretched.place("tank_medium", 4, 4)
	stretched.place("engine_vacuum", 4, 7)

	assert_gt(
		stretched.moment_of_inertia(),
		compact.moment_of_inertia(),
		"a longer ship is harder to turn"
	)


func test_drag_area_comes_from_the_frontal_width() -> void:
	var narrow := Ship.new(_catalog)
	narrow.place("probe_core", 4, 0)
	narrow.place("tank_medium", 4, 1)
	narrow.place("engine_vacuum", 4, 4)

	var wide := Ship.new(_catalog)
	wide.place("probe_core", 4, 0)
	wide.place("tank_large", 4, 1)
	wide.place("engine_vacuum", 4, 5)

	assert_gt(
		wide.to_profile().drag_area, narrow.to_profile().drag_area, "a wider ship catches more air"
	)


func test_a_heat_shield_adds_drag_on_purpose() -> void:
	var plain := MissionDB.stock_ship("wren").to_profile()
	var shielded := MissionDB.stock_ship("petrel").to_profile()
	assert_gt(shielded.drag_area, plain.drag_area * 3.0, "the shield is the point of the Petrel")


# --- placement -------------------------------------------------------------


func test_parts_cannot_overlap() -> void:
	var ship := Ship.new(_catalog)
	assert_ne(ship.place("tank_medium", 4, 0), -1)
	assert_eq(ship.place("tank_medium", 4, 1), -1, "that cell is taken")
	assert_string_contains(ship.placement_blocked_reason("tank_medium", 4, 1).to_lower(), "overlap")


func test_parts_cannot_hang_off_the_grid() -> void:
	var ship := Ship.new(_catalog)
	assert_eq(ship.place("tank_medium", -1, 0), -1)
	assert_eq(ship.place("tank_medium", 4, _catalog.grid_height - 1), -1)
	assert_string_contains(ship.placement_blocked_reason("tank_medium", 99, 0).to_lower(), "fit")


func test_moving_a_part_ignores_its_own_cells() -> void:
	var ship := Ship.new(_catalog)
	var idx := ship.place("tank_medium", 4, 2)
	assert_true(ship.move(idx, 4, 3), "a part may be nudged into cells it already occupies")


func test_index_at_cell_finds_the_part_under_a_click() -> void:
	var ship := Ship.new(_catalog)
	var idx := ship.place("tank_medium", 4, 2)
	assert_eq(ship.index_at_cell(4, 3), idx)
	assert_eq(ship.index_at_cell(0, 0), -1)


# --- validation (AC5) ------------------------------------------------------


func _codes(ship: Ship) -> PackedStringArray:
	var out := PackedStringArray()
	for f in ship.validate():
		out.append(String(f["code"]))
	return out


func test_every_finding_carries_a_hint() -> void:
	var ship := Ship.new(_catalog)
	ship.place("tank_medium", 4, 0)
	for f in ship.validate():
		assert_false(
			String(f["hint"]).is_empty(),
			"'%s' must say what to do about it, not just that it is wrong" % f["code"]
		)


func test_an_empty_ship_says_where_to_start() -> void:
	var ship := Ship.new(_catalog)
	assert_true("empty" in _codes(ship))
	assert_false(ship.is_flyable())


func test_a_ship_with_no_engine_is_refused_with_a_reason() -> void:
	var ship := Ship.new(_catalog)
	ship.place("probe_core", 4, 0)
	ship.place("tank_medium", 4, 1)
	assert_true("no_engine" in _codes(ship))
	assert_false(ship.is_flyable())


func test_a_ship_with_no_propellant_is_refused() -> void:
	var ship := Ship.new(_catalog)
	ship.place("probe_core", 4, 0)
	ship.place("engine_vacuum", 4, 1)
	assert_true("no_fuel" in _codes(ship))


func test_a_ship_with_no_command_part_is_refused() -> void:
	var ship := Ship.new(_catalog)
	ship.place("tank_medium", 4, 0)
	ship.place("engine_vacuum", 4, 3)
	assert_true("no_command" in _codes(ship))


func test_two_command_parts_are_refused() -> void:
	var ship := Ship.new(_catalog)
	ship.place("probe_core", 4, 0)
	ship.place("probe_core", 5, 0)
	ship.place("tank_medium", 4, 1)
	ship.place("engine_vacuum", 4, 4)
	assert_true("multiple_command" in _codes(ship))


func test_a_floating_part_is_found_and_counted() -> void:
	var ship := Ship.new(_catalog)
	ship.place("probe_core", 4, 0)
	ship.place("tank_medium", 4, 1)
	ship.place("engine_vacuum", 4, 4)
	ship.place("structure_beam", 0, 10)  # nowhere near the rest
	assert_true("disconnected" in _codes(ship))
	assert_eq(ship.disconnected_indices().size(), 1)


func test_no_reaction_wheel_is_a_warning_not_a_refusal() -> void:
	var ship := Ship.new(_catalog)
	ship.place("probe_core", 4, 0)
	ship.place("tank_medium", 4, 1)
	ship.place("engine_vacuum", 4, 4)
	assert_true("no_wheel" in _codes(ship))
	assert_true(ship.is_flyable(), "it will fly; it just will not turn")


func test_low_thrust_to_weight_is_flagged_but_allowed() -> void:
	var ship := Ship.new(_catalog)
	ship.place("probe_core", 4, 0)
	ship.place("tank_large", 4, 1)
	ship.place("wheel_small", 4, 5)
	ship.place("engine_vernier", 4, 6)
	assert_true("low_twr" in _codes(ship))
	assert_true(ship.is_flyable(), "a tug that cannot lift off is still a valid tug")


# --- serialisation ---------------------------------------------------------


func test_a_ship_round_trips_through_a_dictionary() -> void:
	var ship := _sparrow()
	var copy := Ship.from_dict(ship.to_dict(), _catalog)
	assert_eq(copy.part_count(), ship.part_count())
	assert_eq(copy.content_hash(), ship.content_hash())
	assert_eq(copy.to_profile().delta_v(), ship.to_profile().delta_v())


func test_the_hash_ignores_the_order_parts_were_placed_in() -> void:
	var a := Ship.new(_catalog)
	a.place("probe_core", 4, 0)
	a.place("tank_medium", 4, 1)
	a.place("engine_vacuum", 4, 4)

	var b := Ship.new(_catalog)
	b.place("engine_vacuum", 4, 4)
	b.place("tank_medium", 4, 1)
	b.place("probe_core", 4, 0)

	assert_eq(
		a.content_hash(),
		b.content_hash(),
		"the same ship is the same ship however it was assembled"
	)


func test_different_ships_hash_differently() -> void:
	assert_ne(
		MissionDB.stock_ship("sparrow").content_hash(), MissionDB.stock_ship("wren").content_hash()
	)
