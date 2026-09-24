class_name ProgramEditor
extends VBoxContainer

## Writing the flight computer's program.
##
## A CodeEdit with syntax highlighting built from the ISA tables, so the colours
## can never disagree with what the assembler accepts, plus a live error list
## that reassembles on every keystroke. A player should find out that they typed
## `THROTLE` while they are looking at it, not thirty seconds into a flight.

signal program_changed(program: Program)

const REASSEMBLE_DELAY := 0.25

var editor: CodeEdit
var _errors: VBoxContainer
var _status: Label
var _timer: Timer
var _program: Program = null


func _ready() -> void:
	add_theme_constant_override("separation", int(Tokens.space(Tokens.SPACE_2)))
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var header := UIKit.hbox(Tokens.SPACE_2)
	var title := UIKit.heading("Flight computer", 3)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_status = UIKit.small("", "text_faint")
	header.add_child(_status)
	add_child(header)

	editor = CodeEdit.new()
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor.custom_minimum_size = Vector2(0, Tokens.space(280.0))
	editor.gutters_draw_line_numbers = true
	editor.draw_tabs = false
	editor.indent_automatic = true
	editor.indent_use_spaces = true
	editor.indent_size = 8
	editor.scroll_smooth = not Settings.reduced_motion
	editor.caret_blink = not Settings.reduced_motion
	editor.add_theme_font_size_override("font_size", Tokens.font_size(Tokens.FONT_MD))
	editor.syntax_highlighter = _highlighter()
	editor.code_completion_enabled = true
	editor.text_changed.connect(_on_text_changed)
	add_child(editor)

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = REASSEMBLE_DELAY
	_timer.timeout.connect(_reassemble)
	add_child(_timer)

	_errors = UIKit.vbox(Tokens.SPACE_1)
	add_child(_errors)


## Colours come straight from the ISA tables, so adding an opcode highlights it
## without anyone remembering to update a list here.
func _highlighter() -> CodeHighlighter:
	var h := CodeHighlighter.new()
	var p := Tokens.palette()
	h.number_color = p["success"]
	h.symbol_color = p["text_muted"]
	h.function_color = p["accent"]
	h.member_variable_color = p["text"]
	h.add_color_region(";", "", p["text_faint"], true)

	for name in ISA.op_names_ordered():
		h.add_keyword_color(name, p["accent"])
		h.add_keyword_color(name.to_lower(), p["accent"])
	for extra in ["UNTIL", "STAGE"]:
		h.add_keyword_color(extra, p["accent"])
		h.add_keyword_color(extra.to_lower(), p["accent"])
	for name in ISA.sensor_names_ordered():
		h.add_keyword_color(name, p["warning"])
		h.add_keyword_color(name.to_lower(), p["warning"])
	for goal in ISA.GOAL_FROM_TEXT:
		h.add_keyword_color(String(goal), p["danger"])
		h.add_keyword_color(String(goal).to_lower(), p["danger"])
	for c in ISA.CONSTANTS:
		h.add_keyword_color(String(c), p["success"])
	for i in ISA.REGISTER_COUNT:
		h.add_keyword_color("R%d" % i, p["text"])
		h.add_keyword_color("r%d" % i, p["text"])
	return h


func set_source(text: String) -> void:
	editor.text = text
	_reassemble()


func source() -> String:
	return editor.text


func program() -> Program:
	if _program == null:
		_reassemble()
	return _program


func _on_text_changed() -> void:
	_timer.start()


func _reassemble() -> void:
	_program = Assembler.assemble(editor.text)
	_show_errors()
	program_changed.emit(_program)


func _show_errors() -> void:
	for child in _errors.get_children():
		child.queue_free()

	# The line-number gutter is repainted from scratch, so a fixed error never
	# lingers.
	editor.set_line_background_color(0, Color(0, 0, 0, 0))
	for i in editor.get_line_count():
		editor.set_line_background_color(i, Color(0, 0, 0, 0))

	if _program == null:
		return

	if _program.errors.is_empty():
		var n := _program.instruction_count()
		_status.text = "%d instruction%s" % [n, "" if n == 1 else "s"]
		_status.add_theme_color_override("font_color", Tokens.color("text_faint"))
		return

	_status.text = (
		"%d problem%s" % [_program.errors.size(), "" if _program.errors.size() == 1 else "s"]
	)
	_status.add_theme_color_override("font_color", Tokens.color("danger"))

	for e in _program.errors:
		var line := int(e["line"])
		if line >= 1 and line <= editor.get_line_count():
			editor.set_line_background_color(line - 1, Color(Tokens.color("danger"), 0.14))

		var row := UIKit.hbox(Tokens.SPACE_2)
		var jump := UIKit.button("line %d" % line, "ghost", "Jump to line %d" % line)
		jump.custom_minimum_size = Vector2(Tokens.space(76.0), 0)
		jump.pressed.connect(
			func():
				editor.set_caret_line(maxi(0, line - 1))
				editor.grab_focus()
		)
		row.add_child(jump)

		var text := UIKit.small(String(e["message"]), "danger")
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(text)

		var hint := String(e["hint"])
		if not hint.is_empty():
			var h := UIKit.small(hint, "text_muted")
			h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var stacked := UIKit.vbox(Tokens.SPACE_1)
			stacked.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.remove_child(text)
			stacked.add_child(text)
			stacked.add_child(h)
			row.add_child(stacked)

		_errors.add_child(row)
