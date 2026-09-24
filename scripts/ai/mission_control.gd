class_name MissionControl
extends Node

## The optional BYOK co-pilot.
##
## You type what you want in English; it proposes instructions in the game's
## assembly language; you read them, change them, and decide whether to fly
## them. It never touches the ship itself.
##
## Why it is allowed to be wrong
## -----------------------------
## The interesting thing about instructing a machine in English is that English
## is imprecise and machines are not. "Circularise at apoapsis" is a complete
## order. "Make the orbit round" is not — round at what altitude, using which
## apsis, at what throttle? A helpful assistant would quietly pick sensible
## answers and hand back a manoeuvre that works. This one is instructed not to.
##
## It is told to translate what was actually said, to choose the most literal
## reading when something is unstated, and to declare every such choice in an
## `assumptions` list. So a vague order produces a long list of assumptions and
## a manoeuvre that is wrong in exactly the way that list predicts — which the
## player can see, before they fly it.
##
## That is the teaching in AC6: imprecision has visible, attributable
## consequences. Auto-correcting it away would remove the only reason the
## feature exists.
##
## Everything here is optional. With no key configured the panel shows a short
## explanation and the rest of the game is untouched.

signal proposal_ready(proposal: Proposal)
signal failed(message: String)
signal busy_changed(busy: bool)

const TIMEOUT_SECONDS := 45.0

var _http: HTTPRequest = null
var _busy := false
var _pending_intent := ""
var _pending_provider := ""
var _pending_model := ""

## Everything asked and answered this session, newest last.
var history: Array[Proposal] = []


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_SECONDS
	_http.accept_gzip = true
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func is_busy() -> bool:
	return _busy


## Is the co-pilot usable at all right now?
func available() -> bool:
	var provider := Settings.ai_provider
	if not AIProvider.needs_key(provider):
		return true  # Ollama: availability is decided by whether the call connects
	return KeyStore.has_key(provider)


## What to show when it is not. Friendly, specific, and never nagging — the
## game is complete without this.
func unavailable_message() -> String:
	var provider := Settings.ai_provider
	var spec := AIProvider.spec(provider)
	return (
		(
			"Mission Control is an optional co-pilot. It needs an API key for %s, "
			+ "which you provide and pay for — Aphelion has no account and no server "
			+ "of its own.\n\n%s\n\nThe game is complete without it: every mission can "
			+ "be solved by hand, and the reference solutions were."
		)
		% [AIProvider.label(provider), String(spec["key_hint"])]
	)


## Asks the co-pilot to turn `intent` into instructions.
##
## `context` is built by `build_context()` from the live flight, so the model
## knows where the ship is and what the mission wants.
func request(intent: String, context: Dictionary) -> void:
	if _busy:
		failed.emit("Mission Control is still working on the last request.")
		return
	var trimmed := intent.strip_edges()
	if trimmed.is_empty():
		failed.emit("Say what you want the ship to do.")
		return

	var provider := Settings.ai_provider
	var key := KeyStore.get_key(provider)
	if AIProvider.needs_key(provider) and key.is_empty():
		failed.emit(unavailable_message())
		return

	var model := Settings.ai_model
	if model.is_empty():
		model = AIProvider.default_model(provider)

	_pending_intent = trimmed
	_pending_provider = provider
	_pending_model = model

	var body := AIProvider.build_body(
		provider, model, system_prompt(), user_prompt(trimmed, context)
	)
	var url := AIProvider.endpoint(provider, model, key)
	var headers := AIProvider.headers(provider, key)

	var err := _http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		failed.emit("Could not start the request (error %d)." % err)
		return
	_set_busy(true)


func cancel() -> void:
	if _busy:
		_http.cancel_request()
		_set_busy(false)


func _set_busy(v: bool) -> void:
	if _busy != v:
		_busy = v
		busy_changed.emit(v)


func _on_request_completed(
	result: int, status: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	_set_busy(false)

	var text := body.get_string_from_utf8()
	# Parsed through an instance rather than JSON.parse_string() so that a
	# proxy's HTML error page, or a truncated reply, is reported to the player
	# instead of pushing an engine error nobody asked for.
	var json := JSON.new()
	var doc: Dictionary = {}
	if json.parse(text) == OK and typeof(json.data) == TYPE_DICTIONARY:
		doc = json.data

	if result != HTTPRequest.RESULT_SUCCESS:
		failed.emit(AIProvider.describe_error(_pending_provider, 0, doc))
		return
	if status < 200 or status >= 300:
		failed.emit(AIProvider.describe_error(_pending_provider, status, doc))
		return
	if doc.is_empty():
		failed.emit(
			"%s returned something that was not JSON." % AIProvider.label(_pending_provider)
		)
		return

	var extracted := AIProvider.extract_text(_pending_provider, doc)
	if not extracted["ok"]:
		failed.emit(String(extracted["error"]))
		return

	var proposal := Proposal.from_reply(
		String(extracted["text"]), _pending_intent, _pending_provider, _pending_model
	)
	proposal.validate()
	history.append(proposal)
	proposal_ready.emit(proposal)


# --- prompts ---------------------------------------------------------------


## The instruction block.
##
## The language reference is generated from the ISA tables rather than written
## out here, so the co-pilot can never be told about an instruction the VM does
## not have, or miss one it does.
static func system_prompt() -> String:
	return (
		"""You are Mission Control, a flight-dynamics assistant for a spacecraft \
whose autopilot runs a small assembly language. The operator radios you an intent in \
English. You reply with instructions in that language.

HOW TO TRANSLATE

Translate what the operator actually said. Do not improve it.

When the intent does not specify something your instructions need — a target \
altitude, which apsis to burn at, a throttle setting, a tolerance — do not infer \
what they probably meant and do not ask. Choose the most literal reading of the \
words they used, write the instructions that follow from it, and record the choice \
in `assumptions`.

This matters. The operator is learning that imprecise orders produce wrong \
manoeuvres, and they can only learn it if your output is faithful to what they \
said. A helpful guess hides the lesson. An honest assumption teaches it.

Never silently correct an order that is physically wrong. If they ask to burn \
prograde at periapsis to lower periapsis, write that burn — and say in `note` what \
it will actually do.

THE LANGUAGE

%s

SENSORS (read-only, usable anywhere a value is expected)

%s

NOTES
- Every angle is in degrees. Distances are metres, speeds m/s, times seconds.
- Thrust is applied only during BURN. THROTTLE sets the level BURN will use.
- ORIENT blocks until the ship is pointing there; POINT sets the goal and returns.
- IF skips the next instruction when the condition is false.
- Labels are `name:` on their own line. Comments start with `;`.

REPLY FORMAT

Reply with one JSON object and nothing else:

{
  "ops": ["THROTTLE 1", "BURN UNTIL APO > 100000", "HALT"],
  "assumptions": ["You did not say which altitude, so I used the 100 km in the \
mission brief."],
  "note": "One sentence, or an empty string."
}

`ops` holds one instruction per entry, no line numbers. `assumptions` is empty only \
when the intent specified everything. Keep it short: an operator reads every line \
before flying it."""
		% [_language_reference(), _sensor_reference()]
	)


## The instruction set, rendered from ISA.OPS.
static func _language_reference() -> String:
	var lines := PackedStringArray()
	for name in ISA.op_names_ordered():
		var spec: Dictionary = ISA.OPS[name]
		lines.append(
			"  %-9s %s  %s" % [name, _form_hint(spec["form"], name), String(spec["summary"])]
		)
	lines.append("  BURN UNTIL <a> <cmp> <b>   Burn until the condition holds.")
	lines.append("  WAIT UNTIL <a> <cmp> <b>   Coast until the condition holds.")
	lines.append("  Comparisons: <  <=  >  >=  ==  !=")
	lines.append("  Registers: R0 to R%d" % (ISA.REGISTER_COUNT - 1))
	lines.append(
		(
			"  Attitude targets: PROGRADE RETROGRADE RADIAL ANTIRADIAL TARGET, "
			+ "a register, or a heading in degrees"
		)
	)
	return "\n".join(lines)


static func _form_hint(form: int, mnemonic: String) -> String:
	match form:
		ISA.Form.NONE:
			return "%-22s" % ""
		ISA.Form.REG:
			return "%-22s" % "Rd"
		ISA.Form.REG_VALUE:
			return "%-22s" % "Rd, <value>"
		ISA.Form.LABEL:
			return "%-22s" % "<label>"
		ISA.Form.CONDITION:
			return "%-22s" % "<a> <cmp> <b>"
		ISA.Form.VALUE_OPT:
			return "%-22s" % "<target>[, <tolerance>]"
		_:
			if mnemonic == "BURN" or mnemonic == "WAIT":
				return "%-22s" % "<seconds>"
			return "%-22s" % "<value>"


static func _sensor_reference() -> String:
	var lines := PackedStringArray()
	for name in ISA.sensor_names_ordered():
		var s: Dictionary = ISA.SENSORS[name]
		var unit := String(s["unit"])
		lines.append(
			(
				"  %-8s %-7s %s"
				% [name, ("(%s)" % unit) if not unit.is_empty() else "", String(s["summary"])]
			)
		)
	return "\n".join(lines)


## The live situation, as the operator's radio call would carry it.
static func user_prompt(intent: String, context: Dictionary) -> String:
	var parts := PackedStringArray()
	parts.append("MISSION: %s" % String(context.get("mission_title", "unknown")))
	var objectives: PackedStringArray = context.get("objectives", PackedStringArray())
	if objectives.size() > 0:
		parts.append("OBJECTIVE: %s" % " and ".join(objectives))
	if context.has("brief"):
		parts.append("BRIEFING: %s" % String(context["brief"]))

	parts.append("")
	parts.append("SHIP: %s" % String(context.get("ship", "unknown")))
	if context.has("ship_detail"):
		parts.append(String(context["ship_detail"]))

	if context.has("readings"):
		parts.append("")
		parts.append("CURRENT READINGS")
		var readings: Dictionary = context["readings"]
		var keys: Array = readings.keys()
		keys.sort()
		for k in keys:
			parts.append("  %-8s %s" % [k, String(readings[k])])

	if context.has("program") and not String(context["program"]).strip_edges().is_empty():
		parts.append("")
		parts.append("THE AUTOPILOT CURRENTLY HOLDS")
		parts.append(String(context["program"]))

	parts.append("")
	parts.append("OPERATOR: %s" % intent)
	return "\n".join(parts)


## Builds the context dictionary from a live flight.
static func build_context(
	mission: Mission, ship: Ship, bus: SensorBus, program: Program
) -> Dictionary:
	var ctx := {
		"mission_title": mission.title,
		"objectives": mission.objective_lines(),
		"brief": mission.brief,
	}
	if ship != null:
		var prof := ship.to_profile()
		ctx["ship"] = ship.display_name
		ctx["ship_detail"] = (
			("  dry %s, propellant %s, thrust %s at %d s Isp, " + "delta-v %s, reaction wheels %s")
			% [
				Fmt.mass(prof.dry_mass),
				Fmt.mass(prof.fuel_capacity),
				Fmt.force(prof.max_thrust),
				int(prof.isp),
				Fmt.speed(prof.delta_v()),
				"none" if prof.max_torque <= 0.0 else Fmt.number(prof.max_torque, "N·m")
			]
		)
	if bus != null:
		var readings := {}
		# A focused set: enough to reason about the situation, not so much that
		# the important numbers are buried.
		for name in [
			"ALT",
			"VEL",
			"VVEL",
			"HVEL",
			"APO",
			"PERI",
			"ECC",
			"TAPO",
			"TPERI",
			"HDG",
			"PRO",
			"FUEL",
			"DV",
			"TWR",
			"SOI",
			"T"
		]:
			var sid: int = ISA.SENSORS[name]["id"]
			readings[name] = Fmt.sensor_value(sid, bus.read(sid))
		ctx["readings"] = readings
	if program != null:
		ctx["program"] = program.to_text()
	return ctx
