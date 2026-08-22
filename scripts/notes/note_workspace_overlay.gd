# SPDX-License-Identifier: GPL-3.0-or-later
class_name NoteWorkspaceOverlay
extends Control

signal closed
signal note_insert_requested(note_id: String)
signal note_workspace_insert_requested(note_id: String)
signal error_requested(message: String)
signal asset_preview_requested(asset_id: String)

const MODE_PREVIEW: int = 0
const MODE_SOURCE: int = 1
const MODE_GRAPH: int = 2
const SOURCE_SAVE_DELAY_SECONDS: float = 0.45
const SEARCH_DELAY_SECONDS: float = 0.12
const FOLDER_ALL: String = AssetLibraryService.FOLDER_ANY

var repository: NoteRepository
var _formula_service: FormulaRenderService
var _app_settings: AppSettingsStore
var allow_board_placement: bool = false
var _current_note_id: String = ""
var _current_content: String = ""
var _current_folder_filter: String = FOLDER_ALL
var _mode: int = MODE_PREVIEW
var _loading_source: bool = false
var _content_loading: bool = false
var _source_dirty: bool = false
var _note_ids: PackedStringArray = PackedStringArray()
var _workspace: PanelContainer
var _search: LineEdit
var _navigation_tree: NotesNavigationTree
var _folder_create_row: HBoxContainer
var _folder_name_edit: LineEdit
var _folder_edit_button: Button
var _folder_delete_button: Button
var _folder_delete_dialog: ConfirmActionDialog
var _folder_edit_id: String = ""
var _folder_delete_id: String = ""
var _backlinks_list: ItemList
var _notes_count_label: Label
var _folder_filter_label: Label
var _title_edit: LineEdit
var _folder_menu: MenuButton
var _folder_menu_ids: Dictionary = {}
var _status_label: Label
var _preview_button: Button
var _source_button: Button
var _graph_button: Button
var _insert_button: Button
var _insert_workspace_button: Button
var _preview: NotePreviewEditor
var _source: CodeEdit
var _graph: NotesGraphCanvas
var _preview_host: Control
var _source_host: Control
var _graph_host: Control
var _source_timer: Timer
var _search_timer: Timer
var _graph_global_button: Button
var _graph_local_button: Button
var _graph_hop_buttons: Array[Button] = []
var _graph_stats_label: Label
var _graph_local_mode: bool = false
var _graph_hops: int = 2


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	z_index = 1200
	_build_ui()
	NotLightL10n.connect_locale_changed(_on_locale_changed)
	_folder_delete_dialog = ConfirmActionDialog.new()
	_folder_delete_dialog.confirmed.connect(_confirm_folder_delete)
	add_child(_folder_delete_dialog)
	_source_timer = Timer.new()
	_source_timer.one_shot = true
	_source_timer.wait_time = SOURCE_SAVE_DELAY_SECONDS
	_source_timer.timeout.connect(_flush_source_editor)
	add_child(_source_timer)
	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = SEARCH_DELAY_SECONDS
	_search_timer.timeout.connect(_refresh_note_list)
	add_child(_search_timer)


func configure(
	note_repository: NoteRepository,
	placement_enabled: bool = false,
	formula_service: FormulaRenderService = null,
	app_settings: AppSettingsStore = null,
	asset_library: AssetLibraryService = null,
	image_cache: ImageAssetCache = null,
	video_media: VideoMediaService = null,
	audio_media: AudioMediaService = null,
	pdf_media: PdfMediaService = null,
	module_registry: ModuleRegistry = null
) -> void:
	if repository != null:
		_disconnect_repository()
	repository = note_repository
	_formula_service = formula_service
	_app_settings = app_settings
	allow_board_placement = placement_enabled
	if _insert_button != null:
		_insert_button.visible = placement_enabled
	if _insert_workspace_button != null:
		_insert_workspace_button.visible = placement_enabled
	if repository != null:
		if not repository.notes_changed.is_connected(_on_notes_changed):
			repository.notes_changed.connect(_on_notes_changed)
		if not repository.folders_changed.is_connected(_on_folders_changed):
			repository.folders_changed.connect(_on_folders_changed)
		if not repository.note_changed.is_connected(_on_note_changed):
			repository.note_changed.connect(_on_note_changed)
		if not repository.note_content_saved.is_connected(_on_note_content_saved):
			repository.note_content_saved.connect(_on_note_content_saved)
		if not repository.note_content_loaded.is_connected(_on_note_content_loaded):
			repository.note_content_loaded.connect(_on_note_content_loaded)
		if not repository.note_content_load_failed.is_connected(_on_note_content_load_failed):
			repository.note_content_load_failed.connect(_on_note_content_load_failed)
		if not repository.note_error.is_connected(_on_note_error):
			repository.note_error.connect(_on_note_error)
		if not repository.relation_index_changed.is_connected(_on_relation_index_changed):
			repository.relation_index_changed.connect(_on_relation_index_changed)
	_graph.configure(repository, _app_settings)
	_preview.configure(_formula_service, asset_library, image_cache, video_media, audio_media, pdf_media, _app_settings, module_registry)
	if not _preview.asset_preview_requested.is_connected(_on_asset_preview_requested):
		_preview.asset_preview_requested.connect(_on_asset_preview_requested)
	_refresh_folder_tree()
	_refresh_note_list()


func open_note(note_id: String, mode: int = MODE_PREVIEW) -> void:
	if repository == null or not repository.contains(note_id):
		_on_note_error(NotLightL10n.text("notes.error.missing"))
		return
	visible = true
	_set_current_note(note_id)
	_set_mode(mode)
	_search.grab_focus()


func open_browser() -> void:
	visible = true
	_refresh_folder_tree()
	_refresh_note_list()
	if _current_note_id.is_empty() and not _note_ids.is_empty():
		_set_current_note(_note_ids[0])
	_set_mode(MODE_PREVIEW if not _current_note_id.is_empty() else MODE_GRAPH)
	_search.grab_focus()


func open_graph(focus_note_id: String = "") -> void:
	visible = true
	_refresh_folder_tree()
	_refresh_note_list()
	_set_mode(MODE_GRAPH)
	if not focus_note_id.is_empty() and repository != null and repository.contains(focus_note_id):
		_set_current_note(focus_note_id)
		_graph.focus_note(focus_note_id)


func close_workspace() -> void:
	_preview.flush_pending_edits()
	_flush_source_editor()
	visible = false
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or event is not InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		close_workspace()
		get_viewport().set_input_as_handled()
	elif key.ctrl_pressed and key.keycode == KEY_S:
		_preview.flush_pending_edits()
		_flush_source_editor()
		get_viewport().set_input_as_handled()
	elif key.ctrl_pressed and key.keycode == KEY_G:
		_set_mode(MODE_GRAPH)
		get_viewport().set_input_as_handled()
	elif key.ctrl_pressed and key.keycode == KEY_N:
		_create_note()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.05, 0.08, 0.06, 0.34)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mouse: InputEventMouseButton = event as InputEventMouseButton
			if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
				close_workspace()
	)
	add_child(backdrop)

	_workspace = PanelContainer.new()
	_workspace.theme_type_variation = "NoteWorkspacePanel"
	_workspace.set_anchors_preset(Control.PRESET_FULL_RECT)
	_workspace.offset_left = 42.0
	_workspace.offset_top = 34.0
	_workspace.offset_right = -42.0
	_workspace.offset_bottom = -34.0
	_workspace.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_workspace)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	_workspace.add_child(root)
	_build_topbar(root)
	root.add_child(HSeparator.new())
	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)
	_build_sidebar(body)
	_build_content_area(body)


func _build_topbar(parent: VBoxContainer) -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	parent.add_child(margin)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)
	var mark_panel: PanelContainer = PanelContainer.new()
	mark_panel.theme_type_variation = "SaveStatusDot"
	mark_panel.custom_minimum_size = Vector2(36.0, 36.0)
	row.add_child(mark_panel)
	var mark: Label = Label.new()
	mark.text = "✎"
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.add_theme_color_override("font_color", NotLightTheme.semantic_color("accent"))
	mark_panel.add_child(mark)

	_title_edit = LineEdit.new()
	NotLightL10n.bind_placeholder_text(_title_edit, "notes.title.placeholder")
	_title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_edit.custom_minimum_size = Vector2(240.0, 40.0)
	_title_edit.text_submitted.connect(func(_value: String) -> void: _commit_title())
	_title_edit.focus_exited.connect(_commit_title)
	row.add_child(_title_edit)

	_folder_menu = MenuButton.new()
	_folder_menu.theme_type_variation = "GhostButton"
	_folder_menu.custom_minimum_size = Vector2(150.0, 40.0)
	NotLightL10n.bind_tooltip(_folder_menu, "notes.folder.move_tooltip")
	_folder_menu.get_popup().id_pressed.connect(_on_folder_menu_pressed)
	row.add_child(_folder_menu)

	_status_label = Label.new()
	_status_label.theme_type_variation = "CaptionLabel"
	_status_label.custom_minimum_size = Vector2(94.0, 0.0)
	row.add_child(_status_label)
	_preview_button = _mode_button("notes.mode.preview", MODE_PREVIEW)
	row.add_child(_preview_button)
	_source_button = _mode_button("notes.mode.source", MODE_SOURCE)
	row.add_child(_source_button)
	_graph_button = _mode_button("notes.mode.graph", MODE_GRAPH)
	row.add_child(_graph_button)
	_insert_button = Button.new()
	NotLightL10n.bind_text(_insert_button, "notes.place_simple_on_board")
	_insert_button.theme_type_variation = "PrimaryButton"
	NotLightL10n.bind_tooltip(_insert_button, "notes.place_simple_on_board_hint")
	_insert_button.visible = false
	_insert_button.pressed.connect(func() -> void:
		if not _current_note_id.is_empty():
			note_insert_requested.emit(_current_note_id)
	)
	row.add_child(_insert_button)
	_insert_workspace_button = Button.new()
	_insert_workspace_button.icon = load("res://assets/icons/workspace.svg") as Texture2D
	_insert_workspace_button.theme_type_variation = "IconButton"
	_insert_workspace_button.custom_minimum_size = Vector2(40.0, 40.0)
	_insert_workspace_button.visible = false
	NotLightL10n.bind_tooltip(_insert_workspace_button, "notes.place_workspace_on_board")
	_insert_workspace_button.pressed.connect(func() -> void:
		if not _current_note_id.is_empty():
			note_workspace_insert_requested.emit(_current_note_id)
	)
	row.add_child(_insert_workspace_button)
	var close_button: Button = Button.new()
	close_button.icon = load("res://assets/icons/close.svg") as Texture2D
	NotLightL10n.bind_tooltip(close_button, "notes.close")
	close_button.theme_type_variation = "IconButton"
	close_button.custom_minimum_size = Vector2(40.0, 40.0)
	close_button.pressed.connect(close_workspace)
	row.add_child(close_button)


func _build_sidebar(parent: HBoxContainer) -> void:
	var sidebar_panel: PanelContainer = PanelContainer.new()
	sidebar_panel.theme_type_variation = "NoteSidebarPanel"
	sidebar_panel.custom_minimum_size = Vector2(320.0, 0.0)
	parent.add_child(sidebar_panel)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	sidebar_panel.add_child(stack)

	var heading_row: HBoxContainer = HBoxContainer.new()
	heading_row.add_theme_constant_override("separation", 8)
	stack.add_child(heading_row)
	var heading: Label = Label.new()
	NotLightL10n.bind_text(heading, "notes.sidebar.title")
	heading.theme_type_variation = "SectionLabel"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_row.add_child(heading)
	_notes_count_label = Label.new()
	_notes_count_label.theme_type_variation = "SettingsValueLabel"
	heading_row.add_child(_notes_count_label)

	_search = LineEdit.new()
	NotLightL10n.bind_placeholder_text(_search, "notes.search.placeholder")
	_search.text_changed.connect(func(_value: String) -> void: _search_timer.start())
	stack.add_child(_search)

	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	stack.add_child(actions)
	var new_button: Button = Button.new()
	NotLightL10n.bind_text(new_button, "notes.new")
	new_button.icon = load("res://assets/icons/plus.svg") as Texture2D
	new_button.theme_type_variation = "PrimaryButton"
	new_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_button.pressed.connect(_create_note)
	actions.add_child(new_button)
	var folder_button: Button = Button.new()
	folder_button.icon = load("res://assets/icons/folder.svg") as Texture2D
	NotLightL10n.bind_tooltip(folder_button, "notes.folder.new")
	folder_button.theme_type_variation = "IconButton"
	folder_button.custom_minimum_size = Vector2(42.0, 42.0)
	folder_button.pressed.connect(_toggle_folder_create)
	actions.add_child(folder_button)

	_folder_create_row = HBoxContainer.new()
	_folder_create_row.visible = false
	_folder_create_row.add_theme_constant_override("separation", 6)
	stack.add_child(_folder_create_row)
	_folder_name_edit = LineEdit.new()
	NotLightL10n.bind_placeholder_text(_folder_name_edit, "notes.folder.name_placeholder")
	_folder_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_folder_name_edit.text_submitted.connect(func(_value: String) -> void: _create_folder())
	_folder_create_row.add_child(_folder_name_edit)
	var folder_create_button: Button = Button.new()
	folder_create_button.icon = load("res://assets/icons/check.svg") as Texture2D
	folder_create_button.theme_type_variation = "IconButton"
	folder_create_button.custom_minimum_size = Vector2(40.0, 40.0)
	NotLightL10n.bind_tooltip(folder_create_button, "notes.folder.create")
	folder_create_button.pressed.connect(_create_folder)
	_folder_create_row.add_child(folder_create_button)

	var navigation_header: HBoxContainer = HBoxContainer.new()
	navigation_header.add_theme_constant_override("separation", 4)
	stack.add_child(navigation_header)
	_folder_filter_label = Label.new()
	_folder_filter_label.theme_type_variation = "CaptionStrongLabel"
	_folder_filter_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_folder_filter_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	navigation_header.add_child(_folder_filter_label)
	_folder_edit_button = Button.new()
	_folder_edit_button.icon = load("res://assets/icons/edit.svg") as Texture2D
	_folder_edit_button.theme_type_variation = "IconButton"
	_folder_edit_button.custom_minimum_size = Vector2(30.0, 30.0)
	NotLightL10n.bind_tooltip(_folder_edit_button, "notes.folder.rename")
	_folder_edit_button.pressed.connect(_begin_folder_rename)
	navigation_header.add_child(_folder_edit_button)
	_folder_delete_button = Button.new()
	_folder_delete_button.icon = load("res://assets/icons/trash.svg") as Texture2D
	_folder_delete_button.theme_type_variation = "IconButton"
	_folder_delete_button.custom_minimum_size = Vector2(30.0, 30.0)
	NotLightL10n.bind_tooltip(_folder_delete_button, "notes.folder.delete")
	_folder_delete_button.pressed.connect(_request_folder_delete)
	navigation_header.add_child(_folder_delete_button)

	var navigation_panel: PanelContainer = PanelContainer.new()
	navigation_panel.theme_type_variation = "NoteInsetPanel"
	navigation_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(navigation_panel)
	_navigation_tree = NotesNavigationTree.new()
	_navigation_tree.custom_minimum_size = Vector2(0.0, 300.0)
	_navigation_tree.note_selected.connect(_on_navigation_note_selected)
	_navigation_tree.note_open_requested.connect(_on_navigation_note_open_requested)
	_navigation_tree.folder_selected.connect(_on_navigation_folder_selected)
	_navigation_tree.note_move_requested.connect(_on_navigation_note_move_requested)
	_navigation_tree.note_rename_requested.connect(_on_navigation_note_rename_requested)
	_navigation_tree.folder_rename_requested.connect(_on_navigation_folder_rename_requested)
	navigation_panel.add_child(_navigation_tree)

	var backlinks_title: Label = Label.new()
	NotLightL10n.bind_text(backlinks_title, "notes.backlinks.title")
	backlinks_title.theme_type_variation = "CaptionStrongLabel"
	stack.add_child(backlinks_title)
	_backlinks_list = ItemList.new()
	_backlinks_list.theme_type_variation = "NoteItemList"
	_backlinks_list.custom_minimum_size = Vector2(0.0, 108.0)
	_backlinks_list.allow_reselect = true
	_backlinks_list.item_selected.connect(_on_backlink_selected)
	stack.add_child(_backlinks_list)

	var hint: Label = Label.new()
	NotLightL10n.bind_text(hint, "notes.sidebar.hint")
	hint.theme_type_variation = "CaptionLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(hint)


func _build_content_area(parent: HBoxContainer) -> void:
	var content: Control = Control.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.clip_contents = true
	parent.add_child(content)

	_preview_host = MarginContainer.new()
	_preview_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	(_preview_host as MarginContainer).add_theme_constant_override("margin_left", 30)
	(_preview_host as MarginContainer).add_theme_constant_override("margin_right", 30)
	(_preview_host as MarginContainer).add_theme_constant_override("margin_top", 22)
	(_preview_host as MarginContainer).add_theme_constant_override("margin_bottom", 22)
	content.add_child(_preview_host)
	_preview = NotePreviewEditor.new()
	_preview.content_replace_requested.connect(_on_preview_replace_requested)
	_preview.note_link_requested.connect(_open_wikilink_target)
	_preview.source_edit_requested.connect(func() -> void: _set_mode(MODE_SOURCE))
	_preview.source_edit_at_requested.connect(_focus_source_offset)
	_preview_host.add_child(_preview)

	_source_host = MarginContainer.new()
	_source_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	(_source_host as MarginContainer).add_theme_constant_override("margin_left", 22)
	(_source_host as MarginContainer).add_theme_constant_override("margin_right", 22)
	(_source_host as MarginContainer).add_theme_constant_override("margin_top", 20)
	(_source_host as MarginContainer).add_theme_constant_override("margin_bottom", 20)
	content.add_child(_source_host)
	_source = CodeEdit.new()
	_source.theme_type_variation = "NoteCodeEdit"
	_source.gutters_draw_line_numbers = true
	_source.gutters_zero_pad_line_numbers = false
	_source.line_folding = false
	_source.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_source.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_source.text_changed.connect(_on_source_changed)
	_source.focus_exited.connect(_flush_source_editor)
	_source_host.add_child(_source)

	_graph_host = Control.new()
	_graph_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(_graph_host)
	_graph = NotesGraphCanvas.new()
	_graph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_graph.note_open_requested.connect(func(note_id: String) -> void:
		_set_current_note(note_id)
		_set_mode(MODE_PREVIEW)
	)
	_graph.relation_create_requested.connect(_on_graph_relation_create)
	_graph.relation_remove_requested.connect(_on_graph_relation_remove)
	_graph_host.add_child(_graph)
	_build_graph_toolbar()


func _build_graph_toolbar() -> void:
	var toolbar: PanelContainer = PanelContainer.new()
	toolbar.theme_type_variation = "NoteGraphToolbarPanel"
	toolbar.position = Vector2(18.0, 18.0)
	toolbar.custom_minimum_size = Vector2(620.0, 48.0)
	_graph_host.add_child(toolbar)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	toolbar.add_child(row)
	_graph_global_button = Button.new()
	NotLightL10n.bind_text(_graph_global_button, "notes.graph.scope.global")
	_graph_global_button.toggle_mode = true
	_graph_global_button.theme_type_variation = "GhostButton"
	_graph_global_button.pressed.connect(_set_graph_global)
	row.add_child(_graph_global_button)
	_graph_local_button = Button.new()
	NotLightL10n.bind_text(_graph_local_button, "notes.graph.scope.local")
	_graph_local_button.toggle_mode = true
	_graph_local_button.theme_type_variation = "GhostButton"
	_graph_local_button.pressed.connect(_set_graph_local)
	row.add_child(_graph_local_button)
	var hop_label: Label = Label.new()
	NotLightL10n.bind_text(hop_label, "notes.graph.hops")
	hop_label.theme_type_variation = "CaptionLabel"
	row.add_child(hop_label)
	for hops: int in range(1, 4):
		var button: Button = Button.new()
		button.text = str(hops)
		button.toggle_mode = true
		button.theme_type_variation = "GhostButton"
		button.custom_minimum_size = Vector2(38.0, 34.0)
		button.pressed.connect(func() -> void: _set_graph_hops(hops))
		_graph_hop_buttons.append(button)
		row.add_child(button)
	var reset_button: Button = Button.new()
	reset_button.icon = load("res://assets/icons/reset.svg") as Texture2D
	reset_button.theme_type_variation = "CompactIconButton"
	reset_button.focus_mode = Control.FOCUS_NONE
	reset_button.custom_minimum_size = Vector2(34.0, 34.0)
	NotLightL10n.bind_tooltip(reset_button, "notes.graph.reset")
	reset_button.pressed.connect(func() -> void: _graph.reset_layout(true))
	row.add_child(reset_button)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_graph_stats_label = Label.new()
	_graph_stats_label.theme_type_variation = "CaptionLabel"
	row.add_child(_graph_stats_label)
	_refresh_graph_toolbar()


func _mode_button(localization_key: String, requested_mode: int) -> Button:
	var button: Button = Button.new()
	NotLightL10n.bind_text(button, localization_key)
	button.toggle_mode = true
	button.theme_type_variation = "GhostButton"
	button.pressed.connect(func() -> void: _set_mode(requested_mode))
	return button


func _focus_source_offset(source_offset: int) -> void:
	_set_mode(MODE_SOURCE)
	var safe_offset: int = clampi(source_offset, 0, _source.text.length())
	var prefix: String = _source.text.substr(0, safe_offset)
	var line: int = prefix.count("\n")
	var last_newline: int = prefix.rfind("\n")
	var column: int = safe_offset if last_newline < 0 else safe_offset - last_newline - 1
	_source.set_caret_line(line)
	_source.set_caret_column(column)
	_source.grab_focus()


func _set_mode(requested_mode: int) -> void:
	if _mode == MODE_PREVIEW and requested_mode != MODE_PREVIEW:
		_preview.flush_pending_edits()
		_preview.deactivate_module_embeds()
	if requested_mode != MODE_GRAPH and _current_note_id.is_empty():
		requested_mode = MODE_GRAPH
	if _mode == MODE_SOURCE and requested_mode != MODE_SOURCE:
		_flush_source_editor()
	_mode = clampi(requested_mode, MODE_PREVIEW, MODE_GRAPH)
	_preview_host.visible = _mode == MODE_PREVIEW
	_source_host.visible = _mode == MODE_SOURCE
	_graph_host.visible = _mode == MODE_GRAPH
	_preview_button.set_pressed_no_signal(_mode == MODE_PREVIEW)
	_source_button.set_pressed_no_signal(_mode == MODE_SOURCE)
	_graph_button.set_pressed_no_signal(_mode == MODE_GRAPH)
	if _mode == MODE_PREVIEW:
		if _content_loading:
			_preview.set_markdown(NotLightL10n.text("notes.status.loading"), false)
		else:
			_preview.set_markdown(_current_content)
	elif _mode == MODE_SOURCE:
		_load_source_text(_current_content)
	else:
		_apply_graph_scope()
		_graph.call_deferred("fit_all")


func _set_current_note(note_id: String) -> void:
	if repository == null or not repository.contains(note_id):
		return
	_preview.flush_pending_edits()
	_flush_source_editor()
	if not _current_note_id.is_empty() and _current_note_id != note_id:
		repository.cancel_content_load(_current_note_id)
	_current_note_id = note_id
	_current_content = ""
	_content_loading = true
	_source.editable = false
	var note: Dictionary = repository.get_note(note_id)
	_title_edit.text = str(note.get("display_name", NotLightL10n.text("notes.untitled")))
	NotLightL10n.bind_text(_status_label, "notes.status.loading")
	_loading_source = true
	_source.text = ""
	_loading_source = false
	_source_dirty = false
	_preview.set_markdown(NotLightL10n.text("notes.status.loading"), false)
	_select_current_in_list()
	_refresh_backlinks()
	_refresh_folder_menu()
	if _mode == MODE_GRAPH:
		_apply_graph_scope()
	elif not _graph_local_mode:
		_graph.focus_note(note_id, false)
	if repository.has_cached_content(note_id):
		_apply_loaded_content(note_id, repository.peek_cached_content(note_id))
		return
	repository.request_content_load(note_id)


func _load_source_text(content: String) -> void:
	_loading_source = true
	_source.text = content
	_loading_source = false
	_source_dirty = false


func _on_source_changed() -> void:
	if _loading_source or _content_loading or _current_note_id.is_empty():
		return
	_current_content = _source.text
	_source_dirty = true
	NotLightL10n.bind_text(_status_label, "notes.status.editing")
	_source_timer.start()


func _flush_source_editor() -> void:
	if _content_loading or not _source_dirty or repository == null or _current_note_id.is_empty():
		return
	_source_timer.stop()
	if repository.request_save(_current_note_id, _current_content):
		_source_dirty = false
		NotLightL10n.bind_text(_status_label, "notes.status.saving")
	else:
		_on_note_error(repository.get_last_error())


func _on_preview_replace_requested(start_offset: int, end_offset: int, replacement: String, keep_live_editor: bool) -> void:
	if repository == null or _current_note_id.is_empty():
		return
	if start_offset < 0 or end_offset < start_offset or end_offset > _current_content.length():
		_on_note_error(NotLightL10n.text("notes.error.stale_edit"))
		return
	_current_content = _current_content.substr(0, start_offset) + replacement + _current_content.substr(end_offset)
	if not repository.request_save(_current_note_id, _current_content):
		_on_note_error(repository.get_last_error())
		return
	NotLightL10n.bind_text(_status_label, "notes.status.saving")
	if not keep_live_editor:
		_preview.set_markdown(_current_content)
	if _mode != MODE_SOURCE:
		_load_source_text(_current_content)


func _commit_title() -> void:
	if repository == null or _current_note_id.is_empty():
		return
	var requested: String = _title_edit.text.strip_edges()
	var current: Dictionary = repository.get_note(_current_note_id)
	if requested == str(current.get("display_name", "")):
		return
	if not repository.rename_note(_current_note_id, requested):
		_on_note_error(repository.get_last_error())
		_title_edit.text = str(current.get("display_name", NotLightL10n.text("notes.untitled")))


func _create_note() -> void:
	if repository == null:
		return
	var folder_id: String = "" if _current_folder_filter == FOLDER_ALL else _current_folder_filter
	var note_id: String = repository.create_note(NotLightL10n.text("notes.default_title"), "", folder_id)
	if note_id.is_empty():
		_on_note_error(repository.get_last_error())
		return
	_refresh_folder_tree()
	_refresh_note_list()
	_set_current_note(note_id)
	_set_mode(MODE_PREVIEW)
	_title_edit.select_all()
	_title_edit.grab_focus()


func _toggle_folder_create() -> void:
	_folder_edit_id = ""
	_folder_create_row.visible = not _folder_create_row.visible
	if _folder_create_row.visible:
		_folder_name_edit.text = ""
		NotLightL10n.bind_placeholder_text(_folder_name_edit, "notes.folder.name_placeholder")
		_folder_name_edit.grab_focus()


func _create_folder() -> void:
	if repository == null:
		return
	var requested_name: String = _folder_name_edit.text.strip_edges()
	if not _folder_edit_id.is_empty():
		var edited_id: String = _folder_edit_id
		if not repository.rename_folder(edited_id, requested_name):
			_on_note_error(repository.get_last_error())
			return
		_folder_edit_id = ""
		_folder_create_row.visible = false
		_folder_name_edit.text = ""
		_refresh_folder_tree()
		_refresh_folder_menu()
		return
	var parent_id: String = ""
	if _current_folder_filter != FOLDER_ALL and not _current_folder_filter.is_empty():
		parent_id = _current_folder_filter
	var folder_id: String = repository.create_folder(requested_name, parent_id)
	if folder_id.is_empty():
		_on_note_error(repository.get_last_error())
		return
	_folder_create_row.visible = false
	_folder_name_edit.text = ""
	_current_folder_filter = folder_id
	_refresh_folder_tree()
	_refresh_note_list()


func _begin_folder_rename() -> void:
	if repository == null or _current_folder_filter == FOLDER_ALL or _current_folder_filter.is_empty():
		return
	var folder: Dictionary = repository.get_folder(_current_folder_filter)
	if folder.is_empty():
		return
	_folder_edit_id = _current_folder_filter
	_folder_create_row.visible = true
	NotLightL10n.bind_placeholder_text(_folder_name_edit, "notes.folder.rename_placeholder")
	_folder_name_edit.text = str(folder.get("name", ""))
	_folder_name_edit.select_all()
	_folder_name_edit.grab_focus()


func _request_folder_delete() -> void:
	if repository == null or _current_folder_filter == FOLDER_ALL or _current_folder_filter.is_empty():
		return
	var folder: Dictionary = repository.get_folder(_current_folder_filter)
	if folder.is_empty():
		return
	_folder_delete_id = _current_folder_filter
	_folder_delete_dialog.open_dialog(
		NotLightL10n.text("notes.folder.delete_title"),
		NotLightL10n.text("notes.folder.delete_help", {"name": str(folder.get("name", ""))}),
		NotLightL10n.text("common.delete"),
		true
	)


func _confirm_folder_delete() -> void:
	if repository == null or _folder_delete_id.is_empty():
		return
	var delete_id: String = _folder_delete_id
	_folder_delete_id = ""
	if not repository.delete_folder(delete_id):
		_on_note_error(repository.get_last_error())
		return
	if _current_folder_filter == delete_id:
		_current_folder_filter = FOLDER_ALL
	_refresh_folder_tree()
	_refresh_note_list()
	_refresh_folder_menu()


func _refresh_folder_tree() -> void:
	if _navigation_tree == null:
		return
	if repository == null:
		_navigation_tree.configure(null)
		_update_folder_filter_label()
		return
	if _navigation_tree.repository != repository:
		_navigation_tree.configure(repository)
	else:
		_navigation_tree.refresh()
	if not _current_note_id.is_empty():
		_navigation_tree.set_selected_note(_current_note_id)
	_update_folder_filter_label()


func _on_navigation_folder_selected(folder_id: String) -> void:
	_current_folder_filter = folder_id
	_update_folder_filter_label()


func _update_folder_filter_label() -> void:
	if _folder_filter_label == null:
		return
	var can_manage_folder: bool = _current_folder_filter != FOLDER_ALL and not _current_folder_filter.is_empty()
	if _folder_edit_button != null:
		_folder_edit_button.disabled = not can_manage_folder
	if _folder_delete_button != null:
		_folder_delete_button.disabled = not can_manage_folder
	if _current_folder_filter == FOLDER_ALL:
		NotLightL10n.bind_text(_folder_filter_label, "notes.navigation.all")
	elif _current_folder_filter.is_empty():
		NotLightL10n.bind_text(_folder_filter_label, "notes.folder.unfiled")
	else:
		_folder_filter_label.text = repository.folder_path(_current_folder_filter) if repository != null else ""


func _refresh_note_list() -> void:
	_note_ids = PackedStringArray()
	if repository == null:
		if _notes_count_label != null:
			_notes_count_label.text = "0"
		return
	var query: String = _search.text if _search != null else ""
	var notes: Array[Dictionary] = repository.list_notes(query, AssetLibraryService.FOLDER_ANY)
	for note: Dictionary in notes:
		var note_id: String = str(note.get("id", ""))
		if not note_id.is_empty():
			_note_ids.append(note_id)
	if _notes_count_label != null:
		_notes_count_label.text = str(_note_ids.size())
	if _navigation_tree != null:
		_navigation_tree.set_query(query)
		if not _current_note_id.is_empty():
			_navigation_tree.set_selected_note(_current_note_id)


func _select_current_in_list() -> void:
	if _navigation_tree != null and not _current_note_id.is_empty():
		_navigation_tree.set_selected_note(_current_note_id)


func _on_navigation_note_selected(note_id: String) -> void:
	if repository == null or not repository.contains(note_id):
		return
	if note_id != _current_note_id:
		_set_current_note(note_id)
	if _mode == MODE_GRAPH:
		_apply_graph_scope()


func _on_navigation_note_open_requested(note_id: String, _open_in_new_tab: bool) -> void:
	if repository == null or not repository.contains(note_id):
		return
	_set_current_note(note_id)
	_set_mode(MODE_PREVIEW)


func _on_navigation_note_move_requested(note_id: String, folder_id: String) -> void:
	if repository == null or not repository.contains(note_id):
		return
	if not repository.move_note(note_id, folder_id):
		_on_note_error(repository.get_last_error())
		return
	_current_folder_filter = folder_id
	_refresh_folder_tree()
	_refresh_note_list()
	_refresh_folder_menu()


func _on_navigation_note_rename_requested(note_id: String, title: String) -> void:
	if repository == null or not repository.rename_note(note_id, title):
		_on_note_error(repository.get_last_error() if repository != null else NotLightL10n.text("notes.error.missing"))
		return
	if note_id == _current_note_id:
		_title_edit.text = str(repository.get_note(note_id).get("display_name", title))
	_refresh_note_list()


func _on_navigation_folder_rename_requested(folder_id: String, name: String) -> void:
	if repository == null or not repository.rename_folder(folder_id, name):
		_on_note_error(repository.get_last_error() if repository != null else NotLightL10n.text("notes.error.missing"))
		return
	_refresh_folder_tree()
	_refresh_folder_menu()


func _refresh_backlinks() -> void:
	if _backlinks_list == null:
		return
	_backlinks_list.clear()
	if repository == null or _current_note_id.is_empty():
		_backlinks_list.add_item(NotLightL10n.text("notes.backlinks.none"))
		_backlinks_list.set_item_disabled(0, true)
		return
	var backlinks: PackedStringArray = repository.get_backlinks(_current_note_id)
	if backlinks.is_empty():
		_backlinks_list.add_item(NotLightL10n.text("notes.backlinks.none"))
		_backlinks_list.set_item_disabled(0, true)
		return
	for source_id: String in backlinks:
		var note: Dictionary = repository.get_note(source_id)
		if note.is_empty():
			continue
		var index: int = _backlinks_list.item_count
		_backlinks_list.add_item(str(note.get("display_name", NotLightL10n.text("notes.untitled"))))
		_backlinks_list.set_item_metadata(index, source_id)


func _on_backlink_selected(index: int) -> void:
	if _backlinks_list == null or index < 0 or index >= _backlinks_list.item_count:
		return
	if _backlinks_list.is_item_disabled(index):
		return
	var note_id: String = str(_backlinks_list.get_item_metadata(index))
	if repository != null and repository.contains(note_id):
		_set_current_note(note_id)
		_set_mode(MODE_PREVIEW)


func _refresh_folder_menu() -> void:
	if _folder_menu == null:
		return
	var popup: PopupMenu = _folder_menu.get_popup()
	popup.clear()
	_folder_menu_ids.clear()
	var next_id: int = 1
	popup.add_item(NotLightL10n.text("notes.folder.unfiled"), next_id)
	_folder_menu_ids[next_id] = ""
	next_id += 1
	if repository != null:
		var folders: Array[Dictionary] = repository.list_folders()
		folders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return repository.folder_path(str(a.get("id", ""))).naturalnocasecmp_to(repository.folder_path(str(b.get("id", "")))) < 0
		)
		for folder: Dictionary in folders:
			var folder_id: String = str(folder.get("id", ""))
			if folder_id.is_empty():
				continue
			popup.add_item(repository.folder_path(folder_id), next_id)
			_folder_menu_ids[next_id] = folder_id
			next_id += 1
	if repository == null or _current_note_id.is_empty():
		NotLightL10n.bind_text(_folder_menu, "notes.folder.none_selected")
		_folder_menu.disabled = true
		return
	_folder_menu.disabled = false
	var note: Dictionary = repository.get_note(_current_note_id)
	var folder_id: String = str(note.get("folder_id", ""))
	_folder_menu.text = NotLightL10n.text("notes.folder.menu", {"folder": NotLightL10n.text("notes.folder.unfiled") if folder_id.is_empty() else repository.folder_path(folder_id)})


func _on_folder_menu_pressed(id: int) -> void:
	if repository == null or _current_note_id.is_empty() or not _folder_menu_ids.has(id):
		return
	var folder_id: String = str(_folder_menu_ids[id])
	if not repository.move_note(_current_note_id, folder_id):
		_on_note_error(repository.get_last_error())
		return
	_refresh_folder_tree()
	_refresh_note_list()
	_refresh_folder_menu()


func _set_graph_global() -> void:
	_graph_local_mode = false
	_graph.set_global_scope()
	_refresh_graph_toolbar()
	_graph.call_deferred("fit_all")


func _set_graph_local() -> void:
	if _current_note_id.is_empty():
		NotLightL10n.bind_text(_status_label, "notes.graph.local_requires_note")
		return
	_graph_local_mode = true
	_graph.set_local_scope(_current_note_id, _graph_hops)
	_refresh_graph_toolbar()
	_graph.call_deferred("fit_all")


func _set_graph_hops(hops: int) -> void:
	_graph_hops = clampi(hops, 1, 3)
	if _graph_local_mode and not _current_note_id.is_empty():
		_graph.set_local_scope(_current_note_id, _graph_hops)
	_refresh_graph_toolbar()


func _apply_graph_scope() -> void:
	if _graph_local_mode and not _current_note_id.is_empty():
		_graph.set_local_scope(_current_note_id, _graph_hops)
	else:
		_graph.set_global_scope()
		if not _current_note_id.is_empty():
			_graph.focus_note(_current_note_id, false)
	_refresh_graph_toolbar()


func _refresh_graph_toolbar() -> void:
	if _graph_global_button == null:
		return
	_graph_global_button.set_pressed_no_signal(not _graph_local_mode)
	_graph_local_button.set_pressed_no_signal(_graph_local_mode)
	for index: int in range(_graph_hop_buttons.size()):
		var button: Button = _graph_hop_buttons[index]
		button.set_pressed_no_signal(index + 1 == _graph_hops)
		button.disabled = not _graph_local_mode
	var summary: Dictionary = _graph.get_graph_summary() if _graph != null else {}
	var nodes: int = int(summary.get("nodes", 0))
	var textual_edges: int = int(summary.get("textual_edges", 0))
	var explicit_edges: int = int(summary.get("explicit_edges", 0))
	var suffix: String = ""
	if bool(summary.get("truncated", false)):
		suffix = NotLightL10n.text("ui.format.append_middle_dot") % NotLightL10n.text("notes.graph.truncated")
	_graph_stats_label.text = NotLightL10n.text("notes.graph.stats_split", {
		"nodes": nodes,
		"textual": textual_edges,
		"explicit": explicit_edges,
	}) + suffix


func _on_locale_changed(_locale: String) -> void:
	_refresh_folder_tree()
	_refresh_note_list()
	_refresh_backlinks()
	_refresh_folder_menu()
	_refresh_graph_toolbar()
	if _graph != null:
		_graph.queue_redraw()


func _on_relation_index_changed() -> void:
	_refresh_backlinks()
	if _mode == MODE_GRAPH:
		_apply_graph_scope()


func _open_wikilink_target(target: String) -> void:
	if repository == null:
		return
	var note_id: String = repository.resolve_title(target)
	if note_id.is_empty():
		_status_label.text = NotLightL10n.text("notes.status.unresolved_link", {"target": target.left(80)})
		return
	_set_current_note(note_id)
	_set_mode(MODE_PREVIEW)


func _on_graph_relation_create(source_note_id: String, target_note_id: String) -> void:
	if repository != null and not repository.add_explicit_link(source_note_id, target_note_id):
		_on_note_error(repository.get_last_error())


func _on_graph_relation_remove(source_note_id: String, target_note_id: String) -> void:
	if repository != null and not repository.remove_explicit_link(source_note_id, target_note_id):
		_on_note_error(repository.get_last_error())


func _on_notes_changed() -> void:
	_refresh_folder_tree()
	_refresh_note_list()
	if not _current_note_id.is_empty() and (repository == null or not repository.contains(_current_note_id)):
		_current_note_id = ""
		_current_content = ""
		_content_loading = false
		_source.editable = false
		_title_edit.text = ""
		_refresh_backlinks()
		_refresh_folder_menu()
		_set_mode(MODE_GRAPH)
	if _mode == MODE_GRAPH:
		_apply_graph_scope()


func _on_folders_changed() -> void:
	_refresh_folder_tree()
	_refresh_folder_menu()
	_refresh_note_list()


func _on_note_changed(note_id: String) -> void:
	_refresh_note_list()
	if note_id != _current_note_id or repository == null:
		return
	var note: Dictionary = repository.get_note(note_id)
	# Background note/index events must not rewrite a title field while the
	# researcher is actively editing it. Commit remains explicit on Enter/focus
	# loss; once focus leaves, the next repository event can refresh the field.
	if not _title_edit.has_focus():
		var next_title: String = str(note.get("display_name", NotLightL10n.text("notes.untitled")))
		if _title_edit.text != next_title:
			_title_edit.text = next_title
	_refresh_folder_menu()
	if _source_dirty:
		return
	if repository.has_cached_content(note_id):
		var content: String = repository.peek_cached_content(note_id)
		if content != _current_content or _content_loading:
			_apply_loaded_content(note_id, content)
	elif not _content_loading:
		_content_loading = true
		_source.editable = false
		NotLightL10n.bind_text(_status_label, "notes.status.loading")
		repository.request_content_load(note_id)


func _on_note_content_loaded(note_id: String, content: String) -> void:
	if note_id != _current_note_id:
		return
	_apply_loaded_content(note_id, content)


func _apply_loaded_content(note_id: String, content: String) -> void:
	if note_id != _current_note_id:
		return
	_content_loading = false
	_source.editable = true
	_current_content = content
	_load_source_text(content)
	_preview.set_markdown(content, false)
	NotLightL10n.bind_text(_status_label, "notes.status.saved")


func _on_note_content_load_failed(note_id: String, message: String) -> void:
	if note_id != _current_note_id:
		return
	_content_loading = false
	_source.editable = false
	NotLightL10n.bind_text(_status_label, "notes.status.error")
	error_requested.emit(message)


func _on_note_content_saved(note_id: String, _revision: int) -> void:
	if note_id == _current_note_id:
		NotLightL10n.bind_text(_status_label, "notes.status.saved")


func _on_asset_preview_requested(asset_id: String) -> void:
	asset_preview_requested.emit(asset_id)


func _on_note_error(message: String) -> void:
	if _status_label != null:
		NotLightL10n.bind_text(_status_label, "notes.status.error")
	if not message.strip_edges().is_empty():
		error_requested.emit(message)


func _disconnect_repository() -> void:
	if repository == null:
		return
	if repository.notes_changed.is_connected(_on_notes_changed):
		repository.notes_changed.disconnect(_on_notes_changed)
	if repository.folders_changed.is_connected(_on_folders_changed):
		repository.folders_changed.disconnect(_on_folders_changed)
	if repository.note_changed.is_connected(_on_note_changed):
		repository.note_changed.disconnect(_on_note_changed)
	if repository.note_content_saved.is_connected(_on_note_content_saved):
		repository.note_content_saved.disconnect(_on_note_content_saved)
	if repository.note_content_loaded.is_connected(_on_note_content_loaded):
		repository.note_content_loaded.disconnect(_on_note_content_loaded)
	if repository.note_content_load_failed.is_connected(_on_note_content_load_failed):
		repository.note_content_load_failed.disconnect(_on_note_content_load_failed)
	if repository.note_error.is_connected(_on_note_error):
		repository.note_error.disconnect(_on_note_error)
	if repository.relation_index_changed.is_connected(_on_relation_index_changed):
		repository.relation_index_changed.disconnect(_on_relation_index_changed)
