class_name SettingsDialog
extends Window

## Settings, with accessibility first rather than buried under Advanced.

var _key_field: LineEdit
var _key_status: Label
var _file_opt_in: CheckBox
var _model_field: LineEdit
var _provider_picker: OptionButton


func _ready() -> void:
	title = "Settings"
	size = Vector2i(int(Tokens.space(640.0)), int(Tokens.space(680.0)))
	unresizable = false
	close_requested.connect(queue_free)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Tokens.color("bg")
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side,
			int(Tokens.space(Tokens.SPACE_5)))
	add_child(margin)

	var scroll := UIKit.scroll()
	margin.add_child(scroll)
	var column := UIKit.vbox(Tokens.SPACE_4)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	column.add_child(_accessibility())
	column.add_child(_appearance())
	column.add_child(_mission_control())
	column.add_child(_progress())


## Builds a titled card and returns the column to fill. The card itself is
## reachable through `_card_of()`, so a caller adds rows and then returns the
## card in one line.
func _section(title_text: String, note: String = "") -> VBoxContainer:
	var card := UIKit.card()
	var column := UIKit.vbox(Tokens.SPACE_3)
	card.add_child(column)
	column.add_child(UIKit.heading(title_text, 3))
	if not note.is_empty():
		column.add_child(UIKit.small(note))
	column.set_meta("card", card)
	return column


func _card_of(column: VBoxContainer) -> Control:
	return _card_of(column) as Control


func _accessibility() -> Control:
	var column := _section("Accessibility",
		"These change how the whole game is drawn, not just this screen.")

	var motion := CheckBox.new()
	motion.text = "Reduced motion"
	motion.tooltip_text = ("Transitions snap instead of easing and the ship marker "
		+ "stops pulsing. Nothing is hidden.")
	motion.button_pressed = Settings.reduced_motion
	motion.toggled.connect(func(on): Settings.reduced_motion = on)
	column.add_child(motion)

	var palette := UIKit.hbox(Tokens.SPACE_3)
	palette.add_child(UIKit.body("Trajectory colours"))
	var picker := OptionButton.new()
	picker.add_item("Default", 0)
	picker.add_item("Colourblind-safe", 1)
	picker.selected = 1 if Settings.palette == "colorblind" else 0
	picker.tooltip_text = ("A different set of hues for deuteranopia and protanopia. "
		+ "Either way every trajectory also carries a line style and a label, so "
		+ "colour is never the only signal.")
	picker.item_selected.connect(func(i):
		Settings.palette = "colorblind" if i == 1 else "default")
	palette.add_child(picker)
	column.add_child(palette)

	var scale_row := UIKit.hbox(Tokens.SPACE_3)
	scale_row.add_child(UIKit.body("Interface scale"))
	var slider := HSlider.new()
	slider.min_value = 0.8
	slider.max_value = 1.6
	slider.step = 0.1
	slider.value = Settings.ui_scale
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var readout := UIKit.small("%d%%" % int(Settings.ui_scale * 100.0))
	slider.value_changed.connect(func(v):
		Settings.ui_scale = v
		readout.text = "%d%%" % int(v * 100.0))
	scale_row.add_child(slider)
	scale_row.add_child(readout)
	column.add_child(scale_row)

	column.add_child(UIKit.small(
		"Every screen is fully keyboard-operable. Ctrl+K opens the command palette, "
		+ "F1 the instruction reference.", "text_faint"))
	return _card_of(column)


func _appearance() -> Control:
	var column := _section("Appearance")
	var row := UIKit.hbox(Tokens.SPACE_3)
	row.add_child(UIKit.body("Theme"))
	var picker := OptionButton.new()
	picker.add_item("Dark", 0)
	picker.add_item("Light", 1)
	picker.add_item("Match the system", 2)
	picker.selected = {"dark": 0, "light": 1, "system": 2}.get(Settings.theme, 0)
	picker.item_selected.connect(func(i):
		Settings.theme = ["dark", "light", "system"][i])
	row.add_child(picker)
	column.add_child(row)
	return _card_of(column)


func _mission_control() -> Control:
	var column := _section("Mission Control",
		"An optional co-pilot. You supply the key and pay for the calls; Aphelion "
		+ "has no account and no server of its own. The game is complete without it.")

	var provider_row := UIKit.hbox(Tokens.SPACE_3)
	provider_row.add_child(UIKit.body("Provider"))
	_provider_picker = OptionButton.new()
	for i in KeyStore.PROVIDERS.size():
		var id: String = KeyStore.PROVIDERS[i]
		_provider_picker.add_item(AIProvider.label(id), i)
		if id == Settings.ai_provider:
			_provider_picker.selected = i
	_provider_picker.item_selected.connect(func(i):
		Settings.ai_provider = KeyStore.PROVIDERS[i]
		Settings.ai_model = AIProvider.default_model(Settings.ai_provider)
		_model_field.text = Settings.ai_model
		_refresh_key_status())
	provider_row.add_child(_provider_picker)
	column.add_child(provider_row)

	var model_row := UIKit.hbox(Tokens.SPACE_3)
	model_row.add_child(UIKit.body("Model"))
	_model_field = LineEdit.new()
	_model_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_model_field.text = Settings.ai_model if not Settings.ai_model.is_empty() \
		else AIProvider.default_model(Settings.ai_provider)
	_model_field.tooltip_text = ("Editable on purpose: a model string baked into a "
		+ "shipped game breaks the day the provider retires it.")
	_model_field.text_submitted.connect(func(t): Settings.ai_model = t.strip_edges())
	_model_field.focus_exited.connect(func():
		Settings.ai_model = _model_field.text.strip_edges())
	model_row.add_child(_model_field)
	column.add_child(model_row)

	var key_row := UIKit.hbox(Tokens.SPACE_3)
	key_row.add_child(UIKit.body("API key"))
	_key_field = LineEdit.new()
	_key_field.secret = true
	_key_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_key_field.placeholder_text = "Paste a key, or leave this blank"
	key_row.add_child(_key_field)
	var save := UIKit.button("Save", "primary", "Store the key")
	save.pressed.connect(_save_key)
	key_row.add_child(save)
	column.add_child(key_row)

	_file_opt_in = CheckBox.new()
	_file_opt_in.text = "Store in a local file (obfuscated, not encrypted)"
	_file_opt_in.tooltip_text = ("Anyone with access to your user directory can read "
		+ "it. Prefer an environment variable or the system keychain.")
	column.add_child(_file_opt_in)

	_key_status = UIKit.small("", "text_muted")
	column.add_child(_key_status)
	_refresh_key_status()

	var clear := UIKit.button("Remove the stored key", "ghost", "Forget this key")
	clear.pressed.connect(func():
		KeyStore.clear_key(Settings.ai_provider)
		_key_field.text = ""
		_refresh_key_status())
	column.add_child(clear)
	return _card_of(column)


func _save_key() -> void:
	var provider := Settings.ai_provider
	var outcome := KeyStore.set_key(provider, _key_field.text, _file_opt_in.button_pressed)
	_key_field.text = ""
	_key_status.text = String(outcome["message"])
	_key_status.add_theme_color_override("font_color",
		Tokens.color("success" if outcome["ok"] else "danger"))
	Settings.ai_enabled = KeyStore.any_key_present()
	if bool(outcome["ok"]):
		await get_tree().create_timer(2.0).timeout
		_refresh_key_status()


func _refresh_key_status() -> void:
	if _key_status == null:
		return
	var provider := Settings.ai_provider
	var source := KeyStore.source_for(provider)
	var spec := AIProvider.spec(provider)

	if not AIProvider.needs_key(provider):
		_key_status.text = String(spec["key_hint"])
		_key_status.add_theme_color_override("font_color", Tokens.color("text_muted"))
		return

	if source == KeyStore.Source.NONE:
		_key_status.text = "No key set. %s  Or set %s in your environment." % [
			String(spec["key_hint"]), KeyStore.env_var_for(provider)]
		_key_status.add_theme_color_override("font_color", Tokens.color("text_muted"))
		return

	var key := KeyStore.get_key(provider)
	_key_status.text = "Using %s from the %s." % [KeyStore.redact(key),
		KeyStore.source_name(source)]
	_key_status.add_theme_color_override("font_color", Tokens.color("success"))
	if not KeyStore.keychain_available() and source != KeyStore.Source.ENVIRONMENT:
		_key_status.text += "  (No system keychain is available on this platform.)"


func _progress() -> Control:
	var column := _section("Progress")
	var summary := Profile.summary()
	column.add_child(UIKit.stat_row("Missions solved",
		"%d of %d" % [summary["solved"], summary["total"]]))
	column.add_child(UIKit.stat_row("Stars",
		"%d of %d" % [summary["stars"], summary["max_stars"]]))

	var reset := UIKit.button("Erase all progress", "ghost",
		"Delete every recorded run and draft")
	reset.add_theme_color_override("font_color", Tokens.color("danger"))
	reset.pressed.connect(func():
		var confirm := ConfirmationDialog.new()
		confirm.dialog_text = ("Erase every recorded run, personal best and draft "
			+ "program? This cannot be undone.")
		confirm.title = "Erase progress"
		add_child(confirm)
		confirm.confirmed.connect(func():
			Profile.clear_all()
			App.instance.toast("Progress erased.", "warning"))
		confirm.popup_centered())
	column.add_child(reset)
	return _card_of(column)
