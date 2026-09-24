extends Control

## What the mission wants, why, and a way in.
##
## The objectives are rendered from the mission's own predicate, so what a
## player is told to do is literally what the game checks.

var _hints_shown := 0
var _hint_box: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mission: Mission = App.instance.active_mission
	if mission == null:
		App.instance.go_to(App.Screen.MENU)
		return

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(Tokens.space(Tokens.SPACE_7)))
	add_child(margin)

	var columns := UIKit.hbox(Tokens.SPACE_6)
	margin.add_child(columns)

	# --- left: the brief ---
	var left := UIKit.vbox(Tokens.SPACE_4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.6
	columns.add_child(left)

	var header := UIKit.hbox(Tokens.SPACE_3)
	var num := UIKit.heading("Mission %02d" % mission.order, 3)
	header.add_child(num)
	header.add_child(UIKit.badge(mission.teaches, "accent"))
	left.add_child(header)
	left.add_child(UIKit.heading(mission.title, 1))

	var scroll := UIKit.scroll()
	left.add_child(scroll)
	var brief_column := UIKit.vbox(Tokens.SPACE_3)
	brief_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(brief_column)
	for paragraph in mission.brief.split("\n\n"):
		var p := String(paragraph).strip_edges()
		if not p.is_empty():
			brief_column.add_child(UIKit.body(p))

	# --- right: objectives, ship, stars, hints ---
	var right := UIKit.vbox(Tokens.SPACE_4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size = Vector2(Tokens.space(360.0), 0)
	columns.add_child(right)

	right.add_child(_objectives(mission))
	right.add_child(_ship_card(mission))
	right.add_child(_stars_card(mission))
	right.add_child(_hints(mission))
	right.add_child(UIKit.spacer())

	var actions := UIKit.hbox(Tokens.SPACE_2)
	var back := UIKit.button("Back", "ghost", "Return to the mission list")
	back.pressed.connect(func(): App.instance.go_to(App.Screen.MENU))
	actions.add_child(back)
	actions.add_child(UIKit.spacer())
	var go := UIKit.button("Open the workshop", "primary", "Build the ship and write the program")
	go.pressed.connect(func(): App.instance.go_to(App.Screen.EDITOR))
	actions.add_child(go)
	right.add_child(actions)

	go.grab_focus()


func _objectives(mission: Mission) -> Control:
	var card := UIKit.card()
	var column := UIKit.vbox(Tokens.SPACE_2)
	card.add_child(column)
	column.add_child(UIKit.heading("To succeed", 3))
	for line in mission.objective_lines():
		var row := UIKit.hbox(Tokens.SPACE_2)
		var bullet := UIKit.small("▸", "accent")
		row.add_child(bullet)
		var text := UIKit.body(line)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		column.add_child(row)

	if not mission.failures.is_empty():
		column.add_child(UIKit.small("The run ends if:", "text_faint"))
		for f in mission.failures:
			column.add_child(UIKit.small("• " + String(f["message"]), "danger"))

	column.add_child(UIKit.small("Time limit: %s" % Fmt.duration(mission.time_limit), "text_faint"))
	return card


func _ship_card(mission: Mission) -> Control:
	var card := UIKit.card()
	var column := UIKit.vbox(Tokens.SPACE_2)
	card.add_child(column)
	var ship: Ship = App.instance.active_ship
	if ship == null:
		column.add_child(UIKit.heading("Build your own ship", 3))
		column.add_child(UIKit.small("This mission does not supply one."))
		return card

	var profile := ship.to_profile()
	column.add_child(UIKit.heading(ship.display_name, 3))
	column.add_child(UIKit.stat_row("Mass, fuelled", Fmt.mass(profile.wet_mass())))
	column.add_child(UIKit.stat_row("Delta-v", Fmt.speed(profile.delta_v())))
	column.add_child(UIKit.stat_row("Thrust", Fmt.force(profile.max_thrust)))
	column.add_child(UIKit.stat_row("Burn time", Fmt.duration(profile.burn_time())))
	if mission.start_fuel_fraction < 1.0:
		column.add_child(
			UIKit.stat_row(
				"Tanks", "%d%% full" % int(mission.start_fuel_fraction * 100.0), "warning"
			)
		)
	return card


func _stars_card(mission: Mission) -> Control:
	var card := UIKit.card()
	var column := UIKit.vbox(Tokens.SPACE_2)
	card.add_child(column)
	column.add_child(UIKit.heading("Three stars", 3))
	column.add_child(
		UIKit.small(
			(
				"One per target met. They pull against each other on purpose: the "
				+ "cheapest flight is slow, and the shortest program is neither."
			)
		)
	)
	column.add_child(UIKit.stat_row("Fuel", "at most " + Fmt.mass(mission.star_fuel)))
	column.add_child(UIKit.stat_row("Time", "at most " + Fmt.duration(mission.star_time)))
	column.add_child(UIKit.stat_row("Instructions", "at most %d" % mission.star_instructions))

	var best := Profile.best_for(mission.id)
	if best != null and best.success:
		column.add_child(UIKit.separator())
		column.add_child(UIKit.stat_row("Your best", best.summary(), "success"))
	return card


func _hints(mission: Mission) -> Control:
	var card := UIKit.card()
	_hint_box = UIKit.vbox(Tokens.SPACE_2)
	card.add_child(_hint_box)
	_hint_box.add_child(UIKit.heading("Stuck?", 3))
	var reveal := UIKit.button("Show a hint", "secondary", "Reveal the next hint for this mission")
	reveal.pressed.connect(
		func():
			if _hints_shown < mission.hints.size():
				_hint_box.add_child(UIKit.body("• " + mission.hints[_hints_shown], true))
				_hints_shown += 1
			if _hints_shown >= mission.hints.size():
				reveal.disabled = true
				reveal.text = "That is every hint"
			else:
				var left := mission.hints.size() - _hints_shown
				reveal.text = "Show another hint (%d left)" % left
	)
	_hint_box.add_child(reveal)
	return card


func palette_commands() -> Array[Dictionary]:
	return [
		{"id": "workshop", "title": "Open the workshop"},
		{"id": "hint", "title": "Show a hint"},
	]


func on_palette_command(id: String) -> void:
	match id:
		"workshop":
			App.instance.go_to(App.Screen.EDITOR)
		"hint":
			var mission: Mission = App.instance.active_mission
			if mission != null and _hints_shown < mission.hints.size():
				_hint_box.add_child(UIKit.body("• " + mission.hints[_hints_shown], true))
				_hints_shown += 1
