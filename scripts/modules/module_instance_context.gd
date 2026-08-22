# SPDX-License-Identifier: GPL-3.0-or-later
class_name ModuleInstanceContext
extends RefCounted

signal state_changed(state: Dictionary)
signal theme_changed(theme_snapshot: Dictionary)
signal locale_changed(locale: String)

var module_id: String = ""
var state_host: ModuleInstanceStateHost
var registry: ModuleRegistry
var _last_error: String = ""


func configure(target_module_id: String, target_state_host: ModuleInstanceStateHost, module_registry: ModuleRegistry) -> void:
	module_id = target_module_id.strip_edges().to_lower()
	state_host = target_state_host
	registry = module_registry
	_last_error = ""


func get_module_id() -> String:
	return module_id


func get_module_instance_id() -> String:
	return state_host.get_module_instance_id() if state_host != null else ""


func get_locale() -> String:
	return NotLightL10n.current_locale()


func text(key: String, values: Dictionary = {}) -> String:
	if registry == null:
		var fallback: String = key.strip_edges()
		return fallback.format(values) if not values.is_empty() else fallback
	return registry.module_text(module_id, key, get_locale(), values)


func get_theme_snapshot() -> Dictionary:
	return {
		"background": NotLightTheme.semantic_color("background").to_html(true),
		"surface": NotLightTheme.semantic_color("surface").to_html(true),
		"surface_alt": NotLightTheme.semantic_color("surface_alt").to_html(true),
		"text": NotLightTheme.semantic_color("text").to_html(true),
		"text_muted": NotLightTheme.semantic_color("text_muted").to_html(true),
		"accent": NotLightTheme.semantic_color("accent").to_html(true),
		"accent_soft": NotLightTheme.semantic_color("accent_soft").to_html(true),
		"border": NotLightTheme.semantic_color("border").to_html(true),
		"border_strong": NotLightTheme.semantic_color("border_strong").to_html(true),
		"danger": NotLightTheme.semantic_color("danger").to_html(true),
	}


func get_capabilities() -> Array:
	var manifest: Dictionary = registry.get_active_manifest(module_id) if registry != null else {}
	var value: Variant = manifest.get("capabilities", [])
	return (value as Array).duplicate(true) if value is Array else []


func commit_state(next_state: Dictionary, action_name: String = "") -> bool:
	_last_error = ""
	if state_host == null or registry == null:
		_last_error = NotLightL10n.text("runtime.modules.context.detached")
		return false
	if not state_host.is_attached(module_id):
		_last_error = NotLightL10n.text("runtime.modules.context.instance_missing")
		return false
	var normalized: Dictionary = registry.normalize_state(module_id, next_state)
	if not bool(normalized.get("ok", false)):
		_last_error = str(normalized.get("error", NotLightL10n.text("runtime.modules.state.validation_failed")))
		return false
	var state: Dictionary = (normalized.get("state", {}) as Dictionary).duplicate(true)
	var state_schema_version: int = registry.get_state_schema_version(module_id)
	if state_schema_version <= 0:
		_last_error = NotLightL10n.text("runtime.modules.context.schema_invalid")
		return false
	if not state_host.commit_normalized_state(state, state_schema_version, action_name):
		_last_error = state_host.get_last_error()
		if _last_error.is_empty():
			_last_error = NotLightL10n.text("runtime.modules.context.commit_rejected")
		return false
	state_changed.emit(state.duplicate(true))
	return true


func get_last_error() -> String:
	return _last_error


func push_host_state(state: Dictionary) -> void:
	state_changed.emit(state.duplicate(true))


func push_host_theme() -> void:
	theme_changed.emit(get_theme_snapshot())


func push_host_locale() -> void:
	locale_changed.emit(get_locale())
