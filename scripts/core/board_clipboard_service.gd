# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardClipboardService
extends RefCounted

var _snapshots: Array[BoardEntitySnapshot] = []
var _source_bounds: Rect2 = Rect2()
var _has_source_bounds: bool = false


func capture(runtime: BoardRuntime, entity_ids: PackedInt64Array) -> bool:
	_snapshots.clear()
	_source_bounds = Rect2()
	_has_source_bounds = false
	if runtime == null or entity_ids.is_empty():
		return false
	var selected_lookup: Dictionary = {}
	for entity_id: int in entity_ids:
		if not runtime.model.contains(entity_id) or runtime.model.get_entity_type(entity_id) == BoardEntityTypes.CONNECTOR:
			continue
		selected_lookup[entity_id] = true
		var snapshot: BoardEntitySnapshot = BoardEntitySnapshot.capture(runtime, entity_id)
		_snapshots.append(snapshot)
		_source_bounds = _source_bounds.merge(snapshot.bounds) if _has_source_bounds else snapshot.bounds
		_has_source_bounds = true
	var connector_lookup: Dictionary = {}
	for entity_key: Variant in selected_lookup.keys():
		var endpoint_id: int = int(entity_key)
		for connector_id: int in runtime.model.connectors.get_attached_connector_ids(endpoint_id):
			if connector_lookup.has(connector_id):
				continue
			var source_id: int = runtime.model.connectors.get_source_entity_id(connector_id)
			var target_id: int = runtime.model.connectors.get_target_entity_id(connector_id)
			if selected_lookup.has(source_id) and selected_lookup.has(target_id):
				connector_lookup[connector_id] = true
				_snapshots.append(BoardEntitySnapshot.capture(runtime, connector_id))
	return not _snapshots.is_empty() and _has_source_bounds


func has_content() -> bool:
	return not _snapshots.is_empty() and _has_source_bounds


func make_paste_command_at(world_position: Vector2) -> PasteBoardObjectsCommand:
	if not has_content():
		return null
	var offset: Vector2 = world_position - _source_bounds.get_center()
	return PasteBoardObjectsCommand.new(_snapshots, offset)


func reset_paste_generation() -> void:
	pass
