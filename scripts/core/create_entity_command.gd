# SPDX-License-Identifier: GPL-3.0-or-later
class_name CreateEntityCommand
extends BoardCommand

var type_id: StringName = StringName()
var bounds: Rect2 = Rect2()
var rotation: float = 0.0
var z_order: int = 0
var flags: int = BoardTransformStore.FLAG_VISIBLE
var created_entity_id: int = 0


func _init(
	new_type_id: StringName,
	new_bounds: Rect2,
	new_rotation: float = 0.0,
	new_z_order: int = 0,
	new_flags: int = BoardTransformStore.FLAG_VISIBLE
) -> void:
	label = NotLightL10n.text("runtime.core.create_entity_command.0a0530e266")
	type_id = new_type_id
	bounds = new_bounds
	rotation = new_rotation
	z_order = new_z_order
	flags = new_flags


func execute(runtime: BoardRuntime) -> bool:
	if runtime == null or type_id == StringName():
		return false
	if created_entity_id > 0:
		return runtime.restore_entity(created_entity_id, type_id, bounds, rotation, z_order, flags)
	created_entity_id = runtime.create_entity(type_id, bounds, rotation, z_order, flags)
	return created_entity_id > 0


func undo(runtime: BoardRuntime) -> bool:
	return runtime != null and created_entity_id > 0 and runtime.remove_entity(created_entity_id)
