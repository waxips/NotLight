# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardRuntime
extends RefCounted

signal runtime_changed

var model: BoardModel = BoardModel.new()
var spatial_index: ChunkSpatialIndex = ChunkSpatialIndex.new()
var selection: BoardSelectionState = BoardSelectionState.new()
var hit_test: BoardHitTestSystem = BoardHitTestSystem.new()
var tools: BoardToolController = BoardToolController.new()
var commands: BoardCommandHistory = BoardCommandHistory.new()
var clipboard: BoardClipboardService = BoardClipboardService.new()
var render_policy: BoardRenderPolicy = BoardRenderPolicy.new()
var _change_batch_depth: int = 0
var _pending_runtime_change: bool = false
var _pending_spatial_updates: Dictionary = {}
var _pending_connector_bounds: Dictionary = {}


func _init() -> void:
	hit_test.configure(model, spatial_index)
	tools.setup_defaults()
	model.entity_created.connect(_on_entity_created)
	model.entity_removed.connect(_on_entity_removed)
	model.entity_transform_changed.connect(_on_transform_changed)
	model.entity_data_changed.connect(_on_entity_data_changed)


func load_document(document: Dictionary, stroke_payload: PackedByteArray = PackedByteArray()) -> void:
	selection.clear()
	_pending_spatial_updates.clear()
	_pending_connector_bounds.clear()
	commands.clear()
	begin_change_batch()
	var runtime_data: Dictionary = document.get("runtime", {}) as Dictionary
	var core_data: Dictionary = document.get("core", {}) as Dictionary
	var merged_core: Dictionary = core_data.duplicate(true)
	merged_core["next_entity_id"] = str(runtime_data.get("next_entity_id", "1"))
	model.deserialize_core(merged_core)
	var content_data: Dictionary = document.get("content", {}) as Dictionary
	model.stores.deserialize_content(content_data)
	if not model.strokes.apply_binary_payload(stroke_payload):
		_remove_orphan_stroke_entities()
	_remove_orphan_text_records()
	_remove_orphan_image_records()
	_remove_orphan_pdf_records()
	_remove_orphan_formula_records()
	_remove_orphan_module_records()
	_remove_orphan_note_portal_records()
	_remove_orphan_video_records()
	_remove_orphan_audio_records()
	_remove_orphan_stroke_records()
	_remove_orphan_connector_records()
	_normalize_text_bounds()
	refresh_all_connector_bounds()
	_pending_spatial_updates.clear()
	spatial_index.rebuild(model)
	_pending_runtime_change = true
	end_change_batch()


func write_document(document: Dictionary) -> Dictionary:
	var result: Dictionary = BoardDocumentSchema.normalize(document)
	var serialized_core: Dictionary = model.serialize_core()
	result["runtime"] = {
		"next_entity_id": str(serialized_core.get("next_entity_id", "1")),
	}
	result["core"] = {
		"entities": (serialized_core.get("entities", []) as Array).duplicate(true),
	}
	var content: Dictionary = result.get("content", {}) as Dictionary
	var serialized_content: Dictionary = model.stores.serialize_content()
	for key: Variant in serialized_content.keys():
		content[str(key)] = (serialized_content[key] as Array).duplicate(true)
	result["content"] = content
	return result


func export_stroke_payload() -> PackedByteArray:
	if model.strokes.size() <= 0:
		return PackedByteArray()
	return model.strokes.encode_binary_payload()


func get_visible_entity_ids(camera_position: Vector2, viewport_size: Vector2, zoom: float) -> PackedInt64Array:
	var visible_rect: Rect2 = render_policy.visible_world_rect(camera_position, viewport_size, zoom)
	return spatial_index.query_rect(visible_rect)


func begin_change_batch() -> void:
	_change_batch_depth += 1


func end_change_batch() -> void:
	if _change_batch_depth <= 0:
		return
	_change_batch_depth -= 1
	if _change_batch_depth != 0:
		return
	# Keep the batch logically active while derived connector bounds and spatial
	# entries are flushed. This prevents one runtime_changed signal per arrow.
	_change_batch_depth = 1
	_flush_pending_connector_bounds()
	_flush_pending_spatial_updates()
	_change_batch_depth = 0
	if _pending_runtime_change:
		_pending_runtime_change = false
		runtime_changed.emit()


func notify_content_changed() -> void:
	_queue_runtime_changed()


func create_entity(
	type_id: StringName,
	bounds: Rect2,
	rotation: float = 0.0,
	z_order: int = 0,
	entity_flags: int = BoardTransformStore.FLAG_VISIBLE
) -> int:
	return model.create_entity(type_id, bounds, rotation, z_order, entity_flags)


func restore_entity(
	entity_id: int,
	type_id: StringName,
	bounds: Rect2,
	rotation: float,
	z_order: int,
	entity_flags: int
) -> bool:
	if not model.restore_entity(entity_id, type_id, bounds, rotation, z_order, entity_flags):
		return false
	spatial_index.insert(entity_id, bounds)
	_queue_runtime_changed()
	return true


func create_connector(
	source_entity_id: int,
	target_entity_id: int,
	source_anchor: int,
	target_anchor: int,
	color: Color = ConnectorStore.DEFAULT_COLOR,
	width: float = ConnectorStore.DEFAULT_WIDTH,
	router_points: PackedVector2Array = PackedVector2Array()
) -> int:
	if (
		not model.contains(source_entity_id)
		or not model.contains(target_entity_id)
		or source_entity_id == target_entity_id
	):
		return 0
	var bounds: Rect2 = connector_bounds_for(
		source_entity_id,
		target_entity_id,
		source_anchor,
		target_anchor,
		router_points
	)
	begin_change_batch()
	var connector_id: int = create_entity(
		BoardEntityTypes.CONNECTOR,
		bounds,
		0.0,
		model.get_max_z_order() + 1,
		BoardTransformStore.FLAG_VISIBLE
	)
	if connector_id <= 0:
		end_change_batch()
		return 0
	if not model.connectors.add_connector(
		connector_id,
		source_entity_id,
		target_entity_id,
		source_anchor,
		target_anchor,
		color,
		width,
		router_points
	):
		model.remove_entity(connector_id)
		end_change_batch()
		return 0
	end_change_batch()
	return connector_id


func connector_bounds_for(
	source_entity_id: int,
	target_entity_id: int,
	source_anchor: int,
	target_anchor: int,
	router_points: PackedVector2Array = PackedVector2Array()
) -> Rect2:
	if not model.contains(source_entity_id) or not model.contains(target_entity_id):
		return Rect2()
	var start: Vector2 = ConnectorGeometry.anchor_position(model.get_entity_bounds(source_entity_id), source_anchor)
	var finish: Vector2 = ConnectorGeometry.anchor_position(model.get_entity_bounds(target_entity_id), target_anchor)
	return ConnectorGeometry.curve_bounds(start, source_anchor, finish, target_anchor, router_points)


func refresh_all_connector_bounds() -> void:
	var connector_ids: PackedInt64Array = model.connectors.entity_ids.duplicate()
	for connector_id: int in connector_ids:
		_refresh_connector_bounds(connector_id)


func refresh_connector_bounds(connector_id: int) -> void:
	_refresh_connector_bounds(connector_id)


func apply_connector_record(connector_id: int, record: Dictionary) -> bool:
	if not model.connectors.contains(connector_id):
		return false
	var source_entity_id: int = int(str(record.get("source_entity_id", "0")))
	var target_entity_id: int = int(str(record.get("target_entity_id", "0")))
	if (
		source_entity_id <= 0
		or target_entity_id <= 0
		or source_entity_id == target_entity_id
		or not model.contains(source_entity_id)
		or not model.contains(target_entity_id)
	):
		return false
	begin_change_batch()
	var applied: bool = model.connectors.apply_record(connector_id, record)
	if applied:
		_refresh_connector_bounds(connector_id)
	end_change_batch()
	return applied


func remove_entity(entity_id: int) -> bool:
	if not model.contains(entity_id):
		return false
	if model.get_entity_type(entity_id) != BoardEntityTypes.CONNECTOR:
		var attached: PackedInt64Array = model.connectors.get_attached_connector_ids(entity_id)
		for connector_id: int in attached:
			if model.contains(connector_id):
				model.remove_entity(connector_id)
	return model.remove_entity(entity_id)


func set_entity_transform(entity_id: int, bounds: Rect2, rotation: float = 0.0) -> bool:
	return model.set_entity_transform(entity_id, bounds, rotation)


func set_entity_z_order(entity_id: int, z_order: int) -> bool:
	return model.set_entity_z_order(entity_id, z_order)


func set_entity_flags(entity_id: int, entity_flags: int) -> bool:
	return model.set_entity_flags(entity_id, entity_flags)


func _on_entity_created(entity_id: int, _type_id: StringName) -> void:
	spatial_index.insert(entity_id, model.get_entity_bounds(entity_id))
	_queue_runtime_changed()


func _on_entity_removed(entity_id: int, _type_id: StringName) -> void:
	_pending_spatial_updates.erase(entity_id)
	_pending_connector_bounds.erase(entity_id)
	spatial_index.remove(entity_id)
	selection.remove(entity_id)
	_queue_runtime_changed()


func _on_transform_changed(entity_id: int, _old_bounds: Rect2, new_bounds: Rect2) -> void:
	if _change_batch_depth > 0:
		_pending_spatial_updates[entity_id] = new_bounds
	else:
		spatial_index.update(entity_id, new_bounds)
	if model.contains(entity_id) and model.get_entity_type(entity_id) != BoardEntityTypes.CONNECTOR:
		var attached: PackedInt64Array = model.connectors.get_attached_connector_ids(entity_id)
		for connector_id: int in attached:
			if _change_batch_depth > 0:
				_pending_connector_bounds[connector_id] = true
			else:
				_refresh_connector_bounds(connector_id)
	_queue_runtime_changed()


func _on_entity_data_changed(entity_id: int) -> void:
	if model.contains(entity_id) and model.get_entity_type(entity_id) == BoardEntityTypes.CONNECTOR:
		if _change_batch_depth > 0:
			_pending_connector_bounds[entity_id] = true
		else:
			_refresh_connector_bounds(entity_id)
	_queue_runtime_changed()


func _refresh_connector_bounds(connector_id: int) -> void:
	if not model.connectors.contains(connector_id) or not model.contains(connector_id):
		return
	var source_id: int = model.connectors.get_source_entity_id(connector_id)
	var target_id: int = model.connectors.get_target_entity_id(connector_id)
	if not model.contains(source_id) or not model.contains(target_id):
		return
	var bounds: Rect2 = connector_bounds_for(
		source_id,
		target_id,
		model.connectors.get_source_anchor(connector_id),
		model.connectors.get_target_anchor(connector_id),
		model.connectors.get_router_points(connector_id)
	)
	model.set_entity_transform(connector_id, bounds, 0.0)


func _flush_pending_connector_bounds() -> void:
	if _pending_connector_bounds.is_empty():
		return
	var connector_ids: PackedInt64Array = PackedInt64Array()
	for connector_key: Variant in _pending_connector_bounds.keys():
		connector_ids.append(int(connector_key))
	_pending_connector_bounds.clear()
	for connector_id: int in connector_ids:
		_refresh_connector_bounds(connector_id)


func _flush_pending_spatial_updates() -> void:
	if _pending_spatial_updates.is_empty():
		return
	for entity_key: Variant in _pending_spatial_updates.keys():
		var entity_id: int = int(entity_key)
		if not model.contains(entity_id):
			continue
		var bounds_value: Variant = _pending_spatial_updates.get(entity_id, Rect2())
		if bounds_value is Rect2:
			spatial_index.update(entity_id, bounds_value as Rect2)
	_pending_spatial_updates.clear()


func _queue_runtime_changed() -> void:
	if _change_batch_depth > 0:
		_pending_runtime_change = true
		return
	runtime_changed.emit()


func _remove_orphan_text_records() -> void:
	var orphan_ids: PackedInt64Array = PackedInt64Array()
	for entity_id: int in model.text_blocks.entity_ids:
		if not model.contains(entity_id) or model.get_entity_type(entity_id) != BoardEntityTypes.TEXT:
			orphan_ids.append(entity_id)
	for entity_id: int in orphan_ids:
		model.text_blocks.remove(entity_id)


func _remove_orphan_image_records() -> void:
	var stale_ids: PackedInt64Array = PackedInt64Array()
	for entity_id: int in model.images.entity_ids:
		if not model.contains(entity_id) or model.get_entity_type(entity_id) != BoardEntityTypes.IMAGE:
			stale_ids.append(entity_id)
	for entity_id: int in stale_ids:
		model.images.remove(entity_id)


func _remove_orphan_pdf_records() -> void:
	var stale_ids: PackedInt64Array = PackedInt64Array()
	for entity_id: int in model.pdfs.entity_ids:
		if not model.contains(entity_id) or model.get_entity_type(entity_id) != BoardEntityTypes.PDF:
			stale_ids.append(entity_id)
	for entity_id: int in stale_ids:
		model.pdfs.remove(entity_id)


func _remove_orphan_formula_records() -> void:
	var stale_ids: PackedInt64Array = PackedInt64Array()
	for entity_id: int in model.formulas.entity_ids:
		if not model.contains(entity_id) or model.get_entity_type(entity_id) != BoardEntityTypes.FORMULA:
			stale_ids.append(entity_id)
	for entity_id: int in stale_ids:
		model.formulas.remove(entity_id)


func _remove_orphan_module_records() -> void:
	var stale_ids: PackedInt64Array = PackedInt64Array()
	for entity_id: int in model.modules.entity_ids:
		if not model.contains(entity_id) or model.get_entity_type(entity_id) != BoardEntityTypes.MODULE:
			stale_ids.append(entity_id)
	for entity_id: int in stale_ids:
		model.modules.remove(entity_id)


func _remove_orphan_note_portal_records() -> void:
	var stale_ids: PackedInt64Array = PackedInt64Array()
	for entity_id: int in model.note_portals.entity_ids:
		if not model.contains(entity_id) or model.get_entity_type(entity_id) != BoardEntityTypes.NOTE_PORTAL:
			stale_ids.append(entity_id)
	for entity_id: int in stale_ids:
		model.note_portals.remove(entity_id)


func _remove_orphan_video_records() -> void:
	var stale_ids: PackedInt64Array = PackedInt64Array()
	for entity_id: int in model.videos.entity_ids:
		if not model.contains(entity_id) or model.get_entity_type(entity_id) != BoardEntityTypes.VIDEO:
			stale_ids.append(entity_id)
	for entity_id: int in stale_ids:
		model.videos.remove(entity_id)



func _remove_orphan_audio_records() -> void:
	var stale_ids: PackedInt64Array = PackedInt64Array()
	for entity_id: int in model.audios.entity_ids:
		if not model.contains(entity_id) or model.get_entity_type(entity_id) != BoardEntityTypes.AUDIO:
			stale_ids.append(entity_id)
	for entity_id: int in stale_ids:
		model.audios.remove(entity_id)


func _remove_orphan_stroke_records() -> void:
	var ids: PackedInt64Array = model.strokes.entity_ids.duplicate()
	for entity_id: int in ids:
		if not model.contains(entity_id) or model.get_entity_type(entity_id) != BoardEntityTypes.STROKE:
			model.strokes.remove(entity_id)


func _remove_orphan_stroke_entities() -> void:
	var entity_ids: PackedInt64Array = model.entities.get_entity_ids()
	for entity_id: int in entity_ids:
		if model.get_entity_type(entity_id) == BoardEntityTypes.STROKE:
			model.remove_entity(entity_id)

func _remove_orphan_connector_records() -> void:
	var orphan_ids: PackedInt64Array = PackedInt64Array()
	for connector_id: int in model.connectors.entity_ids:
		var source_id: int = model.connectors.get_source_entity_id(connector_id)
		var target_id: int = model.connectors.get_target_entity_id(connector_id)
		if (
			not model.contains(connector_id)
			or model.get_entity_type(connector_id) != BoardEntityTypes.CONNECTOR
			or not model.contains(source_id)
			or not model.contains(target_id)
		):
			orphan_ids.append(connector_id)
	for connector_id: int in orphan_ids:
		if model.contains(connector_id):
			model.remove_entity(connector_id)
		elif model.connectors.contains(connector_id):
			model.connectors.remove(connector_id)


func _normalize_text_bounds() -> void:
	for entity_id: int in model.text_blocks.entity_ids:
		if not model.contains(entity_id) or model.get_entity_type(entity_id) != BoardEntityTypes.TEXT:
			continue
		var bounds: Rect2 = model.get_entity_bounds(entity_id)
		var record: Dictionary = model.text_blocks.get_record(entity_id)
		var fitted: Rect2 = TextLayoutUtils.fit_record_bounds(
			bounds,
			record,
			TextLayoutUtils.DEFAULT_MINIMUM_SIZE
		)
		if fitted != bounds:
			model.set_entity_transform(entity_id, fitted, model.transforms.get_rotation(entity_id))
