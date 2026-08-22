# SPDX-License-Identifier: GPL-3.0-or-later
extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_formula_editor_builds_completely()
	_test_formula_context_toolbar_builds()
	_test_asset_preview_overlay_builds()
	_test_module_api_contracts()
	_test_pdf_render_priority_queue()
	_test_formula_color_is_draw_time_tint()
	_test_tool_hint_settings_migration()
	_test_sidecar_utf16_decode()
	_test_sidecar_nul_padded_utf8_decode()
	_test_text_background_shader_source()
	print("NotLight Stage 10.1 Module API host UX/runtime regression smoke test passed.")
	quit(0)


func _test_formula_editor_builds_completely() -> void:
	var panel: FormulaEditorPanel = FormulaEditorPanel.new()
	root.add_child(panel)
	_check(panel.get("_apply_button") is Button, "FormulaEditorPanel _build_ui() aborted before creating the apply button")
	_check(panel.get("_details") is Label, "FormulaEditorPanel details label was not created")
	panel.free()


func _test_formula_context_toolbar_builds() -> void:
	var toolbar: FormulaContextToolbar = FormulaContextToolbar.new()
	root.add_child(toolbar)
	_check(toolbar.get("_mode_option") is OptionButton, "FormulaContextToolbar did not build its mode control")
	_check(toolbar.get("_color_button") is Button, "FormulaContextToolbar did not build its color control")
	toolbar.free()


func _test_asset_preview_overlay_builds() -> void:
	var overlay: AssetPreviewOverlay = AssetPreviewOverlay.new()
	root.add_child(overlay)
	_check(overlay.get("_seek") is HSlider, "AssetPreviewOverlay did not build its seek slider")
	_check(overlay.get("_play_button") is Button, "AssetPreviewOverlay did not build its transport controls")
	var seek: HSlider = overlay.get("_seek") as HSlider
	_check(seek != null and not seek.editable, "AssetPreviewOverlay seek slider must start non-editable")
	var page_input: LineEdit = overlay.get("_pdf_page_input") as LineEdit
	_check(page_input != null, "AssetPreviewOverlay did not build its direct PDF page input")
	_check(page_input.max_length == 6, "AssetPreviewOverlay PDF page input lost its bounded length")
	overlay.free()


func _test_module_api_contracts() -> void:
	var manifest_result: Dictionary = ModuleManifest.validate({
		"schema": "notlight.module",
		"schema_version": 1,
		"module_id": "notlight.smoke",
		"name": "Smoke module",
		"version": "1.2.3",
		"module_api_version": 1,
		"godot_version": "4.4.1",
		"kind": "code",
		"entry_point": "res:/" + "/modules/notlight.smoke/module_entry.gd",
		"state_schema_version": 1,
		"capabilities": ["board.instance_state", "localization.read", "theme.read"],
		"dependencies": [],
		"payload_key": "payload.pck",
		"localizations": {"ru": "localization/ru.json"},
	})
	_check(bool(manifest_result.get("ok", false)), "ModuleManifest rejected the canonical Module API v1 contract")
	var localization_result: Dictionary = ModuleLocalizationBundle.validate_source({
		"_meta": {"module_id": "notlight.smoke", "locale": "ru"},
		"strings": {
			"title": "Дымовой модуль",
			"value": "Значение {value}",
			"module.name": "Дымовой модуль",
			"module.description": "Каноническое описание",
		},
	}, "notlight.smoke", "ru", true)
	_check(bool(localization_result.get("ok", false)), "Module localization validator rejected canonical RU data")
	var localization_strings: Dictionary = localization_result.get("strings", {}) as Dictionary
	var registry: ModuleRegistry = ModuleRegistry.new()
	registry.set("_localization_bundles", {"notlight.smoke": {"ru": localization_strings.duplicate(true)}})
	_check(registry.module_text("notlight.smoke", "title", "en") == "Дымовой модуль", "ModuleRegistry lost canonical RU localization fallback")
	_check(registry.module_text("notlight.smoke", "value", "ru", {"value": 7}) == "Значение 7", "ModuleRegistry localization formatting failed")
	var manifest_metadata: Dictionary = {"name": "Manifest name", "description": "Manifest description"}
	var metadata_bundles: Dictionary = {
		"ru": localization_strings.duplicate(true),
		"en": {
			"module.name": "Smoke module",
			"module.description": "Localized description",
		},
	}
	_check(ModuleLocalizationBundle.resolve_manifest_text(manifest_metadata, metadata_bundles, "name", "en-US") == "Smoke module", "localized module manifest name did not use the requested locale")
	_check(ModuleLocalizationBundle.resolve_manifest_text(manifest_metadata, metadata_bundles, "description", "be") == "Каноническое описание", "localized module manifest description lost RU bundle fallback")
	_check(ModuleLocalizationBundle.resolve_manifest_text(manifest_metadata, {}, "description", "en") == "Manifest description", "localized module manifest description lost raw manifest fallback")
	var context: ModuleInstanceContext = ModuleInstanceContext.new()
	var context_host: ModuleInstanceStateHost = ModuleInstanceStateHost.new()
	context.configure("notlight.smoke", context_host, registry)
	_check(context.text("title") == "Дымовой модуль", "ModuleInstanceContext does not use the registry-owned localization bridge")
	var store: ModuleStore = ModuleStore.new()
	_check(store.add_module(42, "notlight.smoke", 1, {"value": 3.0}, "Smoke"), "ModuleStore rejected bounded canonical state")
	var serialized: Array[Dictionary] = store.serialize()
	var restored: ModuleStore = ModuleStore.new()
	restored.deserialize(serialized)
	_check(restored.contains(42), "ModuleStore round-trip lost a module object")
	_check(restored.get_state(42) == {"value": 3.0}, "ModuleStore round-trip changed module state")
	var unsafe_state: Dictionary = ModuleStore.normalize_state({"runtime_object": Vector2.ONE})
	_check(not bool(unsafe_state.get("ok", false)), "ModuleStore accepted a non-JSON runtime value")
	var portable: NotLightPortablePackageService = NotLightPortablePackageService.new()
	var document: Dictionary = BoardDocumentSchema.make_empty()
	var content: Dictionary = document.get("content", {}) as Dictionary
	content["module_objects"] = [{
		"entity_id": "42",
		"module_id": "notlight.smoke",
		"state_schema_version": 1,
		"instance_state": {"value": 3.0},
		"instance_title": "Smoke",
		"asset_ids": [],
	}]
	document["content"] = content
	_check(str(portable.call("_validate_board_module_records", document)).is_empty(), "Portable board preflight rejected a valid ModuleObject")
	var module_records: Array = content.get("module_objects", []) as Array
	var unsafe_record: Dictionary = module_records[0] as Dictionary
	unsafe_record["instance_state"] = {"runtime": Vector2.ONE}
	module_records[0] = unsafe_record
	content["module_objects"] = module_records
	document["content"] = content
	_check(not str(portable.call("_validate_board_module_records", document)).is_empty(), "Portable board preflight accepted unsafe ModuleObject state")
	var surface_pool: ModuleSurfacePool = ModuleSurfacePool.new()
	surface_pool.set_active_surface_budget(999)
	_check(surface_pool.max_active_surfaces == AppSettingsStore.MAX_MODULE_SURFACES, "Module surface budget did not clamp to the host safety ceiling")
	surface_pool.set_active_surface_budget(0)
	_check(surface_pool.max_active_surfaces == AppSettingsStore.MIN_MODULE_SURFACES, "Module surface budget did not preserve the minimum live surface")
	surface_pool.free()
	var picker: ModulePickerPanel = ModulePickerPanel.new()
	root.add_child(picker)
	_check(picker.get("_search_edit") is LineEdit, "Board Module Library drawer did not build search")
	_check(picker.theme_type_variation == &"LibraryDrawerPanel", "Board Module Library drawer lost the Resource Library visual contract")
	picker.free()
	var library_view: ModuleLibraryView = ModuleLibraryView.new()
	root.add_child(library_view)
	_check(library_view.get("_install_dialog") is FileDialog, "Module Library did not build its import dialog")
	_check(library_view.get("_trust_dialog") is ConfirmActionDialog, "Module Library did not build its trusted-code confirmation")
	_check(library_view.get("_search_edit") is LineEdit, "Module Library did not build its search field")
	_check(library_view.get("_status_filter") is OptionButton, "Module Library did not build its status filter")
	_check(library_view.get("_inspector") is ModuleLibraryInspector, "Module Library did not build its immutable detail inspector")
	var module_inspector: ModuleLibraryInspector = library_view.get("_inspector") as ModuleLibraryInspector
	module_inspector.show_module({
		"module_id": "notlight.smoke",
		"name": "Smoke module",
		"version": "1.0.0",
		"description": "Runtime inspector smoke",
		"active": true,
		"byte_size": 4096,
		"payload_byte_size": 2048,
		"module_api_version": 1,
		"godot_version": "4.4.1",
		"state_schema_version": 1,
		"kind": "code",
		"capabilities": ["board.instance_state"],
		"boards_used": [],
		"boards_used_count": 0,
		"payload_sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
		"source_package_sha256": "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
	}, null)
	_check(str((module_inspector.get("_module_id") as Label).text) == "notlight.smoke", "Module Library inspector lost manifest identity")
	library_view.free()


func _test_pdf_render_priority_queue() -> void:
	var worker: PdfRenderWorker = PdfRenderWorker.new()
	worker.call("_insert_by_priority", {"cache_key": "background", "priority": 0})
	worker.call("_insert_by_priority", {"cache_key": "prefetch", "priority": 20})
	worker.call("_insert_by_priority", {"cache_key": "current", "priority": 100})
	var queued: Array = worker.get("_queue") as Array
	_check(queued.size() == 3, "PdfRenderWorker priority smoke queue size mismatch")
	_check(str((queued[0] as Dictionary).get("cache_key", "")) == "current", "current PDF preview page was not prioritized")
	_check(str((queued[1] as Dictionary).get("cache_key", "")) == "prefetch", "PDF neighbor prefetch priority ordering failed")
	_check(str((queued[2] as Dictionary).get("cache_key", "")) == "background", "background PDF work outranked preview work")


func _test_formula_color_is_draw_time_tint() -> void:
	var service: FormulaRenderService = FormulaRenderService.new()
	var green: Dictionary = {
		"source_latex": "\\frac{3}{4}",
		"display_mode": FormulaStore.DISPLAY_BLOCK,
		"font_scale": 1.0,
		"foreground": Color("#24885a"),
	}
	var red: Dictionary = green.duplicate(true)
	red["foreground"] = Color("#ee5965")
	var green_key_data: Dictionary = service.call("_record_key_data", green) as Dictionary
	var red_key_data: Dictionary = service.call("_record_key_data", red) as Dictionary
	_check(green_key_data == red_key_data, "formula color leaked into the Typst/vector cache key")
	var wrapper: String = str(service.call("_build_typst_document", green))
	_check(wrapper.contains("#FFFFFF"), "formula wrapper no longer renders a neutral white mask")
	_check(not wrapper.contains("24885A"), "formula wrapper baked the canonical foreground into SVG output")


func _test_tool_hint_settings_migration() -> void:
	var store: AppSettingsStore = AppSettingsStore.new()
	var migrated: Dictionary = store.call("_migrate_settings_dictionary", {"schema_version": 10}) as Dictionary
	_check(int(migrated.get("schema_version", 0)) == AppSettingsStore.SETTINGS_SCHEMA_VERSION, "settings migration did not advance schema")
	_check(bool(migrated.get("show_tool_hints", false)), "v10 settings migration did not preserve visible tool hints")
	_check(int(migrated.get("custom_active_module_surfaces", 0)) == 3, "settings migration did not preserve the Stage 10 default module surface budget")
	_check(int(migrated.get("custom_active_note_workspace_surfaces", 0)) == AppSettingsStore.DEFAULT_NOTE_WORKSPACE_SURFACES, "settings migration did not preserve the Stage 11.3 default Notes workspace budget")
	_check(not bool(migrated.get("prefer_maximum_fps", true)), "settings migration unexpectedly enabled maximum-FPS preference")
	_check(not bool(migrated.get("custom_full_note_card_render", true)), "settings migration unexpectedly enabled full lightweight-note rendering")
	var fresh_snapshot: Dictionary = store.get_snapshot()
	_check(fresh_snapshot.has("prefer_maximum_fps"), "settings snapshot lost maximum-FPS preference")
	_check(fresh_snapshot.has("custom_full_note_card_render"), "settings snapshot lost lightweight-note render preference")
	var budget_store: AppSettingsStore = AppSettingsStore.new()
	budget_store.performance_profile = AppSettingsStore.PerformanceProfile.CUSTOM
	budget_store.set_custom_active_video_players(999)
	var budget: Dictionary = budget_store.get_performance_budget()
	_check(int(budget.get("active_video_players", 0)) == AppSettingsStore.MAX_VIDEO_PLAYERS, "custom video budget escaped its safety ceiling")
	budget_store.set_custom_active_module_surfaces(99)
	budget = budget_store.get_performance_budget()
	_check(int(budget.get("active_module_surfaces", 0)) == AppSettingsStore.MAX_MODULE_SURFACES, "custom module surface budget escaped its safety ceiling")
	budget_store.set_custom_active_note_workspace_surfaces(99)
	budget = budget_store.get_performance_budget()
	_check(
		int(budget.get("active_note_workspace_surfaces", 0)) == AppSettingsStore.MAX_NOTE_WORKSPACE_SURFACES,
		"custom Notes workspace surface budget escaped its safety ceiling"
	)
	budget_store.set_custom_full_note_card_render(true)
	budget = budget_store.get_performance_budget()
	_check(bool(budget.get("full_note_card_render", false)), "custom full lightweight-note rendering did not reach the effective budget")
	budget_store.free()


func _test_sidecar_utf16_decode() -> void:
	var runner: SidecarProcessRunner = SidecarProcessRunner.new()
	var expected: String = "battery 73%"
	var utf16: PackedByteArray = expected.to_utf16_buffer()
	var decoded: String = str(runner.call("_decode_text_capture", utf16))
	_check(decoded == expected, "SidecarProcessRunner UTF-16 pipe decoding failed")


func _test_sidecar_nul_padded_utf8_decode() -> void:
	var runner: SidecarProcessRunner = SidecarProcessRunner.new()
	var expected: String = "qpdf ready"
	var padded: PackedByteArray = expected.to_utf8_buffer()
	var original_size: int = padded.size()
	padded.resize(original_size + 3)
	var decoded: String = str(runner.call("_decode_text_capture", padded))
	_check(decoded == expected, "SidecarProcessRunner NUL-padded UTF-8 decoding failed")


func _test_text_background_shader_source() -> void:
	var file: FileAccess = FileAccess.open("res://assets/shaders/text_block_background.gdshader", FileAccess.READ)
	_check(file != null, "text-block background shader is missing")
	var source: String = file.get_as_text() if file != null else ""
	if file != null:
		file.close()
	_check(not source.contains("vec4 source_color"), "text-block shader still declares reserved source_color identifier")
	_check(source.contains("vec4 block_color = COLOR;"), "text-block shader runtime fix is missing")


func _check(condition: bool, message: String) -> void:
	assert(condition, message)
