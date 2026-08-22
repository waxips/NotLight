# SPDX-License-Identifier: GPL-3.0-or-later
extends SceneTree

const STORE_ENTITY_COUNT: int = 20000
const SHARED_ASSET_ID: String = "00000000-0000-4000-8000-000000000002"


func _initialize() -> void:
	_test_dense_store()
	_test_runtime_roundtrip_and_clipboard()
	print("NotLight Stage 6 video DOD/store smoke test passed.")
	quit(0)


func _test_dense_store() -> void:
	var store: VideoStore = VideoStore.new()
	for index: int in range(STORE_ENTITY_COUNT):
		var entity_id: int = index + 1
		var pixel_size: Vector2i = Vector2i(1280 + index % 11, 720 + index % 7)
		var duration: float = 12.0 + float(index % 300)
		_check(store.add_video(entity_id, SHARED_ASSET_ID, pixel_size, duration), "dense video add failed at %d" % index)
	_check(store.size() == STORE_ENTITY_COUNT, "dense video store count mismatch")
	_check(store.get_index(STORE_ENTITY_COUNT) >= 0, "dense video lookup lost final entity")
	for _iteration: int in range(int(STORE_ENTITY_COUNT / 2)):
		var entity_id: int = int(store.entity_ids[store.size() - 1])
		_check(store.remove(entity_id), "dense video swap-remove failed")
	_check(store.size() == int(STORE_ENTITY_COUNT / 2), "dense video swap-remove count mismatch")
	for index: int in range(store.size()):
		var entity_id: int = int(store.entity_ids[index])
		_check(store.get_index(entity_id) == index, "dense video index map drifted after swap-remove")
	var serialized: Array[Dictionary] = store.serialize()
	var restored: VideoStore = VideoStore.new()
	restored.deserialize(serialized)
	_check(restored.size() == store.size(), "dense video store roundtrip count mismatch")
	_check(restored.get_asset_id(int(restored.entity_ids[0])) == SHARED_ASSET_ID, "dense video roundtrip lost asset reference")


func _test_runtime_roundtrip_and_clipboard() -> void:
	var runtime: BoardRuntime = BoardRuntime.new()
	var first: CreateVideoCommand = CreateVideoCommand.new(
		Rect2(Vector2(120.0, 100.0), Vector2(480.0, 270.0)),
		SHARED_ASSET_ID,
		Vector2i(1920, 1080),
		95.25,
		10
	)
	var second: CreateVideoCommand = CreateVideoCommand.new(
		Rect2(Vector2(760.0, 180.0), Vector2(320.0, 180.0)),
		SHARED_ASSET_ID,
		Vector2i(1920, 1080),
		95.25,
		11
	)
	_check(runtime.commands.execute(first, runtime), "first video command failed")
	_check(runtime.commands.execute(second, runtime), "second video command failed")
	var first_id: int = first.created_entity_id
	var second_id: int = second.created_entity_id
	_check(first_id > 0 and second_id > 0, "video entity IDs were not allocated")
	_check(runtime.model.videos.size() == 2, "runtime video store count mismatch")
	_check(runtime.model.videos.get_asset_id(first_id) == runtime.model.videos.get_asset_id(second_id), "duplicate objects did not share one asset ID")
	_check(is_equal_approx(runtime.model.videos.get_aspect_ratio(first_id), 16.0 / 9.0), "video aspect ratio metadata is wrong")
	_check(is_equal_approx(runtime.model.videos.get_duration(first_id), 95.25), "video duration metadata is wrong")
	_check(runtime.spatial_index.query_point(Vector2(180.0, 150.0)).has(first_id), "spatial index missed video")
	var hit: BoardHitResult = runtime.hit_test.hit_test_point(Vector2(180.0, 150.0), 4.0)
	_check(hit.entity_id == first_id and hit.type_id == BoardEntityTypes.VIDEO, "video hit-test failed")

	var connector: CreateConnectorCommand = CreateConnectorCommand.new(
		first_id,
		second_id,
		ConnectorGeometry.ANCHOR_RIGHT,
		ConnectorGeometry.ANCHOR_LEFT
	)
	_check(runtime.commands.execute(connector, runtime), "video connector create failed")
	_check(runtime.model.connectors.size() == 1, "video connector was not stored")

	_check(runtime.clipboard.capture(runtime, PackedInt64Array([first_id, second_id])), "video clipboard capture failed")
	var paste: PasteBoardObjectsCommand = runtime.clipboard.make_paste_command_at(Vector2(1500.0, 900.0))
	_check(paste != null, "video clipboard did not create paste command")
	_check(runtime.commands.execute(paste, runtime), "video clipboard paste failed")
	_check(paste.created_selectable_ids.size() == 2, "video clipboard paste lost selectable objects")
	_check(runtime.model.videos.size() == 4, "video clipboard paste did not recreate video rows")
	_check(runtime.model.connectors.size() == 2, "video clipboard paste did not recreate internal connector")
	for entity_id: int in paste.created_selectable_ids:
		_check(runtime.model.videos.get_asset_id(entity_id) == SHARED_ASSET_ID, "clipboard duplicated source identity instead of reusing asset ID")
	_check(runtime.commands.undo(runtime), "video paste undo failed")
	_check(runtime.model.videos.size() == 2, "video paste undo left video rows")
	_check(runtime.commands.redo(runtime), "video paste redo failed")
	_check(runtime.model.videos.size() == 4, "video paste redo lost video rows")

	var document: Dictionary = runtime.write_document(BoardDocumentSchema.make_empty())
	_check(int(document.get("schema_version", 0)) == BoardDocumentSchema.CURRENT_VERSION, "current schema version mismatch")
	var content: Dictionary = document.get("content", {}) as Dictionary
	_check((content.get("videos", []) as Array).size() == 4, "video store was not serialized")
	var refs: PackedStringArray = BoardDocumentSchema.collect_asset_references(document)
	_check(refs.size() == 1 and refs[0] == SHARED_ASSET_ID, "asset reference collector did not deduplicate shared video asset")

	var restored: BoardRuntime = BoardRuntime.new()
	restored.load_document(document)
	_check(restored.model.videos.size() == 4, "video runtime roundtrip lost objects")
	for entity_id: int in restored.model.videos.entity_ids:
		_check(restored.model.videos.get_asset_id(entity_id) == SHARED_ASSET_ID, "video runtime roundtrip lost asset ID")

	var delete: DeleteEntitiesCommand = DeleteEntitiesCommand.new(PackedInt64Array([first_id]))
	_check(runtime.commands.execute(delete, runtime), "video delete failed")
	_check(not runtime.model.videos.contains(first_id), "video delete left video-store row")
	_check(not runtime.model.connectors.contains(connector.created_entity_id), "video delete left attached connector")
	_check(runtime.commands.undo(runtime), "video delete undo failed")
	_check(runtime.model.videos.contains(first_id), "video delete undo lost video row")
	_check(runtime.model.connectors.contains(connector.created_entity_id), "video delete undo lost attached connector")


func _check(condition: bool, message: String) -> void:
	assert(condition, message)
