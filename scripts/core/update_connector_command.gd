# SPDX-License-Identifier: GPL-3.0-or-later
class_name UpdateConnectorCommand
extends BoardCommand

var connector_id: int = 0
var before_record: Dictionary = {}
var after_record: Dictionary = {}


func _init(entity_id: int, before: Dictionary, after: Dictionary, action_label: String = "") -> void:
	connector_id = entity_id
	before_record = before.duplicate(true)
	after_record = after.duplicate(true)
	label = action_label if not action_label.is_empty() else NotLightL10n.text("runtime.core.update_connector_command.default_action")


func execute(runtime: BoardRuntime) -> bool:
	if runtime == null or connector_id <= 0:
		return false
	return runtime.apply_connector_record(connector_id, after_record)


func undo(runtime: BoardRuntime) -> bool:
	if runtime == null or connector_id <= 0:
		return false
	return runtime.apply_connector_record(connector_id, before_record)
