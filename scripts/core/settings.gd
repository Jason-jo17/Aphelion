extends Node

## Autoload. Player preferences, persisted to user://settings.json.
##
## Accessibility settings are first-class here rather than bolted on: the
## colourblind-safe palette, reduced motion and the keyboard-only flow all
## change how the rest of the game is built, so they need to be readable from
## anywhere and to notify when they change.

signal changed(key: String)

const PATH := "user://settings.json"

## Theme: "dark", "light", or "system".
var theme: String = "dark":
	set(v):
		if theme != v:
			theme = v
			_touch("theme")

## Trajectory palette: "default" or "colorblind". The colourblind palette is
## built for deuteranopia and protanopia and pairs every colour with a distinct
## line style, so nothing is distinguished by hue alone.
var palette: String = "default":
	set(v):
		if palette != v:
			palette = v
			_touch("palette")

## When true, transitions snap instead of animating and the trajectory does not
## sweep. Respects the OS setting on first run.
var reduced_motion: bool = false:
	set(v):
		if reduced_motion != v:
			reduced_motion = v
			_touch("reduced_motion")

## UI scale, 0.8 to 1.6.
var ui_scale: float = 1.0:
	set(v):
		var c := clampf(v, 0.8, 1.6)
		if ui_scale != c:
			ui_scale = c
			_touch("ui_scale")

## Show the value of every sensor beside its name in the flight panel.
var show_sensor_values: bool = true:
	set(v):
		if show_sensor_values != v:
			show_sensor_values = v
			_touch("show_sensor_values")

## Simulation speed multiplier the player selected, 1..8. This is a *rendering*
## rate, not a physics change: the simulation always advances in the same steps.
var sim_speed: int = 1:
	set(v):
		var c := clampi(v, 1, 8)
		if sim_speed != c:
			sim_speed = c
			_touch("sim_speed")

var master_volume: float = 0.8:
	set(v):
		var c := clampf(v, 0.0, 1.0)
		if master_volume != c:
			master_volume = c
			_touch("master_volume")

## Preferred program editor: "text" or "nodes".
var editor_mode: String = "text":
	set(v):
		if editor_mode != v:
			editor_mode = v
			_touch("editor_mode")

## Mission Control (the optional LLM co-pilot) is off until a key is present.
var ai_enabled: bool = false:
	set(v):
		if ai_enabled != v:
			ai_enabled = v
			_touch("ai_enabled")

var ai_provider: String = "anthropic":
	set(v):
		if ai_provider != v:
			ai_provider = v
			_touch("ai_provider")

var ai_model: String = "":
	set(v):
		if ai_model != v:
			ai_model = v
			_touch("ai_model")

var _loaded := false


func _ready() -> void:
	load_settings()


func _touch(key: String) -> void:
	if not _loaded:
		return
	changed.emit(key)
	save_settings()


func load_settings() -> void:
	_loaded = false
	# Default to the OS's own reduced-motion preference, so a player who has
	# already asked their system for less motion does not have to ask again.
	reduced_motion = not DisplayServer.is_touchscreen_available() and _os_prefers_reduced_motion()

	var text := FileAccess.get_file_as_string(PATH)
	if not text.is_empty():
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			var d: Dictionary = parsed
			theme = String(d.get("theme", theme))
			palette = String(d.get("palette", palette))
			reduced_motion = bool(d.get("reduced_motion", reduced_motion))
			ui_scale = float(d.get("ui_scale", ui_scale))
			show_sensor_values = bool(d.get("show_sensor_values", show_sensor_values))
			sim_speed = int(d.get("sim_speed", sim_speed))
			master_volume = float(d.get("master_volume", master_volume))
			editor_mode = String(d.get("editor_mode", editor_mode))
			ai_enabled = bool(d.get("ai_enabled", ai_enabled))
			ai_provider = String(d.get("ai_provider", ai_provider))
			ai_model = String(d.get("ai_model", ai_model))
	_loaded = true
	changed.emit("")


func save_settings() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Settings: could not write %s" % PATH)
		return
	f.store_string(JSON.stringify(to_dict(), "  "))


func to_dict() -> Dictionary:
	return {
		"theme": theme,
		"palette": palette,
		"reduced_motion": reduced_motion,
		"ui_scale": ui_scale,
		"show_sensor_values": show_sensor_values,
		"sim_speed": sim_speed,
		"master_volume": master_volume,
		"editor_mode": editor_mode,
		"ai_enabled": ai_enabled,
		"ai_provider": ai_provider,
		"ai_model": ai_model,
	}


static func _os_prefers_reduced_motion() -> bool:
	# Godot does not expose this directly on every platform; an environment
	# variable lets CI and power users force it, and the accessibility menu
	# always has the switch.
	var env := OS.get_environment("APHELION_REDUCED_MOTION")
	return env == "1" or env.to_lower() == "true"
