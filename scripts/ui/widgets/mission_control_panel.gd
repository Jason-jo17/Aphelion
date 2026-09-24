class_name MissionControlPanel
extends VBoxContainer

## The co-pilot panel. Shows a friendly explanation when no key is configured,
## and otherwise takes an intent and returns a proposal the player can read,
## edit or ignore.
##
## Nothing here ever applies a proposal by itself. The Apply button is the
## player's, and the assumptions list sits above it precisely so it is read
## first.

signal apply_requested(source: String)

var control: MissionControl
var context_provider: Callable = Callable()

var _intent: LineEdit
var _ask: Button
var _body: VBoxContainer
var _spinner: Label


func _ready() -> void:
	add_theme_constant_override("separation", int(Tokens.space(Tokens.SPACE_2)))

	control = MissionControl.new()
	add_child(control)
	control.proposal_ready.connect(_on_proposal)
	control.failed.connect(_on_failed)
	control.busy_changed.connect(_on_busy)

	var header := UIKit.hbox(Tokens.SPACE_2)
	var title := UIKit.heading("Mission Control", 3)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_spinner = UIKit.small("", "accent")
	header.add_child(_spinner)
	add_child(header)

	var row := UIKit.hbox(Tokens.SPACE_2)
	_intent = LineEdit.new()
	_intent.placeholder_text = "Tell the co-pilot what you want…"
	_intent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_intent.text_submitted.connect(func(_t): _send())
	row.add_child(_intent)
	_ask = UIKit.button("Ask", "primary", "Send this intent to the co-pilot")
	_ask.pressed.connect(_send)
	row.add_child(_ask)
	add_child(row)

	_body = UIKit.vbox(Tokens.SPACE_2)
	add_child(_body)

	_refresh_availability()


func _refresh_availability() -> void:
	var usable := control.available()
	_intent.editable = usable
	_ask.disabled = usable == false
	for child in _body.get_children():
		child.queue_free()
	if not usable:
		var note := UIKit.small(control.unavailable_message(), "text_muted")
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(note)
		var open := UIKit.button("Set it up", "secondary", "Open the settings")
		open.pressed.connect(
			func():
				var dialog := SettingsDialog.new()
				App.instance.add_child(dialog)
				dialog.popup_centered()
				dialog.close_requested.connect(_refresh_availability)
		)
		_body.add_child(open)
	else:
		_body.add_child(
			UIKit.small(
				(
					"It translates what you say, not what you meant. Anything you leave "
					+ "unstated it decides for itself — and tells you it did."
				),
				"text_faint"
			)
		)


func _send() -> void:
	var text := _intent.text.strip_edges()
	if text.is_empty():
		return
	var ctx := {}
	if context_provider.is_valid():
		ctx = context_provider.call()
	control.request(text, ctx)


func _on_busy(busy: bool) -> void:
	_spinner.text = "thinking…" if busy else ""
	_ask.disabled = busy
	_intent.editable = not busy


func _on_failed(message: String) -> void:
	for child in _body.get_children():
		child.queue_free()
	var label := UIKit.small(message, "danger")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(label)


func _on_proposal(proposal: Proposal) -> void:
	for child in _body.get_children():
		child.queue_free()

	if not proposal.parse_error.is_empty():
		_body.add_child(UIKit.small(proposal.parse_error, "danger"))
		if not proposal.note.is_empty():
			var raw := UIKit.small(proposal.note, "text_faint")
			raw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_body.add_child(raw)
		return

	# The assumptions go first. They are the interesting part: a vague order
	# produces a long list here, and a manoeuvre wrong in exactly that way.
	if proposal.assumptions.is_empty():
		_body.add_child(UIKit.small("It made no assumptions — you were specific.", "success"))
	else:
		var heading := UIKit.small("It had to decide these for you:", "warning")
		_body.add_child(heading)
		for a in proposal.assumptions:
			var line := UIKit.small("• " + a, "warning")
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_body.add_child(line)

	if not proposal.note.is_empty():
		var note := UIKit.small(proposal.note, "text_muted")
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(note)

	var code := TextEdit.new()
	code.text = proposal.to_source()
	code.editable = false
	code.custom_minimum_size = Vector2(0, Tokens.space(140.0))
	code.add_theme_font_size_override("font_size", Tokens.font_size(Tokens.FONT_SM))
	_body.add_child(code)

	# A suggestion that does not assemble should look broken rather than
	# mysterious.
	if not proposal.assembles():
		_body.add_child(
			UIKit.small(
				"This does not assemble: %s" % proposal.program.first_error_text(), "danger"
			)
		)

	var actions := UIKit.hbox(Tokens.SPACE_2)
	var apply := UIKit.button(
		"Replace my program",
		"secondary",
		"Put this in the editor. Nothing is flown until you say so."
	)
	apply.pressed.connect(func(): apply_requested.emit(proposal.to_source()))
	actions.add_child(apply)
	var dismiss := UIKit.button("Ignore", "ghost", "Leave your program alone")
	dismiss.pressed.connect(_refresh_availability)
	actions.add_child(dismiss)
	_body.add_child(actions)
