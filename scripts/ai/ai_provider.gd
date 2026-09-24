class_name AIProvider
extends RefCounted

## Wire formats for the BYOK providers Aphelion can talk to.
##
## Four providers, one shape: build a request, send it, pull one block of text
## back out. Nothing here knows what the text is for — Mission Control owns the
## prompt and the parsing — so adding a provider means adding one entry to
## `SPECS` and two small functions.
##
## Model IDs are *defaults*, not constants. A model string baked into a shipped
## game goes stale the moment the provider retires it, and the player is then
## stuck with a broken panel and no way out. So every provider's model lives in
## Settings, is editable in the UI, and a "model not found" response is turned
## into a message that says exactly that and points at the setting. Where the
## provider offers a models endpoint, the settings screen can list the live
## options rather than making the player guess.

const ANTHROPIC := "anthropic"
const OPENAI := "openai"
const GEMINI := "gemini"
const OLLAMA := "ollama"

## Per-provider wire details.
##
## `default_model` is what a fresh install uses. The Anthropic default is
## `claude-opus-5`, the current Opus-tier model. Nothing here downgrades a
## model to save the player money: it is their key and their decision, and the
## setting is one click away.
const SPECS := {
	ANTHROPIC: {
		"label": "Anthropic",
		"url": "https://api.anthropic.com/v1/messages",
		"models_url": "https://api.anthropic.com/v1/models",
		"default_model": "claude-opus-5",
		"needs_key": true,
		"key_hint": "Starts with sk-ant-. Create one at console.anthropic.com.",
		"suggested_models": ["claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5"],
	},
	OPENAI: {
		"label": "OpenAI",
		"url": "https://api.openai.com/v1/chat/completions",
		"models_url": "https://api.openai.com/v1/models",
		"default_model": "gpt-4o",
		"needs_key": true,
		"key_hint": "Starts with sk-. Create one at platform.openai.com.",
		"suggested_models": [],
	},
	GEMINI: {
		"label": "Google Gemini",
		"url": "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
		"models_url": "https://generativelanguage.googleapis.com/v1beta/models",
		"default_model": "gemini-2.0-flash",
		"needs_key": true,
		"key_hint": "Create one at aistudio.google.com.",
		"suggested_models": [],
	},
	OLLAMA: {
		"label": "Ollama (local)",
		"url": "http://127.0.0.1:11434/api/chat",
		"models_url": "http://127.0.0.1:11434/api/tags",
		"default_model": "llama3.1",
		"needs_key": false,
		"key_hint": "No key needed. Ollama must be running on this machine.",
		"suggested_models": [],
	},
}

## Cap on the reply. Mission Control asks for a short op list, not an essay.
const MAX_OUTPUT_TOKENS := 2000


static func spec(provider: String) -> Dictionary:
	return SPECS.get(provider, SPECS[ANTHROPIC])


static func label(provider: String) -> String:
	return String(spec(provider)["label"])


static func default_model(provider: String) -> String:
	return String(spec(provider)["default_model"])


static func needs_key(provider: String) -> bool:
	return bool(spec(provider)["needs_key"])


static func endpoint(provider: String, model: String, key: String) -> String:
	var url := String(spec(provider)["url"])
	if provider == GEMINI:
		# Gemini puts the model in the path and the key in the query string.
		return url.replace("{model}", model) + "?key=" + key.uri_encode()
	return url


## HTTP headers, as Godot's HTTPRequest wants them.
##
## The key appears here and nowhere else. It is never logged, never written to
## a save, and never included in an error message — `describe_error()` reports
## status codes and provider messages only.
static func headers(provider: String, key: String) -> PackedStringArray:
	var h := PackedStringArray(["content-type: application/json"])
	match provider:
		ANTHROPIC:
			h.append("x-api-key: " + key)
			h.append("anthropic-version: 2023-06-01")
		OPENAI:
			h.append("authorization: Bearer " + key)
		GEMINI, OLLAMA:
			pass  # key goes in the query string / no key at all
	return h


## Builds the request body. `system` is the instruction block, `user` the
## player's intent plus the flight context.
static func build_body(provider: String, model: String, system: String, user: String) -> String:
	var body := {}
	match provider:
		ANTHROPIC:
			# Messages API. `system` is a top-level field, not a message role.
			# Thinking is deliberately left unset: on current models that means
			# adaptive, which is what a one-shot translation wants, and it keeps
			# the request valid across the whole family.
			body = {
				"model": model,
				"max_tokens": MAX_OUTPUT_TOKENS,
				"system": system,
				"messages": [{"role": "user", "content": user}],
			}
		OPENAI:
			body = {
				"model": model,
				"max_completion_tokens": MAX_OUTPUT_TOKENS,
				"messages": [
					{"role": "system", "content": system},
					{"role": "user", "content": user},
				],
			}
		GEMINI:
			body = {
				"systemInstruction": {"parts": [{"text": system}]},
				"contents": [{"role": "user", "parts": [{"text": user}]}],
				"generationConfig": {"maxOutputTokens": MAX_OUTPUT_TOKENS},
			}
		OLLAMA:
			body = {
				"model": model,
				"stream": false,
				"messages": [
					{"role": "system", "content": system},
					{"role": "user", "content": user},
				],
			}
	return JSON.stringify(body)


## Pulls the assistant's text out of a provider response.
## Returns {"ok": bool, "text": String, "error": String}.
static func extract_text(provider: String, response: Dictionary) -> Dictionary:
	match provider:
		ANTHROPIC:
			# A safety refusal comes back as HTTP 200 with stop_reason
			# "refusal" and no usable content, so it has to be checked before
			# reading content or the panel shows an empty proposal.
			if String(response.get("stop_reason", "")) == "refusal":
				var det: Dictionary = response.get("stop_details", {})
				return _err("The model declined this request%s."
					% ("" if det.is_empty() else " (%s)" % String(det.get("category", ""))))
			var parts := PackedStringArray()
			for block in response.get("content", []):
				if typeof(block) == TYPE_DICTIONARY and String(block.get("type", "")) == "text":
					parts.append(String(block.get("text", "")))
			if parts.is_empty():
				return _err("The reply contained no text.")
			return _ok("\n".join(parts))

		OPENAI:
			var choices: Array = response.get("choices", [])
			if choices.is_empty():
				return _err("The reply contained no choices.")
			var msg: Dictionary = choices[0].get("message", {})
			var text := String(msg.get("content", ""))
			if text.is_empty():
				return _err("The reply contained no text.")
			return _ok(text)

		GEMINI:
			var cands: Array = response.get("candidates", [])
			if cands.is_empty():
				var fb: Dictionary = response.get("promptFeedback", {})
				if fb.has("blockReason"):
					return _err("The model declined this request (%s)."
						% String(fb["blockReason"]))
				return _err("The reply contained no candidates.")
			var gparts: Array = cands[0].get("content", {}).get("parts", [])
			var gtext := PackedStringArray()
			for pt in gparts:
				if typeof(pt) == TYPE_DICTIONARY and pt.has("text"):
					gtext.append(String(pt["text"]))
			if gtext.is_empty():
				return _err("The reply contained no text.")
			return _ok("\n".join(gtext))

		OLLAMA:
			var om: Dictionary = response.get("message", {})
			var otext := String(om.get("content", ""))
			if otext.is_empty():
				return _err("The reply contained no text.")
			return _ok(otext)

	return _err("Unknown provider '%s'." % provider)


## Turns a failed call into something a player can act on.
##
## The commonest failure in a game that ships a default model string is that
## the model has been retired — so that case is named explicitly and points at
## the setting rather than leaving the player staring at "400".
static func describe_error(provider: String, status: int, body: Dictionary) -> String:
	var provider_message := _provider_message(provider, body)

	match status:
		0:
			return "Could not reach %s.%s" % [label(provider),
				" Is Ollama running?" if provider == OLLAMA else " Check your connection."]
		401, 403:
			return "%s rejected the key. Check it in Settings → Mission Control." \
				% label(provider)
		404:
			return "%s does not have a model called '%s'. Pick a different one in " \
				% [label(provider), Settings.ai_model] \
				+ "Settings → Mission Control."
		429:
			return "%s is rate-limiting you. Wait a moment and try again." % label(provider)
		400:
			if _looks_like_model_error(provider_message):
				return "%s rejected the model '%s': %s Change it in Settings → " \
					% [label(provider), Settings.ai_model, provider_message] \
					+ "Mission Control."
			return "%s rejected the request: %s" % [label(provider), provider_message]
		500, 502, 503, 529:
			return "%s is having trouble (%d). Try again shortly." % [label(provider), status]
	if provider_message.is_empty():
		return "%s returned an unexpected status (%d)." % [label(provider), status]
	return "%s: %s" % [label(provider), provider_message]


static func _looks_like_model_error(message: String) -> bool:
	var m := message.to_lower()
	return m.contains("model") and (m.contains("not found") or m.contains("does not exist")
		or m.contains("unknown") or m.contains("invalid") or m.contains("deprecat"))


static func _provider_message(provider: String, body: Dictionary) -> String:
	match provider:
		ANTHROPIC:
			return String(body.get("error", {}).get("message", ""))
		OPENAI:
			return String(body.get("error", {}).get("message", ""))
		GEMINI:
			return String(body.get("error", {}).get("message", ""))
		OLLAMA:
			return String(body.get("error", ""))
	return ""


## Parses a models-list response into ids, so the settings screen can offer the
## live list instead of a stale hard-coded one.
static func extract_models(provider: String, response: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	match provider:
		ANTHROPIC, OPENAI:
			for m in response.get("data", []):
				if typeof(m) == TYPE_DICTIONARY and m.has("id"):
					out.append(String(m["id"]))
		GEMINI:
			for m in response.get("models", []):
				if typeof(m) == TYPE_DICTIONARY and m.has("name"):
					out.append(String(m["name"]).trim_prefix("models/"))
		OLLAMA:
			for m in response.get("models", []):
				if typeof(m) == TYPE_DICTIONARY and m.has("name"):
					out.append(String(m["name"]))
	out.sort()
	return out


static func _ok(text: String) -> Dictionary:
	return {"ok": true, "text": text, "error": ""}


static func _err(message: String) -> Dictionary:
	return {"ok": false, "text": "", "error": message}
