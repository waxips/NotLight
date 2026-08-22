# SPDX-License-Identifier: GPL-3.0-or-later
extends SceneTree

const STORE_ENTITY_COUNT: int = 2048


func _initialize() -> void:
	_test_dense_store()
	_test_runtime_roundtrip_and_clipboard()
	_test_schema_migration()
	print("NotLight Stage 9.5 audio DOD/store/search smoke test passed.")
	quit(0)


func _test_dense_store() -> void:
	var store: AudioStore = AudioStore.new()
	for index: int in range(STORE_ENTITY_COUNT):
		var entity_id: int = index + 1
		_check(
			store.add_audio(
				entity_id,
				"audio_%d" % entity_id,
				float(index % 600) + 0.125,
				AudioStore.FLAG_LOOP if index % 7 == 0 else 0,
				"Локальное аудио %d" % entity_id
			),
			"audio store add failed at %d" % index
		)
	_check(store.size() == STORE_ENTITY_COUNT, "dense audio count mismatch")
	for _iteration: int in range(int(STORE_ENTITY_COUNT / 3)):
		var remove_id: int = int(store.entity_ids[store.size() - 2])
		_check(store.remove(remove_id), "audio swap-remove failed")
	for index: int in range(store.size()):
		var entity_id: int = int(store.entity_ids[index])
		_check(store.get_index(entity_id) == index, "audio index map drifted")
	var records: Array[Dictionary] = store.serialize()
	var restored: AudioStore = AudioStore.new()
	restored.deserialize(records)
	_check(restored.size() == store.size(), "audio store roundtrip count mismatch")
	var probe_id: int = int(store.entity_ids[min(17, store.size() - 1)])
	_check(restored.get_asset_id(probe_id) == store.get_asset_id(probe_id), "audio asset id was lost")
	_check(restored.get_instance_title(probe_id) == store.get_instance_title(probe_id), "audio local title was lost")
	_check(is_equal_approx(restored.get_duration(probe_id), store.get_duration(probe_id)), "audio duration was lost")
	_check(restored.get_flags(probe_id) == store.get_flags(probe_id), "audio playback flags were lost")


func _test_runtime_roundtrip_and_clipboard() -> void:
	var runtime: BoardRuntime = BoardRuntime.new()
	var command: CreateAudioCommand = CreateAudioCommand.new(
		Rect2(Vector2(120.0, 180.0), Vector2(420.0, 128.0)),
		"asset_audio_smoke",
		83.75,
		7
	)
	_check(runtime.commands.execute(command, runtime), "audio create command failed")
	var entity_id: int = command.created_entity_id
	_check(entity_id > 0 and runtime.model.audios.contains(entity_id), "audio entity/store registration failed")
	_check(runtime.model.get_entity_type(entity_id) == BoardEntityTypes.AUDIO, "audio entity type mismatch")

	var title_command: UpdateAssetInstanceTitleCommand = UpdateAssetInstanceTitleCommand.new(
		entity_id,
		"",
		"Голосовая идея"
	)
	_check(runtime.commands.execute(title_command, runtime), "audio local rename command failed")
	_check(runtime.model.audios.get_instance_title(entity_id) == "Голосовая идея", "audio local rename was not stored")

	var before_revision: int = runtime.model.audio_revision
	_check(runtime.set_entity_transform(entity_id, Rect2(Vector2(400.0, 320.0), Vector2(500.0, 152.0))), "audio transform failed")
	_check(runtime.model.audio_revision > before_revision, "audio transform did not invalidate retained rendering")
	_check(runtime.spatial_index.query_point(Vector2(450.0, 350.0)).has(entity_id), "audio transform did not update spatial index")

	_check(runtime.clipboard.capture(runtime, PackedInt64Array([entity_id])), "audio clipboard capture failed")
	var paste: PasteBoardObjectsCommand = runtime.clipboard.make_paste_command_at(Vector2(1200.0, 760.0))
	_check(paste != null, "audio clipboard did not create paste command")
	_check(runtime.commands.execute(paste, runtime), "audio clipboard paste failed")
	_check(runtime.model.audios.size() == 2, "audio clipboard did not restore the DOD record")
	var pasted_id: int = int(paste.created_selectable_ids[0])
	_check(runtime.model.audios.get_instance_title(pasted_id) == "Голосовая идея", "audio clipboard lost board-local title")

	var search_snapshot: Dictionary = BoardSearchSnapshot.build(runtime.model, null)
	var search_ids: PackedInt64Array = search_snapshot.get("entity_ids", PackedInt64Array()) as PackedInt64Array
	var search_texts: PackedStringArray = search_snapshot.get("search_texts", PackedStringArray()) as PackedStringArray
	var found_local_name: bool = false
	for index: int in range(search_ids.size()):
		if int(search_ids[index]) == entity_id and search_texts[index].contains("голосовая идея"):
			found_local_name = true
			break
	_check(found_local_name, "future search snapshot does not include audio board-local title")

	var document: Dictionary = runtime.write_document(BoardDocumentSchema.make_empty())
	_check(int(document.get("schema_version", 0)) == BoardDocumentSchema.CURRENT_VERSION, "audio runtime wrote the wrong schema version")
	var content: Dictionary = document.get("content", {}) as Dictionary
	_check((content.get("audios", []) as Array).size() == 2, "audio store was not serialized")
	var restored: BoardRuntime = BoardRuntime.new()
	restored.load_document(document)
	_check(restored.model.audios.size() == 2, "audio runtime roundtrip lost records")
	_check(restored.model.audios.get_instance_title(entity_id) == "Голосовая идея", "audio runtime roundtrip lost local title")

	_check(runtime.commands.undo(runtime), "audio paste undo failed")
	_check(runtime.model.audios.size() == 1, "audio paste undo left a store row")
	_check(runtime.commands.redo(runtime), "audio paste redo failed")
	_check(runtime.model.audios.size() == 2, "audio paste redo lost a store row")


func _test_schema_migration() -> void:
	_check(BoardDocumentSchema.CURRENT_VERSION >= 9, "unexpected audio schema version")
	var legacy: Dictionary = BoardDocumentSchema.make_empty()
	legacy["schema_version"] = 8
	var content: Dictionary = legacy.get("content", {}) as Dictionary
	content.erase("audios")
	legacy["content"] = content
	var migrated: Dictionary = BoardDocumentSchema.normalize(legacy)
	_check(int(migrated.get("schema_version", 0)) == BoardDocumentSchema.CURRENT_VERSION, "v8 to v9 migration did not advance schema")
	var migrated_content: Dictionary = migrated.get("content", {}) as Dictionary
	_check(migrated_content.has("audios"), "v8 to v9 migration did not create audio content")
	_check((migrated_content.get("audios", []) as Array).is_empty(), "v8 to v9 migration created unexpected audio rows")


func _check(condition: bool, message: String) -> void:
	assert(condition, message)
