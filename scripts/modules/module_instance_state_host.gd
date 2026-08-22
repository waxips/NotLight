# SPDX-License-Identifier: GPL-3.0-or-later
class_name ModuleInstanceStateHost
extends RefCounted

# Board-independent ownership boundary for canonical module instance state.
# ModuleInstanceContext deliberately knows only this contract; concrete hosts
# decide whether state is durable, ephemeral, undoable, or unavailable.
var _last_error: String = ""


func get_module_instance_id() -> String:
	return ""


func is_attached(_module_id: String) -> bool:
	return false


func get_state() -> Dictionary:
	return {}


func get_state_schema_version() -> int:
	return 0


func commit_normalized_state(_next_state: Dictionary, _state_schema_version: int, _action_name: String) -> bool:
	_fail(NotLightL10n.text("runtime.modules.state_host.user_commit_unsupported"))
	return false


func persist_normalized_state(_next_state: Dictionary, _state_schema_version: int) -> bool:
	_fail(NotLightL10n.text("runtime.modules.state_host.normalize_unsupported"))
	return false


func get_last_error() -> String:
	return _last_error


func _clear_error() -> void:
	_last_error = ""


func _fail(message: String) -> void:
	_last_error = message.strip_edges()
