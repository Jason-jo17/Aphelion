extends Control

## The workshop: the ship on the left, the program on the right, the co-pilot
## underneath, and a live read-out of what the ship can do.

var _ship_view: ShipEditorView
var _program_editor: ProgramEditor
var _stats: VBoxContainer
var _findings: VBoxContainer
var _fly_button: Button
var _mission: Mission


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mission = App.instance.active_mission
	if _mission == null:
		App.instance.go_to(App.Screen.MENU)
		return

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side,
			int(Tokens.space(Tokens.SPACE_5)))
	add_child(margin)

	var column := UIKit.vbox(Tokens.SPACE_3)
	margin.add_child(column)
	column.add_child(_header())

	var split := UIKit.hbox(Tokens.SPACE_4)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(split)
	split.add_child(_ship_column())
	split.add_child(_program_column())

	_refresh_stats()


func _header() -> Control:
	var row := UIKit.hbox(Tokens.SPACE_3)
	var back := UIKit.button("Briefing", "ghost", "Back to the briefing")
	back.pressed.connect(func(): App.instance.go_to(App.Screen.BRIEFING))
	row.add_child(back)

	var title := UIKit.heading(_mission.title, 2)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	for line in _mission.objective_lines():
		row.add_child(UIKit.badge(line, "accent"))

	_fly_button = UIKit.button("Fly it", "primary", "Run the simulation")
	_fly_button.pressed.connect(_fly)
	row.add_child(_fly_button)
	return row


func _ship_column() -> Control:
	var column := UIKit.vbox(Tokens.SPACE_3)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.custom_minimum_size = Vector2(Tokens.space(420.0), 0)

	var card := UIKit.card(Tokens.SPACE_3)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var inner := UIKit.vbox(Tokens.SPACE_2)
	card.add_child(inner)

	var header := UIKit.hbox(Tokens.SPACE_2)
	var title := UIKit.heading("Assembly bay", 3)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	if _mission.ship_policy == "stock":
		header.add_child(UIKit.badge("supplied", "text_muted"))
	inner.add_child(header)

	var body := UIKit.hbox(Tokens.SPACE_3)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(body)

	_ship_view = ShipEditorView.new()
	_ship_view.ship = App.instance.active_ship
	_ship_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ship_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ship_view.ship_changed.connect(_refresh_stats)
	body.add_child(_ship_view)
	body.add_child(_palette_column())

	column.add_child(card)

	var stats_card := UIKit.card(Tokens.SPACE_3)
	_stats = UIKit.vbox(Tokens.SPACE_1)
	stats_card.add_child(_stats)
	column.add_child(stats_card)

	_findings = UIKit.vbox(Tokens.SPACE_1)
	column.add_child(_findings)
	return column


func _palette_column() -> Control:
	var scroll := UIKit.scroll()
	scroll.custom_minimum_size = Vector2(Tokens.space(150.0), 0)
	scroll.size_flags_horizontal = Control.SIZE_FILL

	var column := UIKit.vbox(Tokens.SPACE_1)
	scroll.add_child(column)

	var catalog := PartCatalog.shared()
	for category in catalog.categories():
		var parts := catalog.by_category(category)
		if parts.is_empty():
			continue
		column.add_child(UIKit.small(category.capitalize(), "text_faint"))
		for def in parts:
			var b := UIKit.button(def.display_name, "ghost",
				"%s\n%s\n%s" % [def.display_name, def.description,
					_part_summary(def)])
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.pressed.connect(func():
				_ship_view.selected_part = def.id
				_ship_view.grab_focus()
				_ship_view.queue_redraw()
				App.instance.toast("%s selected — Enter places it" % def.display_name))
			column.add_child(b)
	return scroll


static func _part_summary(def: PartDef) -> String:
	var bits := PackedStringArray([Fmt.mass(def.mass)])
	if def.fuel_capacity > 0.0:
		bits.append("+%s propellant" % Fmt.mass(def.fuel_capacity))
	if def.thrust > 0.0:
		bits.append("%s at %d s" % [Fmt.force(def.thrust), int(def.isp)])
	if def.torque > 0.0:
		bits.append("%s torque" % Fmt.number(def.torque, "N·m"))
	if def.max_landing_speed > 0.0:
		bits.append("lands at up to %s" % Fmt.speed(def.max_landing_speed))
	return ", ".join(bits)


func _program_column() -> Control:
	var column := UIKit.vbox(Tokens.SPACE_3)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 1.3

	var card := UIKit.card(Tokens.SPACE_3)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_program_editor = ProgramEditor.new()
	_program_editor.program_changed.connect(_on_program_changed)
	card.add_child(_program_editor)
	column.add_child(card)
	_program_editor.set_source(App.instance.active_program.source
		if App.instance.active_program != null else "")

	var ai_card := UIKit.card(Tokens.SPACE_3)
	var panel := MissionControlPanel.new()
	panel.context_provider = _ai_context
	panel.apply_requested.connect(func(source: String):
		_program_editor.set_source(source)
		App.instance.toast("Proposal loaded. Read it before you fly it."))
	ai_card.add_child(panel)
	column.add_child(ai_card)
	return column


func _ai_context() -> Dictionary:
	return MissionControl.build_context(_mission, App.instance.active_ship, null,
		_program_editor.program())


func _on_program_changed(program: Program) -> void:
	App.instance.active_program = program
	App.instance.save_draft()
	_refresh_fly_button()


func _refresh_stats() -> void:
	var ship: Ship = App.instance.active_ship
	App.instance.save_draft()

	for child in _stats.get_children():
		child.queue_free()
	for child in _findings.get_children():
		child.queue_free()

	if ship == null:
		return
	var p := ship.to_profile()
	_stats.add_child(UIKit.heading("Numbers", 3))
	_stats.add_child(UIKit.stat_row("Mass, fuelled", Fmt.mass(p.wet_mass())))
	_stats.add_child(UIKit.stat_row("Dry mass", Fmt.mass(p.dry_mass)))
	_stats.add_child(UIKit.stat_row("Delta-v", Fmt.speed(p.delta_v()),
		"success" if p.delta_v() > 0.0 else "danger"))
	_stats.add_child(UIKit.stat_row("Thrust", Fmt.force(p.max_thrust)))
	_stats.add_child(UIKit.stat_row("Burn time", Fmt.duration(p.burn_time())))
	var twr := p.twr(9.0)
	_stats.add_child(UIKit.stat_row("Thrust-to-weight, Halcyon", "%.2f" % twr,
		"success" if twr >= 1.0 else "warning"))
	_stats.add_child(UIKit.stat_row("90° turn",
		Fmt.duration(AttitudeController.slew_time(p, DetMath.PI_2))))
	_stats.add_child(UIKit.stat_row("Drag area", Fmt.number(p.drag_area, "m²")))

	for f in ship.validate():
		var role := {"error": "danger", "warning": "warning"}.get(f["level"], "text_muted")
		var box := UIKit.vbox(Tokens.SPACE_1)
		var msg := UIKit.small(String(f["message"]), role)
		msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(msg)
		var hint := UIKit.small(String(f["hint"]), "text_faint")
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(hint)
		_findings.add_child(box)

	_refresh_fly_button()


func _refresh_fly_button() -> void:
	if _fly_button == null:
		return
	var ship: Ship = App.instance.active_ship
	var program := _program_editor.program() if _program_editor != null else null
	var ship_ok := ship != null and ship.is_flyable()
	var program_ok := program != null and program.ok()
	_fly_button.disabled = not (ship_ok and program_ok)
	if not ship_ok:
		_fly_button.tooltip_text = "The ship cannot fly yet — see the notes on the left."
	elif not program_ok:
		_fly_button.tooltip_text = "The program does not assemble yet."
	else:
		_fly_button.tooltip_text = "Run the simulation"


func _fly() -> void:
	App.instance.active_program = _program_editor.program()
	App.instance.save_draft()
	App.instance.go_to(App.Screen.FLIGHT)


func palette_commands() -> Array[Dictionary]:
	return [
		{"id": "fly", "title": "Fly it", "hint": "run the simulation"},
		{"id": "briefing", "title": "Back to the briefing"},
		{"id": "reset_ship", "title": "Reset the ship to the one the mission supplies"},
		{"id": "reset_program", "title": "Clear the program"},
	]


func on_palette_command(id: String) -> void:
	match id:
		"fly":
			if not _fly_button.disabled:
				_fly()
		"briefing":
			App.instance.go_to(App.Screen.BRIEFING)
		"reset_ship":
			var supplied := MissionDB.ship_for(_mission)
			if supplied != null:
				App.instance.active_ship = supplied
				_ship_view.ship = supplied
				_ship_view.queue_redraw()
				_refresh_stats()
				App.instance.toast("Ship reset.")
		"reset_program":
			_program_editor.set_source("        HALT")
