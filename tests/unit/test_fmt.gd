extends GutTest

## Fmt turns numbers into the text the player reads, and had no tests at all
## until a rendered screenshot showed the flight map labelling both apsides
## "%g km".


func test_coarse_distance_drops_a_pointless_decimal() -> void:
	assert_eq(Fmt.distance_coarse(95000.0), "95 km")
	assert_eq(Fmt.distance_coarse(95400.0), "95.4 km")
	assert_eq(Fmt.distance_coarse(740000.0), "740 km")
	assert_eq(Fmt.distance_coarse(1500.0), "1.5 km")


func test_coarse_distance_switches_units_at_sensible_places() -> void:
	assert_eq(Fmt.distance_coarse(950.0), "950 m")
	assert_eq(Fmt.distance_coarse(0.0), "0 m")
	assert_eq(Fmt.distance_coarse(12000000.0), "12.0 Mm")
	assert_eq(Fmt.distance_coarse(INF), "∞")


func test_coarse_distance_handles_negatives_without_producing_minus_zero() -> void:
	assert_eq(Fmt.distance_coarse(-95000.0), "-95 km")
	assert_eq(Fmt.distance_coarse(-0.4), "0 m", "a rounded-away negative is not '-0'")


func test_counts_are_grouped_and_never_carry_a_decimal_point() -> void:
	# "Instructions executed  3665.0" was on the results screen, because a count
	# was going through number(), which is for measurements.
	assert_eq(Fmt.count(3665), "3,665")
	assert_eq(Fmt.count(0), "0")
	assert_eq(Fmt.count(999), "999")
	assert_eq(Fmt.count(1000), "1,000")
	assert_eq(Fmt.count(1638962), "1,638,962")
	assert_eq(Fmt.count(-1234), "-1,234")


func test_objectives_read_coarsely_and_instruments_do_not() -> void:
	# "periapsis at least 90.00 km" in a briefing reads like a measured
	# tolerance; the mission author just typed ninety.
	assert_eq(Fmt.sensor_value(ISA.Sensor.PERI, 90000.0, true), "90 km")
	assert_eq(Fmt.sensor_value(ISA.Sensor.PERI, 90000.0), "90.00 km")
	assert_eq(
		Fmt.sensor_value(ISA.Sensor.VEL, 2232.0, true),
		Fmt.sensor_value(ISA.Sensor.VEL, 2232.0),
		"coarse only affects distances; a speed is already as rounded as it gets"
	)


func test_every_format_string_in_the_project_uses_a_conversion_gdscript_has() -> void:
	# GDScript's `%` operator supports a subset of C's conversions. Asking for
	# one it does not have — `%g` is the tempting one — does not raise: it pushes
	# an engine error and substitutes the literal text, so the wrong string ends
	# up on screen or, worse, in a file. It has happened twice: "%g km" on every
	# apsis marker, and "%.17g" as the fuel figure in the cross-platform
	# determinism report, where it meant the comparator diffed a constant and
	# could never have reported a difference.
	var supported := "sdifeExXoc%"
	var pattern := RegEx.create_from_string("%[-+#0-9.*]*[A-Za-z%]")
	var offenders := PackedStringArray()

	for path in _gd_files("res://scripts") + _gd_files("res://tools"):
		var text := FileAccess.get_file_as_string(path)
		var line_no := 0
		for line in text.split("\n"):
			line_no += 1
			var code := String(line).strip_edges()
			if code.begins_with("#") or code.begins_with("##"):
				continue  # prose, not a format string
			for m in pattern.search_all(code):
				var token := m.get_string()
				var conv := token.substr(token.length() - 1)
				if not supported.contains(conv):
					offenders.append("%s:%d  %s" % [path, line_no, token])

	assert_eq(
		offenders,
		PackedStringArray(),
		(
			"these use a conversion GDScript's %% operator does not have. "
			+ "For %%g, see Fmt._trim_zero(); for the raw bits of a double, "
			+ "PackedFloat64Array([v]).to_byte_array().hex_encode()."
		)
	)


func _gd_files(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		var name := f.trim_suffix(".remap")
		if name.ends_with(".gd"):
			out.append("%s/%s" % [dir_path, name])
	for sub in dir.get_directories():
		out.append_array(_gd_files("%s/%s" % [dir_path, sub]))
	return out
