class_name CommandPalette
extends Control

## Ctrl+K. Fuzzy-searchable, keyboard-only, and the reason the game can be
## played without a mouse: every action a screen offers registers here, so
## "reachable by keyboard" is a property of the shell rather than something each
## button has to remember.
##
## F1 reuses it as the instruction reference, which is the same interaction with
## a different list.

signal command_chosen(id: String)

const MAX_VISIBLE := 12

var _scrim: ColorRect
var _panel: PanelContainer
var _query: LineEdit
var _list: VBoxContainer
var _entries: Array[Dictionary] = []
var _filtered: Array[Dictionary] = []
var _selected := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	z_index = 100

	_scrim = ColorRect.new()
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.color = Color(0, 0, 0, 0.45)
	add_child(_scrim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	_panel = UIKit.card(Tokens.SPACE_3)
	_panel.custom_minimum_size = Vector2(Tokens.space(560.0), 0)
	centre.add_child(_panel)

	var column := UIKit.vbox(Tokens.SPACE_2)
	_panel.add_child(column)

	_query = LineEdit.new()
	_query.placeholder_text = "Type to search — Enter to run, Esc to close"
	_query.custom_minimum_size = Vector2(0, Tokens.space(36.0))
	_query.text_changed.connect(_on_text_changed)
	column.add_child(_query)

	var scroll := UIKit.scroll()
	scroll.custom_minimum_size = Vector2(0, Tokens.space(340.0))
	column.add_child(scroll)

	_list = UIKit.vbox(Tokens.SPACE_1)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)


func is_open() -> bool:
	return visible


func open(entries: Array[Dictionary]) -> void:
	_entries = entries
	_query.text = ""
	visible = true
	_refresh("")
	_query.grab_focus()
	UIKit.fade_in(self)


func close() -> void:
	visible = false


func _on_text_changed(text: String) -> void:
	_refresh(text)


func _refresh(query: String) -> void:
	_filtered = _match(query, _entries)
	_selected = 0
	_rebuild()


## Subsequence matching, the thing people expect from a command palette:
## "gtml" finds "Go to mission list". Entries are ranked by how tightly the
## match sits, so exact prefixes float to the top.
static func _match(query: String, entries: Array[Dictionary]) -> Array[Dictionary]:
	var q := query.strip_edges().to_lower()
	if q.is_empty():
		return entries.duplicate()

	var scored: Array = []
	for e in entries:
		var haystack := (String(e.get("title", "")) + " " + String(e.get("hint", ""))).to_lower()
		var score := _score(q, haystack)
		if score >= 0:
			scored.append({"score": score, "entry": e})
	scored.sort_custom(func(a, b): return a["score"] < b["score"])

	var out: Array[Dictionary] = []
	for s in scored:
		out.append(s["entry"])
	return out


## Lower is better. Returns -1 when the query is not a subsequence at all.
static func _score(query: String, haystack: String) -> int:
	if haystack.begins_with(query):
		return 0
	var idx := haystack.find(query)
	if idx >= 0:
		return 1 + idx

	var at := 0
	var first := -1
	var last := -1
	for i in query.length():
		var found := haystack.find(query[i], at)
		if found < 0:
			return -1
		if first < 0:
			first = found
		last = found
		at = found + 1
	# Spread-out matches rank below tight ones.
	return 100 + (last - first)


func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()

	if _filtered.is_empty():
		_list.add_child(UIKit.small("Nothing matches.", "text_faint"))
		return

	for i in mini(_filtered.size(), 200):
		var entry: Dictionary = _filtered[i]
		var row := UIKit.hbox(Tokens.SPACE_3)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(int(Tokens.RADIUS_SM))
		style.content_margin_left = Tokens.space(Tokens.SPACE_3)
		style.content_margin_right = Tokens.space(Tokens.SPACE_3)
		style.content_margin_top = Tokens.space(Tokens.SPACE_2)
		style.content_margin_bottom = Tokens.space(Tokens.SPACE_2)
		if i == _selected:
			style.bg_color = Tokens.color("accent")
			# The selected row is also outlined, so the selection survives a
			# screenshot in greyscale and a viewer who cannot see the hue.
			style.border_color = Tokens.color("focus")
			style.set_border_width_all(int(Tokens.BORDER_FOCUS))
		else:
			style.bg_color = Color(Tokens.color("surface_high"), 0.0)
		panel.add_theme_stylebox_override("panel", style)

		var title := Label.new()
		title.text = String(entry.get("title", ""))
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.add_theme_color_override(
			"font_color", Tokens.color("accent_text") if i == _selected else Tokens.color("text")
		)
		title.add_theme_font_size_override("font_size", Tokens.font_size(Tokens.FONT_MD))
		row.add_child(title)

		var hint := String(entry.get("hint", ""))
		if not hint.is_empty():
			var h := Label.new()
			h.text = hint
			h.add_theme_font_size_override("font_size", Tokens.font_size(Tokens.FONT_SM))
			h.add_theme_color_override(
				"font_color",
				Tokens.color("accent_text") if i == _selected else Tokens.color("text_muted")
			)
			h.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			h.custom_minimum_size = Vector2(Tokens.space(260.0), 0)
			h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(h)

		panel.add_child(row)
		_list.add_child(panel)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return

	match key.keycode:
		KEY_ESCAPE:
			close()
			accept_event()
		KEY_DOWN:
			_move(1)
			accept_event()
		KEY_UP:
			_move(-1)
			accept_event()
		KEY_PAGEDOWN:
			_move(MAX_VISIBLE)
			accept_event()
		KEY_PAGEUP:
			_move(-MAX_VISIBLE)
			accept_event()
		KEY_ENTER, KEY_KP_ENTER:
			if _selected >= 0 and _selected < _filtered.size():
				var id := String(_filtered[_selected].get("id", ""))
				close()
				if not id.is_empty():
					command_chosen.emit(id)
			accept_event()


func _move(delta: int) -> void:
	if _filtered.is_empty():
		return
	_selected = clampi(_selected + delta, 0, _filtered.size() - 1)
	_rebuild()
