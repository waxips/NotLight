# SPDX-License-Identifier: GPL-3.0-or-later
extends SceneTree

const STORE_ENTITY_COUNT: int = 2048
const SHARED_ASSET_ID: String = "asset_pdf_smoke"


func _initialize() -> void:
	_test_dense_store()
	_test_runtime_roundtrip_clipboard_and_search()
	_test_schema_migration_and_asset_references()
	print("NotLight PDF DOD/store/schema/search smoke test passed.")
	quit(0)


func _test_dense_store() -> void:
	var store: PdfStore = PdfStore.new()
	for index: int in range(STORE_ENTITY_COUNT):
		var entity_id: int = index + 1
		var count: int = 1 + index % 73
		_check(
			store.add_pdf(
				entity_id,
				"pdf_%d" % entity_id,
				count,
				Vector2i(595 + index % 17, 842 + index % 23),
				index % count,
				"PDF %d" % entity_id
			),
			"pdf store add failed at %d" % index
		)
	_check(store.size() == STORE_ENTITY_COUNT, "dense PDF count mismatch")
	for _iteration: int in range(int(STORE_ENTITY_COUNT / 3)):
		var remove_id: int = int(store.entity_ids[store.size() - 2])
		_check(store.remove(remove_id), "PDF swap-remove failed")
	for index: int in range(store.size()):
		var entity_id: int = int(store.entity_ids[index])
		_check(store.get_index(entity_id) == index, "PDF index map drifted")
	var records: Array[Dictionary] = store.serialize()
	var restored: PdfStore = PdfStore.new()
	restored.deserialize(records)
	_check(restored.size() == store.size(), "PDF store roundtrip count mismatch")
	var probe_id: int = int(store.entity_ids[min(17, store.size() - 1)])
	_check(restored.get_asset_id(probe_id) == store.get_asset_id(probe_id), "PDF asset id was lost")
	_check(restored.get_instance_title(probe_id) == store.get_instance_title(probe_id), "PDF local title was lost")
	_check(restored.get_page_index(probe_id) == store.get_page_index(probe_id), "PDF current page was lost")
	_check(restored.get_page_count(probe_id) == store.get_page_count(probe_id), "PDF page count was lost")
	_check(restored.get_page_size(probe_id) == store.get_page_size(probe_id), "PDF page size was lost")


func _test_runtime_roundtrip_clipboard_and_search() -> void:
	var runtime: BoardRuntime = BoardRuntime.new()
	var create: CreatePdfCommand = CreatePdfCommand.new(
		Rect2(Vector2(120.0, 180.0), Vector2(438.0, 620.0)),
		SHARED_ASSET_ID,
		12,
		Vector2i(595, 842),
		7
	)
	_check(runtime.commands.execute(create, runtime), "PDF create command failed")
	var entity_id: int = create.created_entity_id
	_check(entity_id > 0 and runtime.model.pdfs.contains(entity_id), "PDF entity/store registration failed")
	_check(runtime.model.get_entity_type(entity_id) == BoardEntityTypes.PDF, "PDF entity type mismatch")

	var title_command: UpdateAssetInstanceTitleCommand = UpdateAssetInstanceTitleCommand.new(entity_id, "", "Теория к задаче")
	_check(runtime.commands.execute(title_command, runtime), "PDF local rename command failed")
	_check(runtime.model.pdfs.get_instance_title(entity_id) == "Теория к задаче", "PDF local title was not stored")

	var page_command: UpdatePdfPageCommand = UpdatePdfPageCommand.new(entity_id, 0, 7)
	_check(runtime.commands.execute(page_command, runtime), "PDF page command failed")
	_check(runtime.model.pdfs.get_page_index(entity_id) == 7, "PDF page command did not update current page")

	var before_revision: int = runtime.model.pdf_revision
	_check(runtime.set_entity_transform(entity_id, Rect2(Vector2(400.0, 320.0), Vector2(526.0, 745.0))), "PDF transform failed")
	_check(runtime.model.pdf_revision > before_revision, "PDF transform did not invalidate retained rendering")
	_check(runtime.spatial_index.query_point(Vector2(450.0, 350.0)).has(entity_id), "PDF transform did not update spatial index")

	_check(runtime.clipboard.capture(runtime, PackedInt64Array([entity_id])), "PDF clipboard capture failed")
	var paste: PasteBoardObjectsCommand = runtime.clipboard.make_paste_command_at(Vector2(1400.0, 820.0))
	_check(paste != null, "PDF clipboard did not create paste command")
	_check(runtime.commands.execute(paste, runtime), "PDF clipboard paste failed")
	_check(runtime.model.pdfs.size() == 2, "PDF clipboard did not restore the DOD record")
	var pasted_id: int = int(paste.created_selectable_ids[0])
	_check(runtime.model.pdfs.get_instance_title(pasted_id) == "Теория к задаче", "PDF clipboard lost local title")
	_check(runtime.model.pdfs.get_page_index(pasted_id) == 7, "PDF clipboard lost current page")

	var search_snapshot: Dictionary = BoardSearchSnapshot.build(runtime.model, null)
	var search_ids: PackedInt64Array = search_snapshot.get("entity_ids", PackedInt64Array()) as PackedInt64Array
	var search_texts: PackedStringArray = search_snapshot.get("search_texts", PackedStringArray()) as PackedStringArray
	var found_local_name: bool = false
	for index: int in range(search_ids.size()):
		if int(search_ids[index]) == entity_id and search_texts[index].contains("теория к задаче"):
			found_local_name = true
			break
	_check(found_local_name, "board search snapshot does not include PDF local title")

	var document: Dictionary = runtime.write_document(BoardDocumentSchema.make_empty())
	_check(int(document.get("schema_version", 0)) == BoardDocumentSchema.CURRENT_VERSION, "PDF runtime wrote the wrong schema version")
	var content: Dictionary = document.get("content", {}) as Dictionary
	_check((content.get("pdf_blocks", []) as Array).size() == 2, "PDF store was not serialized")
	var restored: BoardRuntime = BoardRuntime.new()
	restored.load_document(document)
	_check(restored.model.pdfs.size() == 2, "PDF runtime roundtrip lost records")
	_check(restored.model.pdfs.get_page_index(entity_id) == 7, "PDF runtime roundtrip lost current page")

	_check(runtime.commands.undo(runtime), "PDF paste undo failed")
	_check(runtime.model.pdfs.size() == 1, "PDF paste undo left a store row")
	_check(runtime.commands.redo(runtime), "PDF paste redo failed")
	_check(runtime.model.pdfs.size() == 2, "PDF paste redo lost a store row")


func _test_schema_migration_and_asset_references() -> void:
	_check(BoardDocumentSchema.CURRENT_VERSION >= 10, "unexpected PDF schema version")
	var legacy: Dictionary = BoardDocumentSchema.make_empty()
	legacy["schema_version"] = 9
	var content: Dictionary = legacy.get("content", {}) as Dictionary
	content.erase("pdf_blocks")
	legacy["content"] = content
	var migrated: Dictionary = BoardDocumentSchema.normalize(legacy)
	_check(int(migrated.get("schema_version", 0)) == BoardDocumentSchema.CURRENT_VERSION, "v9 PDF migration did not advance schema")
	var migrated_content: Dictionary = migrated.get("content", {}) as Dictionary
	_check(migrated_content.has("pdf_blocks"), "PDF migration did not create pdf_blocks")

	var document: Dictionary = BoardDocumentSchema.make_empty()
	var document_content: Dictionary = document.get("content", {}) as Dictionary
	document_content["pdf_blocks"] = [{"entity_id": "42", "asset_id": SHARED_ASSET_ID, "page_index": 0, "page_count": 3, "page_width": 595, "page_height": 842}]
	document["content"] = document_content
	var references: PackedStringArray = BoardDocumentSchema.collect_asset_references(document)
	_check(references.has(SHARED_ASSET_ID), "portable board dependency collection missed PDF asset_id")


func _check(condition: bool, message: String) -> void:
	assert(condition, message)
