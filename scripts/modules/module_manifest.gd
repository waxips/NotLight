# SPDX-License-Identifier: GPL-3.0-or-later
class_name ModuleManifest
extends RefCounted

const SCHEMA_ID: String = "notlight.module"
const SCHEMA_VERSION: int = 1
const MODULE_API_VERSION: int = 1
const GODOT_RUNTIME_VERSION: String = "4.4.1"
const KIND_CODE: String = "code"
const KIND_DATA: String = "data"
const DEFAULT_LOCALIZATION_DIR: String = "localization"
const REQUIRED_CODE_CAPABILITIES: Array[String] = [
	"board.instance_state",
	"localization.read",
	"theme.read",
]
const ALLOWED_CAPABILITIES: Array[String] = [
	"board.instance_state",
	"localization.read",
	"theme.read",
]
const SUPPORTED_LOCALES: Array[String] = ["ru", "be", "en", "uk"]
const MAX_NAME_LENGTH: int = 96
const MAX_DESCRIPTION_LENGTH: int = 1200
const MAX_CAPABILITIES: int = 24


static func validate(source: Dictionary) -> Dictionary:
	var schema: String = str(source.get("schema", "")).strip_edges()
	if schema != SCHEMA_ID:
		return _error(NotLightL10n.text("runtime.modules.module_manifest.7359add628"))
	if int(source.get("schema_version", 0)) != SCHEMA_VERSION:
		return _error(NotLightL10n.text("runtime.modules.module_manifest.0a98d12cbf"))

	var module_id: String = str(source.get("module_id", "")).strip_edges().to_lower()
	if not is_valid_module_id(module_id):
		return _error(NotLightL10n.text("runtime.modules.module_manifest.9da4a5d87b"))
	var name: String = str(source.get("name", "")).strip_edges().left(MAX_NAME_LENGTH)
	if name.is_empty():
		return _error(NotLightL10n.text("runtime.modules.module_manifest.b990b90976"))
	var version: String = str(source.get("version", "")).strip_edges()
	if not is_valid_version(version):
		return _error(NotLightL10n.text("runtime.modules.module_manifest.b850430923"))
	if int(source.get("module_api_version", 0)) != MODULE_API_VERSION:
		return _error(NotLightL10n.text("runtime.modules.module_manifest.10f80856c2"))
	if str(source.get("godot_version", "")).strip_edges() != GODOT_RUNTIME_VERSION:
		return _error(NotLightL10n.text("runtime.modules.module_manifest.a084676957") % GODOT_RUNTIME_VERSION)
	var kind: String = str(source.get("kind", KIND_CODE)).strip_edges().to_lower()
	if kind != KIND_CODE and kind != KIND_DATA:
		return _error(NotLightL10n.text("runtime.modules.module_manifest.91837e77dc"))
	var state_schema_version: int = int(source.get("state_schema_version", 0))
	if state_schema_version <= 0 or state_schema_version > 100000:
		return _error(NotLightL10n.text("runtime.modules.module_manifest.7515058d22"))

	var entry_point: String = str(source.get("entry_point", "")).strip_edges().replace("\\", "/")
	if kind == KIND_CODE:
		if not is_valid_entry_point(module_id, entry_point):
			return _error(NotLightL10n.text("runtime.modules.module_manifest.9da38608a6"))
	else:
		entry_point = ""

	var capabilities_result: Dictionary = _normalize_capabilities(source.get("capabilities", []), kind)
	if not bool(capabilities_result.get("ok", false)):
		return capabilities_result
	var localizations_result: Dictionary = _normalize_localizations(source.get("localizations", {}))
	if not bool(localizations_result.get("ok", false)):
		return localizations_result
	var dependencies_value: Variant = source.get("dependencies", [])
	if dependencies_value is not Array or not (dependencies_value as Array).is_empty():
		return _error(NotLightL10n.text("runtime.modules.module_manifest.ccc68fc967"))

	var payload_key: String = str(source.get("payload_key", "payload.pck")).strip_edges().replace("\\", "/")
	if kind == KIND_CODE and payload_key != "payload.pck":
		return _error(NotLightL10n.text("runtime.modules.module_manifest.f73c4dafb3"))
	var icon_key: String = str(source.get("icon_key", "")).strip_edges().replace("\\", "/")
	if not icon_key.is_empty() and not _is_safe_package_key(icon_key):
		return _error(NotLightL10n.text("runtime.modules.module_manifest.b96a6d4e5a"))
	var preview_key: String = str(source.get("preview_key", "")).strip_edges().replace("\\", "/")
	if not preview_key.is_empty():
		if not _is_safe_package_key(preview_key):
			return _error(NotLightL10n.text("runtime.modules.module_manifest.54163c2c3b"))
		var preview_extension: String = preview_key.get_extension().to_lower()
		if preview_extension != "png" and preview_extension != "webp" and preview_extension != "jpg" and preview_extension != "jpeg" and preview_extension != "svg":
			return _error(NotLightL10n.text("runtime.modules.module_manifest.bf6d83d137"))
	var license_key: String = str(source.get("license_key", "LICENSE")).strip_edges().replace("\\", "/")
	if not license_key.is_empty() and not _is_safe_package_key(license_key):
		return _error(NotLightL10n.text("runtime.modules.module_manifest.1391fabdfc"))
	var notices_key: String = str(source.get("notices_key", "")).strip_edges().replace("\\", "/")
	if not notices_key.is_empty() and not _is_safe_package_key(notices_key):
		return _error(NotLightL10n.text("runtime.modules.module_manifest.645c456cb2"))
	var payload_keys_result: Dictionary = _validate_unique_payload_keys(
		payload_key,
		icon_key,
		preview_key,
		license_key,
		notices_key,
		localizations_result.get("localizations", {}) as Dictionary
	)
	if not bool(payload_keys_result.get("ok", false)):
		return payload_keys_result

	var normalized: Dictionary = {
		"schema": SCHEMA_ID,
		"schema_version": SCHEMA_VERSION,
		"module_id": module_id,
		"name": name,
		"description": str(source.get("description", "")).strip_edges().left(MAX_DESCRIPTION_LENGTH),
		"version": version,
		"module_api_version": MODULE_API_VERSION,
		"godot_version": GODOT_RUNTIME_VERSION,
		"kind": kind,
		"entry_point": entry_point,
		"state_schema_version": state_schema_version,
		"capabilities": capabilities_result.get("capabilities", []),
		"dependencies": [],
		"payload_key": payload_key,
		"icon_key": icon_key,
		"preview_key": preview_key,
		"license": str(source.get("license", "")).strip_edges().left(96),
		"license_key": license_key,
		"notices_key": notices_key,
		"author": str(source.get("author", "")).strip_edges().left(96),
		"homepage": str(source.get("homepage", "")).strip_edges().left(512),
		"localizations": localizations_result.get("localizations", {}),
	}
	return {"ok": true, "manifest": normalized}


static func is_valid_module_id(value: String) -> bool:
	var clean: String = value.strip_edges()
	if clean.is_empty() or clean.length() > 128 or clean != clean.to_lower():
		return false
	var segments: PackedStringArray = clean.split(".", false)
	if segments.size() < 2:
		return false
	const ALLOWED: String = "abcdefghijklmnopqrstuvwxyz0123456789_-"
	for segment: String in segments:
		if segment.is_empty() or "abcdefghijklmnopqrstuvwxyz".find(segment.substr(0, 1).to_lower()) < 0:
			return false
		for index: int in range(segment.length()):
			if ALLOWED.find(segment.substr(index, 1)) < 0:
				return false
	return true


static func is_valid_version(value: String) -> bool:
	var parts: PackedStringArray = value.strip_edges().split(".", false)
	if parts.size() != 3:
		return false
	for part: String in parts:
		if part.is_empty() or not part.is_valid_int():
			return false
		var number: int = int(part)
		if number < 0 or number > 1000000:
			return false
		if part.length() > 1 and part.begins_with("0"):
			return false
	return true


static func compare_versions(left: String, right: String) -> int:
	if not is_valid_version(left) or not is_valid_version(right):
		return 0
	var left_parts: PackedStringArray = left.split(".", false)
	var right_parts: PackedStringArray = right.split(".", false)
	for index: int in range(3):
		var left_value: int = int(left_parts[index])
		var right_value: int = int(right_parts[index])
		if left_value < right_value:
			return -1
		if left_value > right_value:
			return 1
	return 0


static func is_valid_entry_point(module_id: String, path: String) -> bool:
	var clean: String = path.strip_edges().replace("\\", "/")
	var prefix: String = ("res:/" + "/modules/%s/") % module_id
	return (
		clean.begins_with(prefix)
		and clean.ends_with(".gd")
		and not clean.contains("..")
		and clean.get_file().length() > 3
	)


static func module_namespace(module_id: String) -> String:
	return ("res:/" + "/modules/%s/") % module_id


static func _normalize_capabilities(raw_value: Variant, kind: String) -> Dictionary:
	if raw_value is not Array and raw_value is not PackedStringArray:
		return _error(NotLightL10n.text("runtime.modules.module_manifest.2f1f7276c4"))
	var result: Array[String] = []
	var seen: Dictionary = {}
	for raw_capability: Variant in raw_value:
		var capability: String = str(raw_capability).strip_edges()
		if capability.is_empty() or not ALLOWED_CAPABILITIES.has(capability):
			return _error(NotLightL10n.text("runtime.modules.module_manifest.bb04c64635") % capability)
		if not seen.has(capability):
			result.append(capability)
			seen[capability] = true
		if result.size() > MAX_CAPABILITIES:
			return _error(NotLightL10n.text("runtime.modules.module_manifest.aaae92b399"))
	if kind == KIND_CODE:
		for required: String in REQUIRED_CODE_CAPABILITIES:
			if not seen.has(required):
				return _error(NotLightL10n.text("runtime.modules.module_manifest.13c9dc0c52") % required)
	return {"ok": true, "capabilities": result}


static func _normalize_localizations(raw_value: Variant) -> Dictionary:
	if raw_value is not Dictionary:
		return _error(NotLightL10n.text("runtime.modules.module_manifest.6557cd812c"))
	var source: Dictionary = raw_value as Dictionary
	var result: Dictionary = {}
	for raw_locale: Variant in source.keys():
		var locale: String = str(raw_locale).strip_edges().to_lower()
		if not SUPPORTED_LOCALES.has(locale):
			return _error(NotLightL10n.text("runtime.modules.module_manifest.86390e7d01") % locale)
		var key: String = str(source[raw_locale]).strip_edges().replace("\\", "/")
		if not _is_safe_package_key(key) or not key.ends_with(".json"):
			return _error(NotLightL10n.text("runtime.modules.module_manifest.db1d013b0a") % locale)
		result[locale] = key
	if not result.has("ru"):
		return _error(NotLightL10n.text("runtime.modules.module_manifest.3f5e21e6d3"))
	return {"ok": true, "localizations": result}


static func _validate_unique_payload_keys(
	payload_key: String,
	icon_key: String,
	preview_key: String,
	license_key: String,
	notices_key: String,
	localizations: Dictionary
) -> Dictionary:
	var seen: Dictionary = {}
	var keys: Array[String] = [payload_key, icon_key, preview_key, license_key, notices_key]
	for raw_locale: Variant in localizations.keys():
		keys.append(str(localizations[raw_locale]))
	for key: String in keys:
		if key.is_empty():
			continue
		if seen.has(key):
			return _error(NotLightL10n.text("runtime.modules.module_manifest.a794e1f7af") % key)
		seen[key] = true
	return {"ok": true}


static func _is_safe_package_key(value: String) -> bool:
	var clean: String = value.strip_edges().replace("\\", "/")
	return (
		not clean.is_empty()
		and not clean.begins_with("/")
		and not clean.contains("..")
		and clean.get_file() != "."
		and clean.get_file() != ".."
	)


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
