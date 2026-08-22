# SPDX-License-Identifier: GPL-3.0-or-later
extends ModuleInstanceStateHost

var module_id: String = ""
var instance_id: String = ""
var state: Dictionary = {}
var state_schema_version: int = 1
var last_action_name: String = ""
var attached: bool = true


func configure(target_module_id: String, target_instance_id: String, initial_state: Dictionary, schema_version: int = 1) -> void:
	module_id = target_module_id.strip_edges().to_lower()
	instance_id = target_instance_id.strip_edges()
	state = initial_state.duplicate(true)
	state_schema_version = schema_version
	attached = true
	last_action_name = ""
	_clear_error()


func get_module_instance_id() -> String:
	return instance_id


func is_attached(target_module_id: String) -> bool:
	return attached and target_module_id.strip_edges().to_lower() == module_id


func get_state() -> Dictionary:
	return state.duplicate(true)


func get_state_schema_version() -> int:
	return state_schema_version


func commit_normalized_state(next_state: Dictionary, schema_version: int, action_name: String) -> bool:
	_clear_error()
	if not is_attached(module_id):
		_fail("Smoke state host is detached.")
		return false
	state = next_state.duplicate(true)
	state_schema_version = schema_version
	last_action_name = action_name
	return true


func persist_normalized_state(next_state: Dictionary, schema_version: int) -> bool:
	_clear_error()
	if not is_attached(module_id):
		_fail("Smoke state host is detached.")
		return false
	state = next_state.duplicate(true)
	state_schema_version = schema_version
	return true
