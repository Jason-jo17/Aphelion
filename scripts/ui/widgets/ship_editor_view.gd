class_name ShipEditorView
extends Control

## The assembly bay: a grid you place parts on.
##
## Fully keyboard-operable. Arrow keys move the cursor, Enter places the
## selected part, Delete removes what is under the cursor, and Tab cycles the
## palette — because "drag and drop" is not an interface everyone can use, and a
## puzzle game that locks people out at the first screen has failed before it
## started.

signal ship_changed()

const CELL := 34.0

var ship: Ship = null
var selected_part: String = ""

var _cursor := Vector2i(4, 0)
var _hover := Vector2i(-1, -1)


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = ("Assembly bay. Arrow keys move the cursor, Enter places the "
		+ "selected part, Delete removes one, Tab cycles the palette.")
	_update_minimum_size()


func _update_minimum_size() -> void:
	var catalog := PartCatalog.shared()
	custom_minimum_size = Vector2(
		float(catalog.grid_width) * Tokens.space(CELL),
		float(catalog.grid_height) * Tokens.space(CELL))


func _cell_size() -> float:
	return Tokens.space(CELL)


func _origin() -> Vector2:
	var catalog := PartCatalog.shared()
	var w := float(catalog.grid_width) * _cell_size()
	var h := float(catalog.grid_height) * _cell_size()
	return (size - Vector2(w, h)) * 0.5


func _cell_at(point: Vector2) -> Vector2i:
	var local := (point - _origin()) / _cell_size()
	return Vector2i(int(floor(local.x)), int(floor(local.y)))


# --- input -----------------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	if ship == null:
		return

	var mm := event as InputEventMouseMotion
	if mm != null:
		var c := _cell_at(mm.position)
		if c != _hover:
			_hover = c
			queue_redraw()

	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		grab_focus()
		var c := _cell_at(mb.position)
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_cursor = c
			_place_at(c)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_remove_at(c)
			accept_event()

	var key := event as InputEventKey
	if key != null and key.pressed:
		var catalog := PartCatalog.shared()
		match key.keycode:
			KEY_LEFT:
				_cursor.x = maxi(0, _cursor.x - 1)
				queue_redraw()
				accept_event()
			KEY_RIGHT:
				_cursor.x = mini(catalog.grid_width - 1, _cursor.x + 1)
				queue_redraw()
				accept_event()
			KEY_UP:
				_cursor.y = maxi(0, _cursor.y - 1)
				queue_redraw()
				accept_event()
			KEY_DOWN:
				_cursor.y = mini(catalog.grid_height - 1, _cursor.y + 1)
				queue_redraw()
				accept_event()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_place_at(_cursor)
				accept_event()
			KEY_DELETE, KEY_BACKSPACE:
				_remove_at(_cursor)
				accept_event()


func _place_at(cell: Vector2i) -> void:
	if selected_part.is_empty():
		return
	var reason := ship.placement_blocked_reason(selected_part, cell.x, cell.y)
	if not reason.is_empty():
		App.instance.toast(reason, "warning")
		return
	ship.place(selected_part, cell.x, cell.y)
	ship_changed.emit()
	queue_redraw()


func _remove_at(cell: Vector2i) -> void:
	var idx := ship.index_at_cell(cell.x, cell.y)
	if idx < 0:
		return
	ship.remove_at_index(idx)
	ship_changed.emit()
	queue_redraw()


# --- drawing ---------------------------------------------------------------


func _draw() -> void:
	var catalog := PartCatalog.shared()
	var cell := _cell_size()
	var origin := _origin()

	var grid_colour := Color(Tokens.color("border"), 0.6)
	for x in catalog.grid_width + 1:
		var fx := origin.x + float(x) * cell
		draw_line(Vector2(fx, origin.y),
			Vector2(fx, origin.y + float(catalog.grid_height) * cell), grid_colour, 1.0)
	for y in catalog.grid_height + 1:
		var fy := origin.y + float(y) * cell
		draw_line(Vector2(origin.x, fy),
			Vector2(origin.x + float(catalog.grid_width) * cell, fy), grid_colour, 1.0)

	if ship == null:
		return

	var loose := {}
	for i in ship.disconnected_indices():
		loose[i] = true

	for i in ship.placements.size():
		var def := ship.part_def_at(i)
		if def == null:
			continue
		var pl: Dictionary = ship.placements[i]
		var rect := Rect2(
			origin + Vector2(float(pl["x"]) * cell, float(pl["y"]) * cell),
			Vector2(float(def.size_w) * cell, float(def.size_h) * cell))
		_draw_part(rect, def, loose.has(i))

	# The centre of mass, because a ship that pitches when it burns is usually a
	# ship whose engine is not under its centre of mass.
	if ship.part_count() > 0:
		var com := ship.centre_of_mass() / catalog.cell_size
		var p := origin + Vector2(com.x, com.y) * cell
		var c := Tokens.color("focus")
		draw_arc(p, 6.0, 0.0, TAU, 20, c, 1.5, true)
		draw_line(p + Vector2(-9, 0), p + Vector2(9, 0), c, 1.0)
		draw_line(p + Vector2(0, -9), p + Vector2(0, 9), c, 1.0)

	# Where the selected part would land.
	if not selected_part.is_empty() and has_focus():
		var def := catalog.get_part(selected_part)
		if def != null:
			var ok := ship.can_place(selected_part, _cursor.x, _cursor.y)
			var rect := Rect2(
				origin + Vector2(float(_cursor.x) * cell, float(_cursor.y) * cell),
				Vector2(float(def.size_w) * cell, float(def.size_h) * cell))
			var c := Tokens.color("success" if ok else "danger")
			draw_rect(rect, Color(c, 0.18))
			draw_rect(rect, c, false, 2.0)

	var cursor_rect := Rect2(
		origin + Vector2(float(_cursor.x) * cell, float(_cursor.y) * cell),
		Vector2(cell, cell))
	draw_rect(cursor_rect, Tokens.color("focus"), false, 2.0)

	if has_focus():
		draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2.0),
			Tokens.color("focus"), false, Tokens.BORDER_FOCUS)


func _draw_part(rect: Rect2, def: PartDef, disconnected: bool) -> void:
	var colour := _category_colour(def.category)
	draw_rect(rect.grow(-2.0), Color(colour, 0.35))
	draw_rect(rect.grow(-2.0), colour if not disconnected else Tokens.color("danger"),
		false, 2.0 if disconnected else 1.5)

	var font := get_theme_default_font()
	if font == null:
		return
	# Parts are labelled, never distinguished by colour alone.
	var initials := _initials(def.display_name)
	var size_px := Tokens.font_size(Tokens.FONT_SM)
	var text_size := font.get_string_size(initials, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px)
	draw_string(font, rect.get_center() + Vector2(-text_size.x * 0.5, size_px * 0.35),
		initials, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Tokens.color("text"))


static func _initials(name: String) -> String:
	var out := ""
	for word in name.split(" "):
		var w := String(word)
		if not w.is_empty() and out.length() < 3:
			out += w[0].to_upper()
	return out


static func _category_colour(category: String) -> Color:
	match category:
		PartDef.CAT_COMMAND: return Tokens.trajectory_color("current")
		PartDef.CAT_ENGINE: return Tokens.trajectory_color("danger")
		PartDef.CAT_FUEL: return Tokens.trajectory_color("transfer")
		PartDef.CAT_CONTROL: return Tokens.trajectory_color("projected")
	return Tokens.trajectory_color("target")
