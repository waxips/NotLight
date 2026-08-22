# SPDX-License-Identifier: GPL-3.0-or-later
class_name ModuleLibraryView
extends Control

signal error_requested(message: String)
signal info_requested(message: String)
signal module_preview_requested(module_id: String)

const PAGE_SIZE: int = 60
const CARD_WIDTH: float = ModuleLibraryCard.CARD_WIDTH
const CARD_SEPARATION: float = 12.0
const GRID_GUTTER: float = 8.0
const INSPECTOR_WIDTH: float = 480.0

var registry: ModuleRegistry
var packages: ModulePackageService
var repository: BoardRepository
var _install_dialog: FileDialog
var _remove_dialog: ConfirmActionDialog
var _trust_dialog: ConfirmActionDialog
var _pending_remove_id: String = ""
var _pending_install_paths: PackedStringArray = PackedStringArray()
var _summary_label: Label
var _search_edit: LineEdit
var _status_filter: OptionButton
var _grid: GridContainer
var _grid_host: Control
var _body: HBoxContainer
var _catalog_area: VBoxContainer
var _inspector_host: Control
var _inspector: ModuleLibraryInspector
var _selected_module_id: String = ""
var _empty_panel: PanelContainer
var _empty_title: Label
var _empty_body: Label
var _load_more_button: Button
var _visible_limit: int = PAGE_SIZE
var _artwork_cache: Dictionary = {}
var _search_debounce: Timer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_build_dialogs()
	_search_debounce = Timer.new()
	_search_debounce.one_shot = true
	_search_debounce.wait_time = 0.12
	_search_debounce.timeout.connect(_reset_filter_and_refresh)
	add_child(_search_debounce)
	resized.connect(_update_grid_columns)
	call_deferred("_update_grid_columns")
	NotLightL10n.connect_locale_changed(_on_locale_changed)


func _exit_tree() -> void:
	NotLightL10n.disconnect_locale_changed(_on_locale_changed)


func configure(module_registry: ModuleRegistry, package_service: ModulePackageService, board_repository: BoardRepository) -> void:
	if registry != null and registry.modules_changed.is_connected(_on_modules_changed):
		registry.modules_changed.disconnect(_on_modules_changed)
	registry = module_registry
	packages = package_service
	repository = board_repository
	if _inspector != null:
		_inspector.configure(registry)
	if registry != null and not registry.modules_changed.is_connected(_on_modules_changed):
		registry.modules_changed.connect(_on_modules_changed)
	_refresh()


func focus_search() -> void:
	if _search_edit != null:
		_search_edit.grab_focus()


func open_import_dialog() -> void:
	if _install_dialog != null:
		_install_dialog.popup_centered_ratio(0.72)


func handle_external_files(files: PackedStringArray) -> bool:
	if packages == null:
		return false
	var relevant: PackedStringArray = PackedStringArray()
	var summaries: PackedStringArray = PackedStringArray()
	for path: String in files:
		if path.get_extension().to_lower() != NotLightPortablePackageFormat.MODULE_EXTENSION:
			continue
		var inspected: Dictionary = packages.inspect_module(path)
		if not bool(inspected.get("ok", false)):
			error_requested.emit(str(inspected.get("error", NotLightL10n.text("runtime.ui.module_library_view.f062767444"))))
			continue
		var manifest: Dictionary = inspected.get("module_manifest", {}) as Dictionary
		relevant.append(path)
		var capabilities_value: Variant = manifest.get("capabilities", [])
		var capabilities: PackedStringArray = PackedStringArray()
		if capabilities_value is Array:
			for raw_capability: Variant in capabilities_value as Array:
				capabilities.append(str(raw_capability))
		summaries.append(NotLightL10n.text("ui.format.module_summary") % [
			str(manifest.get("name", manifest.get("module_id", "Module"))),
			str(manifest.get("version", "?")),
			str(manifest.get("module_id", "")),
			NotLightL10n.text("modules.library.trust_capabilities", {"capabilities": ", ".join(capabilities)}),
		])
	if relevant.is_empty():
		return false
	_pending_install_paths = relevant
	var body: String = NotLightL10n.text("modules.library.trust_body") + "\n\n" + "\n\n".join(summaries)
	_trust_dialog.open_dialog(
		NotLightL10n.text("modules.library.trust_title"),
		body,
		NotLightL10n.text("modules.library.trust_install"),
		false
	)
	return true


func _build_ui() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 14)
	add_child(root)

	var toolbar: HBoxContainer = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 10)
	root.add_child(toolbar)
	var beta: Label = Label.new()
	NotLightL10n.bind_text(beta, "modules.library.beta")
	beta.theme_type_variation = "SettingsValueLabel"
	toolbar.add_child(beta)
	_summary_label = Label.new()
	_summary_label.theme_type_variation = "BodyMutedLabel"
	_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_summary_label)
	var install: Button = Button.new()
	NotLightL10n.bind_text(install, "modules.library.install")
	install.theme_type_variation = "PrimaryButton"
	install.custom_minimum_size = Vector2(178.0, 42.0)
	install.pressed.connect(open_import_dialog)
	toolbar.add_child(install)

	var filters: HBoxContainer = HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	root.add_child(filters)
	_search_edit = LineEdit.new()
	NotLightL10n.bind_placeholder_text(_search_edit, "modules.library.search")
	_search_edit.clear_button_enabled = true
	_search_edit.custom_minimum_size = Vector2(280.0, 40.0)
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.text_changed.connect(_queue_search_refresh)
	filters.add_child(_search_edit)
	_status_filter = OptionButton.new()
	_status_filter.custom_minimum_size = Vector2(190.0, 40.0)
	_status_filter.add_item(NotLightL10n.text("modules.library.filter_all"), 0)
	_status_filter.add_item(NotLightL10n.text("modules.library.filter_active"), 1)
	_status_filter.add_item(NotLightL10n.text("modules.library.filter_restart"), 2)
	_status_filter.add_item(NotLightL10n.text("modules.library.filter_remove"), 3)
	_status_filter.item_selected.connect(func(_index: int) -> void: _on_filter_changed(""))
	filters.add_child(_status_filter)

	_body = HBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.clip_contents = true
	_body.add_theme_constant_override("separation", 14)
	root.add_child(_body)

	_catalog_area = VBoxContainer.new()
	_catalog_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalog_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_catalog_area.add_theme_constant_override("separation", 10)
	_body.add_child(_catalog_area)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_catalog_area.add_child(scroll)
	var margin: MarginContainer = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", int(GRID_GUTTER))
	scroll.add_child(margin)
	var scroll_body: VBoxContainer = VBoxContainer.new()
	scroll_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_body.add_theme_constant_override("separation", 12)
	margin.add_child(scroll_body)

	_grid_host = Control.new()
	_grid_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_host.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	scroll_body.add_child(_grid_host)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", int(CARD_SEPARATION))
	_grid.add_theme_constant_override("v_separation", int(CARD_SEPARATION))
	_grid_host.add_child(_grid)
	_grid.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_grid_host.resized.connect(_update_grid_columns)

	_empty_panel = PanelContainer.new()
	_empty_panel.theme_type_variation = "CardPanel"
	_empty_panel.custom_minimum_size = Vector2(0.0, 210.0)
	scroll_body.add_child(_empty_panel)
	var center: CenterContainer = CenterContainer.new()
	_empty_panel.add_child(center)
	var empty_box: VBoxContainer = VBoxContainer.new()
	empty_box.custom_minimum_size = Vector2(420.0, 0.0)
	empty_box.add_theme_constant_override("separation", 8)
	center.add_child(empty_box)
	var mark: Label = Label.new()
	mark.text = "◇"
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.add_theme_font_size_override("font_size", 34)
	mark.add_theme_color_override("font_color", NotLightTheme.semantic_color("accent"))
	empty_box.add_child(mark)
	_empty_title = Label.new()
	NotLightL10n.bind_text(_empty_title, "modules.library.empty_title")
	_empty_title.theme_type_variation = "TitleLabel"
	_empty_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_box.add_child(_empty_title)
	_empty_body = Label.new()
	NotLightL10n.bind_text(_empty_body, "modules.library.empty_body")
	_empty_body.theme_type_variation = "BodyMutedLabel"
	_empty_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty_box.add_child(_empty_body)

	_load_more_button = Button.new()
	_load_more_button.theme_type_variation = "GhostButton"
	_load_more_button.custom_minimum_size = Vector2(0.0, 40.0)
	_load_more_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_load_more_button.pressed.connect(_load_more)
	_catalog_area.add_child(_load_more_button)

	_inspector_host = Control.new()
	_inspector_host.visible = false
	_inspector_host.size_flags_horizontal = Control.SIZE_SHRINK_END
	_inspector_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspector_host.custom_minimum_size = Vector2(INSPECTOR_WIDTH, 0.0)
	_inspector_host.clip_contents = true
	_body.add_child(_inspector_host)
	_inspector = ModuleLibraryInspector.new()
	_inspector.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inspector.configure(registry)
	_inspector.close_requested.connect(_close_inspector)
	_inspector.preview_requested.connect(_on_module_preview_requested)
	_inspector.remove_requested.connect(_ask_remove)
	_inspector.cancel_remove_requested.connect(_cancel_remove)
	_inspector_host.add_child(_inspector)


func _build_dialogs() -> void:
	_install_dialog = FileDialog.new()
	_install_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_install_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_install_dialog.use_native_dialog = true
	_install_dialog.filters = PackedStringArray(["*.notlight-module;%s;application/octet-stream" % NotLightL10n.text("file_filter.module_package")])
	_install_dialog.files_selected.connect(_on_files_selected)
	add_child(_install_dialog)
	_remove_dialog = ConfirmActionDialog.new()
	_remove_dialog.confirmed.connect(_confirm_remove)
	add_child(_remove_dialog)
	_trust_dialog = ConfirmActionDialog.new()
	_trust_dialog.confirmed.connect(_confirm_install)
	add_child(_trust_dialog)


func _refresh() -> void:
	if _grid == null:
		return
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var modules: Array[Dictionary] = []
	if registry != null:
		modules = registry.list_modules()
	modules.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("name", left.get("module_id", ""))).naturalnocasecmp_to(str(right.get("name", right.get("module_id", "")))) < 0
	)
	var total_size: int = 0
	for info: Dictionary in modules:
		total_size += int(info.get("byte_size", 0))
	var query: String = _search_edit.text.strip_edges().to_lower() if _search_edit != null else ""
	var status_id: int = _status_filter.get_item_id(_status_filter.selected) if _status_filter != null and _status_filter.selected >= 0 else 0
	var matching: Array[Dictionary] = []
	for info: Dictionary in modules:
		var haystack: String = "%s\n%s\n%s\n%s\n%s" % [str(info.get("name", "")), str(info.get("module_id", "")), str(info.get("description", "")), str(info.get("author", "")), str(info.get("homepage", ""))]
		if not query.is_empty() and not haystack.to_lower().contains(query):
			continue
		if not _matches_status_filter(info, status_id):
			continue
		matching.append(info)
	_empty_panel.visible = matching.is_empty()
	_grid_host.visible = not matching.is_empty()
	if _empty_title != null and _empty_body != null:
		if modules.is_empty():
			NotLightL10n.bind_text(_empty_title, "modules.library.empty_title")
			NotLightL10n.bind_text(_empty_body, "modules.library.empty_body")
		else:
			NotLightL10n.bind_text(_empty_title, "common.nothing_found")
			NotLightL10n.bind_text(_empty_body, "modules.library.no_results")
	var shown: int = mini(_visible_limit, matching.size())
	for index: int in range(shown):
		var info: Dictionary = matching[index]
		var card: ModuleLibraryCard = ModuleLibraryCard.new()
		card.inspect_requested.connect(_open_inspector)
		_grid.add_child(card)
		card.configure(info, _artwork_texture_for(info))
		card.set_selected(str(info.get("module_id", "")) == _selected_module_id)
	_load_more_button.visible = shown < matching.size()
	if _load_more_button.visible:
		_load_more_button.text = NotLightL10n.text("common.show_more_remaining", {"count": matching.size() - shown})
	_summary_label.text = NotLightL10n.text("modules.library.summary", {
		"count": modules.size(),
		"size": _format_bytes(total_size),
	})
	_update_grid_columns()
	_sync_inspector()


func _open_inspector(module_id: String) -> void:
	if registry == null or _inspector == null or _inspector_host == null:
		return
	var info: Dictionary = registry.get_known_module_info(module_id)
	if info.is_empty():
		_close_inspector()
		return
	_selected_module_id = module_id
	_inspector.show_module(info, _artwork_texture_for(info))
	_inspector_host.visible = true
	_update_card_selection()
	_update_grid_columns()


func _on_module_preview_requested(module_id: String) -> void:
	if module_id.strip_edges().is_empty():
		return
	module_preview_requested.emit(module_id.strip_edges().to_lower())


func _close_inspector() -> void:
	_selected_module_id = ""
	if _inspector != null:
		_inspector.clear_module()
	if _inspector_host != null:
		_inspector_host.visible = false
	_update_card_selection()
	_update_grid_columns()


func _update_card_selection() -> void:
	if _grid == null:
		return
	for child: Node in _grid.get_children():
		if child is ModuleLibraryCard:
			var card: ModuleLibraryCard = child as ModuleLibraryCard
			card.set_selected(str(card.get_meta("module_id", "")) == _selected_module_id)


func _sync_inspector() -> void:
	if _selected_module_id.is_empty():
		return
	if registry == null:
		_close_inspector()
		return
	var info: Dictionary = registry.get_known_module_info(_selected_module_id)
	if info.is_empty():
		_close_inspector()
		return
	if _inspector != null:
		_inspector.show_module(info, _artwork_texture_for(info))
	if _inspector_host != null:
		_inspector_host.visible = true


func _matches_status_filter(info: Dictionary, filter_id: int) -> bool:
	match filter_id:
		1:
			return bool(info.get("active", false)) and not bool(info.get("pending_remove", false))
		2:
			return not str(info.get("pending_version_key", "")).is_empty()
		3:
			return bool(info.get("pending_remove", false))
		_:
			return true


func _artwork_texture_for(info: Dictionary) -> Texture2D:
	var path: String = str(info.get("preview_path", ""))
	if path.is_empty():
		path = str(info.get("icon_path", ""))
	if path.is_empty():
		return null
	var cached_value: Variant = _artwork_cache.get(path)
	if cached_value is Texture2D:
		return cached_value as Texture2D
	var texture: Texture2D = ModuleArtworkLoader.load_texture(path)
	if texture != null:
		_artwork_cache[path] = texture
	return texture


func _update_grid_columns() -> void:
	if _grid == null or _grid_host == null:
		return
	var available: float = maxf(CARD_WIDTH, _grid_host.size.x - GRID_GUTTER)
	var span: float = CARD_WIDTH + CARD_SEPARATION
	_grid.columns = clampi(int(floor((available + CARD_SEPARATION) / span)), 1, 6)
	# GridContainer is inside a plain host so its own calculated minimum height can
	# drive scrolling without feeding its width back into the column calculation.
	var minimum_height: float = _grid.get_combined_minimum_size().y
	# _grid uses PRESET_TOP_WIDE, so its horizontal size is anchor-driven. Assigning
	# Control.size here makes Godot 4.4.1 warn because opposite anchors differ.
	# Only the vertical offsets are manual; width remains owned by the anchors.
	_grid.offset_bottom = minimum_height
	_grid_host.custom_minimum_size.y = minimum_height


func _on_modules_changed() -> void:
	_refresh()


func _queue_search_refresh(_value: String) -> void:
	if _search_debounce == null:
		_reset_filter_and_refresh()
		return
	_search_debounce.start()


func _on_filter_changed(_value: String) -> void:
	_reset_filter_and_refresh()


func _reset_filter_and_refresh() -> void:
	_visible_limit = PAGE_SIZE
	_refresh()


func _load_more() -> void:
	_visible_limit += PAGE_SIZE
	_refresh()


func _on_files_selected(paths: PackedStringArray) -> void:
	handle_external_files(paths)


func _confirm_install() -> void:
	if packages == null or _pending_install_paths.is_empty():
		return
	var paths: PackedStringArray = _pending_install_paths.duplicate()
	_pending_install_paths = PackedStringArray()
	var result: Dictionary = packages.install_external_files(paths)
	var installed: int = int(result.get("installed", 0))
	var errors_value: Variant = result.get("errors", [])
	if installed > 0:
		info_requested.emit(NotLightL10n.text("modules.library.install_done", {"count": installed}))
	if errors_value is Array and not (errors_value as Array).is_empty():
		var errors: PackedStringArray = PackedStringArray()
		for raw_error: Variant in errors_value as Array:
			errors.append(str(raw_error))
		error_requested.emit("\n".join(errors))
	_refresh()


func _ask_remove(module_id: String, module_name: String, board_count: int) -> void:
	_pending_remove_id = module_id
	_remove_dialog.open_dialog(
		NotLightL10n.text("modules.library.remove_title"),
		NotLightL10n.text("modules.library.remove_body", {"name": module_name, "boards": board_count}),
		NotLightL10n.text("modules.library.remove"),
		true
	)


func _confirm_remove() -> void:
	if registry == null or _pending_remove_id.is_empty():
		return
	var module_id: String = _pending_remove_id
	_pending_remove_id = ""
	if not registry.request_remove(module_id):
		error_requested.emit(registry.get_last_error())
		return
	info_requested.emit(NotLightL10n.text("modules.library.remove_restart"))
	_refresh()


func _cancel_remove(module_id: String) -> void:
	if registry != null and not registry.cancel_pending_remove(module_id):
		error_requested.emit(registry.get_last_error())
	_refresh()


func _on_locale_changed(_locale: String) -> void:
	NotLightL10n.refresh_tree(self)
	if _status_filter != null:
		var selected_id: int = _status_filter.get_item_id(_status_filter.selected) if _status_filter.selected >= 0 else 0
		_status_filter.set_item_text(0, NotLightL10n.text("modules.library.filter_all"))
		_status_filter.set_item_text(1, NotLightL10n.text("modules.library.filter_active"))
		_status_filter.set_item_text(2, NotLightL10n.text("modules.library.filter_restart"))
		_status_filter.set_item_text(3, NotLightL10n.text("modules.library.filter_remove"))
		for index: int in range(_status_filter.item_count):
			if _status_filter.get_item_id(index) == selected_id:
				_status_filter.select(index)
				break
	_refresh()


static func _format_bytes(byte_size: int) -> String:
	var value: float = float(maxi(0, byte_size))
	if value < 1024.0:
		return NotLightL10n.text("ui.format.bytes_b") % int(value)
	value /= 1024.0
	if value < 1024.0:
		return NotLightL10n.text("ui.format.bytes_kib") % value
	value /= 1024.0
	if value < 1024.0:
		return NotLightL10n.text("ui.format.bytes_mib") % value
	return NotLightL10n.text("ui.format.bytes_gib") % (value / 1024.0)
