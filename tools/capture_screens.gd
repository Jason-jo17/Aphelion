extends Node

## Captures the screenshots in the README, so they cannot quietly go stale.
##
## Run it, do not stage it by hand:
##
##     xvfb-run -a -s "-screen 0 1600x900x24" \
##       godot --path . --rendering-driver opengl3 res://tools/capture_screens.tscn
##
## A headless Godot cannot render, so this needs a display; a virtual one is
## fine, and `make screenshots` supplies one with xvfb. It drives the real App
## through the real screens rather than posing mock widgets, which means a
## screenshot that looks wrong *is* the interface looking wrong. That is the
## point: a README image nobody can regenerate is a README image that is a year
## out of date and nobody noticed.
##
## CI runs it as a smoke test and fails on any SCRIPT ERROR, without looking at
## the images — rasterisation is not reproducible enough to diff, but "every
## screen builds and draws without throwing" is, and that is worth having. It is
## not hypothetical: the first time this was ever run it found three bugs in one
## pass. The flight map was labelling both apsis markers `%g km`, the flight
## computer opened empty on every mission because set_source() wrote to a node
## that did not exist yet, and the results screen had no keyboard focus. The
## whole test suite was green through all of it, because nothing had ever
## rendered a frame.

const OUT_DIR := "res://assets/screenshots/"

## Frames to wait after a screen is built. Layout settles on the frame after
## the one that creates the controls, and anything animating needs a little
## longer than that; ten is comfortably past both without being slow.
const SETTLE_FRAMES := 10

var _app: App = null
var _shots := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# Reduced motion off would mean catching a screen mid-fade.
	Settings.reduced_motion = true

	_app = App.new()
	add_child(_app)
	await _settle()

	await _capture("01-menu", "the mission list")

	var mission := _mission("insertion")
	if mission != null:
		# Start from nothing. A saved draft from a previous run would be loaded
		# instead of the mission's starter program, so the screenshots would
		# depend on whatever happened to be in the user directory of whichever
		# machine ran this last - which is not a screenshot tool, it is a
		# souvenir.
		Profile.clear_mission(mission.id)
		_app.start_mission(mission)
		await _settle()
		await _capture("02-briefing", "a mission briefing")

		_app.go_to(App.Screen.EDITOR)
		await _settle()
		await _capture("03-editor", "the assembly bay and the program editor")

		# Fly far enough that the map has a trajectory on it rather than a dot.
		_app.active_program = Assembler.assemble(_ascent_program())
		_app.go_to(App.Screen.FLIGHT)
		await _settle()
		await _fly_a_while()
		await _capture("04-flight", "the flight view, mid-ascent")

		await _finish_and_capture_results(mission)

	print("# wrote %d screenshots to %s" % [_shots, OUT_DIR])
	get_tree().quit()


func _finish_and_capture_results(mission: Mission) -> void:
	# The results screen needs a completed run, so fly one to the end headlessly
	# rather than waiting for the flight screen to get there in real time.
	var world := MissionDB.world_for(mission)
	var runner := SimRunner.new()
	var ship: Ship = _app.active_ship
	runner.setup(mission, world, ship.to_profile(), _app.active_program, ship.content_hash(), 0)
	_app.last_result = runner.run()
	_app.go_to(App.Screen.RESULTS)
	await _settle()
	await _capture("05-results", "the score for a completed flight")


func _fly_a_while() -> void:
	# The flight screen advances its own runner in _process, so the only thing
	# to do is let frames happen.
	for i in 90:
		await get_tree().process_frame


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await get_tree().process_frame


func _capture(name: String, what: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := OUT_DIR + name + ".png"
	var err := image.save_png(path)
	if err != OK:
		push_error("could not write %s: %d" % [path, err])
		return
	_shots += 1
	print("  %-14s %4dx%-4d  %s" % [name + ".png", image.get_width(), image.get_height(), what])


func _mission(id: String) -> Mission:
	for m in MissionDB.missions:
		if m.id == id:
			return m
	push_error("no mission '%s'" % id)
	return null


## Enough of a gravity turn that the map shows a curve and the instruments show
## numbers worth looking at. Not a reference solution - this is set dressing.
static func _ascent_program() -> String:
	return """
        THROTTLE 1
        POINT   RAD
        BURN    UNTIL ALT > 600
turn:   SENSE   R0, ALT
        DIV     R0, 20000
        MIN     R0, 1
        MUL     R0, 84
        SET     R1, RAD
        SUB     R1, R0
        POINT   R1
        BURN    0.25
        IF      APO < 105000
        JMP     turn
        ORIENT  PROGRADE
        WAIT    UNTIL TAPO < 22
        BURN    UNTIL PERI > 95000
        HALT
"""
