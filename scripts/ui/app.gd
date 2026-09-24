class_name App
extends Control

## The application shell: which screen is showing, the global shortcuts, and the
## command palette.
##
## Screens are plain Control nodes built in code rather than .tscn files. That
## is a deliberate trade: scene files are easier to nudge in the editor, and far
## harder to review, diff, or rebuild when the theme, the UI scale or the
## palette changes. Everything here reads from Tokens and can be rebuilt at any
## time, which is what makes the accessibility settings work at all.

enum Screen { MENU, BRIEFING, EDITOR, FLIGHT, RESULTS }

const SCREEN_SCRIPTS := {
	Screen.MENU: "res://scripts/ui/screens/menu_screen.gd",
	Screen.BRIEFING: "res://scripts/ui/screens/briefing_screen.gd",
	Screen.EDITOR: "res://scripts/ui/screens/editor_screen.gd",
	Screen.FLIGHT: "res://scripts/ui/screens/flight_screen.gd",
	Screen.RESULTS: "res://scripts/ui/screens/results_screen.gd",
}

## The single instance, so screens can navigate without threading a reference
## through every constructor.
static var instance: App = null

var current_screen: int = Screen.MENU
var _screen_node: Control = null
var _background: ColorRect = null
var _palette: CommandPalette = null
var _toast_layer: VBoxContainer = null

## Carried between screens: the mission being played and the work in progress.
var active_mission: Mission = null
var active_ship: Ship = null
var active_program: Program = null
var last_result: RunResult = null


func _ready() -> void:
	instance = self
	name = "App"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_background = ColorRect.new()
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.color = Tokens.color("bg")
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	_toast_layer = UIKit.vbox(Tokens.SPACE_2)
	_toast_layer.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_toast_layer.offset_top = Tokens.space(Tokens.SPACE_4)
	_toast_layer.alignment = BoxContainer.ALIGNMENT_CENTER
	_toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_layer)

	_palette = CommandPalette.new()
	add_child(_palette)
	_palette.command_chosen.connect(_on_command)

	Settings.changed.connect(_on_settings_changed)
	apply_theme()
	go_to(Screen.MENU)


func apply_theme() -> void:
	theme = ThemeBuilder.build()
	if _background != null:
		_background.color = Tokens.color("bg")


func _on_settings_changed(key: String) -> void:
	# Theme, palette and scale all change how everything is drawn, so the
	# simplest correct response is to rebuild the current screen.
	if key in ["", "theme", "palette", "ui_scale"]:
		apply_theme()
		go_to(current_screen, false)


# --- navigation ------------------------------------------------------------


func go_to(screen: int, animate: bool = true) -> void:
	current_screen = screen
	if _screen_node != null and is_instance_valid(_screen_node):
		_screen_node.queue_free()
		_screen_node = null

	var script_path: String = SCREEN_SCRIPTS.get(screen, "")
	if script_path.is_empty():
		push_error("App: no screen registered for %d" % screen)
		return

	var node := Control.new()
	node.set_script(load(script_path))
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(node)
	move_child(node, 1)   # above the background, below toasts and the palette
	_screen_node = node
	if animate:
		UIKit.fade_in(node)


func start_mission(mission: Mission) -> void:
	active_mission = mission
	active_ship = MissionDB.ship_for(mission)
	var draft := Profile.load_draft(mission.id)
	if draft.has("ship") and not (draft["ship"] as Dictionary).is_empty():
		active_ship = Ship.from_dict(draft["ship"], PartCatalog.shared())
	if active_ship == null:
		active_ship = MissionDB.stock_ship("sparrow")
	active_program = Program.from_dict(draft.get("program", {})) if draft.has("program") \
		else Assembler.assemble(_starter_program(mission))
	go_to(Screen.BRIEFING)


## A new mission opens with a comment block rather than a blank page: an empty
## editor is the least helpful thing to show someone who has just read a brief.
static func _starter_program(mission: Mission) -> String:
	var lines := PackedStringArray()
	lines.append("; %s" % mission.title)
	for line in mission.objective_lines():
		lines.append("; Objective: %s" % line)
	lines.append(";")
	lines.append("; F1 opens the instruction reference. Ctrl+K opens the command palette.")
	lines.append("")
	lines.append("        HALT")
	return "\n".join(lines)


func save_draft() -> void:
	if active_mission != null and active_program != null:
		Profile.save_draft(active_mission.id, active_program, active_ship)


# --- global shortcuts ------------------------------------------------------


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return

	# Ctrl/Cmd+K: the command palette. Everything reachable by mouse is
	# reachable here too, which is the backbone of full keyboard control.
	if key.keycode == KEY_K and (key.ctrl_pressed or key.meta_pressed):
		open_command_palette()
		accept_event()
		return

	if key.keycode == KEY_F1:
		open_reference()
		accept_event()
		return

	if key.keycode == KEY_ESCAPE:
		if _palette.is_open():
			_palette.close()
		elif current_screen != Screen.MENU:
			go_to(Screen.MENU)
		accept_event()
		return

	if key.keycode == KEY_F11 or (key.keycode == KEY_ENTER and key.alt_pressed):
		_toggle_fullscreen()
		accept_event()


## Opens the palette. Exposed so a button can do exactly what Ctrl+K does,
## rather than synthesising a keypress.
func open_command_palette() -> void:
	_palette.open(_commands())


func open_reference() -> void:
	_palette.open(_reference_entries())


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN
		else DisplayServer.WINDOW_MODE_FULLSCREEN)


## The palette's contents. Screens add their own by overriding
## `palette_commands()`.
func _commands() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _screen_node != null and _screen_node.has_method("palette_commands"):
		out.append_array(_screen_node.call("palette_commands"))

	out.append_array([
		{"id": "menu", "title": "Go to mission list", "hint": "Esc"},
		{"id": "theme", "title": "Switch theme (currently %s)" % Settings.theme},
		{"id": "palette", "title": "Switch trajectory palette (currently %s)"
			% Settings.palette},
		{"id": "motion", "title": "%s reduced motion"
			% ("Disable" if Settings.reduced_motion else "Enable")},
		{"id": "scale_up", "title": "Larger interface"},
		{"id": "scale_down", "title": "Smaller interface"},
		{"id": "settings", "title": "Settings"},
		{"id": "fullscreen", "title": "Toggle fullscreen", "hint": "F11"},
		{"id": "reference", "title": "Instruction reference", "hint": "F1"},
		{"id": "quit", "title": "Quit Aphelion"},
	])
	return out


func _reference_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for name in ISA.op_names_ordered():
		var spec: Dictionary = ISA.OPS[name]
		out.append({"id": "", "title": name, "hint": String(spec["summary"])})
	for name in ISA.sensor_names_ordered():
		var s: Dictionary = ISA.SENSORS[name]
		var unit := String(s["unit"])
		out.append({"id": "", "title": "%s%s" % [name,
			(" (%s)" % unit) if not unit.is_empty() else ""],
			"hint": String(s["summary"])})
	return out


func _on_command(id: String) -> void:
	match id:
		"":
			pass
		"menu":
			go_to(Screen.MENU)
		"theme":
			Settings.theme = "light" if Settings.theme == "dark" else "dark"
			toast("Theme: %s" % Settings.theme)
		"palette":
			Settings.palette = "colorblind" if Settings.palette == "default" else "default"
			toast("Trajectory palette: %s" % Settings.palette)
		"motion":
			Settings.reduced_motion = not Settings.reduced_motion
			toast("Reduced motion %s" % ("on" if Settings.reduced_motion else "off"))
		"scale_up":
			Settings.ui_scale = Settings.ui_scale + 0.1
			toast("Interface scale %d%%" % int(Settings.ui_scale * 100.0))
		"scale_down":
			Settings.ui_scale = Settings.ui_scale - 0.1
			toast("Interface scale %d%%" % int(Settings.ui_scale * 100.0))
		"settings":
			var dialog := SettingsDialog.new()
			add_child(dialog)
			dialog.popup_centered()
		"fullscreen":
			_toggle_fullscreen()
		"reference":
			open_reference()
		"quit":
			get_tree().quit()
		_:
			if _screen_node != null and _screen_node.has_method("on_palette_command"):
				_screen_node.call("on_palette_command", id)


# --- toasts ----------------------------------------------------------------


## A brief, non-blocking message. Never used for anything the player must act
## on — those get a dialog.
func toast(text: String, role: String = "text") -> void:
	var card := UIKit.card(Tokens.SPACE_3)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var label := UIKit.body(text)
	label.add_theme_color_override("font_color", Tokens.color(role))
	card.add_child(label)
	_toast_layer.add_child(card)

	var hold := 2.4
	if Settings.reduced_motion:
		await get_tree().create_timer(hold).timeout
		if is_instance_valid(card):
			card.queue_free()
		return

	card.modulate.a = 0.0
	var tween := card.create_tween()
	tween.set_ease(Tokens.EASE_OUT).set_trans(Tokens.TRANS_DEFAULT)
	tween.tween_property(card, "modulate:a", 1.0, Tokens.DUR_FAST)
	tween.tween_interval(hold)
	tween.tween_property(card, "modulate:a", 0.0, Tokens.DUR_BASE)
	tween.tween_callback(card.queue_free)
