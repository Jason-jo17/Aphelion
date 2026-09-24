extends Control

## Watching the flight happen.
##
## The simulation advances here, not in `_physics_process`: the orbital sim has
## its own clock and must never be tied to the frame rate, or the same program
## would fly differently on a fast machine. The frame loop only decides *how
## many* already-fixed steps to take before drawing.

## Simulation steps attempted per frame at speed 1. The runner's own step
## scaling does the rest, so a quiet coast covers far more mission time per
## frame than a burn does.
const STEPS_PER_FRAME := 120

## Wall-clock ceiling per frame, so a heavy mission cannot lock the window.
const FRAME_BUDGET_MS := 8

var runner: SimRunner
var _map: TrajectoryView
var _instruments: VBoxContainer
var _objectives: VBoxContainer
var _clock: Label
var _status: Label
var _play_button: Button
var _speed_label: Label
var _timeline: HSlider
var _log_list: VBoxContainer

var _running := true
var _finished := false
var _mission: Mission
var _scrub_state := ShipState.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mission = App.instance.active_mission
	if _mission == null:
		App.instance.go_to(App.Screen.MENU)
		return

	var ship: Ship = App.instance.active_ship
	var program: Program = App.instance.active_program
	var world := MissionDB.world_for(_mission)

	runner = SimRunner.new()
	runner.setup(_mission, world, ship.to_profile(), program, ship.content_hash(), 0)

	_build()
	_map.world = world
	_map.state = runner.state
	_map.target_index = _mission.active_target_index(world)
	_map.frame_ship()
	set_process(true)


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side,
			int(Tokens.space(Tokens.SPACE_4)))
	add_child(margin)

	var column := UIKit.vbox(Tokens.SPACE_3)
	margin.add_child(column)
	column.add_child(_toolbar())

	var body := UIKit.hbox(Tokens.SPACE_3)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	var map_card := UIKit.card(Tokens.SPACE_2)
	map_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map = TrajectoryView.new()
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_card.add_child(_map)
	body.add_child(map_card)

	body.add_child(_side_panel())
	column.add_child(_timeline_row())


func _toolbar() -> Control:
	var row := UIKit.hbox(Tokens.SPACE_3)

	var abort := UIKit.button("Abort", "ghost", "Stop and return to the workshop")
	abort.pressed.connect(func(): App.instance.go_to(App.Screen.EDITOR))
	row.add_child(abort)

	_play_button = UIKit.button("Pause", "secondary", "Pause or resume — Space")
	_play_button.pressed.connect(_toggle_play)
	row.add_child(_play_button)

	var step := UIKit.button("Step", "ghost", "Advance one simulation step — period key")
	step.pressed.connect(func():
		_running = false
		_play_button.text = "Play"
		_advance(1))
	row.add_child(step)

	var slower := UIKit.button("−", "ghost", "Slower")
	slower.pressed.connect(func(): _set_speed(Settings.sim_speed - 1))
	row.add_child(slower)
	_speed_label = UIKit.small("%d×" % Settings.sim_speed)
	_speed_label.custom_minimum_size = Vector2(Tokens.space(34.0), 0)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_speed_label)
	var faster := UIKit.button("+", "ghost", "Faster")
	faster.pressed.connect(func(): _set_speed(Settings.sim_speed + 1))
	row.add_child(faster)

	_clock = UIKit.heading("T+00:00:00", 2)
	_clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_clock)

	var frame_ship := UIKit.button("Follow", "ghost", "Frame the ship — F")
	frame_ship.pressed.connect(func(): _map.frame_ship())
	row.add_child(frame_ship)
	var frame_all := UIKit.button("Whole system", "ghost", "Frame everything — Home")
	frame_all.pressed.connect(func(): _map.frame_all())
	row.add_child(frame_all)
	return row


func _side_panel() -> Control:
	var scroll := UIKit.scroll()
	scroll.custom_minimum_size = Vector2(Tokens.space(310.0), 0)
	scroll.size_flags_horizontal = Control.SIZE_FILL

	var column := UIKit.vbox(Tokens.SPACE_3)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	var status_card := UIKit.card(Tokens.SPACE_3)
	_status = UIKit.body("Flying.")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_card.add_child(_status)
	column.add_child(status_card)

	var obj_card := UIKit.card(Tokens.SPACE_3)
	_objectives = UIKit.vbox(Tokens.SPACE_1)
	obj_card.add_child(_objectives)
	column.add_child(obj_card)

	var inst_card := UIKit.card(Tokens.SPACE_3)
	_instruments = UIKit.vbox(Tokens.SPACE_1)
	inst_card.add_child(_instruments)
	column.add_child(inst_card)

	var log_card := UIKit.card(Tokens.SPACE_3)
	var log_column := UIKit.vbox(Tokens.SPACE_1)
	log_column.add_child(UIKit.heading("Flight log", 3))
	_log_list = UIKit.vbox(Tokens.SPACE_1)
	log_column.add_child(_log_list)
	log_card.add_child(log_column)
	column.add_child(log_card)
	return scroll


func _timeline_row() -> Control:
	var row := UIKit.hbox(Tokens.SPACE_3)
	row.add_child(UIKit.small("Timeline"))
	_timeline = HSlider.new()
	_timeline.min_value = 0.0
	_timeline.max_value = 1.0
	_timeline.step = 0.001
	_timeline.value = 1.0
	_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline.tooltip_text = ("Scrub back through the flight. Pauses the simulation; "
		+ "drag to the end to resume.")
	_timeline.value_changed.connect(_on_scrub)
	row.add_child(_timeline)
	return row


# --- the loop --------------------------------------------------------------


func _process(_delta: float) -> void:
	if _finished or not _running:
		return
	_advance(STEPS_PER_FRAME * Settings.sim_speed)


func _advance(steps: int) -> void:
	var deadline := Time.get_ticks_msec() + FRAME_BUDGET_MS
	var n := 0
	while n < steps and not runner.finished:
		runner.step()
		n += 1
		if (n & 63) == 0 and Time.get_ticks_msec() > deadline:
			break

	_map.state = runner.state
	_map.trail = runner.result.trajectory
	_map.trail_fraction = 1.0
	_map.queue_redraw()
	_refresh_readouts()

	if runner.finished and not _finished:
		_on_finished()


func _refresh_readouts() -> void:
	var bus := runner.bus
	_clock.text = Fmt.clock(SimWorld.time_for_tick(runner.state.tick))

	for child in _instruments.get_children():
		child.queue_free()
	_instruments.add_child(UIKit.heading("Instruments", 3))
	for name in ["ALT", "VEL", "VVEL", "HVEL", "APO", "PERI", "ECC", "TAPO",
			"FUEL", "DV", "TWR", "Q"]:
		var sid: int = ISA.SENSORS[name]["id"]
		var value := bus.read(sid)
		var role := "text"
		if name == "PERI" and value < 0.0:
			role = "danger"
		elif name == "FUEL" and value <= 0.0:
			role = "danger"
		_instruments.add_child(UIKit.stat_row(name, Fmt.sensor_value(sid, value), role))
	if _map.target_index >= 0:
		for name in ["TGTD", "TGTV"]:
			var sid2: int = ISA.SENSORS[name]["id"]
			_instruments.add_child(UIKit.stat_row(name,
				Fmt.sensor_value(sid2, bus.read(sid2))))

	for child in _objectives.get_children():
		child.queue_free()
	_objectives.add_child(UIKit.heading("Objectives", 3))
	for part in _mission.success.parts():
		# Evaluated with dt 0 so reading the panel cannot advance a sustain
		# window — the panel observes, it does not participate.
		var met := part.check(bus, runner.state, runner.vm, 0.0)
		var row := UIKit.hbox(Tokens.SPACE_2)
		row.add_child(UIKit.small("✓" if met else "○", "success" if met else "text_faint"))
		var text := UIKit.small(part.describe(), "success" if met else "text_muted")
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(text)
		_objectives.add_child(row)
		if part.kind == Predicate.Kind.SUSTAIN and part.sustain_progress() > 0.0:
			var bar := ProgressBar.new()
			bar.min_value = 0.0
			bar.max_value = 1.0
			bar.value = part.sustain_progress()
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(0, Tokens.space(6.0))
			_objectives.add_child(bar)

	if runner.vm.log_entries.size() != _log_list.get_child_count():
		for child in _log_list.get_children():
			child.queue_free()
		for entry in runner.vm.log_entries:
			_log_list.add_child(UIKit.small("%s  %s = %s" % [
				Fmt.clock(float(entry["t"])), String(entry["label"]),
				Fmt.number(float(entry["value"]))]))


func _on_finished() -> void:
	_finished = true
	_running = false
	_play_button.disabled = true
	var result := runner.result
	App.instance.last_result = result
	Profile.record(_mission.id, result)

	_status.text = result.outcome
	_status.add_theme_color_override("font_color",
		Tokens.color("success" if result.success else "danger"))

	# A beat to see the final frame before the results screen takes over; with
	# reduced motion, no beat at all.
	await get_tree().create_timer(0.0 if Settings.reduced_motion else 1.1).timeout
	if is_inside_tree():
		App.instance.go_to(App.Screen.RESULTS)


# --- controls --------------------------------------------------------------


func _toggle_play() -> void:
	if _finished:
		return
	_running = not _running
	_play_button.text = "Pause" if _running else "Play"


func _set_speed(value: int) -> void:
	Settings.sim_speed = value
	_speed_label.text = "%d×" % Settings.sim_speed


func _on_scrub(value: float) -> void:
	if value >= 0.999:
		_map.trail_fraction = 1.0
		_map.state = runner.state
		_map.queue_redraw()
		return

	_running = false
	_play_button.text = "Play"
	_map.trail_fraction = value

	var count := runner.result.sample_count()
	if count > 0:
		var sample := runner.result.sample(clampi(int(float(count - 1) * value), 0, count - 1))
		if not sample.is_empty():
			_scrub_state.px = sample["px"]
			_scrub_state.py = sample["py"]
			_scrub_state.vx = sample["vx"]
			_scrub_state.vy = sample["vy"]
			_scrub_state.fuel = sample["fuel"]
			_scrub_state.angle = sample["angle"]
			_scrub_state.tick = int(float(sample["t"]) / SimWorld.DT_BASE)
			_map.state = _scrub_state
			_clock.text = Fmt.clock(float(sample["t"]))
	_map.queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE:
			_toggle_play()
			accept_event()
		KEY_PERIOD:
			_running = false
			_play_button.text = "Play"
			_advance(1)
			accept_event()
		KEY_BRACKETLEFT:
			_set_speed(Settings.sim_speed - 1)
			accept_event()
		KEY_BRACKETRIGHT:
			_set_speed(Settings.sim_speed + 1)
			accept_event()


func palette_commands() -> Array[Dictionary]:
	return [
		{"id": "pause", "title": "Pause or resume", "hint": "Space"},
		{"id": "step", "title": "Advance one step", "hint": "."},
		{"id": "follow", "title": "Frame the ship", "hint": "F"},
		{"id": "frame_all", "title": "Frame the whole system", "hint": "Home"},
		{"id": "abort", "title": "Abort and return to the workshop"},
	]


func on_palette_command(id: String) -> void:
	match id:
		"pause": _toggle_play()
		"step": _advance(1)
		"follow": _map.frame_ship()
		"frame_all": _map.frame_all()
		"abort": App.instance.go_to(App.Screen.EDITOR)
