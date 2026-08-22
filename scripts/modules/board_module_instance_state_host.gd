# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardModuleInstanceStateHost
extends ModuleInstanceStateHost

var module_id: String = ""
var entity_id: int = 0
var session: BoardSession


func configure(target_module_id: String, target_entity_id: int, board_session: BoardSession) -> void:
	module_id = target_module_id.strip_edges().to_lower()
	entity_id = target_entity_id
	session = board_session
	_clear_error()


func get_module_instance_id() -> String:
	return str(entity_id) if entity_id > 0 else ""


func is_attached(target_module_id: String) -> bool:
	if session == null or entity_id <= 0:
		return false
	if not session.runtime.model.modules.contains(entity_id):
		return false
	var expected_module_id: String = target_module_id.strip_edges().to_lower()
	return expected_module_id == module_id and session.runtime.model.modules.get_module_id(entity_id) == module_id


func get_state() -> Dictionary:
	if not is_attached(module_id):
		return {}
	return session.runtime.model.modules.get_state(entity_id)


func get_state_schema_version() -> int:
	if not is_attached(module_id):
		return 0
	return session.runtime.model.modules.get_state_schema_version(entity_id)


func commit_normalized_state(next_state: Dictionary, state_schema_version: int, action_name: String) -> bool:
	_clear_error()
	if not is_attached(module_id):
		_fail(NotLightL10n.text("runtime.modules.board_host.detached"))
		return false
	if state_schema_version <= 0:
		_fail(NotLightL10n.text("runtime.modules.board_host.schema_invalid"))
		return false
	var before: Dictionary = session.runtime.model.modules.get_record(entity_id)
	var after: Dictionary = before.duplicate(true)
	after["state_schema_version"] = state_schema_version
	after["instance_state"] = next_state.duplicate(true)
	var command: UpdateModuleStateCommand = UpdateModuleStateCommand.new(entity_id, before, after, action_name)
	if not session.execute_command(command):
		_fail(NotLightL10n.text("runtime.modules.board_host.command_rejected"))
		return false
	return true


func persist_normalized_state(next_state: Dictionary, state_schema_version: int) -> bool:
	_clear_error()
	if not is_attached(module_id):
		_fail(NotLightL10n.text("runtime.modules.board_host.detached"))
		return false
	if state_schema_version <= 0:
		_fail(NotLightL10n.text("runtime.modules.board_host.schema_invalid"))
		return false
	var current_state: Dictionary = session.runtime.model.modules.get_state(entity_id)
	var current_schema: int = session.runtime.model.modules.get_state_schema_version(entity_id)
	if current_schema == state_schema_version and current_state == next_state:
		return true
	# Normalization/migration belongs to the host and must become canonical without
	# creating an undo entry merely because a verified module version filled defaults.
	var record: Dictionary = session.runtime.model.modules.capture_record(entity_id)
	record["state_schema_version"] = state_schema_version
	record["instance_state"] = next_state.duplicate(true)
	if not session.runtime.model.modules.apply_record(entity_id, record):
		_fail(NotLightL10n.text("runtime.modules.board_host.normalize_rejected"))
		return false
	return true
