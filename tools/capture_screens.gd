extends Node

## Captures the screenshots in the README, and doubles as the only test that
## anything is ever drawn.
##
## Run it, do not stage it by hand:
##
##     make screenshots            # the five README images
##     make screenshots AUDIT=1    # plus every theme, palette and scale
##
## A headless Godot cannot render, so this needs a display; a virtual one is
## fine, and `make screenshots` supplies one with xvfb. It drives the real App
## through the real screens rather than posing mock widgets, which means a
## screenshot that looks wrong *is* the interface looking wrong.
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

## Where the audit sheets go. Not in the README, not in the repository — they
## are for looking at while changing the interface, and there would be dozens.
const AUDIT_DIR := "user://audit/"

## Frames to wait after a screen is built. Layout settles on the frame after
## the one that creates the controls, and anything animating needs a little
## longer than that; ten is comfortably past both without being slow.
const SETTLE_FRAMES := 10

var _app: App = null
var _shots := 0
var _audit := false


func _ready() -> void:
	_audit = OS.get_environment("AUDIT") != ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	if _audit:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AUDIT_DIR))

	# Pin the appearance. Settings persist to the user directory, so without
	# this the README images come out at whatever theme and interface scale the
	# last person to run the game happened to leave behind — which is how they
	# were once captured at 160% without anyone noticing. Reduced motion is on
	# so that nothing is caught mid-fade.
	Settings.theme = "dark"
	Settings.palette = "default"
	Settings.ui_scale = 1.0
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
		await _fly(90)
		await _capture("04-flight", "the flight view, mid-ascent")

		await _finish_and_capture_results(mission)

		await _check_layout()

		if _audit:
			await _audit_sheets()

	print("# wrote %d images" % _shots)
	get_tree().quit()


## Fails the build when a screen's content does not fit and cannot be scrolled
## to. Interface scale is advertised from 80% to 160%, and at 130% the briefing
## was losing 165 pixels off the bottom and the editor 291 - silently, because
## nothing clips loudly. The rule is not "everything must fit": it is that
## anything that does not fit must be reachable.
func _check_layout() -> void:
	var screens := {
		App.Screen.MENU: "menu",
		App.Screen.BRIEFING: "briefing",
		App.Screen.EDITOR: "editor",
		App.Screen.FLIGHT: "flight",
		App.Screen.RESULTS: "results",
	}
	var canvas := _app.get_viewport_rect().size.y
	var failures := 0
	for scale in [0.8, 1.0, 1.3, 1.6]:
		Settings.ui_scale = scale
		for id in screens:
			_app.go_to(id, false)
			await _settle()
			var needs := _content_height()
			if needs <= canvas or _scrolls():
				continue
			failures += 1
			print(
				(
					"LAYOUT FAIL: %s at %d%% needs %d of %d px and cannot scroll"
					% [screens[id], int(scale * 100.0), int(needs), int(canvas)]
				)
			)
	Settings.ui_scale = 1.0
	if failures == 0:
		print("# every screen fits or scrolls, at every interface scale")


func _content_height() -> float:
	var screen := _app.get_child(1) as Control
	var tallest := 0.0
	for c in screen.get_children():
		if c is Control:
			tallest = maxf(tallest, (c as Control).get_combined_minimum_size().y)
	return tallest


func _scrolls() -> bool:
	var screen := _app.get_child(1) as Control
	for c in screen.get_children():
		if c is ScrollContainer:
			return true
	return false


## Every theme, palette and interface scale, on the two busiest screens.
##
## The point is the combinations nobody opens by hand: the light theme at 160%,
## where a panel that only just fits at 100% does not, and the colourblind
## palette on the map, where two trajectories that differ only in hue stop
## differing at all.
func _audit_sheets() -> void:
	for combo in _combinations():
		Settings.theme = String(combo["theme"])
		Settings.palette = String(combo["palette"])
		Settings.ui_scale = float(combo["scale"])
		var slug: String = combo["slug"]

		_app.go_to(App.Screen.EDITOR)
		await _settle()
		await _capture_to(AUDIT_DIR, "editor-" + slug, "")

		_app.go_to(App.Screen.FLIGHT)
		await _settle()
		await _fly(60)
		await _capture_to(AUDIT_DIR, "flight-" + slug, "")

		_app.go_to(App.Screen.RESULTS)
		await _settle()
		await _capture_to(AUDIT_DIR, "results-" + slug, "")

		_app.go_to(App.Screen.MENU)
		await _settle()
		await _capture_to(AUDIT_DIR, "menu-" + slug, "")

	Settings.theme = "dark"
	Settings.palette = "default"
	Settings.ui_scale = 1.0


static func _combinations() -> Array:
	return [
		{"theme": "light", "palette": "default", "scale": 1.0, "slug": "light"},
		{"theme": "dark", "palette": "colorblind", "scale": 1.0, "slug": "dark-cb"},
		{"theme": "light", "palette": "colorblind", "scale": 1.0, "slug": "light-cb"},
		{"theme": "dark", "palette": "default", "scale": 1.6, "slug": "dark-160"},
		{"theme": "light", "palette": "default", "scale": 1.6, "slug": "light-160"},
		{"theme": "dark", "palette": "default", "scale": 0.8, "slug": "dark-80"},
	]


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


func _fly(frames: int) -> void:
	# The flight screen advances its own runner in _process, so the only thing
	# to do is let frames happen.
	for i in frames:
		await get_tree().process_frame


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await get_tree().process_frame


func _capture(name: String, what: String) -> void:
	await _capture_to(OUT_DIR, name, what)


func _capture_to(dir: String, name: String, what: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := dir + name + ".png"
	var err := image.save_png(path)
	if err != OK:
		push_error("could not write %s: %d" % [path, err])
		return
	_shots += 1
	if what.is_empty():
		print("  %s" % path)
	else:
		print("  %-16s %4dx%-4d  %s" % [name + ".png", image.get_width(), image.get_height(), what])


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
