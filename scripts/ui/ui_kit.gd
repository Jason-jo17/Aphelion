class_name UIKit
extends RefCounted

## Small constructors for the pieces of UI that appear over and over.
##
## Every one of them reads from Tokens, so the theme switch, the colourblind
## palette and the UI scale slider reach the whole game rather than the bits
## somebody remembered to wire up.

## A heading. `level` 1 is a screen title, 2 a section, 3 a label above a group.
static func heading(text: String, level: int = 2) -> Label:
	var l := Label.new()
	l.text = text
	var size := Tokens.FONT_XL
	if level == 1:
		size = Tokens.FONT_XXL
	elif level == 3:
		size = Tokens.FONT_MD
	l.add_theme_font_size_override("font_size", Tokens.font_size(size))
	l.add_theme_color_override("font_color", Tokens.color("text"))
	if level >= 3:
		l.add_theme_color_override("font_color", Tokens.color("text_muted"))
	return l


static func body(text: String, muted: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", Tokens.font_size(Tokens.FONT_MD))
	l.add_theme_color_override("font_color",
		Tokens.color("text_muted") if muted else Tokens.color("text"))
	return l


static func small(text: String, role: String = "text_muted") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", Tokens.font_size(Tokens.FONT_SM))
	l.add_theme_color_override("font_color", Tokens.color(role))
	return l


## A bordered surface to group related controls.
static func card(padding: float = Tokens.SPACE_4) -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Tokens.color("surface")
	style.border_color = Tokens.color("border")
	style.set_border_width_all(int(Tokens.BORDER_THIN))
	style.set_corner_radius_all(int(Tokens.RADIUS_MD))
	style.set_content_margin_all(Tokens.space(padding))
	p.add_theme_stylebox_override("panel", style)
	return p


static func vbox(separation: float = Tokens.SPACE_3) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(Tokens.space(separation)))
	return v


static func hbox(separation: float = Tokens.SPACE_3) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(Tokens.space(separation)))
	return h


static func spacer(minimum: float = 0.0) -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if minimum > 0.0:
		c.custom_minimum_size = Vector2(minimum, minimum)
	return c


static func separator() -> HSeparator:
	var s := HSeparator.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Tokens.color("border")
	style.content_margin_top = 1
	s.add_theme_stylebox_override("separator", style)
	return s


## A button. `kind` is "primary", "secondary" or "ghost".
##
## The accessible name matters as much as the label: a keyboard or screen-reader
## user meets `tooltip_text` before they meet the pixels.
static func button(text: String, kind: String = "secondary",
		tooltip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip if not tooltip.is_empty() else text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, Tokens.space(36.0))

	var p := Tokens.palette()
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(int(Tokens.RADIUS_SM))
	normal.content_margin_left = Tokens.space(Tokens.SPACE_4)
	normal.content_margin_right = Tokens.space(Tokens.SPACE_4)
	normal.content_margin_top = Tokens.space(Tokens.SPACE_2)
	normal.content_margin_bottom = Tokens.space(Tokens.SPACE_2)

	match kind:
		"primary":
			normal.bg_color = p["accent"]
			b.add_theme_color_override("font_color", p["accent_text"])
			b.add_theme_color_override("font_hover_color", p["accent_text"])
			b.add_theme_color_override("font_pressed_color", p["accent_text"])
		"ghost":
			normal.bg_color = Color(p["surface"], 0.0)
			normal.set_border_width_all(0)
			b.add_theme_color_override("font_color", p["text_muted"])
		_:
			normal.bg_color = p["surface_high"]
			normal.border_color = p["border"]
			normal.set_border_width_all(int(Tokens.BORDER_THIN))
			b.add_theme_color_override("font_color", p["text"])

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = p["accent"].lightened(0.12) if kind == "primary" else p["overlay"]

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = p["accent"].darkened(0.12) if kind == "primary" else p["border"]

	# Focus is shown as a ring, not merely a colour shift — colour alone fails
	# anyone who cannot see that colour.
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = p["focus"]
	focus.set_border_width_all(int(Tokens.BORDER_FOCUS))

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_font_size_override("font_size", Tokens.font_size(Tokens.FONT_MD))
	return b


## A label/value row, as used by every instrument and stat panel.
static func stat_row(label: String, value: String, role: String = "text") -> HBoxContainer:
	var row := hbox(Tokens.SPACE_2)
	var l := small(label)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := Label.new()
	v.text = value
	v.add_theme_font_size_override("font_size", Tokens.font_size(Tokens.FONT_SM))
	v.add_theme_color_override("font_color", Tokens.color(role))
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(l)
	row.add_child(v)
	return row


## Stars as text plus an explicit count, because three glyphs in a row are hard
## to count at a glance and impossible for a screen reader to describe.
static func stars_label(earned: int, total: int = 3) -> Label:
	var l := Label.new()
	l.text = "%s  %d/%d" % ["★".repeat(earned) + "☆".repeat(maxi(0, total - earned)),
		earned, total]
	l.tooltip_text = "%d of %d stars" % [earned, total]
	l.add_theme_color_override("font_color",
		Tokens.color("warning") if earned > 0 else Tokens.color("text_faint"))
	l.add_theme_font_size_override("font_size", Tokens.font_size(Tokens.FONT_MD))
	return l


## A coloured pill for a status word.
static func badge(text: String, role: String) -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Tokens.color(role), 0.18)
	style.border_color = Tokens.color(role)
	style.set_border_width_all(int(Tokens.BORDER_THIN))
	style.set_corner_radius_all(int(Tokens.RADIUS_SM))
	style.content_margin_left = Tokens.space(Tokens.SPACE_2)
	style.content_margin_right = Tokens.space(Tokens.SPACE_2)
	style.content_margin_top = Tokens.space(2.0)
	style.content_margin_bottom = Tokens.space(2.0)
	p.add_theme_stylebox_override("panel", style)
	var l := small(text, role)
	p.add_child(l)
	return p


## A scrollable region that does not steal horizontal scrolling from the page.
static func scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s


## Fades a node in, honouring the reduced-motion setting.
static func fade_in(node: CanvasItem, from: float = 0.0) -> void:
	var d := Tokens.duration(Tokens.DUR_BASE)
	if d <= 0.0:
		node.modulate.a = 1.0
		return
	node.modulate.a = from
	var tween := node.create_tween()
	tween.set_ease(Tokens.EASE_OUT).set_trans(Tokens.TRANS_DEFAULT)
	tween.tween_property(node, "modulate:a", 1.0, d)
