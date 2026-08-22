# SPDX-License-Identifier: GPL-3.0-or-later
class_name LocalizationRuntimeService
extends Node

signal locale_changed(locale: String)
signal bundles_changed

const DEFAULT_LOCALE: String = "ru"
const CORE_LOCALIZATION_DIR: String = "res://localization/core"
const DEFAULT_MODULE_ROOT: String = "user://notlight/modules"
const SUPPORTED_LOCALES: Array[String] = ["ru", "be", "en", "uk"]
var current_locale: String = DEFAULT_LOCALE
var _core_bundles: Dictionary = {}
var _module_paths: Dictionary = {}
var _module_bundles: Dictionary = {}
var _scanned_module_ids: Dictionary = {}
var _last_error: String = ""


func _enter_tree() -> void:
	# Load before regular scene _ready() callbacks so dynamic module bundles and
	# locale-change signals are available to Hub/Board UI immediately. Core UI
	# translations themselves also have a parser-safe JSON fallback in NotLightL10n.
	reload_core()


func _ready() -> void:
	scan_external_modules(DEFAULT_MODULE_ROOT)


func available_locales() -> Array[String]:
	return SUPPORTED_LOCALES.duplicate()


func locale_label(locale: String) -> String:
	var normalized: String = _normalize_locale(locale)
	return text("locale.name.%s" % normalized)


func set_locale(locale: String) -> bool:
	var normalized: String = _normalize_locale(locale)
	if not SUPPORTED_LOCALES.has(normalized):
		normalized = DEFAULT_LOCALE
	if current_locale == normalized:
		return true
	current_locale = normalized
	TranslationServer.set_locale(normalized)
	# Bound controls are refreshed centrally. This makes static labels/tooltips
	# future-ready for additional locales without each screen having to rebuild.
	var tree: SceneTree = get_tree()
	if tree != null and tree.root != null:
		refresh_tree(tree.root)
	locale_changed.emit(current_locale)
	return true


func text(key: String, values: Dictionary = {}) -> String:
	var translated: String = _lookup_core(key, current_locale)
	if translated.is_empty():
		translated = _lookup_core(key, DEFAULT_LOCALE)
	if translated.is_empty():
		translated = key
	return translated.format(values) if not values.is_empty() else translated


func module_text(module_id: String, key: String, values: Dictionary = {}) -> String:
	var clean_id: String = module_id.strip_edges()
	if clean_id.is_empty():
		return text(key, values)
	var translated: String = _lookup_module(clean_id, key, current_locale)
	if translated.is_empty():
		translated = _lookup_module(clean_id, key, DEFAULT_LOCALE)
	if translated.is_empty():
		translated = text(key)
	return translated.format(values) if not values.is_empty() else translated


func bind_text(control: Control, key: String, values: Dictionary = {}) -> void:
	_bind_property(control, &"text", key, values, "core")


func bind_tooltip(control: Control, key: String, values: Dictionary = {}) -> void:
	_bind_property(control, &"tooltip_text", key, values, "core")


func bind_placeholder_text(control: Control, key: String, values: Dictionary = {}) -> void:
	_bind_property(control, &"placeholder_text", key, values, "core")


func bind_module_text(control: Control, module_id: String, key: String, values: Dictionary = {}) -> void:
	_bind_property(control, &"text", key, values, module_id)


func refresh_tree(root: Node) -> void:
	if root == null:
		return
	_refresh_bound_node(root)
	for child: Node in root.get_children():
		refresh_tree(child)


func _bind_property(control: Control, property_name: StringName, key: String, values: Dictionary, domain: String) -> void:
	if control == null or key.is_empty():
		return
	var bindings: Array = []
	var existing: Variant = control.get_meta("notlight_l10n_bindings", [])
	if existing is Array:
		bindings = (existing as Array).duplicate(true)
	var record: Dictionary = {
		"property": String(property_name),
		"key": key,
		"values": values.duplicate(true),
		"domain": domain,
	}
	var replaced: bool = false
	for index: int in range(bindings.size()):
		if bindings[index] is Dictionary and str((bindings[index] as Dictionary).get("property", "")) == String(property_name):
			bindings[index] = record
			replaced = true
			break
	if not replaced:
		bindings.append(record)
	control.set_meta("notlight_l10n_bindings", bindings)
	_apply_binding(control, record)


func _refresh_bound_node(node: Node) -> void:
	if node is not Control:
		return
	var control: Control = node as Control
	var raw: Variant = control.get_meta("notlight_l10n_bindings", [])
	if raw is not Array:
		return
	for item: Variant in raw:
		if item is Dictionary:
			_apply_binding(control, item as Dictionary)


func _apply_binding(control: Control, record: Dictionary) -> void:
	var property_name: StringName = StringName(str(record.get("property", "text")))
	var key: String = str(record.get("key", ""))
	var domain: String = str(record.get("domain", "core"))
	var values_value: Variant = record.get("values", {})
	var values: Dictionary = {}
	if values_value is Dictionary:
		values = (values_value as Dictionary).duplicate(true)
	var translated: String = text(key, values) if domain == "core" else module_text(domain, key, values)
	control.set(property_name, translated)


func reload_core() -> bool:
	_last_error = ""
	_core_bundles.clear()
	var loaded_any: bool = false
	var russian: Dictionary = NotLightCoreRuFallback.strings()
	var russian_json: Dictionary = _read_bundle(CORE_LOCALIZATION_DIR.path_join("ru.json"))
	for raw_key: Variant in russian_json.keys():
		russian[str(raw_key)] = str(russian_json[raw_key])
	if not russian.is_empty():
		_core_bundles[DEFAULT_LOCALE] = russian
		loaded_any = true
	for locale: String in SUPPORTED_LOCALES:
		if locale == DEFAULT_LOCALE:
			continue
		var path: String = CORE_LOCALIZATION_DIR.path_join("%s.json" % locale)
		var bundle: Dictionary = _read_bundle(path)
		if not bundle.is_empty():
			_core_bundles[locale] = bundle
			loaded_any = true
	if not _core_bundles.has(DEFAULT_LOCALE):
		_last_error = str(russian.get("runtime.localization.missing_ru_bundle", "runtime.localization.missing_ru_bundle"))
		push_error(_last_error)
		return false
	bundles_changed.emit()
	return loaded_any


func register_module_localization(module_id: String, localization_dir: String) -> bool:
	var clean_id: String = module_id.strip_edges()
	var clean_dir: String = localization_dir.strip_edges()
	if clean_id.is_empty() or clean_dir.is_empty():
		return false
	var previous_path: Variant = _module_paths.get(clean_id)
	_module_paths[clean_id] = clean_dir
	if not _reload_module_bundle(clean_id):
		if previous_path == null:
			_module_paths.erase(clean_id)
		else:
			_module_paths[clean_id] = str(previous_path)
			_reload_module_bundle(clean_id)
		return false
	bundles_changed.emit()
	return true


func unregister_module_localization(module_id: String) -> void:
	var clean_id: String = module_id.strip_edges()
	_module_paths.erase(clean_id)
	_module_bundles.erase(clean_id)
	bundles_changed.emit()


func scan_external_modules(root_path: String = DEFAULT_MODULE_ROOT) -> int:
	var root: String = root_path.strip_edges()
	if root.is_empty():
		return 0
	# A rescan is authoritative for modules discovered by the previous scan.
	# Manually registered bundles are intentionally left alone.
	for raw_id: Variant in _scanned_module_ids.keys():
		unregister_module_localization(str(raw_id))
	_scanned_module_ids.clear()
	var absolute_root: String = ProjectSettings.globalize_path(root) if root.begins_with("user://") or root.begins_with("res://") else root
	absolute_root = absolute_root.simplify_path()
	if not DirAccess.dir_exists_absolute(absolute_root):
		return 0
	var directory: DirAccess = DirAccess.open(absolute_root)
	if directory == null:
		return 0
	var registered: int = 0
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if directory.current_is_dir() and entry != "." and entry != "..":
			var module_dir: String = absolute_root.path_join(entry).simplify_path()
			var manifest_path: String = module_dir.path_join("manifest.json")
			var manifest: Dictionary = _read_json_dictionary(manifest_path)
			if not manifest.is_empty():
				var module_id: String = str(manifest.get("id", entry)).strip_edges()
				var localization_relative: String = str(manifest.get("localization_dir", "localization")).strip_edges()
				var localization_dir: String = module_dir.path_join(localization_relative).simplify_path()
				# A module is only allowed to advertise localization files inside its own folder.
				# IDs already present after clearing the previous scan belong either to a
				# manually registered provider or to an earlier module in this scan. Never
				# let a later directory silently replace that localization namespace.
				if (
					not module_id.is_empty()
					and not _module_paths.has(module_id)
					and _path_is_within(localization_dir, module_dir)
				):
					if register_module_localization(module_id, localization_dir):
						_scanned_module_ids[module_id] = true
						registered += 1
		entry = directory.get_next()
	directory.list_dir_end()
	return registered


func _path_is_within(candidate_path: String, parent_path: String) -> bool:
	var candidate: String = candidate_path.simplify_path().replace("\\", "/").trim_suffix("/")
	var parent: String = parent_path.simplify_path().replace("\\", "/").trim_suffix("/")
	if candidate.is_empty() or parent.is_empty():
		return false
	return candidate == parent or candidate.begins_with(parent + "/")


func get_last_error() -> String:
	return _last_error


func _normalize_locale(locale: String) -> String:
	var normalized: String = locale.strip_edges().to_lower().replace("-", "_")
	if normalized.contains("_"):
		normalized = normalized.get_slice("_", 0)
	return normalized


func _lookup_core(key: String, locale: String) -> String:
	var bundle_value: Variant = _core_bundles.get(locale)
	if bundle_value is not Dictionary:
		return ""
	return str((bundle_value as Dictionary).get(key, ""))


func _lookup_module(module_id: String, key: String, locale: String) -> String:
	var module_value: Variant = _module_bundles.get(module_id)
	if module_value is not Dictionary:
		return ""
	var locale_value: Variant = (module_value as Dictionary).get(locale)
	if locale_value is not Dictionary:
		return ""
	return str((locale_value as Dictionary).get(key, ""))


func _reload_module_bundle(module_id: String) -> bool:
	var raw_path: Variant = _module_paths.get(module_id)
	if raw_path == null:
		return false
	var localization_dir: String = str(raw_path)
	var bundles: Dictionary = {}
	for locale: String in SUPPORTED_LOCALES:
		var bundle: Dictionary = _read_bundle(localization_dir.path_join("%s.json" % locale))
		if not bundle.is_empty():
			bundles[locale] = bundle
	if bundles.is_empty():
		_module_bundles.erase(module_id)
		return false
	_module_bundles[module_id] = bundles
	return true


func _read_bundle(path: String) -> Dictionary:
	var source: Dictionary = _read_json_dictionary(path)
	if source.is_empty():
		return {}
	var strings_value: Variant = source.get("strings")
	if strings_value is Dictionary:
		return (strings_value as Dictionary).duplicate(true)
	var result: Dictionary = {}
	for raw_key: Variant in source.keys():
		var key: String = str(raw_key)
		if key.begins_with("_"):
			continue
		var value: Variant = source[raw_key]
		if value is String:
			result[key] = value
	return result


func _read_json_dictionary(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is not Dictionary:
		return {}
	return (parsed as Dictionary).duplicate(true)
