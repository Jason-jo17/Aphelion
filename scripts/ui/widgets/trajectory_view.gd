class_name TrajectoryView
extends Control

## The map: bodies, the ship, where it has been, and where it is going.
##
## Accessibility is built into how this draws rather than added on top.
##
## * Every trajectory carries three signals — a colour, a **line style**, and an
##   always-visible **text label**. Nothing on this map is distinguished by hue
##   alone, so it reads the same in greyscale, to a colourblind player, and in a
##   screenshot.
## * The colourblind palette is a different set of hues chosen for deuteranopia
##   and protanopia, not a filter over the default one.
## * With reduced motion on, the view snaps between framings instead of easing,
##   and the ship marker stops pulsing.
##
## Positions arrive as doubles and are converted to screen space here, at the
## very last moment — see docs/DETERMINISM.md for why that boundary matters.

## Screen pixels per metre is stored as its logarithm, so zooming feels linear.
const MIN_LOG_SCALE := -14.0
const MAX_LOG_SCALE := -2.0
const ZOOM_STEP := 0.25

## How many points to draw a predicted conic with. Enough to look smooth at any
## zoom without costing anything measurable.
const CONIC_SAMPLES := 180

var world: SimWorld = null
var profile: ShipProfile = null

## Live flight state, or the scrubbed-to sample when reviewing a run.
var state: ShipState = null

## Recorded trajectory, as RunResult stores it.
var trail := PackedFloat64Array()

## How much of the trail to draw, 0..1 — the timeline scrubber drives this.
var trail_fraction: float = 1.0

## Index into world.targets to highlight, or -1.
var target_index: int = -1

var _log_scale := -6.0
var _centre := Vector2.ZERO  ## world metres, as a float32 pair for panning only
var _follow_ship := true
var _dragging := false
var _pulse := 0.0


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(320, 240)
	set_process(true)
	tooltip_text = (
		"Orbital map. Scroll or +/- to zoom, drag or arrow keys to pan, "
		+ "F to follow the ship, Home to frame everything."
	)


func _process(delta: float) -> void:
	if not Settings.reduced_motion:
		_pulse = fmod(_pulse + delta, 1.0)
		queue_redraw()


## Frames the whole flight: every body that matters and the recorded path.
func frame_all() -> void:
	if world == null:
		return
	var extent := 0.0
	if state != null:
		extent = maxf(extent, DetMath.hypot(state.px, state.py))
	for i in range(0, trail.size(), RunResult.TRAJECTORY_STRIDE):
		extent = maxf(extent, DetMath.hypot(trail[i + 1], trail[i + 2]))
	for b in world.bodies:
		extent = maxf(extent, b.radius * 1.4)
		if b.orbit_radius > 0.0:
			extent = maxf(extent, b.orbit_radius * 1.1)
	if extent <= 0.0:
		extent = 1.0e6
	var shortest := minf(size.x, size.y)
	_log_scale = clampf(
		log(maxf(1.0, shortest * 0.45) / extent) / log(2.718281828459045),
		MIN_LOG_SCALE,
		MAX_LOG_SCALE
	)
	_centre = Vector2.ZERO
	_follow_ship = false
	queue_redraw()


## Frames the ship and the body it is bound to.
func frame_ship() -> void:
	if world == null or state == null:
		return
	var t := SimWorld.time_for_tick(state.tick)
	var soi := world.dominant_body_index(t, state.px, state.py)
	var body := world.bodies[soi]
	var r := DetMath.hypot(state.px - body.pos_x(t), state.py - body.pos_y(t))
	var extent := maxf(body.radius * 1.5, r * 1.3)
	var shortest := minf(size.x, size.y)
	_log_scale = clampf(
		log(maxf(1.0, shortest * 0.45) / extent) / log(2.718281828459045),
		MIN_LOG_SCALE,
		MAX_LOG_SCALE
	)
	_follow_ship = true
	queue_redraw()


func scale_factor() -> float:
	return exp(_log_scale)


func _origin() -> Vector2:
	var c := _centre
	if _follow_ship and state != null:
		c = Vector2(float(state.px), float(state.py))
	return size * 0.5 - c * scale_factor() * Vector2(1, -1)


## World metres to screen pixels. Y is flipped so +Y is up, as orbital diagrams
## are always drawn.
func _to_screen(x: float, y: float) -> Vector2:
	var s := scale_factor()
	return _origin() + Vector2(float(x) * s, float(-y) * s)


# --- input -----------------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(ZOOM_STEP)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(-ZOOM_STEP)
				accept_event()
			MOUSE_BUTTON_LEFT:
				_dragging = true
				grab_focus()
	elif mb != null and not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_dragging = false

	var mm := event as InputEventMouseMotion
	if mm != null and _dragging:
		_follow_ship = false
		_centre -= mm.relative / scale_factor() * Vector2(1, -1)
		queue_redraw()
		accept_event()

	var key := event as InputEventKey
	if key != null and key.pressed:
		var pan := Tokens.space(48.0) / scale_factor()
		match key.keycode:
			KEY_EQUAL, KEY_KP_ADD:
				_zoom(ZOOM_STEP)
				accept_event()
			KEY_MINUS, KEY_KP_SUBTRACT:
				_zoom(-ZOOM_STEP)
				accept_event()
			KEY_LEFT:
				_pan(Vector2(-pan, 0))
				accept_event()
			KEY_RIGHT:
				_pan(Vector2(pan, 0))
				accept_event()
			KEY_UP:
				_pan(Vector2(0, pan))
				accept_event()
			KEY_DOWN:
				_pan(Vector2(0, -pan))
				accept_event()
			KEY_F:
				frame_ship()
				accept_event()
			KEY_HOME:
				frame_all()
				accept_event()


func _zoom(delta: float) -> void:
	_log_scale = clampf(_log_scale + delta, MIN_LOG_SCALE, MAX_LOG_SCALE)
	queue_redraw()


func _pan(by: Vector2) -> void:
	if _follow_ship and state != null:
		_centre = Vector2(float(state.px), float(state.py))
	_follow_ship = false
	_centre += by
	queue_redraw()


# --- drawing ---------------------------------------------------------------


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Tokens.color("bg"))
	if world == null:
		return

	var t := SimWorld.time_for_tick(state.tick) if state != null else 0.0

	for i in world.bodies.size():
		_draw_body(world.bodies[i], t)
	_draw_targets(t)
	_draw_trail()
	if state != null:
		_draw_predicted_orbit(t)
		_draw_ship(t)
	_draw_scale_bar()
	_draw_legend()

	if has_focus():
		draw_rect(
			Rect2(Vector2.ONE, size - Vector2.ONE * 2.0),
			Tokens.color("focus"),
			false,
			Tokens.BORDER_FOCUS
		)


func _draw_body(body: CelestialBody, t: float) -> void:
	var centre := _to_screen(body.pos_x(t), body.pos_y(t))
	var r := body.radius * scale_factor()

	if body.has_atmosphere():
		var atmo_r := (body.radius + body.atmo_height) * scale_factor()
		if atmo_r > 2.0:
			draw_circle(centre, atmo_r, Color(body.color, 0.16))
			draw_arc(centre, atmo_r, 0.0, TAU, 96, Color(body.color, 0.5), 1.0, true)

	if r < 2.0:
		# Too small to see at this zoom; draw a marker so it is still findable.
		draw_circle(centre, 3.0, body.color)
	else:
		draw_circle(centre, r, Color(body.color, 0.85))
		draw_arc(centre, r, 0.0, TAU, 96, body.color.lightened(0.25), 1.5, true)

	if body.orbit_radius > 0.0:
		var parent := _to_screen(0.0, 0.0)
		var orbit_r := body.orbit_radius * scale_factor()
		if orbit_r > 8.0 and orbit_r < 20000.0:
			_draw_dashed_arc(
				parent, orbit_r, Color(body.color, 0.28), 1.0, PackedFloat32Array([6.0, 10.0])
			)

	_label(
		centre + Vector2(maxf(r, 4.0) + 6.0, -6.0),
		body.display_name,
		Color(body.color.lightened(0.4), 0.95)
	)


func _draw_targets(t: float) -> void:
	for i in world.targets.size():
		var tg := world.targets[i]
		var parent := world.bodies[tg.parent_index]
		var p := _to_screen(parent.pos_x(t) + tg.rel_x(t), parent.pos_y(t) + tg.rel_y(t))
		var colour := Tokens.trajectory_color("target")
		var active := i == target_index

		# A diamond, so it is not just "the orange dot".
		var half := 6.0 if active else 4.0
		var points := PackedVector2Array(
			[
				p + Vector2(0, -half),
				p + Vector2(half, 0),
				p + Vector2(0, half),
				p + Vector2(-half, 0),
				p + Vector2(0, -half)
			]
		)
		draw_polyline(points, colour, 2.0 if active else 1.0, true)
		if active:
			draw_arc(p, 12.0, 0.0, TAU, 32, Color(colour, 0.5), 1.0, true)
		_label(p + Vector2(10, -10), tg.display_name, colour)


## The path already flown.
func _draw_trail() -> void:
	var count := trail.size() / RunResult.TRAJECTORY_STRIDE
	if count < 2:
		return
	var upto := clampi(int(float(count) * clampf(trail_fraction, 0.0, 1.0)), 2, count)

	var points := PackedVector2Array()
	var thrusting := PackedVector2Array()
	for i in upto:
		var o := i * RunResult.TRAJECTORY_STRIDE
		var p := _to_screen(trail[o + 1], trail[o + 2])
		points.append(p)
		# Powered flight is drawn over the coast in the "transfer" colour, so a
		# player can see at a glance where the engine was lit.
		if trail[o + 7] > 0.0:
			thrusting.append(p)

	if points.size() >= 2:
		draw_polyline(points, Color(Tokens.trajectory_color("past"), 0.85), 1.5, true)
	for p in thrusting:
		draw_circle(p, 2.0, Tokens.trajectory_color("transfer"))


## The conic the ship is currently on, drawn from its elements rather than by
## integrating forward — instant, and exact for the two-body case it describes.
func _draw_predicted_orbit(t: float) -> void:
	var soi := world.dominant_body_index(t, state.px, state.py)
	var body := world.bodies[soi]
	var bx := body.pos_x(t)
	var by := body.pos_y(t)
	var el := Orbital.elements(
		body.mu, state.px - bx, state.py - by, state.vx - body.vel_x(t), state.vy - body.vel_y(t)
	)

	var ecc: float = el[Orbital.K_ECC]
	var a: float = el[Orbital.K_SMA]
	if is_inf(a) or a == 0.0:
		return

	var p := a * (1.0 - ecc * ecc)
	if p <= 0.0:
		return

	# Where periapsis points, worked back from the current position and true
	# anomaly so the drawn conic passes through the ship.
	var nu: float = el[Orbital.K_TRUE_ANOMALY]
	var pos_angle := DetMath.atan2(state.py - by, state.px - bx)
	var arg := pos_angle - nu
	if float(el[Orbital.K_ANG_MOMENTUM]) < 0.0:
		arg = pos_angle + nu

	var escaping := ecc >= 1.0
	var colour := Tokens.trajectory_color("danger" if escaping else "projected")
	var dash := Tokens.trajectory_dash("danger" if escaping else "projected")
	if Orbital.periapsis_altitude(el, body.radius) < 0.0:
		colour = Tokens.trajectory_color("danger")
		dash = Tokens.trajectory_dash("danger")

	var points := PackedVector2Array()
	for i in CONIC_SAMPLES + 1:
		var theta := -DetMath.PI_D + DetMath.TAU_D * float(i) / float(CONIC_SAMPLES)
		if escaping:
			# Only the branch that actually exists.
			var limit := DetMath.acos(clampf(-1.0 / ecc, -1.0, 1.0)) * 0.985
			theta = -limit + 2.0 * limit * float(i) / float(CONIC_SAMPLES)
		var denom := 1.0 + ecc * DetMath.cos(theta)
		if denom <= 1.0e-9:
			continue
		var r := p / denom
		if r > 1.0e11:
			continue
		var sc := DetMath.sincos(
			arg + (theta if float(el[Orbital.K_ANG_MOMENTUM]) >= 0.0 else -theta)
		)
		points.append(_to_screen(bx + r * sc[1], by + r * sc[0]))

	if points.size() >= 2:
		_draw_dashed_polyline(points, colour, 1.5, dash)

	_draw_apsis_markers(el, bx, by, arg, body, colour)


func _draw_apsis_markers(
	el: Dictionary, bx: float, by: float, arg: float, body: CelestialBody, colour: Color
) -> void:
	var ecc: float = el[Orbital.K_ECC]
	if ecc < 1.0:
		var ra: float = el[Orbital.K_APOAPSIS]
		if not is_inf(ra):
			var sc := DetMath.sincos(arg + DetMath.PI_D)
			var p := _to_screen(bx + ra * sc[1], by + ra * sc[0])
			_apsis(p, "Ap %s" % Fmt.distance_coarse(ra - body.radius), colour)
	var rp: float = el[Orbital.K_PERIAPSIS]
	if rp > 0.0:
		var sc2 := DetMath.sincos(arg)
		var p2 := _to_screen(bx + rp * sc2[1], by + rp * sc2[0])
		var underground := rp < body.radius
		_apsis(
			p2,
			"Pe %s" % Fmt.distance_coarse(rp - body.radius),
			Tokens.trajectory_color("danger") if underground else colour
		)


func _apsis(at: Vector2, text: String, colour: Color) -> void:
	draw_line(at + Vector2(-4, -4), at + Vector2(4, 4), colour, 1.5, true)
	draw_line(at + Vector2(-4, 4), at + Vector2(4, -4), colour, 1.5, true)
	_label(at + Vector2(7, -4), text, colour)


func _draw_ship(_t: float) -> void:
	var p := _to_screen(state.px, state.py)
	var colour := Tokens.trajectory_color("current")
	if state.crashed:
		colour = Tokens.trajectory_color("danger")

	# A triangle pointing where the ship points, so heading is visible without
	# reading an instrument.
	var sc := DetMath.sincos(state.angle)
	var forward := Vector2(float(sc[1]), float(-sc[0]))
	var right := Vector2(-forward.y, forward.x)
	var nose := p + forward * 9.0
	draw_colored_polygon(
		PackedVector2Array(
			[
				nose,
				p - forward * 5.0 + right * 5.0,
				p - forward * 5.0 - right * 5.0,
			]
		),
		colour
	)

	if not Settings.reduced_motion:
		var radius := 12.0 + 4.0 * sin(_pulse * TAU)
		draw_arc(p, radius, 0.0, TAU, 24, Color(colour, 0.35), 1.0, true)
	else:
		draw_arc(p, 13.0, 0.0, TAU, 24, Color(colour, 0.35), 1.0, true)

	_label(p + Vector2(12, 6), "Ship", colour)


func _draw_scale_bar() -> void:
	# A bar whose length is a round number of metres, so the map can be read
	# quantitatively rather than impressionistically.
	var target_px := Tokens.space(120.0)
	var metres := target_px / scale_factor()
	var magnitude := pow(10.0, floor(log(metres) / log(10.0)))
	var nice := magnitude
	for step in [1.0, 2.0, 5.0, 10.0]:
		if magnitude * step >= metres * 0.5:
			nice = magnitude * step
			break
	var px := nice * scale_factor()
	if px < 10.0 or px > size.x * 0.8:
		return

	var y := size.y - Tokens.space(Tokens.SPACE_5)
	var x := Tokens.space(Tokens.SPACE_4)
	var colour := Tokens.color("text_muted")
	draw_line(Vector2(x, y), Vector2(x + px, y), colour, 1.5)
	draw_line(Vector2(x, y - 4), Vector2(x, y + 4), colour, 1.5)
	draw_line(Vector2(x + px, y - 4), Vector2(x + px, y + 4), colour, 1.5)
	_label(Vector2(x, y - Tokens.space(Tokens.SPACE_4)), Fmt.distance_coarse(nice), colour)


## The legend is not decoration: it is what makes the line styles readable, and
## it names every colour so hue is never the only thing carrying meaning.
func _draw_legend() -> void:
	var entries := [
		["current", "ship"],
		["projected", "predicted orbit"],
		["past", "flown"],
		["transfer", "engine lit"],
		["danger", "impact"],
	]
	if target_index >= 0:
		entries.append(["target", "target"])

	var x := size.x - Tokens.space(150.0)
	var y := Tokens.space(Tokens.SPACE_4)
	for e in entries:
		var colour := Tokens.trajectory_color(e[0])
		var dash := Tokens.trajectory_dash(e[0])
		var from := Vector2(x, y)
		var to := Vector2(x + Tokens.space(26.0), y)
		if dash.is_empty():
			draw_line(from, to, colour, 2.0, true)
		else:
			_draw_dashed_polyline(PackedVector2Array([from, to]), colour, 2.0, dash)
		_label(Vector2(to.x + 6.0, y - 6.0), String(e[1]), Tokens.color("text_muted"))
		y += Tokens.space(Tokens.SPACE_4)


func _label(at: Vector2, text: String, colour: Color) -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var size_px := Tokens.font_size(Tokens.FONT_XS)
	# A dark halo keeps small text legible over a bright planet.
	draw_string(
		font, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(0, 0, 0, 0.7)
	)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, colour)


func _draw_dashed_polyline(
	points: PackedVector2Array, colour: Color, width: float, pattern: PackedFloat32Array
) -> void:
	if pattern.is_empty():
		draw_polyline(points, colour, width, true)
		return
	var seg := 0
	var remaining: float = pattern[0]
	var drawing := true
	for i in range(points.size() - 1):
		var from := points[i]
		var to := points[i + 1]
		var length := from.distance_to(to)
		if length <= 0.0:
			continue
		var dir := (to - from) / length
		var travelled := 0.0
		while travelled < length:
			var step := minf(remaining, length - travelled)
			if drawing:
				draw_line(
					from + dir * travelled, from + dir * (travelled + step), colour, width, true
				)
			travelled += step
			remaining -= step
			if remaining <= 0.0:
				seg = (seg + 1) % pattern.size()
				remaining = pattern[seg]
				drawing = not drawing


func _draw_dashed_arc(
	centre: Vector2, radius: float, colour: Color, width: float, pattern: PackedFloat32Array
) -> void:
	var points := PackedVector2Array()
	for i in 97:
		var a := TAU * float(i) / 96.0
		points.append(centre + Vector2(cos(a), sin(a)) * radius)
	_draw_dashed_polyline(points, colour, width, pattern)
