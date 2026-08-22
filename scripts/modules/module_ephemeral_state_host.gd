# SPDX-License-Identifier: GPL-3.0-or-later
class_name ModuleEphemeralStateHost
extends ModuleInstanceStateHost

# Generic host-owned runtime state for surfaces that intentionally do not persist.
# Closing/rebuilding the owning UI discards the state. Consumers provide their own
# stable-for-session instance identifier so Module API code never needs to know
# whether it is hosted by the Library, Notes, or another transient surface.
var module_id: String = ""
var instance_id: String = ""
var _state: Dictionary = {}
var _state_schema_version: int = 0
var _attached: bool = false


func configure_ephemeral(
	target_module_id: String,
	target_instance_id: String,
	initial_state: Dictionary,
	state_schema_version: int
) -> void:
	module_id = target_module_id.strip_edges().to_lower()
	instance_id = target_instance_id.strip_edges()
	_state = initial_state.duplicate(true)
	_state_schema_version = state_schema_version
	_attached = not module_id.is_empty() and not instance_id.is_empty() and state_schema_version > 0
	_clear_error()


func detach() -> void:
	_attached = false
	_state = {}
	_state_schema_version = 0
	module_id = ""
	instance_id = ""
	_clear_error()


func get_module_instance_id() -> String:
	return instance_id if _attached else ""


func is_attached(target_module_id: String) -> bool:
	return _attached and target_module_id.strip_edges().to_lower() == module_id


func get_state() -> Dictionary:
	return _state.duplicate(true) if _attached else {}


func get_state_schema_version() -> int:
	return _state_schema_version if _attached else 0


func commit_normalized_state(next_state: Dictionary, state_schema_version: int, _action_name: String) -> bool:
	return _store_state(next_state, state_schema_version)


func persist_normalized_state(next_state: Dictionary, state_schema_version: int) -> bool:
	return _store_state(next_state, state_schema_version)


func _store_state(next_state: Dictionary, state_schema_version: int) -> bool:
	_clear_error()
	if not _attached:
		_fail(NotLightL10n.text("runtime.modules.ephemeral.detached"))
		return false
	if state_schema_version <= 0:
		_fail(NotLightL10n.text("runtime.modules.ephemeral.schema_invalid"))
		return false
	_state = next_state.duplicate(true)
	_state_schema_version = state_schema_version
	return true
