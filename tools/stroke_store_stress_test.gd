# SPDX-License-Identifier: GPL-3.0-or-later
extends SceneTree

const STORE_ENTITY_COUNT: int = 12000


func _initialize() -> void:
	_test_dense_binary_store()
	_test_far_zoom_simplification()
	_test_runtime_clipboard_connector_and_roundtrip()
	print("NotLight Stage 9 stroke DOD/binary smoke test passed.")
	quit(0)


func _test_dense_binary_store() -> void:
	var store: StrokeStore = StrokeStore.new()
	for index: int in range(STORE_ENTITY_COUNT):
		var entity_id: int = index + 1
		var y: float = float(index % 300) * 4.0
		var points: PackedVector2Array = PackedVector2Array([
			Vector2(0.0, y),
			Vector2(8.0, y + 2.0),
			Vector2(16.0, y - 1.0),
			Vector2(24.0, y + 3.0),
			Vector2(32.0, y),
		])
		_check(
			store.add_stroke(
				entity_id,
				points,
				index % 4,
				Color("#245cff"),
				3.0 + float(index % 5),
				Vector2(40.0, 20.0),
				1.65 if index % 4 == StrokeStore.STYLE_SPRAY else 1.0
			),
			"dense stroke add failed at %d" % index
		)
	_check(store.size() == STORE_ENTITY_COUNT, "dense stroke count mismatch")
	for _iteration: int in range(int(STORE_ENTITY_COUNT / 3)):
		var entity_id: int = int(store.entity_ids[store.size() - 1])
		_check(store.remove(entity_id), "dense stroke swap-remove failed")
	for index: int in range(store.size()):
		var entity_id: int = int(store.entity_ids[index])
		_check(store.get_index(entity_id) == index, "dense stroke index map drifted")

	var metadata: Array[Dictionary] = store.serialize()
	var payload: PackedByteArray = store.encode_binary_payload()
	_check(not payload.is_empty(), "stroke binary payload is empty")
	# The JSON-facing metadata must not expand every point into dictionaries/arrays.
	for record: Dictionary in metadata:
		_check(not record.has("points"), "stroke point data leaked into JSON metadata")
		_check(record.has("point_offset") and record.has("point_count"), "stroke point arena offsets missing")
		_check(record.has("spray_spread"), "stroke spray spread metadata missing")
	var restored: StrokeStore = StrokeStore.new()
	restored.deserialize(metadata)
	_check(restored.apply_binary_payload(payload), "stroke binary payload roundtrip failed")
	_check(restored.size() == store.size(), "restored stroke count mismatch")
	_check(restored.get_local_points(int(restored.entity_ids[0])).size() == 5, "restored stroke points mismatch")


func _test_far_zoom_simplification() -> void:
	var detailed: PackedVector2Array = PackedVector2Array()
	for index: int in range(2000):
		var x: float = float(index) * 0.8
		detailed.append(Vector2(x, sin(float(index) * 0.055) * 18.0 + sin(float(index) * 0.21) * 3.5))
	var simplified: PackedVector2Array = StrokeGeometry.simplify_polyline(detailed, 2.0, 48)
	_check(simplified.size() >= 2, "far-zoom simplification removed the stroke")
	_check(simplified.size() <= 48, "far-zoom simplification ignored its point budget")
	_check(simplified[0].is_equal_approx(detailed[0]), "far-zoom simplification changed the first point")
	_check(simplified[simplified.size() - 1].is_equal_approx(detailed[detailed.size() - 1]), "far-zoom simplification changed the last point")

	var straight: PackedVector2Array = PackedVector2Array()
	for index: int in range(100):
		straight.append(Vector2(float(index) * 3.0, 42.0))
	var straight_simplified: PackedVector2Array = StrokeGeometry.simplify_polyline(straight, 0.1, 48)
	_check(straight_simplified.size() == 2, "collinear stroke should simplify to its endpoints")

	var fast_simplified: PackedVector2Array = StrokeGeometry.simplify_polyline_fast(detailed, 2.0, 32)
	_check(fast_simplified.size() >= 2, "fast render simplification removed the stroke")
	_check(fast_simplified.size() <= 32, "fast render simplification ignored its point budget")
	_check(fast_simplified[0].is_equal_approx(detailed[0]), "fast render simplification changed the first point")
	_check(fast_simplified[fast_simplified.size() - 1].is_equal_approx(detailed[detailed.size() - 1]), "fast render simplification changed the last point")

	var store: StrokeStore = StrokeStore.new()
	_check(
		store.add_stroke(1, detailed, StrokeStore.STYLE_PEN, Color.WHITE, 3.0, Vector2(1600.0, 80.0)),
		"render decimation test stroke add failed"
	)
	var decimated: PackedVector2Array = store.get_local_points_decimated(1, 24)
	_check(decimated.size() == 24, "stroke arena render decimation did not honor its bounded point count")
	_check(decimated[0].is_equal_approx(detailed[0]), "stroke arena render decimation changed the first point")
	_check(decimated[decimated.size() - 1].is_equal_approx(detailed[detailed.size() - 1]), "stroke arena render decimation changed the last point")


func _test_runtime_clipboard_connector_and_roundtrip() -> void:
	var runtime: BoardRuntime = BoardRuntime.new()
	var stroke_command: CreateStrokeCommand = CreateStrokeCommand.new(
		PackedVector2Array([
			Vector2(100.0, 100.0),
			Vector2(140.0, 125.0),
			Vector2(190.0, 90.0),
			Vector2(250.0, 145.0),
		]),
		StrokeStore.STYLE_PEN,
		Color("#24885a"),
		6.0
	)
	_check(runtime.commands.execute(stroke_command, runtime), "stroke create command failed")
	var stroke_id: int = stroke_command.created_entity_id
	_check(stroke_id > 0 and runtime.model.strokes.contains(stroke_id), "stroke entity was not registered")
	var stroke_bounds: Rect2 = runtime.model.get_entity_bounds(stroke_id)
	_check(runtime.hit_test.hit_test_point(stroke_bounds.get_center(), 24.0).entity_id == stroke_id, "stroke precise hit-test failed")

	var text_command: CreateTextBlockCommand = CreateTextBlockCommand.new(
		Rect2(Vector2(420.0, 100.0), Vector2(240.0, 60.0)),
		"Связанный объект"
	)
	_check(runtime.commands.execute(text_command, runtime), "text endpoint create failed")
	var connector_command: CreateConnectorCommand = CreateConnectorCommand.new(
		stroke_id,
		text_command.created_entity_id,
		ConnectorGeometry.ANCHOR_RIGHT,
		ConnectorGeometry.ANCHOR_LEFT
	)
	_check(runtime.commands.execute(connector_command, runtime), "stroke connector create failed")
	_check(runtime.model.connectors.get_attached_connector_ids(stroke_id).has(connector_command.created_entity_id), "stroke connector lookup failed")

	var before: Rect2 = runtime.model.get_entity_bounds(stroke_id)
	var after: Rect2 = Rect2(before.position + Vector2(60.0, 40.0), before.size * 1.5)
	var before_bounds: Array[Rect2] = [before]
	var after_bounds: Array[Rect2] = [after]
	var transform: TransformEntitiesCommand = TransformEntitiesCommand.new(
		PackedInt64Array([stroke_id]),
		before_bounds,
		after_bounds
	)
	_check(runtime.commands.execute(transform, runtime), "stroke proportional transform failed")
	_check(runtime.model.get_entity_bounds(stroke_id).size.is_equal_approx(after.size), "stroke transform bounds mismatch")

	var style_bounds_before: Rect2 = runtime.model.get_entity_bounds(stroke_id)
	var style_world_before: PackedVector2Array = runtime.model.strokes.get_world_points(stroke_id, style_bounds_before)
	var style_visual_width_before: float = runtime.model.strokes.get_visual_width(stroke_id, style_bounds_before)
	var style_command: UpdateStrokeStyleCommand = UpdateStrokeStyleCommand.new(
		runtime,
		stroke_id,
		StrokeStore.STYLE_HIGHLIGHTER,
		Color("#f1b83f"),
		12.0
	)
	_check(runtime.commands.execute(style_command, runtime), "stroke style command failed")
	_check(runtime.model.strokes.get_style_id(stroke_id) == StrokeStore.STYLE_HIGHLIGHTER, "stroke style was not applied")
	var style_bounds_after: Rect2 = runtime.model.get_entity_bounds(stroke_id)
	var style_world_after: PackedVector2Array = runtime.model.strokes.get_world_points(stroke_id, style_bounds_after)
	_check(style_world_after.size() == style_world_before.size(), "style change altered stroke point count")
	for point_index: int in range(style_world_before.size()):
		_check(style_world_after[point_index].is_equal_approx(style_world_before[point_index]), "style change moved stroke geometry")
	var raw_after_bounds: Rect2 = StrokeGeometry.bounds_for_points(style_world_after)
	var visual_radius: float = runtime.model.strokes.get_visual_width(stroke_id, style_bounds_after) * 0.5
	_check(style_bounds_after.position.x <= raw_after_bounds.position.x - visual_radius, "style bounds do not cover left visual radius")
	_check(style_bounds_after.position.y <= raw_after_bounds.position.y - visual_radius, "style bounds do not cover top visual radius")
	_check(style_bounds_after.end.x >= raw_after_bounds.end.x + visual_radius, "style bounds do not cover right visual radius")
	_check(style_bounds_after.end.y >= raw_after_bounds.end.y + visual_radius, "style bounds do not cover bottom visual radius")
	_check(runtime.commands.undo(runtime), "stroke style undo failed")
	var undo_bounds: Rect2 = runtime.model.get_entity_bounds(stroke_id)
	_check(undo_bounds.is_equal_approx(style_bounds_before), "stroke style undo did not restore bounds")
	_check(is_equal_approx(runtime.model.strokes.get_visual_width(stroke_id, undo_bounds), style_visual_width_before), "stroke style undo changed visual width")
	_check(runtime.commands.redo(runtime), "stroke style redo failed")

	_check(runtime.clipboard.capture(runtime, PackedInt64Array([stroke_id])), "stroke clipboard capture failed")
	var paste: PasteBoardObjectsCommand = runtime.clipboard.make_paste_command_at(Vector2(900.0, 500.0))
	_check(paste != null and runtime.commands.execute(paste, runtime), "stroke clipboard paste failed")
	_check(runtime.model.strokes.size() == 2, "stroke clipboard paste lost DOD record")

	var document: Dictionary = runtime.write_document(BoardDocumentSchema.make_empty())
	var payload: PackedByteArray = runtime.export_stroke_payload()
	var content: Dictionary = document.get("content", {}) as Dictionary
	var stroke_records: Array = content.get("strokes", []) as Array
	_check(stroke_records.size() == 2, "stroke metadata was not serialized")
	_check(not payload.is_empty(), "runtime stroke sidecar payload is empty")
	var restored: BoardRuntime = BoardRuntime.new()
	restored.load_document(document, payload)
	_check(restored.model.strokes.size() == 2, "runtime stroke binary roundtrip lost objects")
	_check(restored.model.connectors.size() == 1, "runtime stroke roundtrip lost connector")

	var delete: DeleteEntitiesCommand = DeleteEntitiesCommand.new(PackedInt64Array([stroke_id]))
	_check(runtime.commands.execute(delete, runtime), "stroke delete failed")
	_check(not runtime.model.strokes.contains(stroke_id), "stroke delete left store row")
	_check(not runtime.model.connectors.contains(connector_command.created_entity_id), "stroke delete left attached connector")
	_check(runtime.commands.undo(runtime), "stroke delete undo failed")
	_check(runtime.model.strokes.contains(stroke_id), "stroke delete undo lost points")
	_check(runtime.model.connectors.contains(connector_command.created_entity_id), "stroke delete undo lost connector")


func _check(condition: bool, message: String) -> void:
	assert(condition, message)
