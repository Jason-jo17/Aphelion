class_name ThemeBuilder
extends RefCounted

## Builds a Godot Theme from the design tokens.
##
## Doing this in code rather than as a .tres resource is what lets the theme be
## rebuilt whenever the player changes the theme, the palette or the UI scale —
## a checked-in resource would have to be duplicated once per combination.


static func build() -> Theme:
	var t := Theme.new()
	var p := Tokens.palette()

	t.default_font_size = Tokens.font_size(Tokens.FONT_MD)

	_panels(t, p)
	_buttons(t, p)
	_inputs(t, p)
	_labels(t, p)
	_lists(t, p)
	_misc(t, p)
	return t


static func _flat(
	bg: Color, radius: float, border: Color = Color.TRANSPARENT, border_w: float = 0.0
) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(int(radius))
	if border_w > 0.0:
		s.set_border_width_all(int(border_w))
		s.border_color = border
	s.set_content_margin_all(Tokens.space(Tokens.SPACE_3))
	s.anti_aliasing = true
	return s


static func _panels(t: Theme, p: Dictionary) -> void:
	t.set_stylebox(
		"panel", "Panel", _flat(p["surface"], Tokens.RADIUS_MD, p["border"], Tokens.BORDER_THIN)
	)
	t.set_stylebox(
		"panel",
		"PanelContainer",
		_flat(p["surface"], Tokens.RADIUS_MD, p["border"], Tokens.BORDER_THIN)
	)

	var popup := _flat(p["surface_high"], Tokens.RADIUS_MD, p["border_strong"], Tokens.BORDER_THIN)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("panel", "PopupPanel", popup)


static func _buttons(t: Theme, p: Dictionary) -> void:
	var normal := _flat(p["surface_high"], Tokens.RADIUS_SM, p["border"], Tokens.BORDER_THIN)
	normal.content_margin_left = Tokens.space(Tokens.SPACE_4)
	normal.content_margin_right = Tokens.space(Tokens.SPACE_4)
	normal.content_margin_top = Tokens.space(Tokens.SPACE_2)
	normal.content_margin_bottom = Tokens.space(Tokens.SPACE_2)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = p["overlay"]
	hover.border_color = p["border_strong"]

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = p["accent"]
	pressed.border_color = p["accent"]

	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = p["surface"]
	disabled.border_color = p["border"]

	# The focus ring is drawn as a thick border in the focus colour, never as a
	# colour change alone: keyboard users need to see where they are, and some
	# of them cannot see the colour.
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = p["focus"]
	focus.set_border_width_all(int(Tokens.BORDER_FOCUS))

	for cls in ["Button", "OptionButton", "MenuButton", "CheckBox", "CheckButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("disabled", cls, disabled)
		t.set_stylebox("focus", cls, focus)
		t.set_color("font_color", cls, p["text"])
		t.set_color("font_hover_color", cls, p["text"])
		t.set_color("font_pressed_color", cls, p["accent_text"])
		t.set_color("font_disabled_color", cls, p["text_faint"])
		t.set_color("font_focus_color", cls, p["text"])
		t.set_font_size("font_size", cls, Tokens.font_size(Tokens.FONT_MD))


static func _inputs(t: Theme, p: Dictionary) -> void:
	var normal := _flat(p["bg"], Tokens.RADIUS_SM, p["border"], Tokens.BORDER_THIN)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = p["focus"]
	focus.set_border_width_all(int(Tokens.BORDER_FOCUS))

	for cls in ["LineEdit", "TextEdit", "CodeEdit", "SpinBox"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("focus", cls, focus)
		t.set_stylebox(
			"read_only", cls, _flat(p["surface"], Tokens.RADIUS_SM, p["border"], Tokens.BORDER_THIN)
		)
		t.set_color("font_color", cls, p["text"])
		t.set_color("font_placeholder_color", cls, p["text_faint"])
		t.set_color("caret_color", cls, p["accent"])
		t.set_color("selection_color", cls, Color(p["accent"], 0.32))
		t.set_font_size("font_size", cls, Tokens.font_size(Tokens.FONT_MD))

	t.set_color("current_line_color", "CodeEdit", Color(p["overlay"], 0.5))
	t.set_color("line_number_color", "CodeEdit", p["text_faint"])
	t.set_color("background_color", "CodeEdit", p["bg"])


static func _labels(t: Theme, p: Dictionary) -> void:
	t.set_color("font_color", "Label", p["text"])
	t.set_font_size("font_size", "Label", Tokens.font_size(Tokens.FONT_MD))
	t.set_color("default_color", "RichTextLabel", p["text"])
	t.set_font_size("normal_font_size", "RichTextLabel", Tokens.font_size(Tokens.FONT_MD))
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())


static func _lists(t: Theme, p: Dictionary) -> void:
	for cls in ["ItemList", "Tree"]:
		t.set_stylebox(
			"panel", cls, _flat(p["bg"], Tokens.RADIUS_SM, p["border"], Tokens.BORDER_THIN)
		)
		t.set_stylebox(
			"focus",
			cls,
			_flat(Color.TRANSPARENT, Tokens.RADIUS_SM, p["focus"], Tokens.BORDER_FOCUS)
		)
		t.set_color("font_color", cls, p["text"])
		t.set_color("font_selected_color", cls, p["accent_text"])
		t.set_stylebox("selected", cls, _flat(p["accent"], Tokens.RADIUS_SM))
		t.set_stylebox("selected_focus", cls, _flat(p["accent"], Tokens.RADIUS_SM))
		t.set_stylebox("hovered", cls, _flat(p["overlay"], Tokens.RADIUS_SM))
		t.set_font_size("font_size", cls, Tokens.font_size(Tokens.FONT_MD))


static func _misc(t: Theme, p: Dictionary) -> void:
	t.set_stylebox("background", "ProgressBar", _flat(p["overlay"], Tokens.RADIUS_SM))
	t.set_stylebox("fill", "ProgressBar", _flat(p["accent"], Tokens.RADIUS_SM))
	t.set_color("font_color", "ProgressBar", p["text"])

	t.set_stylebox("slider", "HSlider", _flat(p["overlay"], Tokens.RADIUS_SM))
	t.set_stylebox("grabber_area", "HSlider", _flat(p["accent"], Tokens.RADIUS_SM))
	t.set_stylebox("grabber_area_highlight", "HSlider", _flat(p["accent"], Tokens.RADIUS_SM))

	t.set_stylebox(
		"tab_selected",
		"TabContainer",
		_flat(p["surface"], Tokens.RADIUS_SM, p["accent"], Tokens.BORDER_FOCUS)
	)
	t.set_stylebox(
		"tab_unselected",
		"TabContainer",
		_flat(p["bg"], Tokens.RADIUS_SM, p["border"], Tokens.BORDER_THIN)
	)
	t.set_stylebox(
		"panel",
		"TabContainer",
		_flat(p["surface"], Tokens.RADIUS_MD, p["border"], Tokens.BORDER_THIN)
	)
	t.set_color("font_selected_color", "TabContainer", p["text"])
	t.set_color("font_unselected_color", "TabContainer", p["text_muted"])

	t.set_constant("separation", "HBoxContainer", int(Tokens.space(Tokens.SPACE_3)))
	t.set_constant("separation", "VBoxContainer", int(Tokens.space(Tokens.SPACE_3)))
	t.set_stylebox("separator", "HSeparator", _flat(p["border"], 0.0))
