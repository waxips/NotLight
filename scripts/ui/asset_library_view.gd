# SPDX-License-Identifier: GPL-3.0-or-later
class_name AssetLibraryView
extends Control

signal request_close
signal error_requested(message: String)
signal info_requested(message: String)
signal asset_insert_requested(asset_id: String)
signal note_workspace_insert_requested(asset_id: String)
signal asset_preview_requested(asset_id: String)
signal notes_graph_requested

var compact_mode: bool = false
var library: AssetLibraryService
var image_cache: ImageAssetCache
var video_media: VideoMediaService
var audio_media: AudioMediaService
var pdf_media: PdfMediaService
var pdf_optimizer: PdfOptimizationService
var settings: AppSettingsStore
var portable_packages: NotLightPortablePackageService
var _search_edit: LineEdit
var _kind_filter: OptionButton
var _usage_filter: OptionButton
var _tag_filter: OptionButton
var _grid: GridContainer
var _body: HBoxContainer
var _asset_host: Control
var _asset_area: VBoxContainer
var _inspector_host: Control
var _inspector: AssetInspectorPanel
var _selected_asset_id: String = ""
var _selected_asset_ids: Dictionary = {}
var _selection_anchor_id: String = ""
var _current_asset_order: PackedStringArray = PackedStringArray()
var _bulk_bar: PanelContainer
var _bulk_count_label: Label
var _export_selected_asset_ids: PackedStringArray = PackedStringArray()
var _library_export_include_notes: bool = true
var _pending_bulk_move: bool = false
var _count_label: Label
var _stats_label: Label
var _folder_caption: Label
var _folder_tree: Tree
var _collapsed_folder_ids: Dictionary = {}
var _folder_tree_rebuild_pending: bool = false
var _folder_panel: PanelContainer
var _empty_panel: PanelContainer
var _empty_title: Label
var _empty_description: Label
var _import_dialog: FileDialog
var _import_preflight_dialog: AssetImportPreflightDialog
var _active_preflight_request_id: String = ""
var _preflight_target_folder_id: String = ""
var _preflight_target_folder_label: String = ""
var _package_import_dialog: FileDialog
var _package_export_dialog: FileDialog
var _exchange_button: MenuButton
var _folder_name_dialog: NameDialog
var _asset_name_dialog: NameDialog
var _confirm_dialog: ConfirmActionDialog
var _move_dialog: AssetFolderPickerDialog
var _progress_panel: PanelContainer
var _progress_label: Label
var _progress_bar: ProgressBar
var _import_cancel_button: Button
var _load_more_button: Button
var _search_debounce: Timer
var _selected_folder_id: String = AssetLibraryService.FOLDER_ANY
var _pending_asset_id: String = ""
var _pending_folder_id: String = ""
var _pending_folder_parent_id: String = ""
var _folder_dialog_mode: int = 0
var _cleanup_stage: int = 0
var _visible_asset_limit: int = 120

const FULL_PAGE_SIZE: int = 120
const COMPACT_PAGE_SIZE: int = 48
const FULL_FOLDER_WIDTH: float = 216.0
const FULL_INSPECTOR_WIDTH: float = 348.0
const FULL_INSPECTOR_MIN_WIDTH: float = 300.0
const FULL_BODY_SEPARATION: float = 14.0
const FULL_CARD_WIDTH: float = 228.0
const FULL_CARD_SEPARATION: float = 12.0
const FULL_GRID_CONTENT_GUTTER: float = 28.0
const FULL_MIN_COLUMNS_WITH_INSPECTOR: int = 2
const FULL_MIN_COLUMNS_WITH_FOLDER_AND_INSPECTOR: int = 3
const FOLDER_DIALOG_NONE: int = 0
const FOLDER_DIALOG_CREATE: int = 1
const FOLDER_DIALOG_RENAME: int = 2


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	_visible_asset_limit = COMPACT_PAGE_SIZE if compact_mode else FULL_PAGE_SIZE
	_build_ui()
	_build_dialogs()
	_search_debounce = Timer.new()
	_search_debounce.one_shot = true
	_search_debounce.wait_time = 0.12
	_search_debounce.timeout.connect(_reset_paging_and_refresh)
	add_child(_search_debounce)
	resized.connect(_update_grid_columns)
	call_deferred("_update_grid_columns")
	NotLightL10n.connect_locale_changed(_on_locale_changed)
	if not compact_mode:
		var window: Window = get_window()
		if window != null and not window.files_dropped.is_connected(_on_library_files_dropped):
			window.files_dropped.connect(_on_library_files_dropped)


func set_compact_mode(enabled: bool) -> void:
	compact_mode = enabled


func configure(
	asset_library: AssetLibraryService,
	cache: ImageAssetCache = null,
	media: VideoMediaService = null,
	app_settings: AppSettingsStore = null,
	audio_service: AudioMediaService = null,
	package_service: NotLightPortablePackageService = null,
	pdf_service: PdfMediaService = null,
	pdf_optimization_service: PdfOptimizationService = null
) -> void:
	library = asset_library
	image_cache = cache
	video_media = media
	audio_media = audio_service
	pdf_media = pdf_service
	pdf_optimizer = pdf_optimization_service
	settings = app_settings
	portable_packages = package_service
	_apply_page_budget()
	if _inspector != null:
		_inspector.configure(library, pdf_media, pdf_optimizer, not compact_mode)
	if library == null:
		return
	if not library.is_available():
		_show_error(NotLightL10n.text("library.error.unavailable", {"error": library.get_last_error()}))
	if not library.library_changed.is_connected(_on_library_changed):
		library.library_changed.connect(_on_library_changed)
	if not library.asset_metadata_changed.is_connected(_on_asset_metadata_changed):
		library.asset_metadata_changed.connect(_on_asset_metadata_changed)
	if not library.folders_changed.is_connected(_refresh_folders):
		library.folders_changed.connect(_refresh_folders)
	if not library.references_changed.is_connected(_refresh):
		library.references_changed.connect(_refresh)
	if not library.import_progress.is_connected(_on_import_progress):
		library.import_progress.connect(_on_import_progress)
	if not library.import_finished.is_connected(_on_import_finished):
		library.import_finished.connect(_on_import_finished)
	if not library.import_failed.is_connected(_on_import_failed):
		library.import_failed.connect(_on_import_failed)
	if not library.import_queue_changed.is_connected(_on_import_queue_changed):
		library.import_queue_changed.connect(_on_import_queue_changed)
	if not library.import_preflight_progress.is_connected(_on_import_preflight_progress):
		library.import_preflight_progress.connect(_on_import_preflight_progress)
	if not library.import_preflight_completed.is_connected(_on_import_preflight_completed):
		library.import_preflight_completed.connect(_on_import_preflight_completed)
	if not library.import_preflight_cancelled.is_connected(_on_import_preflight_cancelled):
		library.import_preflight_cancelled.connect(_on_import_preflight_cancelled)
	if not library.import_preflight_failed.is_connected(_on_import_preflight_failed):
		library.import_preflight_failed.connect(_on_import_preflight_failed)
	if not library.library_error.is_connected(_show_error):
		library.library_error.connect(_show_error)
	_refresh_tag_filter()
	_refresh_folders()
	_refresh()


func focus_search() -> void:
	if _search_edit != null:
		_search_edit.grab_focus()


func _build_ui() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	_build_header(root)
	_build_filters(root)

	_body = HBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.clip_contents = true
	_body.add_theme_constant_override("separation", int(FULL_BODY_SEPARATION))
	root.add_child(_body)

	if not compact_mode:
		_build_folder_sidebar(_body)
	_build_asset_area(_body)
	_build_inspector(_body)
	_build_progress(root)


func _build_header(parent: VBoxContainer) -> void:
	if compact_mode:
		# The board drawer is intentionally narrow. Keep title/close and import on
		# separate rows so localized labels never escape past the viewport edge.
		var title_row: HBoxContainer = HBoxContainer.new()
		title_row.add_theme_constant_override("separation", 8)
		parent.add_child(title_row)
		var title_box: VBoxContainer = VBoxContainer.new()
		title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_box.add_theme_constant_override("separation", 1)
		title_row.add_child(title_box)
		var title: Label = Label.new()
		NotLightL10n.bind_text(title, "library.title")
		title.theme_type_variation = "SectionLabel"
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title_box.add_child(title)
		_folder_caption = Label.new()
		NotLightL10n.bind_text(_folder_caption, "library.folder.all")
		_folder_caption.theme_type_variation = "CaptionLabel"
		_folder_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title_box.add_child(_folder_caption)
		var close_button: Button = Button.new()
		close_button.icon = load("res://assets/icons/close.svg") as Texture2D
		NotLightL10n.bind_tooltip(close_button, "library.close")
		close_button.theme_type_variation = "IconButton"
		close_button.custom_minimum_size = Vector2(38.0, 38.0)
		close_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		close_button.pressed.connect(func() -> void: request_close.emit())
		title_row.add_child(close_button)

		var import_button: Button = Button.new()
		NotLightL10n.bind_text(import_button, "library.import_short")
		import_button.icon = load("res://assets/icons/import.svg") as Texture2D
		NotLightL10n.bind_tooltip(import_button, "library.import_help")
		import_button.theme_type_variation = "PrimaryButton"
		import_button.custom_minimum_size = Vector2(0.0, 40.0)
		import_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		import_button.pressed.connect(_open_import_dialog)
		parent.add_child(import_button)
		var graph_button: Button = Button.new()
		NotLightL10n.bind_text(graph_button, "notes.graph.open")
		graph_button.theme_type_variation = "GhostButton"
		graph_button.custom_minimum_size = Vector2(0.0, 38.0)
		graph_button.pressed.connect(func() -> void: notes_graph_requested.emit())
		parent.add_child(graph_button)
		return

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var summary: VBoxContainer = VBoxContainer.new()
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_theme_constant_override("separation", 2)
	row.add_child(summary)
	_count_label = Label.new()
	_count_label.text = NotLightL10n.text("library.resources", {"count": 0})
	_count_label.theme_type_variation = "SectionLabel"
	summary.add_child(_count_label)
	_stats_label = Label.new()
	NotLightL10n.bind_text(_stats_label, "library.storage.local")
	_stats_label.theme_type_variation = "CaptionLabel"
	_stats_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	summary.add_child(_stats_label)

	var import_button: Button = Button.new()
	NotLightL10n.bind_text(import_button, "library.import")
	import_button.icon = load("res://assets/icons/import.svg") as Texture2D
	NotLightL10n.bind_tooltip(import_button, "library.import_help")
	import_button.theme_type_variation = "PrimaryButton"
	import_button.custom_minimum_size = Vector2(154.0, 40.0)
	import_button.pressed.connect(_open_import_dialog)
	row.add_child(import_button)
	var graph_button: Button = Button.new()
	NotLightL10n.bind_text(graph_button, "notes.graph.open")
	graph_button.theme_type_variation = "GhostButton"
	graph_button.custom_minimum_size = Vector2(118.0, 40.0)
	graph_button.pressed.connect(func() -> void: notes_graph_requested.emit())
	row.add_child(graph_button)
	_exchange_button = MenuButton.new()
	NotLightL10n.bind_text(_exchange_button, "exchange.library.menu")
	_exchange_button.icon = load("res://assets/icons/save.svg") as Texture2D
	NotLightL10n.bind_tooltip(_exchange_button, "exchange.library.menu_help")
	_exchange_button.theme_type_variation = "GhostButton"
	_exchange_button.custom_minimum_size = Vector2(126.0, 40.0)
	_refresh_exchange_menu_labels()
	_exchange_button.get_popup().id_pressed.connect(_on_exchange_menu_action)
	row.add_child(_exchange_button)


func _build_filters(parent: VBoxContainer) -> void:
	if compact_mode:
		var compact_stack: VBoxContainer = VBoxContainer.new()
		compact_stack.add_theme_constant_override("separation", 8)
		parent.add_child(compact_stack)
		_search_edit = _make_search_edit()
		_search_edit.custom_minimum_size = Vector2(0.0, 42.0)
		compact_stack.add_child(_search_edit)
		var compact_row: HBoxContainer = HBoxContainer.new()
		compact_row.clip_contents = true
		compact_row.add_theme_constant_override("separation", 7)
		compact_stack.add_child(compact_row)
		_kind_filter = _make_kind_filter()
		_kind_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_kind_filter.custom_minimum_size = Vector2(0.0, 42.0)
		compact_row.add_child(_kind_filter)
		_usage_filter = _make_usage_filter()
		_usage_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_usage_filter.custom_minimum_size = Vector2(0.0, 42.0)
		compact_row.add_child(_usage_filter)
		var folder_button: Button = Button.new()
		folder_button.icon = load("res://assets/icons/folder.svg") as Texture2D
		NotLightL10n.bind_tooltip(folder_button, "library.folder.switch")
		folder_button.theme_type_variation = "IconButton"
		folder_button.custom_minimum_size = Vector2(42.0, 42.0)
		folder_button.pressed.connect(_cycle_compact_folder)
		compact_row.add_child(folder_button)
		_tag_filter = _make_tag_filter()
		_tag_filter.custom_minimum_size = Vector2(0.0, 42.0)
		_tag_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		compact_stack.add_child(_tag_filter)
		return

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	_search_edit = _make_search_edit()
	row.add_child(_search_edit)
	_kind_filter = _make_kind_filter()
	row.add_child(_kind_filter)
	_usage_filter = _make_usage_filter()
	row.add_child(_usage_filter)
	_tag_filter = _make_tag_filter()
	row.add_child(_tag_filter)


func _make_search_edit() -> LineEdit:
	var search_edit: LineEdit = LineEdit.new()
	NotLightL10n.bind_placeholder_text(search_edit, "library.search.help")
	search_edit.clear_button_enabled = true
	search_edit.right_icon = load("res://assets/icons/search.svg") as Texture2D
	search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_edit.custom_minimum_size = Vector2(150.0, 42.0)
	search_edit.text_changed.connect(_on_search_text_changed)
	return search_edit


func _make_kind_filter() -> OptionButton:
	var option: OptionButton = OptionButton.new()
	_kind_filter = option
	option.theme_type_variation = "SettingsOptionButton"
	option.clip_text = true
	option.custom_minimum_size = Vector2(122.0, 42.0)
	_add_kind_filter_item(NotLightL10n.text("library.kind.all"), AssetKinds.ANY)
	_add_kind_filter_item(NotLightL10n.text("asset.kind.image_plural"), AssetKinds.IMAGE)
	_add_kind_filter_item(NotLightL10n.text("asset.kind.video_plural"), AssetKinds.VIDEO)
	_add_kind_filter_item(NotLightL10n.text("asset.kind.audio_plural"), AssetKinds.AUDIO)
	_add_kind_filter_item(NotLightL10n.text("asset.kind.pdf_plural"), AssetKinds.PDF)
	_add_kind_filter_item(NotLightL10n.text("asset.kind.note_plural"), AssetKinds.NOTE)
	_add_kind_filter_item(NotLightL10n.text("library.kind.3d"), AssetKinds.MODEL_3D)
	option.item_selected.connect(func(_index: int) -> void: _reset_paging_and_refresh())
	return option


func _make_usage_filter() -> OptionButton:
	var option: OptionButton = OptionButton.new()
	option.theme_type_variation = "SettingsOptionButton"
	option.clip_text = true
	option.custom_minimum_size = Vector2(132.0, 42.0)
	option.add_item(NotLightL10n.text("library.usage.any"))
	option.set_item_metadata(0, AssetLibraryService.USAGE_ALL)
	option.add_item(NotLightL10n.text("library.usage.used"))
	option.set_item_metadata(1, AssetLibraryService.USAGE_USED)
	option.add_item(NotLightL10n.text("library.usage.unused"))
	option.set_item_metadata(2, AssetLibraryService.USAGE_UNUSED)
	option.item_selected.connect(func(_index: int) -> void: _reset_paging_and_refresh())
	return option


func _make_tag_filter() -> OptionButton:
	var option: OptionButton = OptionButton.new()
	option.theme_type_variation = "SettingsOptionButton"
	option.clip_text = true
	option.custom_minimum_size = Vector2(138.0, 42.0)
	option.add_item(NotLightL10n.text("library.filter.tags_all"))
	option.set_item_metadata(0, "")
	option.item_selected.connect(func(_index: int) -> void: _reset_paging_and_refresh())
	return option


func _refresh_tag_filter() -> void:
	if _tag_filter == null or library == null:
		return
	var selected_tag: String = ""
	if _tag_filter.selected >= 0:
		selected_tag = str(_tag_filter.get_item_metadata(_tag_filter.selected))
	_tag_filter.clear()
	_tag_filter.add_item(NotLightL10n.text("library.filter.tags_all"))
	_tag_filter.set_item_metadata(0, "")
	var selected_index: int = 0
	for entry: Dictionary in library.list_tags():
		var tag: String = str(entry.get("tag", ""))
		var normalized: String = str(entry.get("normalized", tag.to_lower()))
		_tag_filter.add_item(NotLightL10n.text("ui.format.tag_count") % [tag, int(entry.get("count", 0))])
		var index: int = _tag_filter.item_count - 1
		_tag_filter.set_item_metadata(index, normalized)
		if normalized == selected_tag:
			selected_index = index
	_tag_filter.select(selected_index)


func _build_folder_sidebar(parent: HBoxContainer) -> void:
	_folder_panel = PanelContainer.new()
	_folder_panel.theme_type_variation = "AssetFolderPanel"
	_folder_panel.custom_minimum_size = Vector2(FULL_FOLDER_WIDTH, 0.0)
	_folder_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_folder_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(_folder_panel)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	_folder_panel.add_child(root)
	var title_row: HBoxContainer = HBoxContainer.new()
	root.add_child(title_row)
	var title: Label = Label.new()
	NotLightL10n.bind_text(title, "library.folders")
	title.theme_type_variation = "SectionLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var add_button: Button = Button.new()
	add_button.text = "+"
	NotLightL10n.bind_tooltip(add_button, "library.folder.new")
	add_button.theme_type_variation = "IconButton"
	add_button.custom_minimum_size = Vector2(34.0, 34.0)
	add_button.pressed.connect(_open_create_folder_dialog)
	title_row.add_child(add_button)
	_folder_tree = Tree.new()
	_folder_tree.theme_type_variation = "AssetFolderTree"
	_folder_tree.hide_root = true
	_folder_tree.columns = 1
	_folder_tree.select_mode = Tree.SELECT_ROW
	_folder_tree.set_column_expand(0, true)
	_folder_tree.set_column_clip_content(0, true)
	_folder_tree.scroll_horizontal_enabled = false
	_folder_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_folder_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_folder_tree.custom_minimum_size = Vector2(0.0, 180.0)
	_folder_tree.item_selected.connect(_on_folder_tree_selected)
	_folder_tree.item_collapsed.connect(_on_folder_tree_item_collapsed)
	root.add_child(_folder_tree)
	var separator: HSeparator = HSeparator.new()
	root.add_child(separator)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	root.add_child(actions)
	var rename: Button = Button.new()
	NotLightL10n.bind_text(rename, "common.rename_short")
	NotLightL10n.bind_tooltip(rename, "library.folder.rename_help")
	rename.theme_type_variation = "GhostButton"
	rename.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rename.pressed.connect(_open_rename_folder_dialog)
	actions.add_child(rename)
	var remove: Button = Button.new()
	NotLightL10n.bind_text(remove, "common.delete")
	NotLightL10n.bind_tooltip(remove, "library.folder.delete_help")
	remove.theme_type_variation = "GhostDangerButton"
	remove.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	remove.pressed.connect(_open_delete_folder_dialog)
	actions.add_child(remove)
	var cleanup: Button = Button.new()
	NotLightL10n.bind_text(cleanup, "library.cleanup_unused")
	NotLightL10n.bind_tooltip(cleanup, "library.cleanup_unused_help")
	cleanup.theme_type_variation = "GhostDangerButton"
	cleanup.pressed.connect(_start_cleanup_unused)
	root.add_child(cleanup)
	var clear_cache: Button = Button.new()
	NotLightL10n.bind_text(clear_cache, "library.clear_cache")
	NotLightL10n.bind_tooltip(clear_cache, "library.clear_cache_help")
	clear_cache.theme_type_variation = "GhostButton"
	clear_cache.pressed.connect(_start_clear_cache)
	root.add_child(clear_cache)
	var audit: Button = Button.new()
	NotLightL10n.bind_text(audit, "library.audit")
	NotLightL10n.bind_tooltip(audit, "library.audit_help")
	audit.theme_type_variation = "GhostButton"
	audit.pressed.connect(_audit_library_integrity)
	root.add_child(audit)


func _build_asset_area(parent: HBoxContainer) -> void:
	# GridContainer propagates the minimum width of all currently materialized
	# card columns through Container parents. Put the actual asset area behind a
	# plain Control boundary so a stale/wide grid can never enlarge the entire
	# Resource Library and push the inspector outside the Hub viewport.
	_asset_host = Control.new()
	_asset_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_asset_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_asset_host.custom_minimum_size = Vector2.ZERO
	_asset_host.clip_contents = true
	parent.add_child(_asset_host)
	_asset_host.resized.connect(_update_grid_columns)

	_asset_area = VBoxContainer.new()
	var area: VBoxContainer = _asset_area
	area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	area.add_theme_constant_override("separation", 10)
	_asset_host.add_child(area)
	if compact_mode:
		_count_label = Label.new()
		_count_label.theme_type_variation = "CaptionStrongLabel"
		area.add_child(_count_label)
	else:
		_build_bulk_bar(area)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	area.add_child(scroll)
	var margin: MarginContainer = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 12)
	margin.add_child(stack)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	stack.add_child(_grid)
	_load_more_button = Button.new()
	NotLightL10n.bind_text(_load_more_button, "common.show_more")
	NotLightL10n.bind_tooltip(_load_more_button, "library.show_more_help")
	_load_more_button.theme_type_variation = "GhostButton"
	_load_more_button.custom_minimum_size = Vector2(0.0, 40.0)
	_load_more_button.visible = false
	_load_more_button.pressed.connect(_load_more_assets)
	stack.add_child(_load_more_button)
	_empty_panel = PanelContainer.new()
	_empty_panel.theme_type_variation = "SoftPanel"
	_empty_panel.custom_minimum_size = Vector2(0.0, 220.0)
	stack.add_child(_empty_panel)
	var center: CenterContainer = CenterContainer.new()
	_empty_panel.add_child(center)
	var empty: VBoxContainer = VBoxContainer.new()
	empty.custom_minimum_size = Vector2(260.0, 0.0)
	empty.add_theme_constant_override("separation", 8)
	center.add_child(empty)
	_empty_title = Label.new()
	NotLightL10n.bind_text(_empty_title, "library.empty_title")
	_empty_title.theme_type_variation = "SectionLabel"
	_empty_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.add_child(_empty_title)
	_empty_description = Label.new()
	NotLightL10n.bind_text(_empty_description, "library.empty_description")
	_empty_description.theme_type_variation = "BodyMutedLabel"
	_empty_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty.add_child(_empty_description)


func _build_bulk_bar(parent: VBoxContainer) -> void:
	_bulk_bar = PanelContainer.new()
	_bulk_bar.theme_type_variation = "SoftPanel"
	_bulk_bar.visible = false
	parent.add_child(_bulk_bar)
	var row: HFlowContainer = HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	_bulk_bar.add_child(row)
	_bulk_count_label = Label.new()
	_bulk_count_label.theme_type_variation = "CaptionStrongLabel"
	_bulk_count_label.custom_minimum_size = Vector2(140.0, 0.0)
	row.add_child(_bulk_count_label)
	var select_all: Button = Button.new()
	NotLightL10n.bind_text(select_all, "library.bulk.select_shown")
	select_all.theme_type_variation = "GhostButton"
	select_all.pressed.connect(_select_all_shown)
	row.add_child(select_all)
	var move: Button = Button.new()
	NotLightL10n.bind_text(move, "library.bulk.move")
	move.theme_type_variation = "GhostButton"
	move.pressed.connect(_open_bulk_move_dialog)
	row.add_child(move)
	var export: Button = Button.new()
	NotLightL10n.bind_text(export, "library.bulk.export")
	export.theme_type_variation = "GhostButton"
	export.pressed.connect(_open_selected_export_dialog)
	row.add_child(export)
	var remove: Button = Button.new()
	NotLightL10n.bind_text(remove, "library.bulk.delete")
	remove.theme_type_variation = "GhostDangerButton"
	remove.pressed.connect(_open_bulk_delete_dialog)
	row.add_child(remove)
	var clear: Button = Button.new()
	NotLightL10n.bind_text(clear, "library.bulk.clear")
	clear.theme_type_variation = "GhostButton"
	clear.pressed.connect(_clear_bulk_selection)
	row.add_child(clear)


func _build_inspector(parent: HBoxContainer) -> void:
	# The inspector gets its own layout slot for the same reason as the asset
	# grid. Its content may have non-zero intrinsic minimum sizes, but those must
	# never be allowed to increase the HBox beyond the width assigned by the Hub.
	_inspector_host = Control.new()
	_inspector_host.visible = false
	_inspector_host.size_flags_horizontal = Control.SIZE_SHRINK_END
	_inspector_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspector_host.custom_minimum_size = Vector2(FULL_INSPECTOR_WIDTH, 0.0)
	_inspector_host.clip_contents = true
	parent.add_child(_inspector_host)

	_inspector = AssetInspectorPanel.new()
	_inspector.visible = false
	_inspector.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inspector.close_requested.connect(_close_inspector)
	_inspector.asset_updated.connect(func(_asset_id: String) -> void:
		# Metadata notification already refreshes search/tags exactly once. Keep the
		# post-save callback limited to selection chrome instead of rebuilding cards twice.
		_refresh_card_selection()
	)
	_inspector_host.add_child(_inspector)
	if library != null:
		_inspector.configure(library, pdf_media, pdf_optimizer, not compact_mode)


func _open_inspector(asset_id: String) -> void:
	_selected_asset_id = asset_id
	if _inspector == null or _inspector_host == null:
		return
	_inspector.show_asset(asset_id)
	_inspector.visible = true
	_inspector_host.visible = true
	if compact_mode:
		if _asset_host != null:
			_asset_host.visible = false
		_inspector_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_inspector_host.custom_minimum_size = Vector2.ZERO
	else:
		_update_full_library_layout()
	_refresh_card_selection()
	call_deferred("_update_grid_columns")


func _close_inspector() -> void:
	_selected_asset_id = ""
	if _inspector != null:
		_inspector.clear_asset()
	if _inspector_host != null:
		_inspector_host.visible = false
	if compact_mode:
		if _asset_host != null:
			_asset_host.visible = true
		if _inspector_host != null:
			_inspector_host.size_flags_horizontal = Control.SIZE_SHRINK_END
			_inspector_host.custom_minimum_size = Vector2(FULL_INSPECTOR_WIDTH, 0.0)
	else:
		_update_full_library_layout()
	_refresh_card_selection()
	call_deferred("_update_grid_columns")


func _refresh_card_selection() -> void:
	if _grid == null:
		return
	for child: Node in _grid.get_children():
		if child is AssetLibraryCard:
			var card: AssetLibraryCard = child as AssetLibraryCard
			var bulk_selected: bool = _selected_asset_ids.has(card.asset_id)
			card.set_bulk_selected(bulk_selected)
			card.set_selected(card.asset_id == _selected_asset_id or bulk_selected)


func _apply_page_budget() -> void:
	var base: int = COMPACT_PAGE_SIZE if compact_mode else FULL_PAGE_SIZE
	if settings != null:
		var budget: Dictionary = settings.get_performance_budget()
		var materialized: int = int(budget.get("materialized_ui_budget", 96))
		base = clampi(materialized, 32, AppSettingsStore.MAX_MATERIALIZED_UI_BUDGET)
		if compact_mode:
			base = clampi(int(base / 2), 24, int(AppSettingsStore.MAX_MATERIALIZED_UI_BUDGET / 2))
	_visible_asset_limit = base


func _build_progress(parent: VBoxContainer) -> void:
	_progress_panel = PanelContainer.new()
	_progress_panel.theme_type_variation = "AssetImportPanel"
	_progress_panel.visible = false
	parent.add_child(_progress_panel)
	var row: HFlowContainer = HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 6)
	_progress_panel.add_child(row)
	_progress_label = Label.new()
	NotLightL10n.bind_text(_progress_label, "library.import_progress")
	_progress_label.theme_type_variation = "CaptionStrongLabel"
	_progress_label.custom_minimum_size = Vector2(180.0, 0.0)
	row.add_child(_progress_label)
	_progress_bar = ProgressBar.new()
	_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_bar.show_percentage = false
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	row.add_child(_progress_bar)
	_import_cancel_button = Button.new()
	_import_cancel_button.theme_type_variation = "GhostButton"
	_import_cancel_button.custom_minimum_size = Vector2(98.0, 34.0)
	NotLightL10n.bind_text(_import_cancel_button, "common.cancel")
	_import_cancel_button.pressed.connect(_cancel_active_imports)
	row.add_child(_import_cancel_button)


func _build_dialogs() -> void:
	_import_dialog = FileDialog.new()
	_import_dialog.mode_overrides_title = false
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_import_dialog.title = NotLightL10n.text("library.import_dialog")
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.use_native_dialog = true
	_import_dialog.filters = AssetImportCapabilities.file_dialog_filters()
	_import_dialog.files_selected.connect(_on_files_selected)
	add_child(_import_dialog)
	_import_preflight_dialog = AssetImportPreflightDialog.new()
	_import_preflight_dialog.import_requested.connect(_on_preflight_import_requested)
	_import_preflight_dialog.cancel_requested.connect(_on_preflight_cancel_requested)
	add_child(_import_preflight_dialog)
	_package_import_dialog = FileDialog.new()
	_package_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_package_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_package_import_dialog.use_native_dialog = true
	_package_import_dialog.filters = PackedStringArray(["*.notlight-library;%s;application/octet-stream" % NotLightL10n.text("file_filter.library_package")])
	_package_import_dialog.file_selected.connect(_on_library_package_selected)
	add_child(_package_import_dialog)
	_package_export_dialog = FileDialog.new()
	_package_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_package_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_package_export_dialog.use_native_dialog = true
	_package_export_dialog.filters = PackedStringArray(["*.notlight-library;%s;application/octet-stream" % NotLightL10n.text("file_filter.library_package")])
	_package_export_dialog.file_selected.connect(_on_library_export_path_selected)
	add_child(_package_export_dialog)
	_folder_name_dialog = NameDialog.new()
	_folder_name_dialog.submitted.connect(_on_folder_name_submitted)
	add_child(_folder_name_dialog)
	_asset_name_dialog = NameDialog.new()
	_asset_name_dialog.submitted.connect(_on_asset_name_submitted)
	add_child(_asset_name_dialog)
	_confirm_dialog = ConfirmActionDialog.new()
	_confirm_dialog.confirmed.connect(_on_confirmed)
	add_child(_confirm_dialog)
	_move_dialog = AssetFolderPickerDialog.new()
	_move_dialog.submitted.connect(_on_move_folder_selected)
	add_child(_move_dialog)


func _refresh() -> void:
	if library == null or _grid == null:
		return
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var kind_filter: int = int(_kind_filter.get_item_metadata(_kind_filter.selected)) if _kind_filter.selected >= 0 else AssetKinds.ANY
	var usage_filter: int = int(_usage_filter.get_item_metadata(_usage_filter.selected)) if _usage_filter.selected >= 0 else AssetLibraryService.USAGE_ALL
	var query: String = _search_edit.text if _search_edit != null else ""
	var tag_filter: String = ""
	if _tag_filter != null and _tag_filter.selected >= 0:
		tag_filter = str(_tag_filter.get_item_metadata(_tag_filter.selected))
	var page: Dictionary = library.query_assets(
		query,
		kind_filter,
		_selected_folder_id,
		usage_filter,
		0,
		_visible_asset_limit,
		tag_filter
	)
	var raw_assets: Array = page.get("records", []) as Array
	var total: int = int(page.get("total", 0))
	_current_asset_order = PackedStringArray()
	_prune_bulk_selection()
	var shown: int = 0
	for raw_asset: Variant in raw_assets:
		if raw_asset is not Dictionary:
			continue
		var card: AssetLibraryCard = AssetLibraryCard.new()
		card.rename_requested.connect(_open_rename_asset_dialog)
		card.move_requested.connect(_open_move_asset_dialog)
		card.delete_requested.connect(_open_delete_asset_dialog)
		card.insert_requested.connect(func(asset_id: String) -> void: asset_insert_requested.emit(asset_id))
		card.workspace_insert_requested.connect(func(asset_id: String) -> void: note_workspace_insert_requested.emit(asset_id))
		card.message_requested.connect(func(message: String) -> void: _show_error(message, false))
		card.inspect_requested.connect(_open_inspector)
		card.preview_requested.connect(func(asset_id: String) -> void: asset_preview_requested.emit(asset_id))
		card.bulk_select_requested.connect(_on_bulk_select_requested)
		_grid.add_child(card)
		card.configure(raw_asset as Dictionary, not compact_mode, compact_mode, image_cache, video_media, audio_media, pdf_media, pdf_optimizer, not compact_mode)
		_current_asset_order.append(card.asset_id)
		var bulk_selected: bool = _selected_asset_ids.has(card.asset_id)
		card.set_bulk_selected(bulk_selected)
		card.set_selected(card.asset_id == _selected_asset_id or bulk_selected)
		shown += 1
	_count_label.text = (
		NotLightL10n.text("library.resources", {"count": total})
		if shown >= total
		else NotLightL10n.text("library.resources_shown", {"shown": shown, "total": total})
	)
	if _load_more_button != null:
		_load_more_button.visible = shown < total
		_load_more_button.text = NotLightL10n.text("common.show_more_remaining", {"count": maxi(0, total - shown)})
	var empty: bool = total == 0
	_grid.visible = not empty
	_empty_panel.visible = empty
	if empty:
		var all_count: int = int(library.get_storage_stats(false).get("asset_count", 0))
		if all_count == 0:
			NotLightL10n.bind_text(_empty_title, "library.empty_title")
			NotLightL10n.bind_text(_empty_description, "library.empty_uuid_help")
		else:
			NotLightL10n.bind_text(_empty_title, "common.nothing_found")
			NotLightL10n.bind_text(_empty_description, "library.search_empty")
	_update_stats()
	_refresh_bulk_bar()
	_update_grid_columns()


func _reset_paging_and_refresh() -> void:
	_clear_bulk_selection(false)
	_apply_page_budget()
	_refresh()


func _load_more_assets() -> void:
	var previous_limit: int = _visible_asset_limit
	_apply_page_budget()
	var page_size: int = _visible_asset_limit
	_visible_asset_limit = previous_limit + page_size
	_refresh()


func _on_search_text_changed(_text: String) -> void:
	if _search_debounce == null:
		_reset_paging_and_refresh()
		return
	_search_debounce.start()


func _refresh_folders() -> void:
	if library == null:
		return
	if _selected_folder_id != AssetLibraryService.FOLDER_ANY and not _selected_folder_id.is_empty():
		var found: bool = false
		for folder: Dictionary in library.list_folders():
			if str(folder.get("id", "")) == _selected_folder_id:
				found = true
				break
		if not found:
			_selected_folder_id = AssetLibraryService.FOLDER_ANY
	if _folder_tree != null:
		_request_folder_tree_rebuild()
	if _folder_caption != null:
		_folder_caption.text = library.folder_path(_selected_folder_id)
	_visible_asset_limit = COMPACT_PAGE_SIZE if compact_mode else FULL_PAGE_SIZE
	_refresh()


func _rebuild_folder_tree() -> void:
	if _folder_tree == null or not is_instance_valid(_folder_tree) or library == null:
		return
	_folder_tree_rebuild_pending = false
	_folder_tree.set_block_signals(true)
	_folder_tree.clear()
	var root_item: TreeItem = _folder_tree.create_item()
	if root_item == null:
		# Godot temporarily blocks Tree structural mutation while it is dispatching
		# some Tree callbacks. Never continue with null TreeItems or leave signals
		# blocked; retry after the current engine callback has unwound.
		_folder_tree.set_block_signals(false)
		_defer_folder_tree_rebuild()
		return
	var all_item: TreeItem = _folder_tree.create_item(root_item)
	if all_item == null:
		_folder_tree.set_block_signals(false)
		_defer_folder_tree_rebuild()
		return
	all_item.set_text(0, NotLightL10n.text("library.folder.all"))
	all_item.set_icon(0, load("res://assets/icons/folder.svg") as Texture2D)
	all_item.set_metadata(0, AssetLibraryService.FOLDER_ANY)
	all_item.set_tooltip_text(0, NotLightL10n.text("library.folder.all"))
	if _selected_folder_id == AssetLibraryService.FOLDER_ANY:
		all_item.select(0)
	var none_item: TreeItem = _folder_tree.create_item(root_item)
	if none_item == null:
		_folder_tree.set_block_signals(false)
		_defer_folder_tree_rebuild()
		return
	none_item.set_text(0, NotLightL10n.text("library.folder.none"))
	none_item.set_icon(0, load("res://assets/icons/folder.svg") as Texture2D)
	none_item.set_metadata(0, "")
	none_item.set_tooltip_text(0, NotLightL10n.text("library.folder.none"))
	if _selected_folder_id.is_empty():
		none_item.select(0)
	var folders: Array[Dictionary] = library.list_folders()
	var by_parent: Dictionary = {}
	for folder: Dictionary in folders:
		var parent_id: String = str(folder.get("parent_id", ""))
		var bucket: Array = by_parent.get(parent_id, []) as Array
		bucket.append(folder)
		by_parent[parent_id] = bucket
	var complete: bool = _append_folder_tree_children(root_item, "", by_parent, 0)
	_folder_tree.set_block_signals(false)
	if not complete:
		_defer_folder_tree_rebuild()


func _append_folder_tree_children(parent_item: TreeItem, parent_id: String, by_parent: Dictionary, depth: int) -> bool:
	if depth >= 64:
		return true
	var children_value: Variant = by_parent.get(parent_id, [])
	if children_value is not Array:
		return true
	var children: Array = children_value as Array
	children.sort_custom(func(left: Variant, right: Variant) -> bool:
		if left is not Dictionary or right is not Dictionary:
			return false
		return str((left as Dictionary).get("name", "")).naturalnocasecmp_to(str((right as Dictionary).get("name", ""))) < 0
	)
	for raw_folder: Variant in children:
		if raw_folder is not Dictionary:
			continue
		var folder: Dictionary = raw_folder as Dictionary
		var folder_id: String = str(folder.get("id", "")).strip_edges()
		if folder_id.is_empty():
			continue
		var item: TreeItem = _folder_tree.create_item(parent_item)
		if item == null:
			return false
		var folder_name: String = str(folder.get("name", NotLightL10n.text("library.folder.default_name")))
		item.set_text(0, folder_name)
		item.set_icon(0, load("res://assets/icons/folder.svg") as Texture2D)
		item.set_metadata(0, folder_id)
		item.set_tooltip_text(0, library.folder_path(folder_id))
		item.collapsed = _collapsed_folder_ids.has(folder_id)
		if folder_id == _selected_folder_id:
			item.select(0)
		if not _append_folder_tree_children(item, folder_id, by_parent, depth + 1):
			return false
	return true


func _request_folder_tree_rebuild() -> void:
	# Structural Tree updates always cross an idle-frame boundary while this view
	# is live. Folder/library/locale signals may themselves originate from UI
	# callbacks; coalescing them here makes Tree mutation non-reentrant by design.
	if not is_inside_tree():
		_rebuild_folder_tree()
		return
	_defer_folder_tree_rebuild()


func _defer_folder_tree_rebuild() -> void:
	if _folder_tree_rebuild_pending or not is_inside_tree():
		return
	_folder_tree_rebuild_pending = true
	call_deferred("_run_deferred_folder_tree_rebuild")


func _run_deferred_folder_tree_rebuild() -> void:
	if not _folder_tree_rebuild_pending:
		return
	_folder_tree_rebuild_pending = false
	_rebuild_folder_tree()


func _on_folder_tree_selected() -> void:
	if _folder_tree == null:
		return
	var selected: TreeItem = _folder_tree.get_selected()
	if selected == null:
		return
	_select_folder(str(selected.get_metadata(0)))


func _on_folder_tree_item_collapsed(item: TreeItem) -> void:
	if item == null:
		return
	var folder_id: String = str(item.get_metadata(0)).strip_edges()
	if folder_id.is_empty() or folder_id == AssetLibraryService.FOLDER_ANY:
		return
	if item.collapsed:
		_collapsed_folder_ids[folder_id] = true
	else:
		_collapsed_folder_ids.erase(folder_id)


func _folders_with_paths() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if library == null:
		return result
	for folder: Dictionary in library.list_folders():
		var enriched: Dictionary = folder.duplicate(true)
		enriched["display_path"] = library.folder_path(str(folder.get("id", "")))
		result.append(enriched)
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("display_path", "")).naturalnocasecmp_to(str(right.get("display_path", ""))) < 0
	)
	return result


func _select_folder(folder_id: String) -> void:
	_clear_bulk_selection(false)
	_selected_folder_id = folder_id
	if _folder_caption != null and library != null:
		_folder_caption.text = library.folder_path(folder_id)
	_visible_asset_limit = COMPACT_PAGE_SIZE if compact_mode else FULL_PAGE_SIZE
	# Selection changes filtering only. Rebuilding the same Tree from item_selected
	# re-enters Godot's Tree mutation guard and can make create_item() return null.
	# Structural rebuilds are reserved for folders_changed/locale/import events.
	_refresh()


func _cycle_compact_folder() -> void:
	if library == null:
		return
	var ids: Array[String] = [AssetLibraryService.FOLDER_ANY, ""]
	for folder: Dictionary in _folders_with_paths():
		ids.append(str(folder.get("id", "")))
	var current: int = ids.find(_selected_folder_id)
	var next_index: int = (maxi(0, current) + 1) % ids.size()
	_selected_folder_id = ids[next_index]
	_folder_caption.text = library.folder_path(_selected_folder_id)
	_visible_asset_limit = COMPACT_PAGE_SIZE
	_refresh()


func _on_exchange_menu_action(action_id: int) -> void:
	match action_id:
		1:
			_open_library_package_import_dialog()
		2:
			_library_export_include_notes = true
			_open_library_package_export_dialog()
		3:
			_library_export_include_notes = false
			_open_library_package_export_dialog()


func _open_library_package_import_dialog() -> void:
	if portable_packages == null:
		_show_error(NotLightL10n.text("exchange.error.unavailable"))
		return
	_package_import_dialog.title = NotLightL10n.text("exchange.library.import_title")
	_package_import_dialog.popup_centered_ratio(0.72)


func _open_library_package_export_dialog() -> void:
	_export_selected_asset_ids = PackedStringArray()
	if portable_packages == null:
		_show_error(NotLightL10n.text("exchange.error.unavailable"))
		return
	_package_export_dialog.title = NotLightL10n.text("exchange.library.export_title")
	var date: Dictionary = Time.get_date_dict_from_system()
	_package_export_dialog.current_file = "NotLightLibrary_%04d-%02d-%02d.notlight-library" % [
		int(date.get("year", 1970)),
		int(date.get("month", 1)),
		int(date.get("day", 1)),
	]
	_package_export_dialog.popup_centered_ratio(0.72)


func _on_library_package_selected(path: String) -> void:
	if portable_packages == null:
		return
	var result: Dictionary = portable_packages.import_library(path)
	if not bool(result.get("ok", false)):
		_show_error(str(result.get("error", portable_packages.get_last_error())))
		return
	_refresh_tag_filter()
	_refresh_folders()
	_show_error(NotLightL10n.text("exchange.library.import_done", {
		"added": int(result.get("assets_added", 0)),
		"reused": int(result.get("assets_reused", 0)),
		"folders": int(result.get("folders_added", 0)),
	}), false)


func _on_library_export_path_selected(path: String) -> void:
	if portable_packages == null:
		return
	var destination: String = _ensure_package_extension(path, NotLightPortablePackageFormat.LIBRARY_EXTENSION)
	var result: Dictionary = (
		portable_packages.export_library_selection(destination, _export_selected_asset_ids)
		if not _export_selected_asset_ids.is_empty()
		else portable_packages.export_library_profile(destination, _library_export_include_notes)
	)
	_export_selected_asset_ids = PackedStringArray()
	_library_export_include_notes = true
	if not bool(result.get("ok", false)):
		_show_error(str(result.get("error", portable_packages.get_last_error())))
		return
	_show_error(NotLightL10n.text("exchange.library.export_done", {"count": int(result.get("asset_count", 0))}), false)


func _ensure_package_extension(path: String, extension: String) -> String:
	var suffix: String = ".%s" % extension.strip_edges().trim_prefix(".")
	return path if path.to_lower().ends_with(suffix.to_lower()) else path + suffix


func _open_import_dialog() -> void:
	if library == null:
		return
	if not _active_preflight_request_id.is_empty():
		_show_error(NotLightL10n.text("library.preflight.error.busy"))
		return
	_import_dialog.filters = AssetImportCapabilities.file_dialog_filters()
	_import_dialog.popup_centered_ratio(0.72)


func _on_library_files_dropped(paths: PackedStringArray) -> void:
	# The full Hub Library owns drop-to-library. The compact board drawer never
	# connects this handler because BoardScreen uses the same registry/pipeline and
	# additionally remembers board placement positions for dropped media.
	if compact_mode or not is_visible_in_tree() or library == null or paths.is_empty():
		return
	_on_files_selected(paths)


func _on_files_selected(paths: PackedStringArray) -> void:
	if library == null or paths.is_empty():
		return
	_preflight_target_folder_id = "" if _selected_folder_id == AssetLibraryService.FOLDER_ANY else _selected_folder_id
	_preflight_target_folder_label = (
		NotLightL10n.text("library.folder.none")
		if _preflight_target_folder_id.is_empty()
		else library.folder_path(_preflight_target_folder_id)
	)
	var request_id: String = library.request_import_preflight(paths)
	if request_id.is_empty():
		return
	_active_preflight_request_id = request_id
	_import_preflight_dialog.open_loading(_preflight_target_folder_label, paths.size())


func _on_import_preflight_progress(request_id: String, completed_count: int, total_count: int, source_path: String) -> void:
	if request_id != _active_preflight_request_id or _import_preflight_dialog == null:
		return
	_import_preflight_dialog.set_validation_progress(completed_count, total_count, source_path)


func _on_import_preflight_completed(request_id: String, results: Array) -> void:
	if request_id != _active_preflight_request_id:
		return
	_active_preflight_request_id = ""
	if _import_preflight_dialog != null:
		_import_preflight_dialog.show_results(results, _preflight_target_folder_label)


func _on_import_preflight_cancelled(request_id: String) -> void:
	if request_id == _active_preflight_request_id:
		_active_preflight_request_id = ""


func _on_import_preflight_failed(request_id: String, message: String) -> void:
	if request_id != _active_preflight_request_id:
		return
	_active_preflight_request_id = ""
	if _import_preflight_dialog != null:
		_import_preflight_dialog.show_failure(message)


func _on_preflight_cancel_requested() -> void:
	if library != null and not _active_preflight_request_id.is_empty():
		library.cancel_import_preflight(_active_preflight_request_id)


func _on_preflight_import_requested(results: Array) -> void:
	if library == null:
		return
	library.import_preflight_results(results, _preflight_target_folder_id)


func _on_import_progress(_job_id: String, source_path: String, progress: float) -> void:
	_progress_panel.visible = true
	_progress_label.text = NotLightL10n.text("library.import_file", {"name": source_path.get_file()})
	_progress_label.tooltip_text = source_path
	_progress_bar.value = progress * 100.0


func _on_import_finished(asset_id: String, duplicate: bool) -> void:
	if library != null and not library.has_pending_imports():
		_progress_panel.visible = false
	if duplicate:
		var asset: Dictionary = library.get_asset(asset_id)
		_show_error(NotLightL10n.text("library.duplicate_existing", {"name": str(asset.get("display_name", NotLightL10n.text("library.asset.fallback_name")))}), false)
	_refresh()


func _on_import_failed(_message: String) -> void:
	if _progress_panel != null and (library == null or not library.has_pending_imports()):
		_progress_panel.visible = false


func _on_import_queue_changed(pending_count: int) -> void:
	if _progress_panel != null and pending_count <= 0:
		_progress_panel.visible = false


func _cancel_active_imports() -> void:
	if library != null:
		library.cancel_imports()


func _open_create_folder_dialog() -> void:
	_folder_dialog_mode = FOLDER_DIALOG_CREATE
	_pending_folder_id = ""
	_pending_folder_parent_id = ""
	var parent_name: String = NotLightL10n.text("library.folder.root_label")
	if _selected_folder_id != AssetLibraryService.FOLDER_ANY and not _selected_folder_id.is_empty() and library != null:
		_pending_folder_parent_id = _selected_folder_id
		parent_name = library.folder_path(_selected_folder_id)
	_folder_name_dialog.open_dialog(NotLightL10n.text("library.folder.create_title"), NotLightL10n.text("library.folder.create_help_short", {"parent": parent_name}), "", NotLightL10n.text("common.create"))


func _open_rename_folder_dialog() -> void:
	if library == null or _selected_folder_id == AssetLibraryService.FOLDER_ANY or _selected_folder_id.is_empty():
		_show_error(NotLightL10n.text("library.folder.rename_select"))
		return
	var folder: Dictionary = library.get_folder(_selected_folder_id)
	if folder.is_empty():
		return
	_folder_dialog_mode = FOLDER_DIALOG_RENAME
	_pending_folder_id = _selected_folder_id
	_pending_folder_parent_id = ""
	_folder_name_dialog.open_dialog(NotLightL10n.text("library.folder.rename_title"), NotLightL10n.text("library.folder.rename_help"), str(folder.get("name", NotLightL10n.text("library.folder.default_name"))), NotLightL10n.text("common.save"))


func _on_folder_name_submitted(name: String) -> void:
	if library == null:
		return
	match _folder_dialog_mode:
		FOLDER_DIALOG_CREATE:
			var folder: Dictionary = library.create_folder(name, _pending_folder_parent_id)
			if folder.is_empty():
				_show_error(library.get_last_error())
			else:
				_selected_folder_id = str(folder.get("id", ""))
		FOLDER_DIALOG_RENAME:
			if not _pending_folder_id.is_empty() and not library.rename_folder(_pending_folder_id, name):
				_show_error(library.get_last_error())
		_:
			pass
	_folder_dialog_mode = FOLDER_DIALOG_NONE
	_pending_folder_id = ""
	_pending_folder_parent_id = ""


func _open_delete_folder_dialog() -> void:
	if _selected_folder_id == AssetLibraryService.FOLDER_ANY or _selected_folder_id.is_empty() or library == null:
		_show_error(NotLightL10n.text("library.folder.delete_select"))
		return
	_pending_folder_id = _selected_folder_id
	_cleanup_stage = -1
	_confirm_dialog.open_dialog(NotLightL10n.text("library.folder.delete_title"), NotLightL10n.text("library.folder.delete_help"), NotLightL10n.text("common.delete"), true)


func _open_rename_asset_dialog(asset_id: String, current_name: String) -> void:
	_pending_asset_id = asset_id
	_asset_name_dialog.open_dialog(NotLightL10n.text("library.asset.rename_title"), NotLightL10n.text("library.asset.rename_help"), current_name, NotLightL10n.text("common.save"))


func _on_asset_name_submitted(name: String) -> void:
	if library == null or _pending_asset_id.is_empty():
		return
	if not library.rename_asset(_pending_asset_id, name):
		_show_error(library.get_last_error())
	_pending_asset_id = ""


func _open_move_asset_dialog(asset_id: String) -> void:
	if library == null:
		return
	_pending_bulk_move = false
	_pending_asset_id = asset_id
	var asset: Dictionary = library.get_asset(asset_id)
	_move_dialog.open_dialog(_folders_with_paths(), str(asset.get("folder_id", "")))


func _on_move_folder_selected(folder_id: String) -> void:
	if library == null:
		return
	if _pending_bulk_move:
		_pending_bulk_move = false
		var selected_ids: PackedStringArray = _bulk_selected_ids()
		if selected_ids.is_empty():
			return
		if not library.move_assets(selected_ids, folder_id):
			_show_error(library.get_last_error())
			return
		_clear_bulk_selection()
		return
	if _pending_asset_id.is_empty():
		return
	if not library.move_asset(_pending_asset_id, folder_id):
		_show_error(library.get_last_error())
	_pending_asset_id = ""


func _open_delete_asset_dialog(asset_id: String, display_name: String, usage_count: int) -> void:
	if compact_mode:
		_show_error(NotLightL10n.text("library.asset.delete_hub_only"), false)
		return
	_pending_asset_id = asset_id
	_cleanup_stage = -2
	if usage_count > 0:
		_show_error(NotLightL10n.text("library.asset.delete_in_use", {"name": display_name, "count": usage_count}))
		return
	_confirm_dialog.open_dialog(NotLightL10n.text("library.asset.delete_title"), NotLightL10n.text("library.asset.delete_help", {"name": display_name}), NotLightL10n.text("common.delete"), true)


func _on_bulk_select_requested(asset_id: String, toggle: bool, range_select: bool) -> void:
	if compact_mode or asset_id.is_empty():
		return
	if range_select and not _selection_anchor_id.is_empty():
		var anchor_index: int = _current_asset_order.find(_selection_anchor_id)
		var target_index: int = _current_asset_order.find(asset_id)
		if anchor_index >= 0 and target_index >= 0:
			if not toggle:
				_selected_asset_ids.clear()
			var first: int = mini(anchor_index, target_index)
			var last: int = maxi(anchor_index, target_index)
			for index: int in range(first, last + 1):
				_selected_asset_ids[_current_asset_order[index]] = true
		else:
			_selected_asset_ids[asset_id] = true
	else:
		if _selected_asset_ids.has(asset_id):
			_selected_asset_ids.erase(asset_id)
		else:
			_selected_asset_ids[asset_id] = true
	_selection_anchor_id = asset_id
	_refresh_card_selection()
	_refresh_bulk_bar()


func _select_all_shown() -> void:
	for asset_id: String in _current_asset_order:
		_selected_asset_ids[asset_id] = true
	if not _current_asset_order.is_empty():
		_selection_anchor_id = _current_asset_order[0]
	_refresh_card_selection()
	_refresh_bulk_bar()


func _clear_bulk_selection(refresh_cards: bool = true) -> void:
	_selected_asset_ids.clear()
	_selection_anchor_id = ""
	if refresh_cards:
		_refresh_card_selection()
	_refresh_bulk_bar()


func _prune_bulk_selection() -> void:
	if library == null or _selected_asset_ids.is_empty():
		return
	for raw_id: Variant in _selected_asset_ids.keys():
		var asset_id: String = str(raw_id)
		if library.get_asset(asset_id).is_empty():
			_selected_asset_ids.erase(asset_id)
	if not _selection_anchor_id.is_empty() and not _selected_asset_ids.has(_selection_anchor_id):
		_selection_anchor_id = ""


func _bulk_selected_ids() -> PackedStringArray:
	var sorted_ids: Array[String] = []
	for raw_id: Variant in _selected_asset_ids.keys():
		sorted_ids.append(str(raw_id))
	sorted_ids.sort()
	return PackedStringArray(sorted_ids)


func _refresh_bulk_bar() -> void:
	if _bulk_bar == null or _bulk_count_label == null:
		return
	var count: int = _selected_asset_ids.size()
	_bulk_bar.visible = count > 0
	_bulk_count_label.text = NotLightL10n.text("library.bulk.selected", {"count": count})


func _open_bulk_move_dialog() -> void:
	if library == null or _selected_asset_ids.is_empty():
		return
	_pending_asset_id = ""
	_pending_bulk_move = true
	_move_dialog.open_dialog(_folders_with_paths(), "")


func _open_bulk_delete_dialog() -> void:
	if library == null or _selected_asset_ids.is_empty():
		return
	var used_count: int = 0
	for asset_id: String in _bulk_selected_ids():
		var asset: Dictionary = library.get_asset(asset_id)
		if int(asset.get("usage_count", 0)) > 0:
			used_count += 1
	if used_count > 0:
		_show_error(NotLightL10n.text("library.bulk.delete_in_use", {"count": used_count}))
		return
	_cleanup_stage = -4
	_confirm_dialog.open_dialog(
		NotLightL10n.text("library.bulk.delete_title"),
		NotLightL10n.text("library.bulk.delete_help", {"count": _selected_asset_ids.size()}),
		NotLightL10n.text("common.delete"),
		true
	)


func _open_selected_export_dialog() -> void:
	if portable_packages == null:
		_show_error(NotLightL10n.text("exchange.error.unavailable"))
		return
	var selected_ids: PackedStringArray = _bulk_selected_ids()
	if selected_ids.is_empty():
		return
	_export_selected_asset_ids = selected_ids
	_package_export_dialog.title = NotLightL10n.text("exchange.library.export_selection_title")
	var date: Dictionary = Time.get_date_dict_from_system()
	_package_export_dialog.current_file = "NotLightSelection_%04d-%02d-%02d.notlight-library" % [
		int(date.get("year", 1970)),
		int(date.get("month", 1)),
		int(date.get("day", 1)),
	]
	_package_export_dialog.popup_centered_ratio(0.72)


func _start_cleanup_unused() -> void:
	if library == null:
		return
	var stats: Dictionary = library.get_storage_stats(false)
	var unused: int = int(stats.get("unused_count", 0))
	var orphan_blobs: int = 0
	if unused <= 0:
		var integrity: Dictionary = library.get_integrity_report()
		orphan_blobs = int(integrity.get("orphan_blob_count", 0))
	if unused <= 0 and orphan_blobs <= 0:
		_show_error(NotLightL10n.text("library.cleanup.empty"), false)
		return
	_cleanup_stage = 1
	var detail: String = NotLightL10n.text("library.cleanup.detail", {"unused": unused})
	if orphan_blobs > 0:
		detail += " · " + NotLightL10n.text("library.cleanup.orphans", {"count": orphan_blobs})
	_confirm_dialog.open_dialog(NotLightL10n.text("library.cleanup.title"), NotLightL10n.text("library.cleanup.help", {"detail": detail}), NotLightL10n.text("common.continue"), true)


func _audit_library_integrity() -> void:
	if library == null:
		return
	var report: Dictionary = library.get_integrity_report()
	if report.is_empty():
		return
	var missing: int = int(report.get("missing_count", 0))
	var dangling: int = int(report.get("dangling_reference_count", 0))
	var orphan_blobs: int = int(report.get("orphan_blob_count", 0))
	if missing <= 0 and dangling <= 0 and orphan_blobs <= 0:
		_show_error(NotLightL10n.text("library.audit.ok"), false)
		return
	var problems: Array[String] = []
	if missing > 0:
		problems.append(NotLightL10n.text("library.audit.missing", {"count": missing}))
	if dangling > 0:
		problems.append(NotLightL10n.text("library.audit.dangling", {"count": dangling}))
	if orphan_blobs > 0:
		problems.append(NotLightL10n.text("library.audit.orphans", {"count": orphan_blobs, "size": _format_bytes(int(report.get("orphan_blob_bytes", 0))) }))
	_show_error(NotLightL10n.text("library.audit.result", {"problems": ", ".join(problems)}))


func _start_clear_cache() -> void:
	if library == null:
		return
	_cleanup_stage = -3
	_confirm_dialog.open_dialog(
		NotLightL10n.text("library.cache.clear_title"),
		NotLightL10n.text("library.cache.clear_help"),
		NotLightL10n.text("library.cache.clear_action"),
		false
	)


func _on_confirmed() -> void:
	if library == null:
		return
	if _cleanup_stage == -4:
		_cleanup_stage = 0
		var selected_ids: PackedStringArray = _bulk_selected_ids()
		var result: Dictionary = library.delete_assets(selected_ids, false)
		if result.is_empty() and not library.get_last_error().is_empty():
			_show_error(library.get_last_error())
			return
		_clear_bulk_selection()
		var failures: int = int(result.get("blob_delete_failures", 0))
		var message: String = NotLightL10n.text("library.bulk.deleted", {"count": int(result.get("removed", 0))})
		if failures > 0:
			message += " · " + NotLightL10n.text("library.cleanup.failures", {"count": failures})
		_show_error(message, failures > 0)
		return
	if _cleanup_stage == -1:
		var folder_id: String = _pending_folder_id
		_pending_folder_id = ""
		_cleanup_stage = 0
		if not library.delete_folder(folder_id):
			_show_error(library.get_last_error())
		return
	if _cleanup_stage == -2:
		var asset_id: String = _pending_asset_id
		_pending_asset_id = ""
		_cleanup_stage = 0
		if not library.delete_asset(asset_id, false):
			_show_error(library.get_last_error())
		return
	if _cleanup_stage == -3:
		_cleanup_stage = 0
		var cache_result: Dictionary = library.clear_derived_cache()
		if cache_result.is_empty() and not library.get_last_error().is_empty():
			_show_error(library.get_last_error())
			return
		_show_error(NotLightL10n.text("library.cache.cleared", {"size": _format_bytes(int(cache_result.get("bytes", 0)))}), false)
		return
	if _cleanup_stage == 1:
		_cleanup_stage = 2
		_confirm_dialog.open_dialog(NotLightL10n.text("library.cleanup.confirm_title"), NotLightL10n.text("library.cleanup.confirm_help"), NotLightL10n.text("library.cleanup.confirm_action"), true)
		return
	if _cleanup_stage == 2:
		_cleanup_stage = 0
		var result: Dictionary = library.cleanup_unused()
		if result.is_empty() and not library.get_last_error().is_empty():
			_show_error(library.get_last_error())
			return
		var failures: int = int(result.get("blob_delete_failures", 0))
		var message: String = NotLightL10n.text("library.cleanup.result", {"count": int(result.get("removed", 0)), "size": _format_bytes(int(result.get("bytes", 0)))})
		if int(result.get("orphan_blobs_removed", 0)) > 0:
			message += " · " + NotLightL10n.text("library.cleanup.orphans_removed", {"count": int(result.get("orphan_blobs_removed", 0))})
		if failures > 0:
			message += " · " + NotLightL10n.text("library.cleanup.failures", {"count": failures})
		_show_error(message, failures > 0)


func _update_stats() -> void:
	if library == null or _stats_label == null:
		return
	var stats: Dictionary = library.get_storage_stats(false)
	var stored_bytes: int = int(stats.get("blob_bytes", 0))
	var active_bytes: int = int(stats.get("active_blob_bytes", stored_bytes))
	var size_text: String = NotLightL10n.text("library.stats.storage", {"size": _format_bytes(stored_bytes)})
	if active_bytes != stored_bytes:
		size_text += " · " + NotLightL10n.text("library.stats.active", {"size": _format_bytes(active_bytes)})
	_stats_label.text = NotLightL10n.text("library.stats.summary", {
		"size": size_text,
		"used": int(stats.get("used_count", 0)),
		"unused": int(stats.get("unused_count", 0)),
		"folders": int(stats.get("folder_count", 0)),
	})


func _update_grid_columns() -> void:
	if _grid == null:
		return
	if compact_mode:
		_grid.columns = 1
		return
	_update_full_library_layout()
	if _asset_host == null or not _asset_host.visible:
		_grid.columns = 1
		return

	# The host is the width the HBox actually assigned to cards after accounting
	# for folders and the inspector. It is deliberately a plain Control, so this
	# measurement cannot be inflated by GridContainer's own minimum size.
	var available: float = maxf(FULL_CARD_WIDTH, _asset_host.size.x - FULL_GRID_CONTENT_GUTTER)
	var cell_span: float = FULL_CARD_WIDTH + FULL_CARD_SEPARATION
	_grid.columns = clampi(int(floor((available + FULL_CARD_SEPARATION) / cell_span)), 1, 8)


func _update_full_library_layout() -> void:
	if compact_mode:
		return
	var view_width: float = _body.size.x if _body != null and _body.size.x > 0.0 else size.x
	view_width = maxf(0.0, view_width)
	var inspector_open: bool = _inspector_host != null and _inspector_host.visible
	var responsive_inspector_width: float = clampf(
		view_width * 0.30,
		FULL_INSPECTOR_MIN_WIDTH,
		FULL_INSPECTOR_WIDTH
	)
	var asset_width_without_folder: float = view_width - responsive_inspector_width - FULL_BODY_SEPARATION
	var inspector_replaces_asset_area: bool = inspector_open and (
		asset_width_without_folder < _required_grid_host_width(FULL_MIN_COLUMNS_WITH_INSPECTOR)
	)
	var asset_width_with_folder: float = asset_width_without_folder - FULL_FOLDER_WIDTH - FULL_BODY_SEPARATION

	# Responsive state is derived from how many real card columns fit, not from
	# arbitrary viewport breakpoints. The folder yields before it would reduce the
	# inspector layout below three columns; the inspector takes over only when even
	# two card columns cannot coexist with it.
	if _asset_host != null:
		_asset_host.visible = not inspector_replaces_asset_area
	if _folder_panel != null:
		var hide_folder: bool = inspector_replaces_asset_area or (
			inspector_open and asset_width_with_folder < _required_grid_host_width(FULL_MIN_COLUMNS_WITH_FOLDER_AND_INSPECTOR)
		)
		_folder_panel.visible = not hide_folder
	if _inspector_host == null:
		return
	if inspector_replaces_asset_area:
		_inspector_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_inspector_host.custom_minimum_size = Vector2.ZERO
		return
	_inspector_host.size_flags_horizontal = Control.SIZE_SHRINK_END
	_inspector_host.custom_minimum_size = Vector2(responsive_inspector_width, 0.0)


func _required_grid_host_width(column_count: int) -> float:
	var columns: int = maxi(1, column_count)
	return (
		FULL_GRID_CONTENT_GUTTER
		+ FULL_CARD_WIDTH * float(columns)
		+ FULL_CARD_SEPARATION * float(maxi(0, columns - 1))
	)


func _add_kind_filter_item(label_text: String, kind: int) -> void:
	var index: int = _kind_filter.item_count
	_kind_filter.add_item(label_text)
	_kind_filter.set_item_metadata(index, kind)


func _on_library_changed() -> void:
	_prune_bulk_selection()
	_refresh_tag_filter()
	if not _selected_asset_id.is_empty() and library.get_asset(_selected_asset_id).is_empty():
		_close_inspector()
	_refresh()


func _on_asset_metadata_changed(_asset_id: String) -> void:
	# Description participates in Library search and tags participate in filtering,
	# so metadata needs one targeted UI refresh. It intentionally does not fan out
	# through the coarse library_changed signal to media/Notes/runtime consumers.
	_prune_bulk_selection()
	_refresh_tag_filter()
	_refresh()


func _on_locale_changed(_locale: String) -> void:
	NotLightL10n.refresh_tree(self)
	_refresh_filter_labels()
	_refresh_tag_filter()
	_refresh_folders()
	if _import_dialog != null:
		_import_dialog.title = NotLightL10n.text("library.import_dialog")
		_import_dialog.filters = AssetImportCapabilities.file_dialog_filters()
	if _package_import_dialog != null:
		_package_import_dialog.title = NotLightL10n.text("exchange.library.import_title")
	if _package_export_dialog != null:
		_package_export_dialog.title = NotLightL10n.text("exchange.library.export_title")
	_refresh_exchange_menu_labels()


func _refresh_exchange_menu_labels() -> void:
	if _exchange_button == null:
		return
	var popup: PopupMenu = _exchange_button.get_popup()
	popup.clear()
	popup.add_item(NotLightL10n.text("exchange.library.import"), 1)
	popup.add_item(NotLightL10n.text("exchange.library.export"), 2)
	popup.add_item(NotLightL10n.text("exchange.library.export_without_notes"), 3)


func _refresh_filter_labels() -> void:
	if _kind_filter != null and _kind_filter.item_count >= 7:
		_kind_filter.set_item_text(0, NotLightL10n.text("library.kind.all"))
		_kind_filter.set_item_text(1, NotLightL10n.text("asset.kind.image_plural"))
		_kind_filter.set_item_text(2, NotLightL10n.text("asset.kind.video_plural"))
		_kind_filter.set_item_text(3, NotLightL10n.text("asset.kind.audio_plural"))
		_kind_filter.set_item_text(4, NotLightL10n.text("asset.kind.pdf_plural"))
		_kind_filter.set_item_text(5, NotLightL10n.text("asset.kind.note_plural"))
		_kind_filter.set_item_text(6, NotLightL10n.text("library.kind.3d"))
	if _usage_filter != null and _usage_filter.item_count >= 3:
		_usage_filter.set_item_text(0, NotLightL10n.text("library.usage.any"))
		_usage_filter.set_item_text(1, NotLightL10n.text("library.usage.used"))
		_usage_filter.set_item_text(2, NotLightL10n.text("library.usage.unused"))


func _show_error(message: String, danger: bool = true) -> void:
	if message.is_empty():
		return
	if danger:
		error_requested.emit(message)
	else:
		info_requested.emit(message)


func _format_bytes(byte_count: int) -> String:
	var value: float = float(maxi(0, byte_count))
	if value < 1024.0:
		return NotLightL10n.text("runtime.ui.video_player_overlay.900cf07d0d") % int(value)
	value /= 1024.0
	if value < 1024.0:
		return NotLightL10n.text("runtime.ui.video_player_overlay.7a76f539cd") % value
	value /= 1024.0
	if value < 1024.0:
		return NotLightL10n.text("runtime.ui.video_player_overlay.93eb0c0182") % value
	value /= 1024.0
	return NotLightL10n.text("runtime.ui.video_player_overlay.f4aee12c68") % value
