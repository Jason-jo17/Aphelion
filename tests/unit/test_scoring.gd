extends GutTest

## Scoring, personal bests, predicates and the design tokens' contrast.


func test_the_star_label_does_not_print_forty_five_glyphs() -> void:
	# A mission has three stars and shows them individually. The campaign total
	# is forty-five, and a row of forty-five tiny glyphs on the menu reads as
	# corruption rather than progress.
	assert_eq(_stars_text(2, 3), "★★☆  2/3")
	assert_eq(_stars_text(0, 3), "☆☆☆  0/3")
	assert_eq(_stars_text(0, 45), "★  0/45")
	assert_eq(_stars_text(12, 45), "★  12/45")

	var label := UIKit.stars_label(12, 45)
	assert_eq(
		label.tooltip_text, "12 of 45 stars", "the tooltip still spells it out, however it is drawn"
	)
	label.free()


## Labels are not added to the tree here, so nothing else will free them.
func _stars_text(earned: int, total: int) -> String:
	var label := UIKit.stars_label(earned, total)
	var text := label.text
	label.free()
	return text


func _result(success: bool, fuel: float, elapsed: float, instructions: int) -> RunResult:
	var r := RunResult.new()
	r.success = success
	r.fuel_used = fuel
	r.elapsed = elapsed
	r.instruction_count = instructions
	return r


func _mission(fuel: float, time: float, instructions: int) -> Mission:
	var m := Mission.new()
	m.id = "test"
	m.star_fuel = fuel
	m.star_time = time
	m.star_instructions = instructions
	return m


func test_a_star_per_metric_met() -> void:
	var m := _mission(100.0, 60.0, 10)
	var r := _result(true, 90.0, 50.0, 8)
	Scoring.apply(m, r)
	assert_eq(r.stars, 3)
	assert_true(r.star_fuel and r.star_time and r.star_instructions)


func test_metrics_are_scored_independently() -> void:
	var m := _mission(100.0, 60.0, 10)
	var r := _result(true, 90.0, 500.0, 40)
	Scoring.apply(m, r)
	assert_eq(r.stars, 1, "cheap but slow and long earns exactly one star")
	assert_true(r.star_fuel)
	assert_false(r.star_time)
	assert_false(r.star_instructions)


func test_the_threshold_is_inclusive() -> void:
	var m := _mission(100.0, 60.0, 10)
	var r := _result(true, 100.0, 60.0, 10)
	Scoring.apply(m, r)
	assert_eq(r.stars, 3, "hitting the number exactly must count")


func test_a_failed_run_scores_nothing() -> void:
	var m := _mission(100.0, 60.0, 10)
	var r := _result(false, 1.0, 1.0, 1)
	Scoring.apply(m, r)
	assert_eq(r.stars, 0, "you do not get a fuel star for not finishing")


func test_success_beats_failure() -> void:
	assert_true(Scoring.is_better(_result(true, 999.0, 999.0, 99), _result(false, 1.0, 1.0, 1)))


func test_more_stars_beats_fewer() -> void:
	var a := _result(true, 10.0, 10.0, 10)
	a.stars = 3
	var b := _result(true, 1.0, 1.0, 1)
	b.stars = 1
	assert_true(Scoring.is_better(a, b))


func test_the_chosen_metric_breaks_the_tie() -> void:
	var cheap := _result(true, 10.0, 900.0, 40)
	var quick := _result(true, 900.0, 10.0, 40)
	assert_true(Scoring.is_better(cheap, quick, Scoring.METRIC_FUEL))
	assert_true(Scoring.is_better(quick, cheap, Scoring.METRIC_TIME))


func test_anything_beats_nothing() -> void:
	assert_true(
		Scoring.is_better(_result(false, 0.0, 0.0, 0), null),
		"the first attempt is always the best one so far"
	)


func test_the_breakdown_reports_both_numbers() -> void:
	var m := _mission(100.0, 60.0, 10)
	var r := _result(true, 150.0, 50.0, 10)
	Scoring.apply(m, r)
	var rows := Scoring.breakdown(m, r)
	assert_eq(rows.size(), 3)
	for row in rows:
		assert_false(String(row["value_text"]).is_empty())
		assert_false(String(row["target_text"]).is_empty())
	assert_almost_eq(
		float(rows[0]["over_fraction"]), 0.5, 1.0e-9, "150 against a target of 100 is 50% over"
	)


# --- predicates ------------------------------------------------------------


func test_predicates_describe_themselves() -> void:
	var errors: Array[String] = []
	var p := Predicate.from_dict({"sensor": "APO", "op": ">=", "value": 100000}, errors)
	assert_eq(errors.size(), 0)
	var text := p.describe().to_lower()
	assert_string_contains(text, "apoapsis")
	assert_string_contains(text, "at least")


func test_a_compound_predicate_reads_as_a_sentence() -> void:
	var errors: Array[String] = []
	var p := (
		Predicate
		. from_dict(
			{
				"all":
				[
					{"sensor": "PERI", "op": ">=", "value": 90000},
					{"sensor": "ECC", "op": "<=", "value": 0.01},
				]
			},
			errors
		)
	)
	assert_string_contains(p.describe(), " and ")
	assert_eq(p.parts().size(), 2, "the panel ticks them off one at a time")


func test_a_sustain_predicate_says_how_long() -> void:
	var errors: Array[String] = []
	var p := Predicate.from_dict(
		{"sustain": 30.0, "of": {"sensor": "ECC", "op": "<=", "value": 0.01}}, errors
	)
	assert_string_contains(p.describe().to_lower(), "held for")


func test_a_malformed_predicate_fails_loudly() -> void:
	var errors: Array[String] = []
	var p := Predicate.from_dict({"sensor": "NOT_A_SENSOR", "op": ">=", "value": 1}, errors)
	assert_eq(
		p.kind, Predicate.Kind.NEVER, "an unwinnable mission must be obvious at load, not at play"
	)
	assert_gt(errors.size(), 0)


func test_infinity_survives_json() -> void:
	var errors: Array[String] = []
	var p := Predicate.from_dict({"sensor": "APO", "op": "<", "value": "inf"}, errors)
	assert_eq(errors.size(), 0)
	assert_true(is_inf(p.value))


# --- tokens: accessibility is a test, not an intention ---------------------


func test_body_text_meets_wcag_aa_in_both_themes() -> void:
	for palette in [Tokens.DARK, Tokens.LIGHT]:
		for pair in [
			["text", "bg"],
			["text", "surface"],
			["text", "surface_high"],
			["text_muted", "bg"],
			["text_muted", "surface"],
			["accent", "bg"],
			["accent", "surface"],
			["accent_text", "accent"],
			["success", "surface"],
			["warning", "surface"],
			["danger", "surface"]
		]:
			var ratio := Tokens.contrast(palette[pair[0]], palette[pair[1]])
			assert_gte(
				ratio,
				4.5,
				(
					"%s on %s is %.2f:1, below the 4.5:1 AA minimum for body text"
					% [pair[0], pair[1], ratio]
				)
			)


func test_ui_boundaries_meet_the_three_to_one_minimum() -> void:
	for palette in [Tokens.DARK, Tokens.LIGHT]:
		for bg in ["bg", "surface", "surface_high", "overlay"]:
			assert_gte(
				Tokens.contrast(palette["border_strong"], palette[bg]),
				3.0,
				"border_strong on %s must clear 3:1 (WCAG 1.4.11)" % bg
			)
		for bg2 in ["bg", "surface"]:
			assert_gte(
				Tokens.contrast(palette["focus"], palette[bg2]),
				3.0,
				"the focus ring must be visible on %s" % bg2
			)
			assert_gte(
				Tokens.contrast(palette["text_faint"], palette[bg2]),
				3.0,
				"even faint text must clear 3:1"
			)


func test_trajectory_colours_are_visible_in_both_palettes() -> void:
	for palette in [Tokens.TRAJECTORY_DEFAULT, Tokens.TRAJECTORY_COLORBLIND]:
		for role in palette:
			assert_gte(
				Tokens.contrast(palette[role], Tokens.DARK["bg"]),
				3.0,
				"trajectory '%s' must be visible against the starfield" % role
			)


func test_every_trajectory_role_has_its_own_line_style() -> void:
	# Colour is never the only signal: the map has to be readable in greyscale.
	var seen := {}
	for role in Tokens.TRAJECTORY_DEFAULT:
		assert_true(
			Tokens.TRAJECTORY_DASH.has(role), "'%s' needs a dash pattern as well as a colour" % role
		)
		var key := str(Tokens.TRAJECTORY_DASH[role])
		assert_false(
			seen.has(key), "'%s' shares a line style with '%s'" % [role, seen.get(key, "")]
		)
		seen[key] = role


func test_the_two_palettes_cover_the_same_roles() -> void:
	for role in Tokens.TRAJECTORY_DEFAULT:
		assert_true(
			Tokens.TRAJECTORY_COLORBLIND.has(role), "the colourblind palette is missing '%s'" % role
		)


func test_reduced_motion_removes_every_duration() -> void:
	var was := Settings.reduced_motion
	Settings.reduced_motion = true
	assert_eq(
		Tokens.duration(Tokens.DUR_BASE),
		0.0,
		"every animation goes through duration(), so the switch reaches all of them"
	)
	Settings.reduced_motion = false
	assert_eq(Tokens.duration(Tokens.DUR_BASE), Tokens.DUR_BASE)
	Settings.reduced_motion = was


func test_transitions_are_in_the_range_the_design_calls_for() -> void:
	for d in [Tokens.DUR_FAST, Tokens.DUR_BASE, Tokens.DUR_SLOW]:
		assert_gte(d, 0.15)
		assert_lte(d, 0.25)


# --- formatting ------------------------------------------------------------


func test_distances_pick_a_sensible_unit() -> void:
	assert_string_contains(Fmt.distance(1234.0), "km")
	assert_string_contains(Fmt.distance(12.0), "m")
	assert_string_contains(Fmt.distance(12000000.0), "Mm")
	assert_eq(Fmt.distance(INF), "∞")


func test_durations_drop_the_units_that_are_zero() -> void:
	assert_eq(Fmt.duration(45.0), "45s")
	assert_string_contains(Fmt.duration(125.0), "2m")
	assert_string_contains(Fmt.duration(3725.0), "1h")


func test_the_mission_clock_keeps_its_width() -> void:
	assert_eq(
		Fmt.clock(0.0).length(),
		Fmt.clock(35999.0).length(),
		"a clock that changes width jitters the whole panel"
	)
