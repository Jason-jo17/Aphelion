class_name KeyStore
extends RefCounted

## Where a BYOK API key lives.
##
## Aphelion never sees your key except to put it in a request header to the
## provider you chose. It is never written into a save file, a solution file, a
## log line or a crash report, and the game is fully playable without one.
##
## Three sources are tried in order, best first:
##
## 1. **An environment variable** — `APHELION_ANTHROPIC_API_KEY` and friends.
##    Nothing is stored by the game at all. This is the recommended setup and
##    the only one CI ever uses.
## 2. **The OS keychain**, through the tool the platform already ships:
##    `security` on macOS, `secret-tool` (libsecret) on Linux. The key is held
##    by the OS, encrypted at rest, and the game asks for it per session.
## 3. **A local file**, only if you explicitly opt in. This is plainly less safe
##    — it is obfuscated, not encrypted, and anyone with your user directory can
##    read it — so the settings screen says so in those words before you can
##    turn it on.
##
## Windows has no equivalent of `security`/`secret-tool` that can be driven from
## a game process without shipping an extra dependency, so option 2 is not
## offered there and the UI says so rather than pretending.

const SERVICE_NAME := "aphelion-mission-control"
const FILE_PATH := "user://credentials.cfg"

enum Source { NONE, ENVIRONMENT, KEYCHAIN, FILE }

## Providers, in the order the settings screen lists them.
const PROVIDERS := ["anthropic", "openai", "gemini", "ollama"]


static func env_var_for(provider: String) -> String:
	return "APHELION_%s_API_KEY" % provider.to_upper()


## Reads the key for a provider, or "" if there is none.
static func get_key(provider: String) -> String:
	var env := OS.get_environment(env_var_for(provider))
	if not env.is_empty():
		return env
	var chain := _keychain_read(provider)
	if not chain.is_empty():
		return chain
	return _file_read(provider)


## Where the key currently in use came from, for the settings screen to show.
static func source_for(provider: String) -> int:
	if not OS.get_environment(env_var_for(provider)).is_empty():
		return Source.ENVIRONMENT
	if not _keychain_read(provider).is_empty():
		return Source.KEYCHAIN
	if not _file_read(provider).is_empty():
		return Source.FILE
	return Source.NONE


static func source_name(source: int) -> String:
	match source:
		Source.ENVIRONMENT: return "environment variable"
		Source.KEYCHAIN: return "system keychain"
		Source.FILE: return "local file (not encrypted)"
	return "not set"


static func has_key(provider: String) -> bool:
	return not get_key(provider).is_empty()


## Any provider configured at all? Mission Control stays off until one is.
static func any_key_present() -> bool:
	for p in PROVIDERS:
		if p == "ollama":
			continue  # local models need no key; presence is decided by reachability
		if has_key(p):
			return true
	return false


## Stores a key. `use_file` opts in to the unencrypted fallback; without it,
## storing fails on platforms with no keychain helper and says why.
static func set_key(provider: String, key: String, use_file: bool = false) -> Dictionary:
	if key.strip_edges().is_empty():
		clear_key(provider)
		return {"ok": true, "stored_in": Source.NONE, "message": "Key removed."}

	if not use_file and keychain_available():
		if _keychain_write(provider, key):
			return {"ok": true, "stored_in": Source.KEYCHAIN,
				"message": "Stored in the system keychain."}
		return {"ok": false, "stored_in": Source.NONE,
			"message": "The system keychain refused to store the key."}

	if not use_file:
		return {"ok": false, "stored_in": Source.NONE,
			"message": "No system keychain is available on this platform. "
				+ "Set %s in your environment, or tick the box to store it in a "
				% env_var_for(provider)
				+ "local file — which is not encrypted."}

	if _file_write(provider, key):
		return {"ok": true, "stored_in": Source.FILE,
			"message": "Stored in %s. This file is obfuscated, not encrypted."
				% ProjectSettings.globalize_path(FILE_PATH)}
	return {"ok": false, "stored_in": Source.NONE, "message": "Could not write the file."}


static func clear_key(provider: String) -> void:
	_keychain_delete(provider)
	_file_write(provider, "")


static func keychain_available() -> bool:
	match OS.get_name():
		"macOS":
			return _has_command("security")
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			return _has_command("secret-tool")
	return false


# --- keychain ---------------------------------------------------------------


static func _has_command(cmd: String) -> bool:
	var out: Array = []
	# `command -v` is the POSIX way and does not depend on `which` being present.
	var code := OS.execute("/bin/sh", ["-c", "command -v %s" % cmd], out, false, false)
	return code == 0


static func _keychain_read(provider: String) -> String:
	var out: Array = []
	match OS.get_name():
		"macOS":
			if not _has_command("security"):
				return ""
			var code := OS.execute("security", [
				"find-generic-password", "-s", SERVICE_NAME, "-a", provider, "-w",
			], out, false, false)
			if code != 0 or out.is_empty():
				return ""
			return String(out[0]).strip_edges()
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			if not _has_command("secret-tool"):
				return ""
			var code2 := OS.execute("secret-tool", [
				"lookup", "service", SERVICE_NAME, "account", provider,
			], out, false, false)
			if code2 != 0 or out.is_empty():
				return ""
			return String(out[0]).strip_edges()
	return ""


static func _keychain_write(provider: String, key: String) -> bool:
	var out: Array = []
	match OS.get_name():
		"macOS":
			# -U updates in place if the item already exists.
			return OS.execute("security", [
				"add-generic-password", "-U", "-s", SERVICE_NAME, "-a", provider,
				"-w", key,
			], out, false, false) == 0
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			# secret-tool reads the secret from stdin, which keeps it off the
			# process table where `ps` would show it.
			var script := "printf '%%s' \"$APHELION_TMP_KEY\" | secret-tool store " \
				+ "--label='Aphelion Mission Control' service %s account %s" \
				% [SERVICE_NAME, provider]
			OS.set_environment("APHELION_TMP_KEY", key)
			var code := OS.execute("/bin/sh", ["-c", script], out, false, false)
			OS.set_environment("APHELION_TMP_KEY", "")
			return code == 0
	return false


static func _keychain_delete(provider: String) -> void:
	var out: Array = []
	match OS.get_name():
		"macOS":
			OS.execute("security", ["delete-generic-password", "-s", SERVICE_NAME,
				"-a", provider], out, false, false)
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			OS.execute("secret-tool", ["clear", "service", SERVICE_NAME,
				"account", provider], out, false, false)


# --- local file -------------------------------------------------------------


## Obfuscation, not encryption, and the UI says so. Storing the bytes plainly
## would mean a key showing up in a screenshot of a text editor or in a backup
## preview; this at least stops it being readable at a glance. It stops nothing
## else, which is why it is third in the list and opt-in.
static func _obfuscate(text: String, provider: String) -> PackedByteArray:
	var raw := text.to_utf8_buffer()
	var pad := (SERVICE_NAME + ":" + provider + ":" + OS.get_unique_id()).sha256_buffer()
	var out := PackedByteArray()
	out.resize(raw.size())
	for i in raw.size():
		out[i] = raw[i] ^ pad[i % pad.size()]
	return out


static func _file_read(provider: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(FILE_PATH) != OK:
		return ""
	var blob: String = cfg.get_value("keys", provider, "")
	if blob.is_empty():
		return ""
	var bytes := Marshalls.base64_to_raw(blob)
	return _obfuscate_bytes(bytes, provider)


static func _obfuscate_bytes(bytes: PackedByteArray, provider: String) -> String:
	var pad := (SERVICE_NAME + ":" + provider + ":" + OS.get_unique_id()).sha256_buffer()
	var out := PackedByteArray()
	out.resize(bytes.size())
	for i in bytes.size():
		out[i] = bytes[i] ^ pad[i % pad.size()]
	return out.get_string_from_utf8()


static func _file_write(provider: String, key: String) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(FILE_PATH)  # ignore failure; a missing file is an empty one
	if key.is_empty():
		# erase_section_key complains if the section was never created.
		if cfg.has_section_key("keys", provider):
			cfg.erase_section_key("keys", provider)
	else:
		cfg.set_value("keys", provider, Marshalls.raw_to_base64(_obfuscate(key, provider)))
	return cfg.save(FILE_PATH) == OK


## A key with its middle removed, for display. Never log the whole thing.
static func redact(key: String) -> String:
	if key.length() <= 10:
		return "•".repeat(key.length())
	return key.substr(0, 6) + "…" + key.substr(key.length() - 4)
