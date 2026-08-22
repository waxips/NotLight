# SPDX-License-Identifier: GPL-3.0-or-later
extends SceneTree

const ENTITY_COUNT: int = 10000
const COLUMNS: int = 100
const CELL_SIZE: Vector2 = Vector2(360.0, 210.0)


func _initialize() -> void:
	var runtime: BoardRuntime = BoardRuntime.new()
	runtime.begin_change_batch()
	for index: int in range(ENTITY_COUNT):
		var column: int = index % COLUMNS
		var row: int = floori(float(index) / float(COLUMNS))
		var bounds: Rect2 = Rect2(Vector2(column, row) * CELL_SIZE, Vector2(320.0, 170.0))
		var entity_id: int = runtime.create_entity(BoardEntityTypes.TEXT, bounds, 0.0, index, BoardTransformStore.FLAG_VISIBLE)
		_check(entity_id > 0, "entity allocation failed at %d" % index)
		_check(runtime.model.text_blocks.add_block(entity_id, "Блок %d" % index), "text add failed at %d" % index)
	runtime.end_change_batch()
	_check(runtime.model.text_blocks.size() == ENTITY_COUNT, "text store count mismatch")
	_check(runtime.model.transforms.size() == ENTITY_COUNT, "transform store count mismatch")

	var rich_id: int = int(runtime.model.text_blocks.entity_ids[0])
	var rich_text: String = "Первый пункт\nВторой пункт\nТретий пункт"
	_check(runtime.model.text_blocks.set_text(rich_id, rich_text), "rich stress text mutation failed")
	var first_style_end: int = "Первый".length()
	_check(
		runtime.model.text_blocks.apply_style_range(
			rich_id,
			0,
			first_style_end,
			TextBlockStore.FONT_STYLE_BOLD | TextBlockStore.FONT_STYLE_ITALIC,
			Color("#3568c8")
		),
		"rich stress style range failed"
	)
	var list_indices: PackedInt32Array = PackedInt32Array()
	list_indices.append(0)
	list_indices.append(1)
	list_indices.append(2)
	_check(runtime.model.text_blocks.set_paragraph_list_type(rich_id, list_indices, TextBlockStore.LIST_NUMBERED), "rich stress list metadata failed")
	_check(runtime.model.text_blocks.adjust_paragraph_indent(rich_id, PackedInt32Array([1]), 1), "rich stress indent failed")
	for mutation: int in range(320):
		var color: Color = Color.from_hsv(float(mutation % 60) / 60.0, 0.55, 0.78, 1.0)
		_check(runtime.model.text_blocks.apply_text_color_range(rich_id, 0, first_style_end, color), "rich pool mutation failed")
	var rich_record: Dictionary = runtime.model.text_blocks.get_record(rich_id)
	_check((rich_record.get("style_runs", []) as Array).size() >= 1, "rich runs vanished after pool compaction")
	_check((rich_record.get("paragraphs", []) as Array).size() == 3, "rich paragraphs vanished after mutations")

	var query_rect: Rect2 = Rect2(Vector2.ZERO, CELL_SIZE * Vector2(10.0, 10.0))
	var visible: PackedInt64Array = runtime.spatial_index.query_rect(query_rect)
	_check(not visible.is_empty(), "spatial query returned no entities")

	var serialized: Dictionary = runtime.write_document(BoardDocumentSchema.make_empty())
	var restored: BoardRuntime = BoardRuntime.new()
	restored.load_document(serialized)
	_check(restored.model.text_blocks.size() == ENTITY_COUNT, "roundtrip count mismatch")

	for index: int in range(0, ENTITY_COUNT, 2):
		var entity_id: int = int(restored.model.text_blocks.entity_ids[restored.model.text_blocks.size() - 1])
		_check(restored.remove_entity(entity_id), "swap-remove failed at %d" % index)
	_check(restored.model.text_blocks.size() == floori(float(ENTITY_COUNT) / 2.0), "swap-remove final count mismatch")

	print("NotLight Stage 3.3 rich text stress test passed: %d text blocks." % ENTITY_COUNT)
	quit(0)


func _check(condition: bool, message: String) -> void:
	assert(condition, message)
