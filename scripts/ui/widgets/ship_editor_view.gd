class_name ShipEditorView
extends Control

## The assembly bay: a grid you place parts on.
##
## Fully keyboard-operable. Arrow keys move the cursor, Enter places the
## selected part, Delete removes what is under the cursor, and Tab cycles the
## palette — because "drag and drop" is not an interface everyone can use, and a
## puzzle game that locks people out at the first screen has failed before it
## started.

signal ship_changed

const CELL := 34.0

## Smallest a part's initials are allowed to shrink to before a letter is
## dropped instead. Below this the text stops being readable, at which point
## making it fit is no longer the point.
const MIN_LABEL_PX := 8

var ship: Ship = null
var selected_part: String = ""

var _cursor := Vector2i(4, 0)
var _hover := Vector2i(-1, -1)


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = (
		"Assembly bay. Arrow keys move the cursor, Enter places the "
		+ "selected part, Delete removes one, Tab cycles the palette."
	)
	_update_minimum_size()


func _update_minimum_size() -> void:
	var catalog := PartCatalog.shared()
	custom_minimum_size = Vector2(
		float(catalog.grid_width) * Tokens.space(CELL),
		float(catalog.grid_height) * Tokens.space(CELL)
	)


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
		draw_line(
			Vector2(fx, origin.y),
			Vector2(fx, origin.y + float(catalog.grid_height) * cell),
			grid_colour,
			1.0
		)
	for y in catalog.grid_height + 1:
		var fy := origin.y + float(y) * cell
		draw_line(
			Vector2(origin.x, fy),
			Vector2(origin.x + float(catalog.grid_width) * cell, fy),
			grid_colour,
			1.0
		)

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
			Vector2(float(def.size_w) * cell, float(def.size_h) * cell)
		)
		_draw_part(rect, def, loose.has(i))

	# The centre of mass, because a ship that pitches when it burns is usually a
	# ship whose engine is not under its centre of mass.
	if ship.part_count() > 0:
		# The rendering boundary: doubles become a Vector2 here, and only here.
		var com := ship.centre_of_mass()
		var p := (
			origin
			+ Vector2(float(com[0] / catalog.cell_size), float(com[1] / catalog.cell_size)) * cell
		)
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
				Vector2(float(def.size_w) * cell, float(def.size_h) * cell)
			)
			var c := Tokens.color("success" if ok else "danger")
			draw_rect(rect, Color(c, 0.18))
			draw_rect(rect, c, false, 2.0)

	var cursor_rect := Rect2(
		origin + Vector2(float(_cursor.x) * cell, float(_cursor.y) * cell), Vector2(cell, cell)
	)
	draw_rect(cursor_rect, Tokens.color("focus"), false, 2.0)

	if has_focus():
		draw_rect(
			Rect2(Vector2.ONE, size - Vector2.ONE * 2.0),
			Tokens.color("focus"),
			false,
			Tokens.BORDER_FOCUS
		)


func _draw_part(rect: Rect2, def: PartDef, disconnected: bool) -> void:
	var colour := _category_colour(def.category)
	var edge := colour if not disconnected else Tokens.color("danger")
	var width := 2.0 if disconnected else 1.5
	var r := rect.grow(-2.0)

	# Shape first, because shape is what says which part this is. Colour repeats
	# the category for people who can see it, and the initials repeat it again
	# for people who cannot — but a capsule should read as a capsule before any
	# of that, the way it would on any drawing of a rocket.
	match def.shape:
		PartDef.SHAPE_CAPSULE:
			_shape_capsule(r, colour, edge, width)
		PartDef.SHAPE_PROBE:
			_shape_probe(r, colour, edge, width)
		PartDef.SHAPE_TANK:
			_shape_tank(r, colour, edge, width)
		PartDef.SHAPE_ENGINE:
			_shape_engine(r, colour, edge, width)
		PartDef.SHAPE_WHEEL:
			_shape_wheel(r, colour, edge, width)
		PartDef.SHAPE_SHIELD:
			_shape_shield(r, colour, edge, width)
		PartDef.SHAPE_LEGS:
			_shape_legs(r, colour, edge, width)
		_:
			_shape_beam(r, colour, edge, width)

	var font := get_theme_default_font()
	if font == null:
		return

	# Parts are labelled, never distinguished by colour alone — a shape is a
	# non-colour signal too, but it is not one anything can read aloud, so the
	# initials stay. They sit along the bottom edge rather than the middle,
	# because centred they landed straight on the capsule's window and the
	# reaction wheel's gyro, and two marks on top of each other read as neither.
	# Make it fit the part rather than the other way round: three letters at the
	# body size are wider than a one-cell part, so "HVE" and "WPC" hung over
	# their neighbours and the backing plate covered cells the part does not
	# occupy. A narrow part gets two letters; anything still over shrinks, down
	# to the size where text stops being worth drawing.
	var initials := _initials(def.display_name, 3 if def.size_w > 1 else 2)
	var size_px := Tokens.font_size(Tokens.FONT_SM)
	var text_size := font.get_string_size(initials, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px)
	var avail := r.size.x - 4.0
	if text_size.x > avail and text_size.x > 0.0:
		size_px = maxi(MIN_LABEL_PX, int(float(size_px) * avail / text_size.x))
		text_size = font.get_string_size(initials, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px)
	var at := Vector2(rect.get_center().x - text_size.x * 0.5, r.end.y - maxf(2.0, r.size.y * 0.06))
	# A dark backing plate, so the letters hold up over a filled silhouette in
	# either theme without having to pick a colour that suits both.
	draw_rect(
		Rect2(at + Vector2(-2.0, -size_px * 0.88), Vector2(text_size.x + 4.0, size_px * 1.05)),
		Color(Tokens.color("bg"), 0.72)
	)
	draw_string(font, at, initials, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Tokens.color("text"))


## Initials, at most `limit` of them. One cell is 34 logical pixels and three
## letters do not fit in it at a size anybody can read, so a one-cell part gets
## two. The full name is a hover away, and the silhouette says what it is.
static func _initials(name: String, limit: int = 3) -> String:
	var out := ""
	for word in name.split(" "):
		var w := String(word)
		if not w.is_empty() and out.length() < limit:
			out += w[0].to_upper()
	return out


static func _category_colour(category: String) -> Color:
	match category:
		PartDef.CAT_COMMAND:
			return Tokens.trajectory_color("current")
		PartDef.CAT_ENGINE:
			return Tokens.trajectory_color("danger")
		PartDef.CAT_FUEL:
			return Tokens.trajectory_color("transfer")
		PartDef.CAT_CONTROL:
			return Tokens.trajectory_color("projected")
	return Tokens.trajectory_color("target")


# --- part silhouettes ------------------------------------------------------
#
# Each of these fills a shape at low alpha and strokes its outline, inside the
# rect the part occupies. They are schematic rather than pictorial: this is an
# assembly drawing, not cover art, and a part has to stay readable at a 34-pixel
# cell in both themes and at 80% interface scale.


## Fills a closed outline and strokes it, which is what every shape below wants.
func _silhouette(points: PackedVector2Array, fill: Color, edge: Color, width: float) -> void:
	if points.size() < 3:
		return
	draw_colored_polygon(points, Color(fill, 0.35))
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, edge, width, true)


## A crewed capsule: flat top, flared sides, with a window.
func _shape_capsule(r: Rect2, fill: Color, edge: Color, width: float) -> void:
	var inset := r.size.x * 0.22
	_silhouette(
		PackedVector2Array(
			[
				Vector2(r.position.x + inset, r.position.y),
				Vector2(r.end.x - inset, r.position.y),
				Vector2(r.end.x, r.end.y),
				Vector2(r.position.x, r.end.y),
			]
		),
		fill,
		edge,
		width
	)
	draw_arc(
		Vector2(r.get_center().x, r.position.y + r.size.y * 0.3),
		maxf(2.0, r.size.x * 0.13),
		0.0,
		TAU,
		12,
		edge,
		width * 0.8,
		true
	)


## An uncrewed core: a small box under an antenna.
func _shape_probe(r: Rect2, fill: Color, edge: Color, width: float) -> void:
	var body := Rect2(
		r.position + Vector2(r.size.x * 0.18, r.size.y * 0.34),
		Vector2(r.size.x * 0.64, r.size.y * 0.58)
	)
	draw_rect(body, Color(fill, 0.35))
	draw_rect(body, edge, false, width)
	var mast_x := r.get_center().x
	draw_line(
		Vector2(mast_x, body.position.y), Vector2(mast_x, r.position.y), edge, width * 0.8, true
	)
	draw_line(
		Vector2(mast_x - r.size.x * 0.16, r.position.y),
		Vector2(mast_x + r.size.x * 0.16, r.position.y),
		edge,
		width * 0.8,
		true
	)


## A propellant tank: a cylinder, banded so that stacked tanks stay countable.
func _shape_tank(r: Rect2, fill: Color, edge: Color, width: float) -> void:
	var body := r.grow_individual(-r.size.x * 0.08, 0.0, -r.size.x * 0.08, 0.0)
	draw_rect(body, Color(fill, 0.35))
	draw_rect(body, edge, false, width)
	for f: float in [0.3, 0.7]:
		var y := body.position.y + body.size.y * f
		draw_line(
			Vector2(body.position.x, y),
			Vector2(body.end.x, y),
			Color(edge, 0.55),
			width * 0.7,
			true
		)


## An engine: a bell, narrow at the throat and flared at the mouth.
func _shape_engine(r: Rect2, fill: Color, edge: Color, width: float) -> void:
	var throat := r.size.x * 0.28
	var shoulder := r.position.y + r.size.y * 0.3
	_silhouette(
		PackedVector2Array(
			[
				Vector2(r.get_center().x - throat, r.position.y),
				Vector2(r.get_center().x + throat, r.position.y),
				Vector2(r.get_center().x + throat, shoulder),
				Vector2(r.end.x, r.end.y),
				Vector2(r.position.x, r.end.y),
				Vector2(r.get_center().x - throat, shoulder),
			]
		),
		fill,
		edge,
		width
	)


## A reaction wheel: a housing around a gyro.
func _shape_wheel(r: Rect2, fill: Color, edge: Color, width: float) -> void:
	var body := r.grow(-r.size.x * 0.06)
	draw_rect(body, Color(fill, 0.35))
	draw_rect(body, edge, false, width)
	# The gyro sits above centre, clear of the label strip along the bottom.
	var hub := Vector2(body.get_center().x, body.position.y + body.size.y * 0.29)
	var radius := minf(body.size.x, body.size.y) * 0.21
	draw_arc(hub, radius, 0.0, TAU, 20, edge, width * 0.8, true)
	draw_line(
		hub - Vector2(radius, 0.0), hub + Vector2(radius, 0.0), Color(edge, 0.7), width * 0.7, true
	)


## An ablative shield: a dome presented to the airflow.
func _shape_shield(r: Rect2, fill: Color, edge: Color, width: float) -> void:
	var points := PackedVector2Array()
	var steps := 14
	for i in steps + 1:
		var f := float(i) / float(steps)
		points.append(
			Vector2(
				r.position.x + r.size.x * f, r.position.y + r.size.y * (0.35 + 0.55 * sin(f * PI))
			)
		)
	points.append(Vector2(r.end.x, r.position.y + r.size.y * 0.2))
	points.append(Vector2(r.position.x, r.position.y + r.size.y * 0.2))
	_silhouette(points, fill, edge, width)


## Landing legs: struts braced out to a pair of feet.
func _shape_legs(r: Rect2, fill: Color, edge: Color, width: float) -> void:
	var top := Rect2(
		r.position + Vector2(r.size.x * 0.3, 0.0), Vector2(r.size.x * 0.4, r.size.y * 0.3)
	)
	draw_rect(top, Color(fill, 0.35))
	draw_rect(top, edge, false, width)
	var hip := Vector2(r.get_center().x, top.end.y)
	for dir: float in [-1.0, 1.0]:
		var foot := Vector2(r.get_center().x + dir * r.size.x * 0.42, r.end.y)
		draw_line(hip, foot, edge, width, true)
		draw_line(
			foot - Vector2(r.size.x * 0.1, 0.0),
			foot + Vector2(r.size.x * 0.1, 0.0),
			edge,
			width,
			true
		)


## A strut: open framework, drawn as one because that is all it is.
func _shape_beam(r: Rect2, fill: Color, edge: Color, width: float) -> void:
	var body := r.grow_individual(-r.size.x * 0.28, 0.0, -r.size.x * 0.28, 0.0)
	draw_rect(body, Color(fill, 0.35))
	draw_rect(body, edge, false, width)
	draw_line(body.position, body.end, Color(edge, 0.5), width * 0.7, true)
	draw_line(
		Vector2(body.end.x, body.position.y),
		Vector2(body.position.x, body.end.y),
		Color(edge, 0.5),
		width * 0.7,
		true
	)
