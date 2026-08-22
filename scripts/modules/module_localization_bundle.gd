# SPDX-License-Identifier: GPL-3.0-or-later
class_name ModuleLocalizationBundle
extends RefCounted

const MAX_STRINGS: int = 5000
const MAX_KEY_LENGTH: int = 256
const MAX_VALUE_LENGTH: int = 65536
const MANIFEST_NAME_KEY: String = "module.name"
const MANIFEST_DESCRIPTION_KEY: String = "module.description"


static func read_file(
	path: String,
	module_id: String,
	locale: String,
	require_nonempty: bool
) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error(NotLightL10n.text("runtime.modules.module_localization_bundle.f745835807") % locale)
	var text: String = file.get_as_text()
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK:
		return _error(NotLightL10n.text("runtime.modules.module_localization_bundle.7633fc8bd2") % locale)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		return _error(NotLightL10n.text("runtime.modules.module_localization_bundle.0657767128") % locale)
	return validate_source(parsed as Dictionary, module_id, locale, require_nonempty)


static func validate_source(
	source: Dictionary,
	module_id: String,
	locale: String,
	require_nonempty: bool
) -> Dictionary:
	var clean_id: String = module_id.strip_edges().to_lower()
	var clean_locale: String = locale.strip_edges().to_lower()
	if clean_id.is_empty() or clean_locale.is_empty():
		return _error(NotLightL10n.text("runtime.modules.module_localization_bundle.26dadbdc27"))
	var meta_value: Variant = source.get("_meta", {})
	if meta_value is not Dictionary:
		return _error(NotLightL10n.text("runtime.modules.module_localization_bundle.a253e8af5f") % clean_locale)
	var meta: Dictionary = meta_value as Dictionary
	var declared_module_id: String = str(meta.get("module_id", "")).strip_edges().to_lower()
	var declared_locale: String = str(meta.get("locale", "")).strip_edges().to_lower()
	if declared_module_id != clean_id or declared_locale != clean_locale:
		return _error(NotLightL10n.text("runtime.modules.module_localization_bundle.9f89a9dd41") % clean_locale)
	var strings_value: Variant = source.get("strings", {})
	if strings_value is not Dictionary:
		return _error(NotLightL10n.text("runtime.modules.module_localization_bundle.f8ee00cba9") % clean_locale)
	var strings: Dictionary = strings_value as Dictionary
	if strings.size() > MAX_STRINGS:
		return _error(NotLightL10n.text("runtime.modules.module_localization_bundle.f0b0fa4b4e") % clean_locale)
	var normalized: Dictionary = {}
	for raw_key: Variant in strings.keys():
		var key: String = str(raw_key).strip_edges()
		if key.begins_with("_"):
			continue
		var value: Variant = strings[raw_key]
		if key.is_empty() or key.length() > MAX_KEY_LENGTH or value is not String or str(value).length() > MAX_VALUE_LENGTH:
			return _error(NotLightL10n.text("runtime.modules.module_localization_bundle.dfe35d93f3") % clean_locale)
		normalized[key] = str(value)
	if require_nonempty and normalized.is_empty():
		return _error(NotLightL10n.text("runtime.modules.module_localization_bundle.e295e66e0c"))
	return {"ok": true, "strings": normalized}


static func resolve_manifest_text(
	manifest: Dictionary,
	bundles: Dictionary,
	field: String,
	locale: String
) -> String:
	var fallback: String = str(manifest.get(field, "")).strip_edges()
	var localization_key: String = _manifest_localization_key(field)
	if localization_key.is_empty():
		return fallback
	var clean_locale: String = _normalize_locale(locale)
	var translated: String = _lookup(bundles, clean_locale, localization_key).strip_edges()
	if translated.is_empty() and clean_locale != "ru":
		translated = _lookup(bundles, "ru", localization_key).strip_edges()
	if translated.is_empty():
		translated = fallback
	match field:
		"name":
			return translated.left(ModuleManifest.MAX_NAME_LENGTH)
		"description":
			return translated.left(ModuleManifest.MAX_DESCRIPTION_LENGTH)
		_:
			return translated


static func _manifest_localization_key(field: String) -> String:
	match field.strip_edges():
		"name":
			return MANIFEST_NAME_KEY
		"description":
			return MANIFEST_DESCRIPTION_KEY
		_:
			return ""


static func _lookup(bundles: Dictionary, locale: String, key: String) -> String:
	var locale_value: Variant = bundles.get(locale, {})
	if locale_value is not Dictionary:
		return ""
	return str((locale_value as Dictionary).get(key, ""))


static func _normalize_locale(locale: String) -> String:
	var normalized: String = locale.strip_edges().to_lower().replace("-", "_")
	if normalized.contains("_"):
		normalized = normalized.get_slice("_", 0)
	return normalized if ModuleManifest.SUPPORTED_LOCALES.has(normalized) else "ru"


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
