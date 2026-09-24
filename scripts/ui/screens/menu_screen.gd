extends Control

## The mission list: what you have solved, what it cost, and what is next.

var _list: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(Tokens.space(Tokens.SPACE_7)))
	add_child(margin)

	var column := UIKit.vbox(Tokens.SPACE_4)
	margin.add_child(column)

	column.add_child(_header())
	column.add_child(UIKit.separator())

	var scroll := UIKit.scroll()
	column.add_child(scroll)

	_list = UIKit.vbox(Tokens.SPACE_2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_build_list()

	if not MissionDB.load_errors.is_empty():
		column.add_child(_load_errors())


func _header() -> Control:
	var row := UIKit.hbox(Tokens.SPACE_4)

	var titles := UIKit.vbox(Tokens.SPACE_1)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(UIKit.heading("Aphelion", 1))
	titles.add_child(
		UIKit.body(
			(
				"Design a spacecraft, program its flight computer, and let real orbital "
				+ "mechanics decide what happens next."
			),
			true
		)
	)
	row.add_child(titles)

	var summary := Profile.summary()
	var stats := UIKit.vbox(Tokens.SPACE_1)
	stats.alignment = BoxContainer.ALIGNMENT_END
	stats.add_child(UIKit.stars_label(int(summary["stars"]), int(summary["max_stars"])))
	stats.add_child(UIKit.small("%d of %d missions solved" % [summary["solved"], summary["total"]]))
	var buttons := UIKit.hbox(Tokens.SPACE_2)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	var settings := UIKit.button("Settings", "ghost", "Open settings")
	settings.pressed.connect(
		func():
			var dialog := SettingsDialog.new()
			add_child(dialog)
			dialog.popup_centered()
	)
	buttons.add_child(settings)
	var palette := UIKit.button("Commands  Ctrl+K", "ghost", "Open the command palette")
	palette.pressed.connect(func(): App.instance.open_command_palette())
	buttons.add_child(palette)
	stats.add_child(buttons)
	row.add_child(stats)
	return row


func _build_list() -> void:
	for child in _list.get_children():
		child.queue_free()

	var missions := MissionDB.playable_missions()
	if missions.is_empty():
		_list.add_child(
			UIKit.body(
				"No missions were found. Check that missions/ " + "contains the mission files.",
				true
			)
		)
		return

	for m in missions:
		_list.add_child(_mission_row(m))


func _mission_row(mission: Mission) -> Control:
	var unlocked := Profile.is_unlocked(mission.id)
	var best := Profile.best_for(mission.id)
	var stars := Profile.stars_for(mission.id)

	var card := UIKit.card(Tokens.SPACE_4)
	var row := UIKit.hbox(Tokens.SPACE_4)
	card.add_child(row)

	var number := UIKit.heading("%02d" % mission.order, 2)
	number.add_theme_color_override("font_color", Tokens.color("text_faint"))
	number.custom_minimum_size = Vector2(Tokens.space(48.0), 0)
	row.add_child(number)

	var text := UIKit.vbox(Tokens.SPACE_1)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_row := UIKit.hbox(Tokens.SPACE_2)
	var title := UIKit.heading(mission.title, 2)
	if not unlocked:
		title.add_theme_color_override("font_color", Tokens.color("text_faint"))
	title_row.add_child(title)
	if best != null and best.success:
		title_row.add_child(UIKit.badge("solved", "success"))
	elif Profile.attempts_for(mission.id) > 0:
		title_row.add_child(
			UIKit.badge("%d attempts" % Profile.attempts_for(mission.id), "text_muted")
		)
	text.add_child(title_row)
	text.add_child(UIKit.small("teaches %s" % mission.teaches))
	if best != null and best.success:
		text.add_child(UIKit.small(best.summary(), "text_faint"))
	row.add_child(text)

	var right := UIKit.vbox(Tokens.SPACE_2)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(UIKit.stars_label(stars))

	if unlocked:
		var play := UIKit.button(
			"Fly" if best == null else "Fly again", "primary", "Start %s" % mission.title
		)
		play.pressed.connect(func(): App.instance.start_mission(mission))
		right.add_child(play)
	else:
		var locked := UIKit.small("Solve the mission above first", "text_faint")
		locked.tooltip_text = (
			"Missions unlock in order so the teaching builds up. "
			+ "You can turn this off in Settings."
		)
		right.add_child(locked)
	row.add_child(right)
	return card


func _load_errors() -> Control:
	var card := UIKit.card()
	var column := UIKit.vbox(Tokens.SPACE_2)
	card.add_child(column)
	column.add_child(UIKit.heading("Some mission files did not load", 3))
	for e in MissionDB.load_errors:
		column.add_child(UIKit.small(e, "danger"))
	return card


## Extra entries for the command palette while this screen is showing.
func palette_commands() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in MissionDB.playable_missions():
		if Profile.is_unlocked(m.id):
			out.append({"id": "fly:" + m.id, "title": "Fly %s" % m.title, "hint": m.teaches})
	return out


func on_palette_command(id: String) -> void:
	if id.begins_with("fly:"):
		var mission := MissionDB.get_mission(id.substr(4))
		if mission != null:
			App.instance.start_mission(mission)
