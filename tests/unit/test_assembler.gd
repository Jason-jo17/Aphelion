extends GutTest

## The assembler, and especially its diagnostics. Error messages are part of how
## the game teaches, so they are tested like any other output.


func test_a_minimal_program_assembles() -> void:
	var p := Assembler.assemble("THROTTLE 1\nBURN UNTIL ALT > 10000\nHALT")
	assert_true(p.ok(), p.first_error_text())
	assert_eq(p.instruction_count(), 3)


func test_comments_labels_and_blank_lines_are_free() -> void:
	var p := Assembler.assemble("""
; a comment
        THROTTLE 1     ; trailing comment

loop:
        BURN 1
        JMP loop
""")
	assert_true(p.ok(), p.first_error_text())
	assert_eq(p.instruction_count(), 3,
		"formatting a program readably must not cost instructions")
	assert_true(p.labels.has("LOOP"))


func test_labels_are_case_insensitive() -> void:
	var p := Assembler.assemble("Loop:\n JMP LOOP\n")
	assert_true(p.ok(), p.first_error_text())
	assert_eq(p.instructions[0].target, 0)


func test_a_label_at_the_end_is_a_valid_jump_target() -> void:
	var p := Assembler.assemble("JMP done\nBURN 1\ndone:")
	assert_true(p.ok(), p.first_error_text())
	assert_eq(p.labels["DONE"], 2, "one past the last instruction is where you fall off")


func test_comparisons_parse_with_or_without_spaces() -> void:
	for src in ["IF ALT>70000", "IF ALT > 70000", "IF ALT>=70000", "IF ALT != 0"]:
		var p := Assembler.assemble(src)
		assert_true(p.ok(), "%s should assemble: %s" % [src, p.first_error_text()])


func test_burn_and_wait_have_both_forms() -> void:
	var p := Assembler.assemble("BURN 30\nBURN UNTIL APO > 100000\nWAIT 5\nWAIT UNTIL TAPO < 20")
	assert_true(p.ok(), p.first_error_text())
	assert_eq(p.instructions[0].op, ISA.Op.BURN)
	assert_eq(p.instructions[1].op, ISA.Op.BURN_UNTIL)
	assert_eq(p.instructions[2].op, ISA.Op.WAIT)
	assert_eq(p.instructions[3].op, ISA.Op.WAIT_UNTIL)


func test_orient_accepts_keywords_registers_numbers_and_a_tolerance() -> void:
	for src in ["ORIENT PROGRADE", "ORIENT RETROGRADE, 2", "ORIENT 90", "ORIENT R0",
			"ORIENT TARGET", "POINT RADIAL"]:
		var p := Assembler.assemble(src)
		assert_true(p.ok(), "%s should assemble: %s" % [src, p.first_error_text()])


func test_numbers_in_every_shape_players_write_them() -> void:
	var p := Assembler.assemble("SET R0, 100\nSET R1, -3.5\nSET R2, 1e4\nSET R3, 0.0625")
	assert_true(p.ok(), p.first_error_text())
	assert_eq(p.instructions[1].b.value, -3.5)
	assert_eq(p.instructions[2].b.value, 10000.0)


func test_named_constants() -> void:
	var p := Assembler.assemble("SET R0, INF\nSET R1, PI\nIF APO == INF")
	assert_true(p.ok(), p.first_error_text())
	assert_true(is_inf(p.instructions[0].b.value))


# --- diagnostics -----------------------------------------------------------

func test_an_unknown_instruction_is_named_and_a_guess_offered() -> void:
	var p := Assembler.assemble("THROTLE 1")
	assert_false(p.ok())
	assert_eq(p.errors.size(), 1)
	assert_string_contains(String(p.errors[0]["message"]), "THROTLE")
	assert_string_contains(String(p.errors[0]["hint"]), "THROTTLE",
		"a one-character typo should get a suggestion")


func test_a_misspelled_sensor_gets_a_suggestion() -> void:
	var p := Assembler.assemble("SENSE R0, APOA")
	assert_false(p.ok())
	assert_string_contains(String(p.errors[0]["hint"]), "APO")


func test_a_register_that_does_not_exist_says_which_ones_do() -> void:
	var p := Assembler.assemble("SET R9, 1")
	assert_false(p.ok())
	assert_string_contains(String(p.errors[0]["message"]), "R9")
	assert_string_contains(String(p.errors[0]["hint"]), "R7")


func test_writing_to_a_sensor_is_refused() -> void:
	var p := Assembler.assemble("SET ALT, 1000")
	assert_false(p.ok())
	assert_string_contains(String(p.errors[0]["message"]).to_lower(), "cannot be written")


func test_an_undefined_label_is_reported_with_its_name() -> void:
	var p := Assembler.assemble("JMP nowhere")
	assert_false(p.ok())
	assert_string_contains(String(p.errors[0]["message"]), "nowhere")


func test_a_duplicate_label_is_refused() -> void:
	var p := Assembler.assemble("loop:\nBURN 1\nloop:\nBURN 1")
	assert_false(p.ok())
	assert_string_contains(String(p.errors[0]["message"]).to_lower(), "already defined")


func test_errors_carry_the_line_they_are_on() -> void:
	var p := Assembler.assemble("THROTTLE 1\nBURN 1\nWHAT IS THIS\nHALT")
	assert_false(p.ok())
	assert_eq(int(p.errors[0]["line"]), 3)


func test_every_error_is_collected_not_just_the_first() -> void:
	var p := Assembler.assemble("FOO 1\nBAR 2\nSET R9, 3")
	assert_gte(p.errors.size(), 3, "a player fixing typos should see them all at once")


func test_a_bad_comparison_operator_lists_the_good_ones() -> void:
	var p := Assembler.assemble("IF ALT ~ 5")
	assert_false(p.ok())
	assert_string_contains(String(p.errors[0]["hint"]), ">=")


func test_wrong_operand_count_explains_the_right_shape() -> void:
	var p := Assembler.assemble("SET R0")
	assert_false(p.ok())
	assert_string_contains(String(p.errors[0]["hint"]), "R0")


func test_an_empty_program_is_not_ok_but_is_not_an_error_either() -> void:
	var p := Assembler.assemble("")
	assert_false(p.ok())
	assert_eq(p.errors.size(), 0, "nothing was wrong; there was just nothing there")


# --- round trip ------------------------------------------------------------

func test_disassembly_reassembles_to_the_same_program() -> void:
	var source := """
        THROTTLE 0.5
        POINT   RAD
        BURN    UNTIL ALT > 800
turn:   SENSE   R0, ALT
        DIV     R0, 24000
        MIN     R0, 1
        SET     R1, RAD
        SUB     R1, R0
        POINT   R1
        BURN    0.5
        IF      APO < 100000
        JMP     turn
        ORIENT  PROGRADE, 1.5
        WAIT    UNTIL TAPO < 20
        LOG     PERI
        HALT
"""
	var first := Assembler.assemble(source)
	assert_true(first.ok(), first.first_error_text())
	var second := Assembler.assemble(first.to_text())
	assert_true(second.ok(), second.first_error_text())
	assert_eq(second.instruction_count(), first.instruction_count())
	assert_eq(second.content_hash(), first.content_hash(),
		"a program's identity must survive a round trip through text")


func test_reformatting_does_not_change_the_hash() -> void:
	var a := Assembler.assemble("THROTTLE 1\nBURN 5\nHALT")
	var b := Assembler.assemble("; a comment\n\n   THROTTLE   1   ; why\n   BURN 5\n   HALT\n")
	assert_eq(a.content_hash(), b.content_hash(),
		"recommenting a program must not invalidate a recorded run")
