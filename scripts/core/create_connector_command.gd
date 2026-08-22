# SPDX-License-Identifier: GPL-3.0-or-later
class_name CreateConnectorCommand
extends BoardCommand

var source_entity_id: int = 0
var target_entity_id: int = 0
var source_anchor: int = ConnectorGeometry.ANCHOR_RIGHT
var target_anchor: int = ConnectorGeometry.ANCHOR_LEFT
var color: Color = ConnectorStore.DEFAULT_COLOR
var width: float = ConnectorStore.DEFAULT_WIDTH
var created_entity_id: int = 0


func _init(
	new_source_entity_id: int,
	new_target_entity_id: int,
	new_source_anchor: int,
	new_target_anchor: int
) -> void:
	label = NotLightL10n.text("runtime.core.create_connector_command.e48c6e184f")
	source_entity_id = new_source_entity_id
	target_entity_id = new_target_entity_id
	source_anchor = new_source_anchor
	target_anchor = new_target_anchor


func execute(runtime: BoardRuntime) -> bool:
	if (
		runtime == null
		or not runtime.model.contains(source_entity_id)
		or not runtime.model.contains(target_entity_id)
	):
		return false
	if created_entity_id > 0:
		var bounds: Rect2 = runtime.connector_bounds_for(
			source_entity_id,
			target_entity_id,
			source_anchor,
			target_anchor
		)
		if not runtime.restore_entity(
			created_entity_id,
			BoardEntityTypes.CONNECTOR,
			bounds,
			0.0,
			runtime.model.get_max_z_order() + 1,
			BoardTransformStore.FLAG_VISIBLE
		):
			return false
		var restored_data: bool = runtime.model.connectors.add_connector(
			created_entity_id,
			source_entity_id,
			target_entity_id,
			source_anchor,
			target_anchor,
			color,
			width
		)
		if not restored_data:
			runtime.remove_entity(created_entity_id)
		return restored_data
	created_entity_id = runtime.create_connector(
		source_entity_id,
		target_entity_id,
		source_anchor,
		target_anchor,
		color,
		width
	)
	return created_entity_id > 0


func undo(runtime: BoardRuntime) -> bool:
	return runtime != null and created_entity_id > 0 and runtime.remove_entity(created_entity_id)
