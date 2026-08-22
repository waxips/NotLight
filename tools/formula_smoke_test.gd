# SPDX-License-Identifier: GPL-3.0-or-later
extends SceneTree

const STORE_ENTITY_COUNT: int = 1024


func _initialize() -> void:
	_test_typst_mitex_contract()
	_test_dense_store()
	_test_runtime_roundtrip_search_and_clipboard()
	_test_schema_migration()
	print("NotLight Stage 9.7.4 FormulaObject/Typst+MiTeX smoke test passed.")
	quit(0)


func _test_typst_mitex_contract() -> void:
	_check(TypstMiTexTools.BUNDLED_TYPST_VERSION == "0.15.1", "unexpected Typst version pin")
	_check(TypstMiTexTools.MITEX_VERSION == "0.2.7", "unexpected MiTeX version pin")
	_check(TypstMiTexTools.expected_local_import() == "@local/mitex:0.2.7", "formula runtime lost its local-only MiTeX import")
	var arguments: PackedStringArray = TypstMiTexTools.compile_arguments(
		"C:/tmp/job/formula.typ",
		"C:/tmp/job/formula.svg",
		"C:/tmp/job",
		"C:/project/tools/typst/packages",
		"C:/tmp/job/package-cache"
	)
	var argument_text: String = "\n".join(arguments)
	for required: String in ["--format", "svg", "--root", "--package-path", "--package-cache-path", "--ignore-system-fonts", "--creation-timestamp", "--jobs", "1"]:
		_check(argument_text.contains(required), "Typst compile args lost required bounded/offline argument: %s" % required)
	_check(TypstMiTexTools.parse_version_value("typst 0.15.1 (abcdef)\n") == "0.15.1", "Typst version parsing failed")
	_check(FormulaRenderService.WRAPPER_VERSION.contains("mitex"), "formula wrapper is no longer MiTeX-backed")
	_check(FormulaRenderService.WRAPPER_VERSION.contains("white-mask"), "formula wrapper lost the draw-time tint optimization")
	_check(FormulaRenderService.VECTOR_CONTRACT_VERSION.contains("svg"), "formula derived cache lost the SVG vector contract")
	_check(FormulaRenderService.VECTOR_CONTRACT_VERSION.contains("godot-tint"), "formula vector contract lost Godot-side color tinting")
	_check(FormulaRenderService.MAX_PENDING_JOBS == 8, "formula render queue bound drifted")
	_check(FormulaRenderService.MAX_WAITING_REQUESTS == 64, "formula waiting queue bound drifted")
	_check(FormulaRenderService.MAX_SOURCE_LENGTH == FormulaStore.MAX_SOURCE_LENGTH, "formula source limits disagree")


func _test_dense_store() -> void:
	var store: FormulaStore = FormulaStore.new()
	for index: int in range(STORE_ENTITY_COUNT):
		var entity_id: int = index + 1
		_check(
			store.add_formula(
				entity_id,
				"x_{%d}^2 + y^2 = r^2" % entity_id,
				FormulaStore.DISPLAY_BLOCK if index % 2 == 0 else FormulaStore.DISPLAY_INLINE,
				1.0 + float(index % 5) * 0.1,
				Color("#26372d")
			),
			"formula store add failed"
		)
	_check(store.size() == STORE_ENTITY_COUNT, "formula dense store count mismatch")
	for _iteration: int in range(int(STORE_ENTITY_COUNT / 4)):
		var remove_id: int = int(store.entity_ids[store.size() - 2])
		_check(store.remove(remove_id), "formula swap-remove failed")
	for index: int in range(store.size()):
		var entity_id: int = int(store.entity_ids[index])
		_check(store.get_index(entity_id) == index, "formula dense index map drifted")
	var serialized: Array[Dictionary] = store.serialize()
	var restored: FormulaStore = FormulaStore.new()
	restored.deserialize(serialized)
	_check(restored.size() == store.size(), "formula dense store roundtrip count mismatch")
	var probe_id: int = int(store.entity_ids[min(31, store.size() - 1)])
	_check(restored.get_source(probe_id) == store.get_source(probe_id), "formula source was lost")
	_check(restored.get_display_mode(probe_id) == store.get_display_mode(probe_id), "formula display mode was lost")
	_check(is_equal_approx(restored.get_font_scale(probe_id), store.get_font_scale(probe_id)), "formula scale was lost")
	_check(restored.get_foreground(probe_id) == store.get_foreground(probe_id), "formula foreground was lost")


func _test_runtime_roundtrip_search_and_clipboard() -> void:
	var runtime: BoardRuntime = BoardRuntime.new()
	var create: CreateFormulaCommand = CreateFormulaCommand.new(
		Rect2(Vector2(120.0, 180.0), Vector2(360.0, 160.0)),
		"\\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}",
		FormulaStore.DISPLAY_BLOCK,
		1.15,
		Color("#26372d"),
		11
	)
	_check(runtime.commands.execute(create, runtime), "formula create command failed")
	var entity_id: int = create.created_entity_id
	_check(entity_id > 0, "formula create command did not expose its entity id")
	_check(runtime.model.get_entity_type(entity_id) == BoardEntityTypes.FORMULA, "formula entity type mismatch")
	_check(runtime.model.formulas.contains(entity_id), "formula DOD record is missing")

	var before: Dictionary = runtime.model.formulas.get_record(entity_id)
	var after: Dictionary = before.duplicate(true)
	after["source_latex"] = "E = mc^2"
	var update: UpdateFormulaCommand = UpdateFormulaCommand.new(entity_id, before, after)
	_check(runtime.commands.execute(update, runtime), "formula update command failed")
	_check(runtime.model.formulas.get_source(entity_id) == "E = mc^2", "formula update was not applied")
	_check(runtime.commands.undo(runtime), "formula update undo failed")
	_check(runtime.model.formulas.get_source(entity_id).contains("\\frac"), "formula update undo lost source")
	_check(runtime.commands.redo(runtime), "formula update redo failed")
	_check(runtime.model.formulas.get_source(entity_id) == "E = mc^2", "formula update redo failed")

	var search_snapshot: Dictionary = BoardSearchSnapshot.build(runtime.model, null)
	var search_ids: PackedInt64Array = search_snapshot.get("entity_ids", PackedInt64Array()) as PackedInt64Array
	var search_texts: PackedStringArray = search_snapshot.get("search_texts", PackedStringArray()) as PackedStringArray
	var found_formula: bool = false
	for index: int in range(search_ids.size()):
		if int(search_ids[index]) == entity_id and search_texts[index].contains("e = mc^2"):
			found_formula = true
			break
	_check(found_formula, "BoardSearchSnapshot does not include FormulaObject source")

	_check(runtime.clipboard.capture(runtime, PackedInt64Array([entity_id])), "formula clipboard capture failed")
	var paste: PasteBoardObjectsCommand = runtime.clipboard.make_paste_command_at(Vector2(980.0, 740.0))
	_check(paste != null, "formula clipboard paste command was not created")
	_check(runtime.commands.execute(paste, runtime), "formula clipboard paste failed")
	_check(runtime.model.formulas.size() == 2, "formula clipboard did not duplicate the DOD row")

	var document: Dictionary = runtime.write_document(BoardDocumentSchema.make_empty())
	_check(int(document.get("schema_version", 0)) == BoardDocumentSchema.CURRENT_VERSION, "formula runtime wrote the wrong schema")
	var content: Dictionary = document.get("content", {}) as Dictionary
	_check((content.get("formulas", []) as Array).size() == 2, "formula store was not serialized")
	var restored: BoardRuntime = BoardRuntime.new()
	restored.load_document(document)
	_check(restored.model.formulas.size() == 2, "formula runtime roundtrip lost rows")
	_check(restored.model.formulas.get_source(entity_id) == "E = mc^2", "formula runtime roundtrip lost source")
	_check(restored.model.formulas.get_foreground(entity_id) == Color("#26372d"), "formula runtime roundtrip lost foreground")


func _test_schema_migration() -> void:
	_check(BoardDocumentSchema.CURRENT_VERSION == 11, "unexpected FormulaObject schema version")
	var legacy: Dictionary = BoardDocumentSchema.make_empty()
	legacy["schema_version"] = 10
	var content: Dictionary = legacy.get("content", {}) as Dictionary
	content.erase("formulas")
	legacy["content"] = content
	var migrated: Dictionary = BoardDocumentSchema.normalize(legacy)
	_check(int(migrated.get("schema_version", 0)) == BoardDocumentSchema.CURRENT_VERSION, "v10 to v11 migration did not advance schema")
	var migrated_content: Dictionary = migrated.get("content", {}) as Dictionary
	_check(migrated_content.has("formulas"), "v10 to v11 migration did not create formula content")
	_check((migrated_content.get("formulas", []) as Array).is_empty(), "v10 to v11 migration created unexpected formula rows")


func _check(condition: bool, message: String) -> void:
	assert(condition, message)
