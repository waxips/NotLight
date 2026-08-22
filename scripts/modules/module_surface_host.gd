# SPDX-License-Identifier: GPL-3.0-or-later
class_name ModuleSurfaceHost
extends RefCounted

# Shared, board-independent materialization path for Module API live surfaces.
# Geometry, budgets and interaction chrome remain responsibilities of the caller.
const ERROR_INACTIVE: String = "inactive_module"
const ERROR_DETACHED: String = "detached_instance"
const ERROR_STATE_INVALID: String = "state_invalid"
const ERROR_STATE_COMMIT: String = "state_commit_failed"
const ERROR_SURFACE_INVALID: String = "surface_invalid"


func materialize(
	parent: Control,
	module_id: String,
	state_host: ModuleInstanceStateHost,
	registry: ModuleRegistry
) -> Dictionary:
	var clean_module_id: String = module_id.strip_edges().to_lower()
	if parent == null or not is_instance_valid(parent) or registry == null or state_host == null:
		return _failure(ERROR_DETACHED, NotLightL10n.text("runtime.modules.surface.not_configured"))
	if not registry.is_module_active(clean_module_id):
		return _failure(ERROR_INACTIVE, NotLightL10n.text("runtime.modules.surface.inactive"))
	if not state_host.is_attached(clean_module_id):
		return _failure(ERROR_DETACHED, NotLightL10n.text("runtime.modules.surface.state_host_detached"))

	var current_state: Dictionary = state_host.get_state()
	var normalized_result: Dictionary = registry.normalize_state(clean_module_id, current_state)
	if not bool(normalized_result.get("ok", false)):
		return _failure(ERROR_STATE_INVALID, str(normalized_result.get("error", NotLightL10n.text("runtime.modules.state.validation_failed"))))
	var normalized_state: Dictionary = (normalized_result.get("state", {}) as Dictionary).duplicate(true)
	var target_schema: int = registry.get_state_schema_version(clean_module_id)
	if target_schema <= 0:
		return _failure(ERROR_STATE_INVALID, "state_schema_version")
	if state_host.get_state_schema_version() != target_schema or current_state != normalized_state:
		if not state_host.persist_normalized_state(normalized_state, target_schema):
			return _failure(ERROR_STATE_COMMIT, state_host.get_last_error())

	var surface: Control = registry.create_surface(clean_module_id)
	if surface == null or not surface.has_method("notlight_attach_context"):
		if surface != null:
			surface.queue_free()
		return _failure(ERROR_SURFACE_INVALID, NotLightL10n.text("runtime.modules.surface.attach_context_missing"))
	var context: ModuleInstanceContext = ModuleInstanceContext.new()
	context.configure(clean_module_id, state_host, registry)
	parent.add_child(surface)
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.call("notlight_attach_context", context, normalized_state.duplicate(true))
	return {
		"ok": true,
		"surface": surface,
		"context": context,
		"state": normalized_state,
		"state_host": state_host,
	}


func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "error_code": code, "error": message.strip_edges()}
