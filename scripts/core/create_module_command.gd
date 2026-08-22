# SPDX-License-Identifier: GPL-3.0-or-later
class_name CreateModuleCommand
extends BoardCommand

var bounds: Rect2 = Rect2()
var module_id: String = ""
var state_schema_version: int = 1
var instance_state: Dictionary = {}
var instance_title: String = ""
var asset_ids: PackedStringArray = PackedStringArray()
var z_order: int = 0
var created_entity_id: int = 0


func _init(
	new_bounds: Rect2,
	new_module_id: String,
	new_state_schema_version: int,
	new_instance_state: Dictionary,
	new_instance_title: String = "",
	new_asset_ids: PackedStringArray = PackedStringArray(),
	new_z_order: int = 0
) -> void:
	label = NotLightL10n.text("command.module.create")
	bounds = Rect2(new_bounds.position, Vector2(maxf(240.0, new_bounds.size.x), maxf(180.0, new_bounds.size.y)))
	module_id = new_module_id.strip_edges().to_lower()
	state_schema_version = maxi(1, new_state_schema_version)
	instance_state = new_instance_state.duplicate(true)
	instance_title = new_instance_title.strip_edges().left(ModuleStore.MAX_TITLE_LENGTH)
	asset_ids = ModuleStore.normalize_asset_refs(new_asset_ids)
	z_order = new_z_order


func execute(runtime: BoardRuntime) -> bool:
	if runtime == null or not ModuleManifest.is_valid_module_id(module_id):
		return false
	runtime.begin_change_batch()
	if created_entity_id > 0:
		if not runtime.restore_entity(created_entity_id, BoardEntityTypes.MODULE, bounds, 0.0, z_order, BoardTransformStore.FLAG_VISIBLE):
			runtime.end_change_batch()
			return false
	else:
		created_entity_id = runtime.create_entity(BoardEntityTypes.MODULE, bounds, 0.0, z_order, BoardTransformStore.FLAG_VISIBLE)
		if created_entity_id <= 0:
			runtime.end_change_batch()
			return false
	var added: bool = runtime.model.modules.add_module(
		created_entity_id,
		module_id,
		state_schema_version,
		instance_state,
		instance_title,
		asset_ids
	)
	if not added:
		runtime.remove_entity(created_entity_id)
	runtime.end_change_batch()
	return added


func undo(runtime: BoardRuntime) -> bool:
	return runtime != null and created_entity_id > 0 and runtime.remove_entity(created_entity_id)
