# SPDX-License-Identifier: GPL-3.0-or-later
extends SceneTree


func _initialize() -> void:
	_test_render_policy_hysteresis()
	var runtime: BoardRuntime = BoardRuntime.new()
	var first_create: CreateTextBlockCommand = CreateTextBlockCommand.new(
		Rect2(Vector2(100.0, 80.0), Vector2(320.0, 70.0)),
		"Первая мысль\nВторая строка",
		24.0,
		HORIZONTAL_ALIGNMENT_LEFT,
		TextBlockStore.STYLE_PLAIN
	)
	var second_create: CreateTextBlockCommand = CreateTextBlockCommand.new(
		Rect2(Vector2(620.0, 260.0), Vector2(280.0, 64.0)),
		"Связанная мысль",
		22.0,
		HORIZONTAL_ALIGNMENT_CENTER,
		TextBlockStore.STYLE_PLAIN,
		TextBlockStore.LAYOUT_AUTO_WIDTH,
		Color("#fff2b8")
	)
	_check(runtime.commands.execute(first_create, runtime), "first text create failed")
	_check(runtime.commands.execute(second_create, runtime), "second text create failed")
	var first_id: int = first_create.created_entity_id
	var second_id: int = second_create.created_entity_id
	_check(first_id > 0 and second_id > 0, "runtime IDs were not allocated")
	_check(runtime.model.text_blocks.get_background_color(first_id).a <= 0.001, "plain text is not transparent")
	_check(runtime.model.text_blocks.get_background_color(second_id).a > 0.99, "styled text background was not stored")

	var rich_before: Dictionary = runtime.model.text_blocks.get_record(first_id)
	var rich_after: Dictionary = rich_before.duplicate(true)
	rich_after["font_family"] = "Arial"
	rich_after["base_style_flags"] = 0
	rich_after["style_runs"] = [
		{
			"start": 0,
			"length": 6,
			"flags": TextBlockStore.FONT_STYLE_BOLD | TextBlockStore.FONT_STYLE_UNDERLINE,
			"color": Color("#3568c8").to_html(true),
		},
	]
	rich_after["paragraphs"] = [
		{"list_type": TextBlockStore.LIST_BULLET, "indent": 0},
		{"list_type": TextBlockStore.LIST_NUMBERED, "indent": 1},
	]
	var rich_ids: PackedInt64Array = PackedInt64Array()
	rich_ids.append(first_id)
	var rich_before_records: Array[Dictionary] = [rich_before]
	var rich_after_records: Array[Dictionary] = [rich_after]
	var rich_command: UpdateTextPropertiesCommand = UpdateTextPropertiesCommand.new(
		rich_ids,
		rich_before_records,
		rich_after_records,
		"Rich text smoke"
	)
	_check(runtime.commands.execute(rich_command, runtime), "rich text command failed")
	var rich_record: Dictionary = runtime.model.text_blocks.get_record(first_id)
	_check(str(rich_record.get("font_family", "")) == "Arial", "font family was not stored")
	var rich_runs: Array = rich_record.get("style_runs", []) as Array
	_check(not rich_runs.is_empty(), "rich style runs were not stored")
	_check((int((rich_runs[0] as Dictionary).get("flags", 0)) & TextBlockStore.FONT_STYLE_BOLD) != 0, "bold style run was lost")
	var rich_paragraphs: Array = rich_record.get("paragraphs", []) as Array
	_check(rich_paragraphs.size() == 2, "paragraph metadata count mismatch")
	_check(int((rich_paragraphs[0] as Dictionary).get("list_type", 0)) == TextBlockStore.LIST_BULLET, "bullet list metadata was lost")
	_check(runtime.commands.undo(runtime), "rich text undo failed")
	_check(runtime.commands.redo(runtime), "rich text redo failed")
	_check(runtime.spatial_index.query_point(Vector2(120.0, 100.0)).has(first_id), "spatial query missed text")

	var hit: BoardHitResult = runtime.hit_test.hit_test_point(Vector2(120.0, 100.0), 4.0)
	_check(hit.entity_id == first_id, "text hit-test missed a visible block")

	var edit_command: EditTextBlockCommand = EditTextBlockCommand.new(
		first_id,
		"Первая мысль\nВторая строка",
		"Новая мысль\nВторая строка"
	)
	_check(runtime.commands.execute(edit_command, runtime), "text edit command failed")
	_check(runtime.commands.undo(runtime), "text edit undo failed")
	_check(runtime.commands.redo(runtime), "text edit redo failed")

	var connector_command: CreateConnectorCommand = CreateConnectorCommand.new(
		first_id,
		second_id,
		ConnectorGeometry.ANCHOR_RIGHT,
		ConnectorGeometry.ANCHOR_LEFT
	)
	_check(runtime.commands.execute(connector_command, runtime), "connector create failed")
	var connector_id: int = connector_command.created_entity_id
	_check(runtime.model.connectors.contains(connector_id), "connector store lost the new arrow")
	_check(runtime.model.connectors.get_attached_connector_ids(first_id).has(connector_id), "endpoint lookup missed connector")
	var connector_bounds_before: Rect2 = runtime.model.get_entity_bounds(connector_id)

	var connector_before_route: Dictionary = runtime.model.connectors.get_record(connector_id)
	var connector_after_route: Dictionary = connector_before_route.duplicate(true)
	connector_after_route["router_points"] = [{"x": 520.0, "y": 90.0}, {"x": 560.0, "y": 320.0}]
	var route_command: UpdateConnectorCommand = UpdateConnectorCommand.new(
		connector_id,
		connector_before_route,
		connector_after_route,
		"Тест маршрута"
	)
	_check(runtime.commands.execute(route_command, runtime), "connector route update failed")
	_check(runtime.model.connectors.get_router_points(connector_id).size() == 2, "connector router points were not stored")
	_check(runtime.commands.undo(runtime), "connector route undo failed")
	_check(runtime.model.connectors.get_router_points(connector_id).is_empty(), "connector route undo left points")
	_check(runtime.commands.redo(runtime), "connector route redo failed")
	_check(runtime.model.connectors.get_router_points(connector_id).size() == 2, "connector route redo lost points")

	var connector_before_style: Dictionary = runtime.model.connectors.get_record(connector_id)
	var connector_after_style: Dictionary = connector_before_style.duplicate(true)
	var test_connector_color: Color = Color("#3568c8")
	connector_after_style["color"] = test_connector_color.to_html(true)
	connector_after_style["direction"] = ConnectorStore.DIRECTION_BOTH
	var connector_style_command: UpdateConnectorCommand = UpdateConnectorCommand.new(
		connector_id,
		connector_before_style,
		connector_after_style,
		"Тест оформления стрелки"
	)
	_check(runtime.commands.execute(connector_style_command, runtime), "connector style update failed")
	_check(runtime.model.connectors.get_color(connector_id).is_equal_approx(test_connector_color), "connector color was not stored")
	_check(runtime.model.connectors.get_direction(connector_id) == ConnectorStore.DIRECTION_BOTH, "connector direction was not stored")
	_check(runtime.commands.undo(runtime), "connector style undo failed")
	_check(runtime.model.connectors.get_direction(connector_id) == ConnectorStore.DEFAULT_DIRECTION, "connector style undo lost direction")
	_check(runtime.commands.redo(runtime), "connector style redo failed")
	_check(runtime.model.connectors.get_color(connector_id).is_equal_approx(test_connector_color), "connector style redo lost color")
	_check(runtime.model.connectors.get_direction(connector_id) == ConnectorStore.DIRECTION_BOTH, "connector style redo lost direction")

	var before_bounds: Array[Rect2] = [runtime.model.get_entity_bounds(first_id)]
	var after_bounds: Array[Rect2] = [Rect2(Vector2(260.0, 180.0), before_bounds[0].size)]
	var transform_command: TransformEntitiesCommand = TransformEntitiesCommand.new(
		PackedInt64Array([first_id]),
		before_bounds,
		after_bounds
	)
	_check(runtime.commands.execute(transform_command, runtime), "transform command failed")
	_check(runtime.spatial_index.query_point(Vector2(280.0, 200.0)).has(first_id), "spatial index did not move")
	_check(runtime.model.get_entity_bounds(connector_id) != connector_bounds_before, "connector bounds did not follow endpoint")

	_check(runtime.clipboard.capture(runtime, PackedInt64Array([first_id, second_id])), "clipboard capture failed")
	var paste_command: PasteBoardObjectsCommand = runtime.clipboard.make_paste_command_at(Vector2(1400.0, 900.0))
	_check(paste_command != null, "clipboard did not create paste command")
	_check(runtime.commands.execute(paste_command, runtime), "paste command failed")
	_check(paste_command.created_selectable_ids.size() == 2, "paste did not recreate both selectable objects")
	_check(runtime.model.connectors.size() == 2, "paste did not recreate the internal connector")
	_check(runtime.commands.undo(runtime), "paste undo failed")
	_check(runtime.model.connectors.size() == 1, "paste undo left copied connector")
	_check(runtime.commands.redo(runtime), "paste redo failed")
	_check(runtime.model.connectors.size() == 2, "paste redo lost copied connector")

	var document: Dictionary = runtime.write_document(BoardDocumentSchema.make_empty())
	_check(int(document.get("schema_version", 0)) == BoardDocumentSchema.CURRENT_VERSION, "wrong schema version")
	var content: Dictionary = document.get("content", {}) as Dictionary
	_check((content.get("text_blocks", []) as Array).size() == 4, "text store was not serialized")
	_check((content.get("connectors", []) as Array).size() == 2, "connector store was not serialized")
	var restored: BoardRuntime = BoardRuntime.new()
	restored.load_document(document)
	_check(restored.model.text_blocks.size() == 4, "roundtrip lost text objects")
	_check(restored.model.connectors.size() == 2, "roundtrip lost connectors")
	_check(restored.model.connectors.get_color(connector_id).is_equal_approx(test_connector_color), "roundtrip lost connector color")
	_check(restored.model.connectors.get_direction(connector_id) == ConnectorStore.DIRECTION_BOTH, "roundtrip lost connector direction")
	_check(restored.model.allocator.get_next_id() > connector_id, "allocator did not reserve restored IDs")

	var delete_command: DeleteEntitiesCommand = DeleteEntitiesCommand.new(PackedInt64Array([first_id]))
	_check(runtime.commands.execute(delete_command, runtime), "delete command failed")
	_check(not runtime.model.contains(first_id), "delete left endpoint in registry")
	_check(not runtime.model.contains(connector_id), "delete left attached connector")
	_check(runtime.commands.undo(runtime), "delete undo failed")
	_check(runtime.model.contains(first_id), "delete undo lost endpoint")
	_check(runtime.model.connectors.contains(connector_id), "delete undo lost connector")

	var blank_command: CreateTextBlockCommand = CreateTextBlockCommand.new(
		Rect2(Vector2(900.0, 120.0), Vector2(260.0, 48.0))
	)
	_check(runtime.commands.execute(blank_command, runtime), "blank text create failed")
	_check(runtime.commands.discard_last_applied(blank_command, runtime), "blank text discard failed")
	_check(not runtime.model.contains(blank_command.created_entity_id), "discarded blank text remained in runtime")

	var future_document: Dictionary = document.duplicate(true)
	future_document["schema_version"] = BoardDocumentSchema.CURRENT_VERSION + 1
	_check(not BoardDocumentSchema.is_supported(future_document), "future schema was accepted")

	print("NotLight Stage 3.3.1 rich text caret and directional connector core smoke test passed.")
	quit(0)


func _test_render_policy_hysteresis() -> void:
	var policy: BoardRenderPolicy = BoardRenderPolicy.new()
	_check(policy.lod_for_zoom_hysteretic(0.68, int(BoardRenderPolicy.LodLevel.FULL)) == BoardRenderPolicy.LodLevel.FULL, "FULL LOD hysteresis released too early")
	_check(policy.lod_for_zoom_hysteretic(0.63, int(BoardRenderPolicy.LodLevel.FULL)) == BoardRenderPolicy.LodLevel.MEDIUM, "FULL LOD hysteresis did not release")
	_check(policy.lod_for_zoom_hysteretic(0.73, int(BoardRenderPolicy.LodLevel.MEDIUM)) == BoardRenderPolicy.LodLevel.MEDIUM, "MEDIUM LOD hysteresis upgraded too early")
	_check(policy.lod_for_zoom_hysteretic(0.77, int(BoardRenderPolicy.LodLevel.MEDIUM)) == BoardRenderPolicy.LodLevel.FULL, "MEDIUM LOD hysteresis did not upgrade")
	_check(policy.lod_for_zoom_hysteretic(0.27, int(BoardRenderPolicy.LodLevel.MEDIUM)) == BoardRenderPolicy.LodLevel.MEDIUM, "MEDIUM LOD hysteresis downgraded too early")
	_check(policy.lod_for_zoom_hysteretic(0.25, int(BoardRenderPolicy.LodLevel.MEDIUM)) == BoardRenderPolicy.LodLevel.LOW, "MEDIUM LOD hysteresis did not downgrade")
	_check(policy.lod_for_zoom_hysteretic(0.095, int(BoardRenderPolicy.LodLevel.LOW)) == BoardRenderPolicy.LodLevel.LOW, "LOW LOD hysteresis downgraded too early")
	_check(policy.lod_for_zoom_hysteretic(0.089, int(BoardRenderPolicy.LodLevel.LOW)) == BoardRenderPolicy.LodLevel.PLACEHOLDER, "LOW LOD hysteresis did not downgrade")
	_check(policy.lod_for_zoom_hysteretic(0.104, int(BoardRenderPolicy.LodLevel.PLACEHOLDER)) == BoardRenderPolicy.LodLevel.PLACEHOLDER, "PLACEHOLDER LOD hysteresis upgraded too early")
	_check(policy.lod_for_zoom_hysteretic(0.11, int(BoardRenderPolicy.LodLevel.PLACEHOLDER)) == BoardRenderPolicy.LodLevel.LOW, "PLACEHOLDER LOD hysteresis did not upgrade")


func _check(condition: bool, message: String) -> void:
	assert(condition, message)
