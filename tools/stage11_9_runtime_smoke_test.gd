# SPDX-License-Identifier: GPL-3.0-or-later
extends SceneTree

const TEST_ROOT: String = "user://notlight_stage11_9_runtime_smoke"
const SOURCE_LIBRARY_ROOT: String = TEST_ROOT + "/source_library"
const TARGET_LIBRARY_ON_ROOT: String = TEST_ROOT + "/target_library_on"
const TARGET_LIBRARY_OFF_ROOT: String = TEST_ROOT + "/target_library_off"
const PACKAGE_ROOT: String = TEST_ROOT + "/packages"
const VIEW_PROBE_SCRIPT: Script = preload("res://tools/fixtures/stage11_9_asset_library_view_probe.gd")
const BOARD_REPOSITORY_STUB_SCRIPT: Script = preload("res://tools/fixtures/stage11_9_board_repository_stub.gd")
const MODULE_ENTRY_SCRIPT: Script = preload("res://tools/fixtures/stage11_9_module_entry.gd")
const MODULE_STATE_HOST_SCRIPT: Script = preload("res://tools/fixtures/stage11_9_module_state_host.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_delete_directory_recursive(TEST_ROOT)
	_check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PACKAGE_ROOT)) == OK, "Stage 11.9 runtime smoke root setup failed")

	var source_library: AssetLibraryService = _make_library(SOURCE_LIBRARY_ROOT, "Stage11_9SourceLibrary")
	var media_records: Array[Dictionary] = _register_media_fixture_set(source_library)

	await _test_folder_tree_runtime(source_library)
	_test_note_media_embed_runtime(source_library, media_records)
	_test_note_inline_markup_runtime()
	_test_note_formula_layout_runtime()
	_test_schema_aware_asset_remap()
	_test_board_independent_module_surface_host()
	_test_module_library_preview_runtime()
	_test_note_module_embed_runtime()
	_test_portable_note_embed_roundtrip(source_library, media_records[0])

	source_library.free()
	_delete_directory_recursive(TEST_ROOT)
	print("NotLight Stage 11.9 Godot 4.4.1 runtime hardening smoke test passed.")
	quit(0)


func _test_folder_tree_runtime(library: AssetLibraryService) -> void:
	var parent: Dictionary = library.create_folder("Runtime Parent")
	_check(not parent.is_empty(), "Resource Library runtime folder parent creation failed")
	var parent_id: String = str(parent.get("id", ""))
	var child: Dictionary = library.create_folder("Runtime Child", parent_id)
	_check(not child.is_empty(), "Resource Library runtime nested folder creation failed")
	var child_id: String = str(child.get("id", ""))

	var view: AssetLibraryView = VIEW_PROBE_SCRIPT.new() as AssetLibraryView
	_check(view != null, "Resource Library Tree probe could not be instantiated")
	root.add_child(view)
	view.configure(library)
	# Folder-tree reconstruction is intentionally deferred to escape any caller's
	# signal stack. Two frames also let the view's own deferred layout settle.
	await process_frame
	await process_frame
	var tree: Tree = view.get("_folder_tree") as Tree
	_check(tree != null and tree.get_root() != null, "Resource Library folder Tree was not materialized")
	var child_item: TreeItem = _find_tree_item_by_metadata(tree.get_root(), child_id)
	_check(child_item != null, "nested Resource Library folder is missing from the Tree")
	var root_before: TreeItem = tree.get_root()
	var root_before_id: int = root_before.get_instance_id()
	var rebuild_before: int = int(view.get("rebuild_count"))

	# TreeItem.select() drives the real Tree item_selected signal path. Selection is
	# filtering state only and must not synchronously rebuild the same Tree.
	child_item.select(0)
	_check(str(view.get("_selected_folder_id")) == child_id, "Tree item_selected did not select the requested Resource Library folder")
	_check(int(view.get("rebuild_count")) == rebuild_before, "folder selection synchronously rebuilt its own Tree")
	await process_frame
	_check(int(view.get("rebuild_count")) == rebuild_before, "folder selection scheduled an unnecessary structural Tree rebuild")
	var root_after_selection: TreeItem = tree.get_root()
	_check(root_after_selection != null and root_after_selection.get_instance_id() == root_before_id, "folder selection replaced the Tree structure")

	# A real structural change must still rebuild, but only after the signal stack.
	var late_folder: Dictionary = library.create_folder("Runtime Late Child", child_id)
	_check(not late_folder.is_empty(), "Resource Library late nested folder creation failed")
	var late_id: String = str(late_folder.get("id", ""))
	_check(int(view.get("rebuild_count")) == rebuild_before, "folders_changed rebuilt the Tree reentrantly")
	await process_frame
	_check(int(view.get("rebuild_count")) == rebuild_before + 1, "deferred structural folder rebuild did not run exactly once")
	_check(_find_tree_item_by_metadata(tree.get_root(), late_id) != null, "deferred folder rebuild lost the newly created folder")
	view.free()


func _test_note_media_embed_runtime(library: AssetLibraryService, media_records: Array[Dictionary]) -> void:
	_check(media_records.size() == 4, "Stage 11.9 media fixture set is incomplete")
	for record: Dictionary in media_records:
		var hash_sha256: String = str(record.get("hash_sha256", ""))
		var asset_id: String = str(record.get("id", ""))
		var block: NoteResourceEmbedBlock = NoteResourceEmbedBlock.new()
		root.add_child(block)
		block.configure(library, null, null, null, null, hash_sha256, "Runtime embed", true)
		_check(block.get_asset_id() == asset_id, "Notes media embed did not resolve its SHA-pinned Library asset")
		var content: VBoxContainer = block.get("_content") as VBoxContainer
		_check(content != null and content.get_child_count() > 0, "Notes media embed did not build its bounded rich presentation")
		var open_button: Button = block.get("_open_button") as Button
		_check(open_button != null and not open_button.disabled, "resolved Notes media embed did not expose Library preview")
		var kind: int = int(record.get("kind", AssetKinds.OTHER))
		if kind == AssetKinds.VIDEO:
			_check(block.get("_video_aspect") is AspectRatioContainer, "Notes video embed is missing its aspect-preserving host")
		if kind == AssetKinds.PDF:
			_check(block.get("_pdf_scroll") is ScrollContainer, "Notes PDF embed is missing its bounded zoom/scroll viewport")
			_check(is_equal_approx(float(block.get("_pdf_zoom")), 1.0), "Notes PDF embed did not start at natural 100% zoom")
			block.call("_on_pdf_zoom_in")
			_check(float(block.get("_pdf_zoom")) > 1.0, "Notes PDF in-embed zoom control did not increase scale")
			block.call("_on_pdf_zoom_reset")
			_check(is_equal_approx(float(block.get("_pdf_zoom")), 1.0), "Notes PDF 100% reset did not restore natural zoom")
		block.free()

	var missing_hash: String = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
	_check(library.find_asset_by_hash(missing_hash).is_empty(), "missing-SHA fixture unexpectedly exists")
	var missing_syntax: String = NoteResourceEmbed.syntax_for_hash(missing_hash, "Отсутствующий ресурс")
	var parsed_blocks: Array[Dictionary] = NoteMarkdownBlocks.parse(missing_syntax)
	_check(parsed_blocks.size() == 1 and StringName(str(parsed_blocks[0].get("type", ""))) == NoteMarkdownBlocks.TYPE_EMBED, "missing SHA changed canonical Markdown embed parsing")
	var missing_block: NoteResourceEmbedBlock = NoteResourceEmbedBlock.new()
	root.add_child(missing_block)
	missing_block.configure(library, null, null, null, null, missing_hash, "Отсутствующий ресурс", true)
	_check(missing_block.get_asset_id().is_empty(), "missing SHA incorrectly resolved to a local Library asset")
	var missing_open: Button = missing_block.get("_open_button") as Button
	_check(missing_open != null and missing_open.disabled, "missing SHA embed did not remain a recoverable non-preview state")
	missing_block.free()


func _test_note_inline_markup_runtime() -> void:
	var wiki_name: String = "Первая_заметка_как_оригинально"
	var wiki_bbcode: String = NoteInlineMarkup.to_bbcode("[[%s]]" % wiki_name)
	_check(wiki_bbcode.contains("[i]%s[/i]" % wiki_name), "wiki-link title was not rendered as one literal italic label")
	_check(NoteInlineMarkup.strip_markup("[[%s]]" % wiki_name) == wiki_name, "wiki-link plain-text projection changed underscores in the note title")
	var alias: String = "Alias_with_*_symbols"
	var alias_bbcode: String = NoteInlineMarkup.to_bbcode("[[Target_Name|%s]]" % alias)
	_check(alias_bbcode.contains("[i]%s[/i]" % alias), "wiki-link alias was parsed as nested Markdown instead of literal text")
	var strong_outer: String = NoteInlineMarkup.to_bbcode("**жирный и *курсив внутри***")
	_check(strong_outer == "[b]жирный и [i]курсив внутри[/i][/b]", "nested strong/italic Markdown triple-close parsing regressed")
	var italic_outer: String = NoteInlineMarkup.to_bbcode("*курсив и **жирный внутри***")
	_check(italic_outer == "[i]курсив и [b]жирный внутри[/b][/i]", "nested italic/strong Markdown triple-close parsing regressed")
	var strike_nested: String = NoteInlineMarkup.to_bbcode("~~зачёркнутый с **жирным** и *курсивом*~~")
	_check(strike_nested == "[s]зачёркнутый с [b]жирным[/b] и [i]курсивом[/i][/s]", "nested strike/strong/italic Markdown parsing regressed")
	var escaped: String = NoteInlineMarkup.to_bbcode("\\*не курсив\\* / \\_тоже не курсив\\_")
	_check(escaped == "*не курсив* / _тоже не курсив_", "escaped emphasis markers were not kept literal")
	var intraword: String = "name_with_underscores"
	_check(NoteInlineMarkup.to_bbcode(intraword) == intraword, "intraword underscores were incorrectly treated as emphasis")


func _test_note_formula_layout_runtime() -> void:
	var formula: NoteFormulaBlock = NoteFormulaBlock.new()
	root.add_child(formula)
	formula.size = Vector2(900.0, 360.0)
	formula.configure(null, "f(x)=x^3-2x\nf'(x)=3x^2-2\nf'(2)=10")
	var image: Image = Image.create(420, 1400, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	formula.call("_apply_texture", texture)
	var texture_view: TextureRect = formula.get("_texture") as TextureRect
	var layout_host: Control = formula.get("_layout_host") as Control
	_check(texture_view != null and layout_host != null, "Notes formula runtime fixture did not create its explicit layout host")
	_check(layout_host.custom_minimum_size.y > texture_view.size.y, "Notes formula host did not reserve breathing room around a tall raster")
	_check(texture_view.size.y > 700.0, "tall multi-row Notes formula was collapsed back into a fixed-height preview")
	_check(texture_view.size.x <= 844.0, "Notes formula ignored the available Notes column width")
	_check(float(formula.get("_request_extent")) >= 1536.0, "multi-row Notes formula did not request a higher bounded raster tier")
	var render_source: String = str(formula.get("_render_source"))
	_check(render_source.contains("\\begin{aligned}"), "sequential Notes formula did not retain aligned presentation sugar")
	formula.free()


func _test_schema_aware_asset_remap() -> void:
	var source_asset_id: String = "asset-source"
	var target_asset_id: String = "asset-target"
	var document: Dictionary = BoardDocumentSchema.make_empty()
	var content: Dictionary = document.get("content", {}) as Dictionary
	content["images"] = [{"entity_id": "1", "asset_id": source_asset_id}]
	content["module_objects"] = [{
		"entity_id": "2",
		"module_id": "notlight.smoke",
		"state_schema_version": 1,
		"instance_state": {
			"asset_id": source_asset_id,
			"asset_ids": [source_asset_id],
			"nested": {"asset_id": source_asset_id},
		},
		"instance_title": "Opaque state",
		"asset_ids": [source_asset_id],
	}]
	document["content"] = content
	document["feature_data"] = {"asset_id": source_asset_id, "asset_ids": [source_asset_id]}
	var references: PackedStringArray = BoardDocumentSchema.collect_asset_references(document)
	_check(references.size() == 1 and references[0] == source_asset_id, "schema-aware asset collector did not collect declared board references")
	var remapped: Dictionary = BoardDocumentSchema.remap_asset_references(document, {source_asset_id: target_asset_id})
	var remapped_content: Dictionary = remapped.get("content", {}) as Dictionary
	var images: Array = remapped_content.get("images", []) as Array
	var modules: Array = remapped_content.get("module_objects", []) as Array
	_check(str((images[0] as Dictionary).get("asset_id", "")) == target_asset_id, "declared image asset reference was not remapped")
	var module_record: Dictionary = modules[0] as Dictionary
	var module_asset_ids: Array = module_record.get("asset_ids", []) as Array
	_check(module_asset_ids.size() == 1 and str(module_asset_ids[0]) == target_asset_id, "declared ModuleObject asset_ids were not remapped")
	var opaque_state: Dictionary = module_record.get("instance_state", {}) as Dictionary
	_check(str(opaque_state.get("asset_id", "")) == source_asset_id, "core portability rewrote opaque module.instance_state asset_id")
	_check(str(((opaque_state.get("nested", {}) as Dictionary).get("asset_id", ""))) == source_asset_id, "core portability traversed nested opaque module.instance_state")
	_check(remapped.get("feature_data", {}) == document.get("feature_data", {}), "core portability rewrote opaque feature_data by magic key name")


func _test_board_independent_module_surface_host() -> void:
	var entry: Object = MODULE_ENTRY_SCRIPT.new()
	_check(entry != null, "Module API runtime fixture entry could not be instantiated")
	var registry: ModuleRegistry = ModuleRegistry.new()
	registry.set("_entries", {"notlight.smoke": entry})
	registry.set("_active_manifests", {
		"notlight.smoke": {
			"module_id": "notlight.smoke",
			"state_schema_version": 2,
			"capabilities": ["board.instance_state", "localization.read", "theme.read"],
		},
	})
	var state_host: ModuleInstanceStateHost = MODULE_STATE_HOST_SCRIPT.new() as ModuleInstanceStateHost
	_check(state_host != null, "board-independent module state-host fixture could not be instantiated")
	state_host.call("configure", "notlight.smoke", "runtime-smoke-instance", {"value": 125.0}, 1)
	var parent: Control = Control.new()
	root.add_child(parent)
	var surface_host: ModuleSurfaceHost = ModuleSurfaceHost.new()
	var result: Dictionary = surface_host.materialize(parent, "notlight.smoke", state_host, registry)
	_check(bool(result.get("ok", false)), "board-independent ModuleSurfaceHost failed to materialize a valid SDK surface")
	_check(state_host.get_state_schema_version() == 2, "ModuleSurfaceHost did not persist host-owned schema normalization")
	_check(float(state_host.get_state().get("value", -1.0)) == 100.0, "ModuleSurfaceHost did not persist normalized state")
	var context: ModuleInstanceContext = result.get("context") as ModuleInstanceContext
	_check(context != null and context.get_module_instance_id() == "runtime-smoke-instance", "ModuleInstanceContext leaked Board entity identity assumptions")
	_check(context.commit_state({"value": 7.0}, "Runtime smoke commit"), "board-independent context commit was rejected")
	_check(float(state_host.get_state().get("value", -1.0)) == 7.0, "board-independent state host did not receive context commit")
	_check(str(state_host.get("last_action_name")) == "Runtime smoke commit", "module context lost the host action name")
	parent.free()


func _test_module_library_preview_runtime() -> void:
	var entry: Object = MODULE_ENTRY_SCRIPT.new()
	_check(entry != null, "Module Library preview fixture entry could not be instantiated")
	var registry: ModuleRegistry = ModuleRegistry.new()
	registry.set("_entries", {"notlight.smoke": entry})
	registry.set("_active_manifests", {
		"notlight.smoke": {
			"module_id": "notlight.smoke",
			"state_schema_version": 2,
			"capabilities": ["board.instance_state", "localization.read", "theme.read"],
		},
	})
	registry.set("_states", {
		"notlight.smoke": {
			"module_id": "notlight.smoke",
			"active_version_key": "",
			"pending_version_key": "",
			"pending_remove": false,
			"last_error": "",
		},
	})
	var overlay: ModulePreviewOverlay = ModulePreviewOverlay.new()
	root.add_child(overlay)
	overlay.configure(registry)
	overlay.open_module("notlight.smoke")
	var surface: Control = overlay.get("_surface") as Control
	_check(overlay.visible and surface != null, "Module Library overlay did not materialize an isolated live preview surface")
	var state_host: ModulePreviewStateHost = overlay.get("_state_host") as ModulePreviewStateHost
	var context: ModuleInstanceContext = overlay.get("_context") as ModuleInstanceContext
	_check(state_host != null and state_host.is_attached("notlight.smoke"), "Module Library overlay preview state host was not attached")
	_check(context != null and context.get_module_instance_id() == "library-preview:notlight.smoke", "Module Library overlay preview leaked board entity identity")
	_check(context.commit_state({"value": 37.0}, "Ephemeral preview smoke"), "Module Library overlay preview rejected an ephemeral state commit")
	_check(float(state_host.get_state().get("value", -1.0)) == 37.0, "Module Library overlay preview did not keep ephemeral state in its host")
	overlay.close_preview()
	_check(not state_host.is_attached("notlight.smoke"), "closing Module Library overlay preview did not discard/detach ephemeral state")
	overlay.free()


func _test_note_module_embed_runtime() -> void:
	var module_id: String = "notlight.smoke"
	var syntax: String = NoteModuleEmbed.syntax_for_module(module_id, "Runtime smoke module")
	_check(syntax == "![[module:notlight.smoke|Runtime smoke module]]", "Notes module embed canonical syntax is unstable")
	var parsed: Dictionary = NoteModuleEmbed.parse_exact(syntax)
	_check(str(parsed.get("module_id", "")) == module_id, "Notes module embed parser lost module identity")
	var markdown_blocks: Array[Dictionary] = NoteMarkdownBlocks.parse(syntax)
	_check(markdown_blocks.size() == 1 and StringName(str(markdown_blocks[0].get("type", ""))) == NoteMarkdownBlocks.TYPE_MODULE_EMBED, "Notes module embed was not promoted to its own Markdown block")
	_check(NoteLinkParser.extract_wikilink_targets(syntax).is_empty(), "Notes module embed polluted the wiki-link knowledge graph")

	var entry: Object = MODULE_ENTRY_SCRIPT.new()
	_check(entry != null, "Notes module embed fixture entry could not be instantiated")
	var registry: ModuleRegistry = ModuleRegistry.new()
	registry.set("_entries", {module_id: entry})
	registry.set("_active_manifests", {
		module_id: {
			"module_id": module_id,
			"state_schema_version": 2,
			"capabilities": ["board.instance_state", "localization.read", "theme.read"],
		},
	})
	registry.set("_states", {
		module_id: {
			"module_id": module_id,
			"active_version_key": "",
			"pending_version_key": "",
			"pending_remove": false,
			"last_error": "",
		},
	})

	var block: NoteModuleEmbedBlock = NoteModuleEmbedBlock.new()
	block.configure(registry, module_id, "Runtime smoke module", "note-embed:runtime-smoke")
	root.add_child(block)
	var stage_panel: PanelContainer = block.get("_stage_panel") as PanelContainer
	_check(stage_panel != null and stage_panel.custom_minimum_size.y >= 520.0, "Notes module embed stage regressed to an undersized runtime surface")
	_check(not block.is_live(), "Notes module embed auto-ran executable module code during Markdown materialization")
	_check(block.activate_live(), "Notes module embed did not materialize an isolated live surface")
	var surface: Control = block.get("_surface") as Control
	var state_host: ModuleEphemeralStateHost = block.get("_state_host") as ModuleEphemeralStateHost
	var context: ModuleInstanceContext = block.get("_context") as ModuleInstanceContext
	_check(surface != null and state_host != null and context != null, "Notes module embed lost its runtime host/context boundary")
	_check(context.get_module_instance_id() == "note-embed:runtime-smoke", "Notes module embed leaked Board entity identity")
	_check(context.commit_state({"value": 41.0}, "Ephemeral Notes smoke"), "Notes module embed rejected an ephemeral state commit")
	_check(float(state_host.get_state().get("value", -1.0)) == 41.0, "Notes module embed did not retain runtime-only state while live")
	block.deactivate_live()
	_check(not state_host.is_attached(module_id), "stopping a Notes module embed did not discard ephemeral state")
	block.free()


func _test_portable_note_embed_roundtrip(source_library: AssetLibraryService, embedded_media: Dictionary) -> void:
	var source_notes: NoteRepository = NoteRepository.new()
	root.add_child(source_notes)
	source_notes.configure(source_library)
	var media_hash: String = str(embedded_media.get("hash_sha256", ""))
	var media_id: String = str(embedded_media.get("id", ""))
	var syntax: String = NoteResourceEmbed.syntax_for_hash(media_hash, "Portable runtime embed")
	var module_embed_syntax: String = NoteModuleEmbed.syntax_for_module("notlight.smoke", "Portable runtime module")
	var note_id: String = source_notes.create_note("Portable runtime note", "# Portable\n\n%s\n\n%s\n" % [syntax, module_embed_syntax])
	_check(not note_id.is_empty(), "portable runtime note creation failed")

	var runtime: BoardRuntime = BoardRuntime.new()
	var portal_command: CreateNotePortalCommand = CreateNotePortalCommand.new(Rect2(40.0, 60.0, 420.0, 300.0), note_id)
	_check(portal_command.execute(runtime), "portable runtime NotePortal creation failed")
	var module_command: CreateModuleCommand = CreateModuleCommand.new(
		Rect2(520.0, 60.0, 420.0, 300.0),
		"notlight.smoke",
		1,
		{"asset_id": media_id, "nested": {"asset_ids": [media_id]}},
		"Opaque portability smoke",
		PackedStringArray([media_id])
	)
	_check(module_command.execute(runtime), "portable runtime ModuleObject creation failed")
	var source_document_with_module: Dictionary = runtime.write_document(BoardDocumentSchema.make_empty())

	var source_repository: BoardRepository = BOARD_REPOSITORY_STUB_SCRIPT.new() as BoardRepository
	_check(source_repository != null, "source portable BoardRepository stub could not be instantiated")
	root.add_child(source_repository)
	source_repository.call("seed_board", "stage11_9_source_board", "Stage 11.9 source", source_document_with_module)
	var source_portable: NotLightPortablePackageService = NotLightPortablePackageService.new()
	root.add_child(source_portable)
	source_portable.configure(source_repository, source_library, source_notes)
	var package_with_embeds: String = PACKAGE_ROOT.path_join("notes_embeds_on.notlight-board")
	var exported_on: Dictionary = source_portable.export_board_profile("stage11_9_source_board", package_with_embeds, {
		"resource_mode": "none",
		"include_derived_variants": false,
		"include_notes": true,
		"include_note_embeds": true,
	})
	_check(bool(exported_on.get("ok", false)), "portable Notes+embeds ON export failed: %s" % str(exported_on.get("error", "")))
	_check(int(exported_on.get("note_embed_asset_count", 0)) == 1, "portable export did not compute the Note media dependency closure")

	var target_library_on: AssetLibraryService = _make_library(TARGET_LIBRARY_ON_ROOT, "Stage11_9TargetLibraryOn")
	# Force logical-ID collision for the media resource. Import must remap declared
	# board asset references while leaving module-owned opaque state untouched.
	_register_media_asset(target_library_on, "Collision", "bin", AssetKinds.OTHER, "collision bytes".to_utf8_buffer(), media_id)
	var target_notes_on: NoteRepository = NoteRepository.new()
	root.add_child(target_notes_on)
	target_notes_on.configure(target_library_on)
	var target_repository_on: BoardRepository = BOARD_REPOSITORY_STUB_SCRIPT.new() as BoardRepository
	_check(target_repository_on != null, "target portable BoardRepository stub could not be instantiated")
	root.add_child(target_repository_on)
	var target_portable_on: NotLightPortablePackageService = NotLightPortablePackageService.new()
	root.add_child(target_portable_on)
	target_portable_on.configure(target_repository_on, target_library_on, target_notes_on)
	var imported_on: Dictionary = target_portable_on.import_board(package_with_embeds)
	_check(bool(imported_on.get("ok", false)), "portable Notes+embeds ON import failed: %s" % str(imported_on.get("error", "")))
	var imported_document_on: Dictionary = target_repository_on.call("get_stored_document") as Dictionary
	var imported_note_ids: PackedStringArray = BoardDocumentSchema.collect_note_references(imported_document_on)
	_check(imported_note_ids.size() == 1, "portable import lost the NotePortal note reference")
	var imported_note_content: String = target_notes_on.read_content(imported_note_ids[0])
	_check(imported_note_content.contains(syntax), "portable round-trip rewrote canonical SHA-pinned Note Markdown")
	_check(imported_note_content.contains(module_embed_syntax), "portable round-trip rewrote canonical runtime-only module embed Markdown")
	var imported_media: Dictionary = target_library_on.find_asset_by_hash(media_hash)
	_check(not imported_media.is_empty(), "portable Notes+embeds ON import omitted the pinned media blob")
	var remapped_media_id: String = str(imported_media.get("id", ""))
	_check(remapped_media_id != media_id, "logical asset-ID collision did not trigger portable remap")
	var imported_content: Dictionary = imported_document_on.get("content", {}) as Dictionary
	var imported_modules: Array = imported_content.get("module_objects", []) as Array
	_check(imported_modules.size() == 1, "portable round-trip lost ModuleObject")
	var imported_module: Dictionary = imported_modules[0] as Dictionary
	var imported_module_refs: Array = imported_module.get("asset_ids", []) as Array
	_check(imported_module_refs.size() == 1 and str(imported_module_refs[0]) == remapped_media_id, "portable import did not remap declared ModuleObject asset_ids")
	var imported_opaque_state: Dictionary = imported_module.get("instance_state", {}) as Dictionary
	_check(str(imported_opaque_state.get("asset_id", "")) == media_id, "portable import rewrote opaque module.instance_state")

	# Second round-trip isolates the explicit Notes ON / embed dependencies OFF
	# policy into an empty target Library. Markdown must survive with a recoverable
	# missing SHA and no media payload smuggled into the package.
	var runtime_note_only: BoardRuntime = BoardRuntime.new()
	var note_only_portal: CreateNotePortalCommand = CreateNotePortalCommand.new(Rect2(40.0, 60.0, 420.0, 300.0), note_id)
	_check(note_only_portal.execute(runtime_note_only), "note-only portable runtime NotePortal creation failed")
	var source_document_note_only: Dictionary = runtime_note_only.write_document(BoardDocumentSchema.make_empty())
	source_repository.call("seed_board", "stage11_9_note_only_board", "Stage 11.9 note only", source_document_note_only)
	var package_without_embeds: String = PACKAGE_ROOT.path_join("notes_embeds_off.notlight-board")
	var exported_off: Dictionary = source_portable.export_board_profile("stage11_9_note_only_board", package_without_embeds, {
		"resource_mode": "none",
		"include_derived_variants": false,
		"include_notes": true,
		"include_note_embeds": false,
	})
	_check(bool(exported_off.get("ok", false)), "portable Notes ON / embeds OFF export failed: %s" % str(exported_off.get("error", "")))
	_check(int(exported_off.get("note_embed_asset_count", -1)) == 0, "embeds-OFF export unexpectedly included Note media dependencies")

	var target_library_off: AssetLibraryService = _make_library(TARGET_LIBRARY_OFF_ROOT, "Stage11_9TargetLibraryOff")
	var target_notes_off: NoteRepository = NoteRepository.new()
	root.add_child(target_notes_off)
	target_notes_off.configure(target_library_off)
	var target_repository_off: BoardRepository = BOARD_REPOSITORY_STUB_SCRIPT.new() as BoardRepository
	_check(target_repository_off != null, "embeds-OFF target BoardRepository stub could not be instantiated")
	root.add_child(target_repository_off)
	var target_portable_off: NotLightPortablePackageService = NotLightPortablePackageService.new()
	root.add_child(target_portable_off)
	target_portable_off.configure(target_repository_off, target_library_off, target_notes_off)
	var imported_off: Dictionary = target_portable_off.import_board(package_without_embeds)
	_check(bool(imported_off.get("ok", false)), "portable Notes ON / embeds OFF import failed: %s" % str(imported_off.get("error", "")))
	var imported_document_off: Dictionary = target_repository_off.call("get_stored_document") as Dictionary
	var imported_note_ids_off: PackedStringArray = BoardDocumentSchema.collect_note_references(imported_document_off)
	_check(imported_note_ids_off.size() == 1, "embeds-OFF round-trip lost the canonical note")
	var imported_note_content_off: String = target_notes_off.read_content(imported_note_ids_off[0])
	_check(imported_note_content_off.contains(syntax), "embeds-OFF round-trip rewrote canonical Note Markdown")
	_check(imported_note_content_off.contains(module_embed_syntax), "embeds-OFF round-trip rewrote runtime-only module embed Markdown")
	_check(target_library_off.find_asset_by_hash(media_hash).is_empty(), "embeds-OFF round-trip imported a media dependency that should remain missing")

	target_portable_off.free()
	target_repository_off.free()
	target_notes_off.free()
	target_library_off.free()
	target_portable_on.free()
	target_repository_on.free()
	target_notes_on.free()
	target_library_on.free()
	source_portable.free()
	source_repository.free()
	source_notes.free()


func _make_library(path: String, node_name: String) -> AssetLibraryService:
	var library: AssetLibraryService = AssetLibraryService.new()
	library.name = node_name
	root.add_child(library)
	_check(library.setup(null, path), "Asset Library setup failed for %s" % path)
	return library


func _register_media_fixture_set(library: AssetLibraryService) -> Array[Dictionary]:
	return [
		_register_media_asset(library, "Runtime image", "png", AssetKinds.IMAGE, "stage11.9 image bytes".to_utf8_buffer()),
		_register_media_asset(library, "Runtime audio", "mp3", AssetKinds.AUDIO, "stage11.9 audio bytes".to_utf8_buffer()),
		_register_media_asset(library, "Runtime video", "mp4", AssetKinds.VIDEO, "stage11.9 video bytes".to_utf8_buffer()),
		_register_media_asset(library, "Runtime PDF", "pdf", AssetKinds.PDF, "stage11.9 pdf bytes".to_utf8_buffer()),
	]


func _register_media_asset(
	library: AssetLibraryService,
	display_name: String,
	extension: String,
	kind: int,
	bytes: PackedByteArray,
	forced_asset_id: String = ""
) -> Dictionary:
	var temp_path: String = library.blobs.make_temp_path(AssetId.make_temporary_id("stage11-9-runtime"))
	_write_bytes(temp_path, bytes)
	var hash_sha256: String = FileAccess.get_sha256(temp_path).to_lower()
	var commit: Dictionary = library.blobs.commit_temp(temp_path, hash_sha256, extension)
	_check(not commit.is_empty(), "Stage 11.9 media blob commit failed")
	var asset_id: String = forced_asset_id.strip_edges()
	if asset_id.is_empty():
		asset_id = AssetId.make_uuid()
	var now: int = int(Time.get_unix_time_from_system())
	var record: Dictionary = {
		"id": asset_id,
		"hash_sha256": hash_sha256,
		"blob_relpath": str(commit.get("relative_path", "")),
		"display_name": display_name,
		"original_filename": "runtime_fixture.%s" % extension,
		"extension": extension,
		"kind": kind,
		"byte_size": bytes.size(),
		"folder_id": "",
		"created_at_unix": now,
		"imported_at_unix": now,
		"metadata": {},
	}
	_check(library.register_managed_asset(record), "Stage 11.9 media Library registration failed: %s" % library.get_last_error())
	return library.get_asset(asset_id)


func _find_tree_item_by_metadata(parent: TreeItem, metadata: String, depth: int = 0) -> TreeItem:
	if parent == null or depth >= 64:
		return null
	if str(parent.get_metadata(0)) == metadata:
		return parent
	var child: TreeItem = parent.get_first_child()
	while child != null:
		var found: TreeItem = _find_tree_item_by_metadata(child, metadata, depth + 1)
		if found != null:
			return found
		child = child.get_next()
	return null


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var parent: String = path.get_base_dir()
	if not parent.is_empty() and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(parent)):
		_check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(parent)) == OK, "failed to create Stage 11.9 runtime smoke parent")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "failed to open Stage 11.9 runtime smoke file")
	_check(file.store_buffer(bytes), "failed to write Stage 11.9 runtime smoke bytes")
	file.flush()
	_check(file.get_error() == OK, "failed to flush Stage 11.9 runtime smoke file")
	file.close()


func _delete_directory_recursive(path: String) -> bool:
	var absolute: String = ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return true
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return false
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child: String = path.path_join(entry)
			if directory.current_is_dir():
				if not _delete_directory_recursive(child):
					directory.list_dir_end()
					return false
			else:
				if directory.remove(entry) != OK:
					directory.list_dir_end()
					return false
		entry = directory.get_next()
	directory.list_dir_end()
	return DirAccess.remove_absolute(absolute) == OK


func _check(condition: bool, message: String) -> void:
	assert(condition, message)
