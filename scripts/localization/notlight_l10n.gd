# SPDX-License-Identifier: GPL-3.0-or-later
class_name NotLightL10n
extends RefCounted

# Parser-safe localization facade.
#
# Core translations are loaded directly from JSON by this class and therefore
# do not depend on autoload initialization order. The optional runtime node is
# only responsible for locale-change signals and dynamic module bundles.
# This keeps Hub/Settings/Library text available even if a runtime service is
# temporarily unavailable while the scene tree is being constructed.

const RUNTIME_NODE_NAME: StringName = &"LocalizationRuntime"
const CORE_LOCALIZATION_DIR: String = "res://localization/core"
const DEFAULT_LOCALE: String = "ru"
const FALLBACK_LOCALES: Array[String] = ["ru", "be", "en", "uk"]
static var _core_bundles: Dictionary = {}
static var _core_loaded: bool = false
static var _core_error: String = ""


static func initialize() -> bool:
	return _ensure_core_loaded(true)


static func runtime() -> LocalizationRuntimeService:
	# SceneTree/Node traversal is not thread-safe. Worker-side callers still have
	# access to the parser-safe core fallback, but must never touch /root.
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return null
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is not SceneTree:
		return null
	var tree: SceneTree = main_loop as SceneTree
	var root: Window = tree.root
	if root == null:
		return null
	var node: Node = root.get_node_or_null(NodePath(String(RUNTIME_NODE_NAME)))
	if node is LocalizationRuntimeService:
		return node as LocalizationRuntimeService
	return null


static func is_available() -> bool:
	return _ensure_core_loaded(false)


static func connect_locale_changed(callback: Callable) -> bool:
	if not callback.is_valid():
		return false
	var service: LocalizationRuntimeService = runtime()
	if service == null:
		return false
	if not service.locale_changed.is_connected(callback):
		service.locale_changed.connect(callback)
	return true


static func disconnect_locale_changed(callback: Callable) -> void:
	if not callback.is_valid():
		return
	var service: LocalizationRuntimeService = runtime()
	if service == null:
		return
	if service.locale_changed.is_connected(callback):
		service.locale_changed.disconnect(callback)


static func available_locales() -> Array[String]:
	_ensure_core_loaded(false)
	var result: Array[String] = []
	for locale: String in FALLBACK_LOCALES:
		if _core_bundles.has(locale) or locale == DEFAULT_LOCALE:
			result.append(locale)
	return result if not result.is_empty() else FALLBACK_LOCALES.duplicate()


static func locale_label(locale: String) -> String:
	var normalized: String = _normalize_supported_locale(locale)
	return text_for_locale(normalized, "locale.name.%s" % normalized)


static func current_locale() -> String:
	var service: LocalizationRuntimeService = runtime()
	if service != null:
		return _normalize_supported_locale(service.current_locale)
	return _normalize_supported_locale(TranslationServer.get_locale())


static func set_locale(locale: String) -> bool:
	var normalized: String = _normalize_supported_locale(locale)
	TranslationServer.set_locale(normalized)
	var service: LocalizationRuntimeService = runtime()
	if service != null:
		return service.set_locale(normalized)
	return true


static func text(key: String, values: Dictionary = {}) -> String:
	var clean_key: String = key.strip_edges()
	if clean_key.is_empty():
		return ""
	_ensure_core_loaded(false)
	var translated: String = _lookup_core(clean_key, current_locale())
	if translated.is_empty():
		translated = _lookup_core(clean_key, DEFAULT_LOCALE)
	# A technical localization key is the last-resort diagnostic only. Under a
	# normal packaged/editor run the Russian bundle is guaranteed by validation.
	if translated.is_empty():
		translated = clean_key
	return translated.format(values) if not values.is_empty() else translated


static func text_for_locale(locale: String, key: String, values: Dictionary = {}) -> String:
	var clean_key: String = key.strip_edges()
	if clean_key.is_empty():
		return ""
	_ensure_core_loaded(false)
	var normalized: String = _normalize_supported_locale(locale)
	var translated: String = _lookup_core(clean_key, normalized)
	if translated.is_empty():
		translated = _lookup_core(clean_key, DEFAULT_LOCALE)
	if translated.is_empty():
		translated = clean_key
	return translated.format(values) if not values.is_empty() else translated


static func module_text(module_id: String, key: String, values: Dictionary = {}) -> String:
	var clean_id: String = module_id.strip_edges()
	if clean_id.is_empty():
		return text(key, values)
	var service: LocalizationRuntimeService = runtime()
	if service != null:
		var translated: String = service.module_text(clean_id, key, values)
		if translated != key:
			return translated
	return text(key, values)


static func bind_text(control: Control, key: String, values: Dictionary = {}) -> void:
	_bind_property(control, &"text", key, values, "core")


static func bind_tooltip(control: Control, key: String, values: Dictionary = {}) -> void:
	_bind_property(control, &"tooltip_text", key, values, "core")


static func bind_placeholder_text(control: Control, key: String, values: Dictionary = {}) -> void:
	_bind_property(control, &"placeholder_text", key, values, "core")


static func bind_module_text(
	control: Control,
	module_id: String,
	key: String,
	values: Dictionary = {}
) -> void:
	_bind_property(control, &"text", key, values, module_id.strip_edges())


static func refresh_tree(root_node: Node) -> void:
	if root_node == null:
		return
	_refresh_bound_node(root_node)
	for child: Node in root_node.get_children():
		refresh_tree(child)


static func reload_core() -> bool:
	var local_success: bool = _ensure_core_loaded(true)
	var service: LocalizationRuntimeService = runtime()
	if service != null:
		service.reload_core()
	return local_success


static func register_module_localization(module_id: String, localization_dir: String) -> bool:
	var service: LocalizationRuntimeService = runtime()
	return service.register_module_localization(module_id, localization_dir) if service != null else false


static func unregister_module_localization(module_id: String) -> void:
	var service: LocalizationRuntimeService = runtime()
	if service != null:
		service.unregister_module_localization(module_id)


static func scan_external_modules(root_path: String = "user://notlight/modules") -> int:
	var service: LocalizationRuntimeService = runtime()
	return service.scan_external_modules(root_path) if service != null else 0


static func get_last_error() -> String:
	if not _core_error.is_empty():
		return _core_error
	var service: LocalizationRuntimeService = runtime()
	return service.get_last_error() if service != null else ""


static func _bind_property(
	control: Control,
	property_name: StringName,
	key: String,
	values: Dictionary,
	domain: String
) -> void:
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
		"domain": domain if not domain.is_empty() else "core",
	}
	var replaced: bool = false
	for index: int in range(bindings.size()):
		if bindings[index] is not Dictionary:
			continue
		var existing_record: Dictionary = bindings[index] as Dictionary
		if str(existing_record.get("property", "")) == String(property_name):
			bindings[index] = record
			replaced = true
			break
	if not replaced:
		bindings.append(record)
	control.set_meta("notlight_l10n_bindings", bindings)
	_apply_binding(control, record)


static func _refresh_bound_node(node: Node) -> void:
	if node is not Control:
		return
	var control: Control = node as Control
	var raw: Variant = control.get_meta("notlight_l10n_bindings", [])
	if raw is not Array:
		return
	for item: Variant in raw:
		if item is Dictionary:
			_apply_binding(control, item as Dictionary)


static func _apply_binding(control: Control, record: Dictionary) -> void:
	if control == null:
		return
	var property_name: StringName = StringName(str(record.get("property", "text")))
	var key: String = str(record.get("key", ""))
	var domain: String = str(record.get("domain", "core"))
	var values: Dictionary = {}
	var raw_values: Variant = record.get("values", {})
	if raw_values is Dictionary:
		values = (raw_values as Dictionary).duplicate(true)
	var translated: String = text(key, values) if domain == "core" else module_text(domain, key, values)
	control.set(property_name, translated)


static func _ensure_core_loaded(force_reload: bool) -> bool:
	if _core_loaded and not force_reload:
		return _core_bundles.has(DEFAULT_LOCALE)
	_core_bundles.clear()
	_core_error = ""
	# The generated Russian snapshot is a defensive bootstrap. ru.json remains
	# the canonical source, but the application must never expose technical keys
	# merely because a raw JSON file was unavailable during early startup/export.
	var russian: Dictionary = NotLightCoreRuFallback.strings()
	var russian_json: Dictionary = _read_bundle(CORE_LOCALIZATION_DIR.path_join("ru.json"))
	for raw_key: Variant in russian_json.keys():
		russian[str(raw_key)] = str(russian_json[raw_key])
	if not russian.is_empty():
		_core_bundles[DEFAULT_LOCALE] = russian
	for locale: String in FALLBACK_LOCALES:
		if locale == DEFAULT_LOCALE:
			continue
		var path: String = CORE_LOCALIZATION_DIR.path_join("%s.json" % locale)
		var bundle: Dictionary = _read_bundle(path)
		if not bundle.is_empty():
			_core_bundles[locale] = bundle
	_core_loaded = true
	if not _core_bundles.has(DEFAULT_LOCALE):
		_core_error = str(russian.get("runtime.localization.missing_ru_bundle", "runtime.localization.missing_ru_bundle"))
		push_error(_core_error)
		return false
	return true


static func _lookup_core(key: String, locale: String) -> String:
	var bundle_value: Variant = _core_bundles.get(_normalize_locale(locale))
	if bundle_value is not Dictionary:
		return ""
	return str((bundle_value as Dictionary).get(key, ""))


static func _read_bundle(path: String) -> Dictionary:
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


static func _read_json_dictionary(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var source_text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(source_text)
	if parsed is not Dictionary:
		return {}
	return (parsed as Dictionary).duplicate(true)


static func _normalize_supported_locale(locale: String) -> String:
	var normalized: String = _normalize_locale(locale)
	if not FALLBACK_LOCALES.has(normalized):
		return DEFAULT_LOCALE
	return normalized


static func _normalize_locale(locale: String) -> String:
	var normalized: String = locale.strip_edges().to_lower().replace("-", "_")
	if normalized.contains("_"):
		normalized = normalized.get_slice("_", 0)
	return normalized
