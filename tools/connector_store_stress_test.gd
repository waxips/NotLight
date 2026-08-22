# SPDX-License-Identifier: GPL-3.0-or-later
extends SceneTree

const ENDPOINT_COUNT: int = 512
const CONNECTOR_COUNT: int = 4096
const COLUMNS: int = 32
const CELL: Vector2 = Vector2(180.0, 120.0)


func _initialize() -> void:
	var runtime: BoardRuntime = BoardRuntime.new()
	var endpoint_ids: PackedInt64Array = PackedInt64Array()
	endpoint_ids.resize(ENDPOINT_COUNT)
	runtime.begin_change_batch()
	for index: int in range(ENDPOINT_COUNT):
		var column: int = index % COLUMNS
		var row: int = floori(float(index) / float(COLUMNS))
		var bounds: Rect2 = Rect2(Vector2(float(column), float(row)) * CELL, Vector2(120.0, 52.0))
		var entity_id: int = runtime.create_entity(
			BoardEntityTypes.TEXT,
			bounds,
			0.0,
			index,
			BoardTransformStore.FLAG_VISIBLE
		)
		_check(entity_id > 0, "endpoint allocation failed at %d" % index)
		_check(runtime.model.text_blocks.add_block(entity_id, "E%d" % index), "endpoint text failed at %d" % index)
		endpoint_ids[index] = entity_id
	runtime.end_change_batch()

	for index: int in range(CONNECTOR_COUNT):
		var source_index: int = index % ENDPOINT_COUNT
		var target_index: int = (index * 17 + 23) % ENDPOINT_COUNT
		if target_index == source_index:
			target_index = (target_index + 1) % ENDPOINT_COUNT
		var source_id: int = int(endpoint_ids[source_index])
		var target_id: int = int(endpoint_ids[target_index])
		var source_center: Vector2 = runtime.model.get_entity_bounds(source_id).get_center()
		var target_center: Vector2 = runtime.model.get_entity_bounds(target_id).get_center()
		var midpoint: Vector2 = (source_center + target_center) * 0.5
		var router_points: PackedVector2Array = PackedVector2Array([
			midpoint + Vector2(0.0, float((index % 7) - 3) * 18.0)
		])
		var connector_id: int = runtime.create_connector(
			source_id,
			target_id,
			ConnectorGeometry.ANCHOR_RIGHT,
			ConnectorGeometry.ANCHOR_LEFT,
			ConnectorStore.DEFAULT_COLOR,
			ConnectorStore.DEFAULT_WIDTH,
			router_points
		)
		_check(connector_id > 0, "connector creation failed at %d" % index)

	_check(runtime.model.connectors.size() == CONNECTOR_COUNT, "connector count mismatch")
	var first_connector_id: int = int(runtime.model.connectors.entity_ids[0])
	var first_points: PackedVector2Array = runtime.model.connectors.get_router_points(first_connector_id)
	_check(first_points.size() == 1, "router point pool lost the first route")

	var sample_source_id: int = runtime.model.connectors.get_source_entity_id(first_connector_id)
	var sample_target_id: int = runtime.model.connectors.get_target_entity_id(first_connector_id)
	var sampled: PackedVector2Array = ConnectorGeometry.sample_routed_curve(
		ConnectorGeometry.anchor_position(runtime.model.get_entity_bounds(sample_source_id), ConnectorGeometry.ANCHOR_RIGHT),
		ConnectorGeometry.ANCHOR_RIGHT,
		ConnectorGeometry.anchor_position(runtime.model.get_entity_bounds(sample_target_id), ConnectorGeometry.ANCHOR_LEFT),
		ConnectorGeometry.ANCHOR_LEFT,
		first_points,
		1.0,
		240
	)
	_check(sampled.size() > 12, "adaptive connector sampling is unexpectedly coarse")

	var document: Dictionary = runtime.write_document(BoardDocumentSchema.make_empty())
	var restored: BoardRuntime = BoardRuntime.new()
	restored.load_document(document)
	_check(restored.model.connectors.size() == CONNECTOR_COUNT, "connector roundtrip count mismatch")
	_check(restored.model.connectors.get_router_points(first_connector_id).size() == 1, "router point roundtrip failed")

	print("NotLight Stage 3.2 connector stress test passed: %d routed connectors." % CONNECTOR_COUNT)
	quit(0)


func _check(condition: bool, message: String) -> void:
	assert(condition, message)
