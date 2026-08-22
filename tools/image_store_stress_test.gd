# SPDX-License-Identifier: GPL-3.0-or-later
extends SceneTree

const STORE_ENTITY_COUNT: int = 20000
const SHARED_ASSET_ID: String = "00000000-0000-4000-8000-000000000001"


func _initialize() -> void:
	_test_dense_store()
	_test_runtime_roundtrip_and_clipboard()
	print("NotLight Stage 5 image DOD/store smoke test passed.")
	quit(0)


func _test_dense_store() -> void:
	var store: ImageStore = ImageStore.new()
	for index: int in range(STORE_ENTITY_COUNT):
		var entity_id: int = index + 1
		var pixel_size: Vector2i = Vector2i(640 + index % 7, 360 + index % 5)
		_check(store.add_image(entity_id, SHARED_ASSET_ID, pixel_size), "dense image add failed at %d" % index)
	_check(store.size() == STORE_ENTITY_COUNT, "dense image store count mismatch")
	_check(store.get_index(STORE_ENTITY_COUNT) >= 0, "dense image lookup lost final entity")
	for _iteration: int in range(int(STORE_ENTITY_COUNT / 2)):
		var entity_id: int = int(store.entity_ids[store.size() - 1])
		_check(store.remove(entity_id), "dense image swap-remove failed")
	_check(store.size() == int(STORE_ENTITY_COUNT / 2), "dense image swap-remove count mismatch")
	for index: int in range(store.size()):
		var entity_id: int = int(store.entity_ids[index])
		_check(store.get_index(entity_id) == index, "dense image index map drifted after swap-remove")
	var serialized: Array[Dictionary] = store.serialize()
	var restored: ImageStore = ImageStore.new()
	restored.deserialize(serialized)
	_check(restored.size() == store.size(), "dense image store roundtrip count mismatch")
	_check(restored.get_asset_id(int(restored.entity_ids[0])) == SHARED_ASSET_ID, "dense image roundtrip lost asset reference")


func _test_runtime_roundtrip_and_clipboard() -> void:
	var runtime: BoardRuntime = BoardRuntime.new()
	var first: CreateImageCommand = CreateImageCommand.new(
		Rect2(Vector2(120.0, 100.0), Vector2(480.0, 270.0)),
		SHARED_ASSET_ID,
		Vector2i(1920, 1080),
		10
	)
	var second: CreateImageCommand = CreateImageCommand.new(
		Rect2(Vector2(760.0, 180.0), Vector2(320.0, 180.0)),
		SHARED_ASSET_ID,
		Vector2i(1920, 1080),
		11
	)
	_check(runtime.commands.execute(first, runtime), "first image command failed")
	_check(runtime.commands.execute(second, runtime), "second image command failed")
	var first_id: int = first.created_entity_id
	var second_id: int = second.created_entity_id
	_check(first_id > 0 and second_id > 0, "image entity IDs were not allocated")
	_check(runtime.model.images.size() == 2, "runtime image store count mismatch")
	_check(runtime.model.images.get_asset_id(first_id) == runtime.model.images.get_asset_id(second_id), "duplicate objects did not share one asset ID")
	_check(is_equal_approx(runtime.model.images.get_aspect_ratio(first_id), 16.0 / 9.0), "image aspect ratio metadata is wrong")
	_check(runtime.spatial_index.query_point(Vector2(180.0, 150.0)).has(first_id), "spatial index missed image")
	var hit: BoardHitResult = runtime.hit_test.hit_test_point(Vector2(180.0, 150.0), 4.0)
	_check(hit.entity_id == first_id and hit.type_id == BoardEntityTypes.IMAGE, "image hit-test failed")

	var connector: CreateConnectorCommand = CreateConnectorCommand.new(
		first_id,
		second_id,
		ConnectorGeometry.ANCHOR_RIGHT,
		ConnectorGeometry.ANCHOR_LEFT
	)
	_check(runtime.commands.execute(connector, runtime), "image connector create failed")
	_check(runtime.model.connectors.size() == 1, "image connector was not stored")

	_check(runtime.clipboard.capture(runtime, PackedInt64Array([first_id, second_id])), "image clipboard capture failed")
	var paste: PasteBoardObjectsCommand = runtime.clipboard.make_paste_command_at(Vector2(1500.0, 900.0))
	_check(paste != null, "image clipboard did not create paste command")
	_check(runtime.commands.execute(paste, runtime), "image clipboard paste failed")
	_check(paste.created_selectable_ids.size() == 2, "image clipboard paste lost selectable objects")
	_check(runtime.model.images.size() == 4, "image clipboard paste did not recreate image rows")
	_check(runtime.model.connectors.size() == 2, "image clipboard paste did not recreate internal connector")
	for entity_id: int in paste.created_selectable_ids:
		_check(runtime.model.images.get_asset_id(entity_id) == SHARED_ASSET_ID, "clipboard duplicated source identity instead of reusing asset ID")
	_check(runtime.commands.undo(runtime), "image paste undo failed")
	_check(runtime.model.images.size() == 2, "image paste undo left image rows")
	_check(runtime.commands.redo(runtime), "image paste redo failed")
	_check(runtime.model.images.size() == 4, "image paste redo lost image rows")

	var document: Dictionary = runtime.write_document(BoardDocumentSchema.make_empty())
	_check(int(document.get("schema_version", 0)) == BoardDocumentSchema.CURRENT_VERSION, "current schema version mismatch")
	var content: Dictionary = document.get("content", {}) as Dictionary
	_check((content.get("images", []) as Array).size() == 4, "image store was not serialized")
	var refs: PackedStringArray = BoardDocumentSchema.collect_asset_references(document)
	_check(refs.size() == 1 and refs[0] == SHARED_ASSET_ID, "asset reference collector did not deduplicate shared image asset")

	var restored: BoardRuntime = BoardRuntime.new()
	restored.load_document(document)
	_check(restored.model.images.size() == 4, "image runtime roundtrip lost objects")
	for entity_id: int in restored.model.images.entity_ids:
		_check(restored.model.images.get_asset_id(entity_id) == SHARED_ASSET_ID, "image runtime roundtrip lost asset ID")

	var delete: DeleteEntitiesCommand = DeleteEntitiesCommand.new(PackedInt64Array([first_id]))
	_check(runtime.commands.execute(delete, runtime), "image delete failed")
	_check(not runtime.model.images.contains(first_id), "image delete left image-store row")
	_check(not runtime.model.connectors.contains(connector.created_entity_id), "image delete left attached connector")
	_check(runtime.commands.undo(runtime), "image delete undo failed")
	_check(runtime.model.images.contains(first_id), "image delete undo lost image row")
	_check(runtime.model.connectors.contains(connector.created_entity_id), "image delete undo lost attached connector")


func _check(condition: bool, message: String) -> void:
	assert(condition, message)
