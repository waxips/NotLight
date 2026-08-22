# SPDX-License-Identifier: GPL-3.0-or-later
class_name PasteBoardObjectsCommand
extends BoardCommand

var source_snapshots: Array[BoardEntitySnapshot] = []
var world_offset: Vector2 = Vector2.ZERO
var created_snapshots: Array[BoardEntitySnapshot] = []
var created_selectable_ids: PackedInt64Array = PackedInt64Array()
var _has_created_once: bool = false


func _init(new_snapshots: Array[BoardEntitySnapshot], offset: Vector2) -> void:
	label = NotLightL10n.text("runtime.core.paste_board_objects_command.ff4fcb24ea")
	world_offset = offset
	for snapshot: BoardEntitySnapshot in new_snapshots:
		source_snapshots.append(snapshot.duplicate_snapshot())


func execute(runtime: BoardRuntime) -> bool:
	if runtime == null or source_snapshots.is_empty():
		return false
	if _has_created_once:
		return _restore_created(runtime)
	return _create_first_time(runtime)


func undo(runtime: BoardRuntime) -> bool:
	if runtime == null or created_snapshots.is_empty():
		return false
	runtime.begin_change_batch()
	for index: int in range(created_snapshots.size() - 1, -1, -1):
		var snapshot: BoardEntitySnapshot = created_snapshots[index]
		if runtime.model.contains(snapshot.entity_id):
			runtime.remove_entity(snapshot.entity_id)
	runtime.end_change_batch()
	return true


func _create_first_time(runtime: BoardRuntime) -> bool:
	var id_map: Dictionary = {}
	var provisional_ids: PackedInt64Array = PackedInt64Array()
	var ordered_sources: Array[BoardEntitySnapshot] = _ordered_snapshots(source_snapshots)
	created_snapshots.clear()
	created_selectable_ids = PackedInt64Array()
	runtime.begin_change_batch()
	for source: BoardEntitySnapshot in ordered_sources:
		if source.type_id == BoardEntityTypes.CONNECTOR:
			continue
		var translated_bounds: Rect2 = Rect2(source.bounds.position + world_offset, source.bounds.size)
		var new_id: int = runtime.create_entity(
			source.type_id,
			translated_bounds,
			source.rotation,
			runtime.model.get_max_z_order() + 1,
			source.flags
		)
		if new_id <= 0:
			_rollback_provisional(runtime, provisional_ids)
			runtime.end_change_batch()
			return false
		provisional_ids.append(new_id)
		id_map[source.entity_id] = new_id
		var remapped_payload: Dictionary = runtime.model.stores.remap_entity_payload(source.data_payload, id_map)
		if not runtime.model.stores.restore_entity_payload(remapped_payload):
			_rollback_provisional(runtime, provisional_ids)
			runtime.end_change_batch()
			return false
		created_selectable_ids.append(new_id)
	for source: BoardEntitySnapshot in ordered_sources:
		if source.type_id != BoardEntityTypes.CONNECTOR:
			continue
		var remapped_payload: Dictionary = runtime.model.stores.remap_entity_payload(source.data_payload, id_map)
		var connector_record: Dictionary = remapped_payload.get("record", {}) as Dictionary
		var source_id: int = int(str(connector_record.get("source_entity_id", "0")))
		var target_id: int = int(str(connector_record.get("target_entity_id", "0")))
		if source_id <= 0 or target_id <= 0:
			continue
		var connector_id: int = runtime.create_connector(
			source_id,
			target_id,
			int(connector_record.get("source_anchor", ConnectorGeometry.ANCHOR_RIGHT)),
			int(connector_record.get("target_anchor", ConnectorGeometry.ANCHOR_LEFT)),
			_parse_color(connector_record.get("color", ""), ConnectorStore.DEFAULT_COLOR),
			float(connector_record.get("width", ConnectorStore.DEFAULT_WIDTH)),
			_translated_router_points(
				ConnectorStore.parse_router_points(connector_record.get("router_points", [])),
				world_offset
			)
		)
		if connector_id > 0:
			provisional_ids.append(connector_id)
			id_map[source.entity_id] = connector_id
	runtime.end_change_batch()
	for created_id: int in _collect_created_ids(runtime, id_map):
		created_snapshots.append(BoardEntitySnapshot.capture(runtime, created_id))
	_has_created_once = not created_snapshots.is_empty()
	return _has_created_once


func _restore_created(runtime: BoardRuntime) -> bool:
	var ordered: Array[BoardEntitySnapshot] = _ordered_snapshots(created_snapshots)
	runtime.begin_change_batch()
	for snapshot: BoardEntitySnapshot in ordered:
		if not snapshot.restore(runtime):
			runtime.end_change_batch()
			return false
	runtime.refresh_all_connector_bounds()
	runtime.end_change_batch()
	return true


func _rollback_provisional(runtime: BoardRuntime, provisional_ids: PackedInt64Array) -> void:
	for index: int in range(provisional_ids.size() - 1, -1, -1):
		var entity_id: int = int(provisional_ids[index])
		if runtime.model.contains(entity_id):
			runtime.remove_entity(entity_id)


func _ordered_snapshots(source: Array[BoardEntitySnapshot]) -> Array[BoardEntitySnapshot]:
	var regular: Array[BoardEntitySnapshot] = []
	var connectors: Array[BoardEntitySnapshot] = []
	for snapshot: BoardEntitySnapshot in source:
		if snapshot.type_id == BoardEntityTypes.CONNECTOR:
			connectors.append(snapshot)
		else:
			regular.append(snapshot)
	regular.append_array(connectors)
	return regular


func _collect_created_ids(runtime: BoardRuntime, id_map: Dictionary) -> PackedInt64Array:
	var result: PackedInt64Array = PackedInt64Array()
	for value: Variant in id_map.values():
		var entity_id: int = int(value)
		if entity_id > 0 and runtime.model.contains(entity_id):
			result.append(entity_id)
	return result


func _parse_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value as Color
	var text: String = str(value)
	return Color(text) if not text.is_empty() and Color.html_is_valid(text) else fallback


func _translated_router_points(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	result.resize(points.size())
	for index: int in range(points.size()):
		result[index] = points[index] + offset
	return result
