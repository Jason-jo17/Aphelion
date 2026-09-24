extends Control

## What the flight cost, what it earned, and what to do next.
##
## The metric breakdown shows both numbers — what you scored and what was needed
## — because "two stars" tells you nothing about which way to push, and the
## whole point of three separate metrics is that they pull against each other.

var _mission: Mission
var _result: RunResult


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mission = App.instance.active_mission
	_result = App.instance.last_result
	if _mission == null or _result == null:
		App.instance.go_to(App.Screen.MENU)
		return

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(Tokens.space(Tokens.SPACE_7)))
	add_child(margin)

	var columns := UIKit.hbox(Tokens.SPACE_6)
	margin.add_child(columns)

	var left := UIKit.vbox(Tokens.SPACE_4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	left.add_child(_verdict())
	left.add_child(_metrics())
	if _result.success:
		left.add_child(_flight_facts())
	left.add_child(UIKit.spacer())
	left.add_child(_actions())

	var right := UIKit.vbox(Tokens.SPACE_4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size = Vector2(Tokens.space(380.0), 0)
	columns.add_child(right)
	right.add_child(_personal_bests())
	right.add_child(_history())


func _verdict() -> Control:
	var card := UIKit.card(Tokens.SPACE_5)
	var column := UIKit.vbox(Tokens.SPACE_2)
	card.add_child(column)

	var headline := UIKit.heading("Objective complete" if _result.success else "Mission failed", 1)
	headline.add_theme_color_override(
		"font_color", Tokens.color("success" if _result.success else "danger")
	)
	column.add_child(headline)
	column.add_child(UIKit.heading(_mission.title, 3))

	if not _result.success:
		var why := UIKit.body(_result.outcome)
		why.add_theme_color_override("font_color", Tokens.color("danger"))
		column.add_child(why)
		if not _result.outcome_detail.is_empty():
			column.add_child(UIKit.body(_result.outcome_detail, true))
		if not _result.fault_hint.is_empty():
			column.add_child(UIKit.small(_result.fault_hint, "text_muted"))
	else:
		column.add_child(UIKit.stars_label(_result.stars))

	# A program that spent most of its ticks against the instruction budget is
	# almost always looping by accident; say so rather than leaving it to be
	# discovered.
	if _result.spin_ticks > 0 and _result.vm_ticks > 0:
		var fraction := float(_result.spin_ticks) / float(_result.vm_ticks)
		if fraction > 0.5:
			column.add_child(
				UIKit.small(
					(
						"Your program hit its per-tick instruction budget on most ticks. "
						+ "That usually means a loop with no WAIT in it."
					),
					"warning"
				)
			)
	return card


func _metrics() -> Control:
	var card := UIKit.card()
	var column := UIKit.vbox(Tokens.SPACE_3)
	card.add_child(column)
	column.add_child(UIKit.heading("The three metrics", 3))

	for row in Scoring.breakdown(_mission, _result):
		var block := UIKit.vbox(Tokens.SPACE_1)
		var header := UIKit.hbox(Tokens.SPACE_2)
		var earned := bool(row["earned"])
		header.add_child(UIKit.small("★" if earned else "☆", "warning" if earned else "text_faint"))
		var label := UIKit.body(String(row["label"]))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(label)
		var value := UIKit.small(String(row["value_text"]), "success" if earned else "text")
		header.add_child(value)
		header.add_child(UIKit.small("/ %s" % row["target_text"], "text_faint"))
		block.add_child(header)

		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		var target := float(row["target"])
		var got := float(row["value"])
		bar.value = clampf(target / maxf(got, 0.0001), 0.0, 1.0) if got > 0.0 else 1.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, Tokens.space(6.0))
		block.add_child(bar)

		if not earned and _result.success:
			var over := float(row["over_fraction"])
			if over > 0.0:
				block.add_child(
					UIKit.small("%d%% over the target" % int(over * 100.0), "text_faint")
				)
		column.add_child(block)
	return card


func _flight_facts() -> Control:
	var card := UIKit.card()
	var column := UIKit.vbox(Tokens.SPACE_1)
	card.add_child(column)
	column.add_child(UIKit.heading("The flight", 3))
	column.add_child(UIKit.stat_row("Delta-v spent", Fmt.speed(_result.delta_v_used)))
	column.add_child(UIKit.stat_row("Propellant left", Fmt.mass(_result.fuel_remaining)))
	column.add_child(UIKit.stat_row("Highest point", Fmt.distance(_result.max_altitude)))
	if _result.max_dynamic_pressure > 0.0:
		column.add_child(
			UIKit.stat_row("Peak dynamic pressure", Fmt.pressure(_result.max_dynamic_pressure))
		)
	if _result.touchdown_speed >= 0.0:
		column.add_child(UIKit.stat_row("Touchdown", Fmt.speed(_result.touchdown_speed)))
	column.add_child(
		UIKit.stat_row("Instructions executed", Fmt.count(_result.instructions_executed))
	)
	column.add_child(UIKit.stat_row("Flight computer", _result.vm_status))
	return card


func _personal_bests() -> Control:
	var card := UIKit.card()
	var column := UIKit.vbox(Tokens.SPACE_2)
	card.add_child(column)
	column.add_child(UIKit.heading("Your records", 3))
	column.add_child(
		UIKit.small(
			(
				"A fuel record and a speed record are rarely the same flight, so all "
				+ "three are kept."
			),
			"text_faint"
		)
	)

	var any := false
	for metric in [Scoring.METRIC_FUEL, Scoring.METRIC_TIME, Scoring.METRIC_INSTRUCTIONS]:
		var best := Profile.best_for_metric(_mission.id, metric)
		if best == null:
			continue
		any = true
		var text := ""
		match metric:
			Scoring.METRIC_FUEL:
				text = Fmt.mass(best.fuel_used)
			Scoring.METRIC_TIME:
				text = Fmt.duration(best.elapsed)
			_:
				text = "%d instructions" % best.instruction_count
		var is_now := best.state_hash == _result.state_hash
		column.add_child(
			UIKit.stat_row(
				metric.capitalize() + (" (new)" if is_now else ""),
				text,
				"success" if is_now else "text"
			)
		)
	if not any:
		column.add_child(UIKit.small("No successful flights recorded yet.", "text_faint"))
	return card


func _history() -> Control:
	var card := UIKit.card()
	var column := UIKit.vbox(Tokens.SPACE_1)
	card.add_child(column)
	column.add_child(UIKit.heading("Recent attempts", 3))
	var history := Profile.history_for(_mission.id)
	if history.is_empty():
		column.add_child(UIKit.small("Nothing yet.", "text_faint"))
		return card
	for i in mini(history.size(), 10):
		var r := history[i]
		var row := UIKit.hbox(Tokens.SPACE_2)
		row.add_child(
			UIKit.small(
				"★%d" % r.stars if r.success else "—", "warning" if r.success else "text_faint"
			)
		)
		var text := UIKit.small(
			r.summary() if r.success else r.outcome, "text" if r.success else "text_faint"
		)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(text)
		column.add_child(row)
	return card


func _actions() -> Control:
	var row := UIKit.hbox(Tokens.SPACE_2)

	var again := UIKit.button(
		"Back to the workshop", "primary", "Change the ship or the program and try again"
	)
	again.pressed.connect(func(): App.instance.go_to(App.Screen.EDITOR))
	row.add_child(again)

	var export_button := UIKit.button(
		"Export this solution", "secondary", "Save a file that reproduces this exact flight"
	)
	export_button.pressed.connect(_export)
	row.add_child(export_button)

	row.add_child(UIKit.spacer())

	var next := MissionDB.next_mission(_mission.id)
	if _result.success and next != null:
		var go := UIKit.button("Next: %s" % next.title, "primary", "Start the next mission")
		go.pressed.connect(func(): App.instance.start_mission(next))
		row.add_child(go)

	var menu := UIKit.button("Mission list", "ghost", "Back to the mission list")
	menu.pressed.connect(func(): App.instance.go_to(App.Screen.MENU))
	row.add_child(menu)

	# Deferred: _actions() builds this row and returns it, so nothing in it is
	# in the tree yet and grab_focus() would only push an error and do nothing —
	# leaving the results screen with no keyboard focus at all, which for a
	# project that promises full keyboard control is the bug, not the error line.
	again.grab_focus.call_deferred()
	return row


func _export() -> void:
	var solution := SolutionFile.from_run(
		_mission, App.instance.active_ship, App.instance.active_program, _result
	)
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.add_filter("*." + SolutionFile.EXTENSION, "Aphelion solution")
	dialog.current_file = solution.suggested_filename()
	dialog.title = "Export solution"
	add_child(dialog)
	dialog.file_selected.connect(
		func(path: String):
			var err := solution.save_to(path)
			if err == OK:
				App.instance.toast("Saved %s" % path.get_file(), "success")
			else:
				App.instance.toast("Could not write that file (error %d)." % err, "danger")
	)
	dialog.popup_centered_ratio(0.7)


func palette_commands() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		{"id": "workshop", "title": "Back to the workshop"},
		{"id": "export", "title": "Export this solution"},
		{"id": "menu", "title": "Mission list"},
	]
	var next := MissionDB.next_mission(_mission.id)
	if _result.success and next != null:
		out.append({"id": "next", "title": "Next mission: %s" % next.title})
	return out


func on_palette_command(id: String) -> void:
	match id:
		"workshop":
			App.instance.go_to(App.Screen.EDITOR)
		"export":
			_export()
		"menu":
			App.instance.go_to(App.Screen.MENU)
		"next":
			var next := MissionDB.next_mission(_mission.id)
			if next != null:
				App.instance.start_mission(next)
