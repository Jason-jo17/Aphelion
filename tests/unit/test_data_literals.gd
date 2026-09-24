extends GutTest

## Every number in data/ and missions/ must mean the same thing in Godot as it
## does in the Python reference.
##
## This is the one place in Aphelion where a decimal still has to survive a
## parser. Everywhere else the numbers are either derived from arithmetic or
## written as exact ratios (see scripts/core/det_math.gd), because Godot's
## float reader is not correctly rounded. On short literals it agrees with
## Python; on long fractions it does not, and not by a little. Halcyon's
## rotation rate, written out as 0.0002908882086657216, came back twenty-nine
## ULP away — enough to give four missions a different final state hash while
## every other test in the suite passed.
##
## So the fixture pins what each literal must parse to, and this test is the
## thing that notices when a new one does not.

var _lits: Array


func before_all() -> void:
	var loaded: Variant = FixtureLoader.load_json("data_literals.json")
	assert_not_null(loaded, "data_literals.json must load")
	_lits = loaded if loaded is Array else []


func test_every_number_in_the_data_files_parses_to_the_reference_bits() -> void:
	assert_gt(_lits.size(), 50, "the fixture should cover the whole of data/ and missions/")
	for entry in _lits:
		var e: Dictionary = entry
		var text := String(e["text"])
		var expected := String(e["bits"])
		var actual := PackedFloat64Array([text.to_float()]).to_byte_array().hex_encode()
		assert_eq(
			actual,
			expected,
			(
				(
					"%s in %s reads as a different double in Godot than in Python. "
					+ "Shorten it, or have the loader derive it — a rotation period is "
					+ "a round number, the rate it implies is not."
				)
				% [text, ", ".join(PackedStringArray(e["files"]))]
			)
		)


func test_the_fixture_matches_the_files_it_claims_to_cover() -> void:
	# A literal added to a mission without regenerating the fixture would
	# otherwise go unchecked, which is exactly the hole this is here to close.
	var pinned := {}
	for entry in _lits:
		pinned[String((entry as Dictionary)["text"])] = true

	var missing: Array[String] = []
	for folder in ["res://data", "res://missions"]:
		for lit in _literals_in(folder):
			if not pinned.has(lit):
				missing.append(lit)
	assert_eq(
		missing,
		[] as Array[String],
		(
			"these numbers are not in tests/fixtures/data_literals.json; "
			+ "regenerate it with tools/refsim/generate_fixtures.py"
		)
	)


func _literals_in(folder: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(folder)
	if dir == null:
		return out
	var number := RegEx.create_from_string(
		'(?<![\\w."])-?\\d+(?:\\.\\d+)?(?:[eE][-+]?\\d+)?(?![\\w.])'
	)
	for f in dir.get_files():
		var name := f.trim_suffix(".remap")
		if not name.ends_with(".json"):
			continue
		var text := FileAccess.get_file_as_string("%s/%s" % [folder, name])
		for m in number.search_all(text):
			var lit := m.get_string()
			# Plain integers parse exactly in every reader; only fractions and
			# exponents are at risk.
			if lit.contains(".") or lit.contains("e") or lit.contains("E"):
				if not out.has(lit):
					out.append(lit)
	return out
