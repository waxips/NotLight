# SPDX-License-Identifier: GPL-3.0-or-later
class_name TransformEntitiesCommand
extends BoardCommand

var entity_ids: PackedInt64Array = PackedInt64Array()
var before_bounds: Array[Rect2] = []
var after_bounds: Array[Rect2] = []
var before_rotations: PackedFloat32Array = PackedFloat32Array()
var after_rotations: PackedFloat32Array = PackedFloat32Array()


func _init(
	new_entity_ids: PackedInt64Array,
	new_before_bounds: Array[Rect2],
	new_after_bounds: Array[Rect2],
	new_before_rotations: PackedFloat32Array = PackedFloat32Array(),
	new_after_rotations: PackedFloat32Array = PackedFloat32Array()
) -> void:
	label = NotLightL10n.text("runtime.core.transform_entities_command.59a923c4e2")
	merge_key = &"transform_entities"
	entity_ids = new_entity_ids.duplicate()
	before_bounds = new_before_bounds.duplicate()
	after_bounds = new_after_bounds.duplicate()
	before_rotations = _normalized_rotations(new_before_rotations, entity_ids.size())
	after_rotations = _normalized_rotations(new_after_rotations, entity_ids.size())


func execute(runtime: BoardRuntime) -> bool:
	return _apply(runtime, after_bounds, after_rotations)


func undo(runtime: BoardRuntime) -> bool:
	return _apply(runtime, before_bounds, before_rotations)


func can_merge_with(newer_command: BoardCommand) -> bool:
	if newer_command is not TransformEntitiesCommand:
		return false
	var newer: TransformEntitiesCommand = newer_command as TransformEntitiesCommand
	return merge_key == newer.merge_key and entity_ids == newer.entity_ids


func merge_from(newer_command: BoardCommand) -> void:
	if newer_command is not TransformEntitiesCommand:
		return
	var newer: TransformEntitiesCommand = newer_command as TransformEntitiesCommand
	after_bounds = newer.after_bounds.duplicate()
	after_rotations = newer.after_rotations.duplicate()


func _apply(runtime: BoardRuntime, bounds_values: Array[Rect2], rotations: PackedFloat32Array) -> bool:
	if runtime == null or entity_ids.size() != bounds_values.size() or rotations.size() != entity_ids.size():
		return false
	for index: int in range(entity_ids.size()):
		var entity_id: int = int(entity_ids[index])
		if not runtime.model.contains(entity_id):
			return false
	runtime.begin_change_batch()
	for index: int in range(entity_ids.size()):
		var entity_id: int = int(entity_ids[index])
		if not runtime.set_entity_transform(entity_id, bounds_values[index], float(rotations[index])):
			runtime.end_change_batch()
			return false
	runtime.end_change_batch()
	return true


func _normalized_rotations(source: PackedFloat32Array, required_size: int) -> PackedFloat32Array:
	if source.size() == required_size:
		return source.duplicate()
	var result: PackedFloat32Array = PackedFloat32Array()
	result.resize(required_size)
	return result
