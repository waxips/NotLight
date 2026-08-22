# SPDX-License-Identifier: GPL-3.0-or-later
class_name NoteBoardWorkspaceSurface
extends Control

signal surface_error(message: String)
signal asset_preview_requested(asset_id: String)

const MODE_PREVIEW: int = 0
const MODE_SOURCE: int = 1
const MODE_GRAPH: int = 2
const SOURCE_SAVE_DELAY_SECONDS: float = 0.45
const SEARCH_DELAY_SECONDS: float = 0.12
const SIDEBAR_FULL_WIDTH: float = 210.0
const SIDEBAR_COMPACT_WIDTH: float = 168.0

var repository: NoteRepository
var formula_service: FormulaRenderService
var app_settings: AppSettingsStore
var session: BoardSession
var entity_id: int = 0
var _tabs: PackedStringArray = PackedStringArray()
var _active_tab: int = 0
var _current_note_id: String = ""
var _current_content: String = ""
var _mode: int = MODE_PREVIEW
var _source_loading: bool = false
var _source_dirty: bool = false
var _content_loading: bool = false
var _sidebar: PanelContainer
var _navigation: NotesNavigationTree
var _search: LineEdit
var _folder_create_row: HBoxContainer
var _folder_name_edit: LineEdit
var _tabs_row: HBoxContainer
var _title_label: Label
var _preview: NotePreviewEditor
var _source: CodeEdit
var _graph: NotesGraphCanvas
var _preview_host: Control
var _source_host: Control
var _graph_host: Control
var _preview_button: Button
var _source_button: Button
var _graph_button: Button
var _graph_scope_global: Button
var _graph_scope_local: Button
var _graph_hop_buttons: Array[Button] = []
var _graph_local: bool = true
var _graph_hops: int = 2
var _source_timer: Timer
var _search_timer: Timer
var _presentation_mode: String = "full"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_build_ui()
	_source_timer = Timer.new()
	_source_timer.one_shot = true
	_source_timer.wait_time = SOURCE_SAVE_DELAY_SECONDS
	_source_timer.timeout.connect(_flush_source)
	add_child(_source_timer)
	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = SEARCH_DELAY_SECONDS
	_search_timer.timeout.connect(_refresh_navigation)
	add_child(_search_timer)
	NotLightL10n.connect_locale_changed(_on_locale_changed)


func _exit_tree() -> void:
	_flush_preview()
	_flush_source()
	_disconnect_repository()
	NotLightL10n.disconnect_locale_changed(_on_locale_changed)


func configure(
	note_repository: NoteRepository,
	render_service: FormulaRenderService,
	settings: AppSettingsStore,
	board_session: BoardSession,
	portal_entity_id: int,
	asset_library: AssetLibraryService = null,
	image_cache: ImageAssetCache = null,
	video_media: VideoMediaService = null,
	audio_media: AudioMediaService = null,
	pdf_media: PdfMediaService = null,
	module_registry: ModuleRegistry = null
) -> void:
	_disconnect_repository()
	repository = note_repository
	formula_service = render_service
	app_settings = settings
	session = board_session
	entity_id = portal_entity_id
	if repository != null:
		repository.note_content_loaded.connect(_on_content_loaded)
		repository.note_content_load_failed.connect(_on_content_load_failed)
		repository.note_content_saved.connect(_on_content_saved)
		repository.note_changed.connect(_on_note_changed)
		repository.notes_changed.connect(_on_notes_changed)
		repository.folders_changed.connect(_on_folders_changed)
	_preview.configure(formula_service, asset_library, image_cache, video_media, audio_media, pdf_media, app_settings, module_registry)
	if not _preview.asset_preview_requested.is_connected(_on_asset_preview_requested):
		_preview.asset_preview_requested.connect(_on_asset_preview_requested)
	_graph.configure(repository, app_settings)
	_navigation.configure(repository)
	sync_from_store()


func sync_from_store() -> void:
	if session == null or entity_id <= 0 or not session.runtime.model.note_portals.contains(entity_id):
		return
	_tabs = session.runtime.model.note_portals.get_workspace_tabs(entity_id)
	if _tabs.is_empty():
		var fallback: String = session.runtime.model.note_portals.get_note_id(entity_id)
		if not fallback.is_empty():
			_tabs.append(fallback)
	_active_tab = clampi(session.runtime.model.note_portals.get_workspace_active_index(entity_id), 0, maxi(0, _tabs.size() - 1))
	_rebuild_tabs()
	if not _tabs.is_empty():
		_open_note(_tabs[_active_tab], false)
	_refresh_navigation()


func notlight_set_host_presentation(presentation: Dictionary) -> void:
	_presentation_mode = str(presentation.get("mode", "full"))
	if _sidebar == null:
		return
	if _presentation_mode == "content_only":
		_sidebar.visible = false
	elif _presentation_mode == "compact":
		_sidebar.visible = true
		_sidebar.custom_minimum_size.x = SIDEBAR_COMPACT_WIDTH
	else:
		_sidebar.visible = true
		_sidebar.custom_minimum_size.x = SIDEBAR_FULL_WIDTH


func _build_ui() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	var top: PanelContainer = PanelContainer.new()
	top.theme_type_variation = "NoteBoardWorkspaceTopbar"
	root.add_child(top)
	var top_stack: VBoxContainer = VBoxContainer.new()
	top_stack.add_theme_constant_override("separation", 4)
	top.add_child(top_stack)
	var title_row: HBoxContainer = HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 5)
	top_stack.add_child(title_row)
	_title_label = Label.new()
	_title_label.theme_type_variation = "CaptionStrongLabel"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_row.add_child(_title_label)
	_preview_button = _mode_button("notes.mode.preview", MODE_PREVIEW)
	title_row.add_child(_preview_button)
	_source_button = _mode_button("notes.mode.source", MODE_SOURCE)
	title_row.add_child(_source_button)
	_graph_button = _mode_button("notes.mode.graph", MODE_GRAPH)
	title_row.add_child(_graph_button)
	var tabs_clip: ScrollContainer = ScrollContainer.new()
	tabs_clip.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tabs_clip.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs_clip.custom_minimum_size = Vector2(0.0, 36.0)
	top_stack.add_child(tabs_clip)
	_tabs_row = HBoxContainer.new()
	_tabs_row.add_theme_constant_override("separation", 4)
	tabs_clip.add_child(_tabs_row)

	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)
	_sidebar = PanelContainer.new()
	_sidebar.theme_type_variation = "NoteBoardWorkspaceSidebar"
	_sidebar.custom_minimum_size = Vector2(SIDEBAR_FULL_WIDTH, 0.0)
	body.add_child(_sidebar)
	var sidebar_stack: VBoxContainer = VBoxContainer.new()
	sidebar_stack.add_theme_constant_override("separation", 6)
	_sidebar.add_child(sidebar_stack)
	var explorer_actions: HBoxContainer = HBoxContainer.new()
	explorer_actions.add_theme_constant_override("separation", 5)
	sidebar_stack.add_child(explorer_actions)
	var new_note_button: Button = Button.new()
	new_note_button.icon = load("res://assets/icons/plus.svg") as Texture2D
	new_note_button.theme_type_variation = "CompactIconButton"
	new_note_button.custom_minimum_size = Vector2(32.0, 32.0)
	new_note_button.focus_mode = Control.FOCUS_NONE
	NotLightL10n.bind_tooltip(new_note_button, "notes.new")
	new_note_button.pressed.connect(_create_note_from_sidebar)
	explorer_actions.add_child(new_note_button)
	var new_folder_button: Button = Button.new()
	new_folder_button.icon = load("res://assets/icons/folder.svg") as Texture2D
	new_folder_button.theme_type_variation = "CompactIconButton"
	new_folder_button.custom_minimum_size = Vector2(32.0, 32.0)
	new_folder_button.focus_mode = Control.FOCUS_NONE
	NotLightL10n.bind_tooltip(new_folder_button, "notes.folder.create")
	new_folder_button.pressed.connect(_toggle_folder_create)
	explorer_actions.add_child(new_folder_button)
	var explorer_hint: Label = Label.new()
	explorer_hint.text = "F2"
	explorer_hint.theme_type_variation = "CaptionLabel"
	explorer_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	explorer_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	NotLightL10n.bind_tooltip(explorer_hint, "notes.navigation.rename_hint")
	explorer_actions.add_child(explorer_hint)
	_folder_create_row = HBoxContainer.new()
	_folder_create_row.visible = false
	_folder_create_row.add_theme_constant_override("separation", 4)
	sidebar_stack.add_child(_folder_create_row)
	_folder_name_edit = LineEdit.new()
	_folder_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	NotLightL10n.bind_placeholder_text(_folder_name_edit, "notes.folder.name_placeholder")
	_folder_name_edit.text_submitted.connect(func(_value: String) -> void: _commit_folder_create())
	_folder_name_edit.gui_input.connect(_on_folder_name_input)
	_folder_create_row.add_child(_folder_name_edit)
	var confirm_folder_button: Button = Button.new()
	confirm_folder_button.icon = load("res://assets/icons/check.svg") as Texture2D
	confirm_folder_button.theme_type_variation = "CompactIconButton"
	confirm_folder_button.custom_minimum_size = Vector2(30.0, 30.0)
	confirm_folder_button.focus_mode = Control.FOCUS_NONE
	NotLightL10n.bind_tooltip(confirm_folder_button, "notes.folder.create")
	confirm_folder_button.pressed.connect(_commit_folder_create)
	_folder_create_row.add_child(confirm_folder_button)
	_search = LineEdit.new()
	NotLightL10n.bind_placeholder_text(_search, "notes.search.placeholder")
	_search.text_changed.connect(func(_value: String) -> void: _search_timer.start())
	sidebar_stack.add_child(_search)
	_navigation = NotesNavigationTree.new()
	_navigation.note_selected.connect(_on_navigation_note_selected)
	_navigation.note_open_requested.connect(_on_navigation_note_open_requested)
	_navigation.note_move_requested.connect(_on_navigation_note_move_requested)
	_navigation.note_rename_requested.connect(_on_navigation_note_rename_requested)
	_navigation.folder_rename_requested.connect(_on_navigation_folder_rename_requested)
	_navigation.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar_stack.add_child(_navigation)

	var content: Control = Control.new()
	content.clip_contents = true
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(content)
	_preview_host = MarginContainer.new()
	_preview_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	(_preview_host as MarginContainer).add_theme_constant_override("margin_left", 12)
	(_preview_host as MarginContainer).add_theme_constant_override("margin_right", 12)
	(_preview_host as MarginContainer).add_theme_constant_override("margin_top", 10)
	(_preview_host as MarginContainer).add_theme_constant_override("margin_bottom", 10)
	content.add_child(_preview_host)
	_preview = NotePreviewEditor.new()
	_preview.content_replace_requested.connect(_on_preview_replace_requested)
	_preview.note_link_requested.connect(_open_wikilink)
	_preview.source_edit_requested.connect(func() -> void: _set_mode(MODE_SOURCE))
	_preview.source_edit_at_requested.connect(_focus_source_offset)
	_preview_host.add_child(_preview)
	_source_host = MarginContainer.new()
	_source_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	(_source_host as MarginContainer).add_theme_constant_override("margin_left", 10)
	(_source_host as MarginContainer).add_theme_constant_override("margin_right", 10)
	(_source_host as MarginContainer).add_theme_constant_override("margin_top", 8)
	(_source_host as MarginContainer).add_theme_constant_override("margin_bottom", 8)
	content.add_child(_source_host)
	_source = CodeEdit.new()
	_source.theme_type_variation = "NoteCodeEdit"
	_source.gutters_draw_line_numbers = true
	_source.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_source.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_source.text_changed.connect(_on_source_changed)
	_source.focus_exited.connect(_flush_source)
	_source_host.add_child(_source)
	_graph_host = Control.new()
	_graph_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(_graph_host)
	_graph = NotesGraphCanvas.new()
	_graph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_graph.note_open_requested.connect(func(note_id: String) -> void: _open_note(note_id, true))
	_graph.relation_create_requested.connect(_create_relation)
	_graph.relation_remove_requested.connect(_remove_relation)
	_graph_host.add_child(_graph)
	_build_graph_toolbar()
	_set_mode(MODE_PREVIEW)


func _build_graph_toolbar() -> void:
	var toolbar: PanelContainer = PanelContainer.new()
	toolbar.theme_type_variation = "NoteGraphToolbarPanel"
	toolbar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	toolbar.position = Vector2(10.0, 10.0)
	_graph_host.add_child(toolbar)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	toolbar.add_child(row)
	_graph_scope_global = Button.new()
	NotLightL10n.bind_text(_graph_scope_global, "notes.graph.scope.global")
	_graph_scope_global.theme_type_variation = "GhostButton"
	_graph_scope_global.toggle_mode = true
	_graph_scope_global.focus_mode = Control.FOCUS_NONE
	_graph_scope_global.pressed.connect(func() -> void:
		_graph_local = false
		_apply_graph_scope()
	)
	row.add_child(_graph_scope_global)
	_graph_scope_local = Button.new()
	NotLightL10n.bind_text(_graph_scope_local, "notes.graph.scope.local")
	_graph_scope_local.theme_type_variation = "GhostButton"
	_graph_scope_local.toggle_mode = true
	_graph_scope_local.focus_mode = Control.FOCUS_NONE
	_graph_scope_local.pressed.connect(func() -> void:
		_graph_local = true
		_apply_graph_scope()
	)
	row.add_child(_graph_scope_local)
	var depth: Label = Label.new()
	NotLightL10n.bind_text(depth, "notes.graph.hops")
	depth.theme_type_variation = "CaptionLabel"
	row.add_child(depth)
	for hops: int in range(1, 4):
		var hop_button: Button = Button.new()
		hop_button.text = str(hops)
		hop_button.theme_type_variation = "GhostButton"
		hop_button.toggle_mode = true
		hop_button.focus_mode = Control.FOCUS_NONE
		hop_button.custom_minimum_size = Vector2(30.0, 30.0)
		hop_button.pressed.connect(_set_graph_hops.bind(hops))
		_graph_hop_buttons.append(hop_button)
		row.add_child(hop_button)
	var reset_button: Button = Button.new()
	reset_button.icon = load("res://assets/icons/reset.svg") as Texture2D
	reset_button.theme_type_variation = "CompactIconButton"
	reset_button.focus_mode = Control.FOCUS_NONE
	reset_button.custom_minimum_size = Vector2(34.0, 34.0)
	NotLightL10n.bind_tooltip(reset_button, "notes.graph.reset")
	reset_button.pressed.connect(func() -> void: _graph.reset_layout(true))
	row.add_child(reset_button)
	_refresh_graph_toolbar()


func _set_graph_hops(hops: int) -> void:
	_graph_hops = clampi(hops, 1, 3)
	_graph_local = true
	_apply_graph_scope()


func _apply_graph_scope() -> void:
	if _graph == null:
		return
	if _graph_local and not _current_note_id.is_empty():
		_graph.set_local_scope(_current_note_id, _graph_hops)
	else:
		_graph.set_global_scope()
	_refresh_graph_toolbar()


func _refresh_graph_toolbar() -> void:
	if _graph_scope_global != null:
		_graph_scope_global.set_pressed_no_signal(not _graph_local)
	if _graph_scope_local != null:
		_graph_scope_local.set_pressed_no_signal(_graph_local)
	for index: int in range(_graph_hop_buttons.size()):
		_graph_hop_buttons[index].set_pressed_no_signal(_graph_local and index + 1 == _graph_hops)


func _mode_button(key: String, mode: int) -> Button:
	var button: Button = Button.new()
	NotLightL10n.bind_text(button, key)
	button.theme_type_variation = "GhostButton"
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void: _set_mode(mode))
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


func _set_mode(mode: int) -> void:
	_flush_preview()
	if _mode == MODE_PREVIEW and mode != MODE_PREVIEW:
		_preview.deactivate_module_embeds()
	if _mode == MODE_SOURCE and mode != MODE_SOURCE:
		_flush_source()
	_mode = clampi(mode, MODE_PREVIEW, MODE_GRAPH)
	if _preview_host == null:
		return
	_preview_host.visible = _mode == MODE_PREVIEW
	_source_host.visible = _mode == MODE_SOURCE
	_graph_host.visible = _mode == MODE_GRAPH
	_preview_button.set_pressed_no_signal(_mode == MODE_PREVIEW)
	_source_button.set_pressed_no_signal(_mode == MODE_SOURCE)
	_graph_button.set_pressed_no_signal(_mode == MODE_GRAPH)
	if _mode == MODE_GRAPH:
		_apply_graph_scope()
		_graph.call_deferred("fit_all")


func _open_note(note_id: String, new_tab: bool) -> void:
	if repository == null or not repository.contains(note_id):
		return
	_flush_preview()
	_flush_source()
	if new_tab:
		var existing: int = _tabs.find(note_id)
		if existing < 0:
			if _tabs.size() >= NotePortalStore.MAX_WORKSPACE_TABS:
				surface_error.emit(NotLightL10n.text("notes.tabs.limit", {"count": NotePortalStore.MAX_WORKSPACE_TABS}))
				return
			_tabs.append(note_id)
			existing = _tabs.size() - 1
		_active_tab = existing
	else:
		if _tabs.is_empty():
			_tabs.append(note_id)
			_active_tab = 0
		else:
			_tabs[_active_tab] = note_id
			_tabs = _deduplicate_tabs(_tabs, _active_tab)
			_active_tab = maxi(0, _tabs.find(note_id))
	_commit_workspace_state()
	_rebuild_tabs()
	_load_current_note(note_id)


func _load_current_note(note_id: String) -> void:
	_current_note_id = note_id
	_current_content = ""
	_content_loading = true
	_source_dirty = false
	var note: Dictionary = repository.get_note(note_id) if repository != null else {}
	_title_label.text = str(note.get("display_name", NotLightL10n.text("notes.untitled")))
	_source_loading = true
	_source.text = ""
	_source_loading = false
	_preview.set_markdown(NotLightL10n.text("notes.status.loading"), false)
	_navigation.set_selected_note(note_id)
	if repository != null and repository.has_cached_content(note_id):
		_apply_content(note_id, repository.peek_cached_content(note_id))
	elif repository != null:
		repository.request_content_load(note_id)
	if _mode == MODE_GRAPH:
		_apply_graph_scope()


func _rebuild_tabs() -> void:
	if _tabs_row == null:
		return
	for child: Node in _tabs_row.get_children():
		child.queue_free()
	for index: int in range(_tabs.size()):
		var note_id: String = _tabs[index]
		var note: Dictionary = repository.get_note(note_id) if repository != null else {}
		var title: String = str(note.get("display_name", NotLightL10n.text("notes.untitled")))
		var tab: Button = Button.new()
		tab.text = title
		tab.theme_type_variation = "NoteActiveTabButton" if index == _active_tab else "NoteTabButton"
		tab.focus_mode = Control.FOCUS_NONE
		tab.custom_minimum_size = Vector2(88.0, 30.0)
		tab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tab.pressed.connect(_activate_tab.bind(index))
		_tabs_row.add_child(tab)
		if _tabs.size() > 1:
			var close: Button = Button.new()
			close.icon = load("res://assets/icons/close.svg") as Texture2D
			close.theme_type_variation = "CompactIconButton"
			close.custom_minimum_size = Vector2(27.0, 27.0)
			close.focus_mode = Control.FOCUS_NONE
			NotLightL10n.bind_tooltip(close, "notes.tabs.close")
			close.pressed.connect(_close_tab.bind(index))
			_tabs_row.add_child(close)


func _activate_tab(index: int) -> void:
	if index < 0 or index >= _tabs.size() or index == _active_tab:
		return
	_flush_preview()
	_flush_source()
	_active_tab = index
	_commit_workspace_state()
	_rebuild_tabs()
	_load_current_note(_tabs[_active_tab])


func _close_tab(index: int) -> void:
	if _tabs.size() <= 1 or index < 0 or index >= _tabs.size():
		return
	_flush_preview()
	_flush_source()
	_tabs.remove_at(index)
	if index < _active_tab:
		_active_tab -= 1
	elif index == _active_tab:
		_active_tab = mini(_active_tab, _tabs.size() - 1)
	_commit_workspace_state()
	_rebuild_tabs()
	_load_current_note(_tabs[_active_tab])


func _commit_workspace_state() -> void:
	if session == null or entity_id <= 0:
		return
	session.runtime.model.note_portals.set_workspace_state(entity_id, _tabs, _active_tab)


func _deduplicate_tabs(source: PackedStringArray, preferred_index: int) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	var preferred: String = source[preferred_index] if preferred_index >= 0 and preferred_index < source.size() else ""
	for index: int in range(source.size()):
		var value: String = source[index]
		if value.is_empty() or seen.has(value):
			continue
		seen[value] = true
		result.append(value)
	if not preferred.is_empty() and result.find(preferred) < 0:
		result.append(preferred)
	return result


func _refresh_navigation() -> void:
	if _navigation == null:
		return
	_navigation.set_query(_search.text if _search != null else "")
	if not _current_note_id.is_empty():
		_navigation.set_selected_note(_current_note_id)


func _create_note_from_sidebar() -> void:
	if repository == null:
		return
	var folder_id: String = _creation_folder_id()
	var note_id: String = repository.create_note(NotLightL10n.text("notes.new"), "", folder_id)
	if note_id.is_empty():
		surface_error.emit(repository.get_last_error())
		return
	_refresh_navigation()
	_open_note(note_id, true)


func _toggle_folder_create() -> void:
	if _folder_create_row == null or _folder_name_edit == null:
		return
	_folder_create_row.visible = not _folder_create_row.visible
	if _folder_create_row.visible:
		_folder_name_edit.text = ""
		_folder_name_edit.grab_focus()


func _commit_folder_create() -> void:
	if repository == null or _folder_name_edit == null:
		return
	var name: String = _folder_name_edit.text.strip_edges()
	if name.is_empty():
		_folder_name_edit.grab_focus()
		return
	var folder_id: String = repository.create_folder(name, _creation_folder_id())
	if folder_id.is_empty():
		surface_error.emit(repository.get_last_error())
		return
	_folder_name_edit.text = ""
	_folder_create_row.visible = false
	_refresh_navigation()


func _on_folder_name_input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		_folder_name_edit.text = ""
		_folder_create_row.visible = false
		get_viewport().set_input_as_handled()


func _creation_folder_id() -> String:
	if _navigation == null:
		return ""
	var selected: String = _navigation.selected_folder_id()
	return "" if selected == AssetLibraryService.FOLDER_ANY else selected


func _on_navigation_note_selected(note_id: String) -> void:
	if note_id == _current_note_id:
		return
	_open_note(note_id, false)


func _on_navigation_note_open_requested(note_id: String, open_in_new_tab: bool) -> void:
	_open_note(note_id, true if open_in_new_tab else false)


func _on_navigation_note_move_requested(note_id: String, folder_id: String) -> void:
	if repository != null and not repository.move_note(note_id, folder_id):
		surface_error.emit(repository.get_last_error())


func _on_navigation_note_rename_requested(note_id: String, title: String) -> void:
	if repository == null or not repository.rename_note(note_id, title):
		surface_error.emit(repository.get_last_error() if repository != null else NotLightL10n.text("notes.error.missing"))
		return
	_rebuild_tabs()
	if note_id == _current_note_id:
		_title_label.text = str(repository.get_note(note_id).get("display_name", title))


func _on_navigation_folder_rename_requested(folder_id: String, name: String) -> void:
	if repository == null or not repository.rename_folder(folder_id, name):
		surface_error.emit(repository.get_last_error() if repository != null else NotLightL10n.text("notes.error.missing"))


func _on_source_changed() -> void:
	if _source_loading or _content_loading or _current_note_id.is_empty():
		return
	_current_content = _source.text
	_source_dirty = true
	_source_timer.start()


func _flush_source() -> void:
	if not _source_dirty or repository == null or _current_note_id.is_empty() or _content_loading:
		return
	_source_timer.stop()
	if repository.request_save(_current_note_id, _current_content):
		_source_dirty = false
	else:
		surface_error.emit(repository.get_last_error())


func _flush_preview() -> void:
	if _preview != null:
		_preview.flush_pending_edits()


func _on_preview_replace_requested(start_offset: int, end_offset: int, replacement: String, keep_live_editor: bool) -> void:
	if repository == null or _current_note_id.is_empty():
		return
	if start_offset < 0 or end_offset < start_offset or end_offset > _current_content.length():
		surface_error.emit(NotLightL10n.text("notes.error.stale_edit"))
		return
	_current_content = _current_content.substr(0, start_offset) + replacement + _current_content.substr(end_offset)
	if not repository.request_save(_current_note_id, _current_content):
		surface_error.emit(repository.get_last_error())
		return
	if not keep_live_editor:
		_preview.set_markdown(_current_content)
	_source_loading = true
	_source.text = _current_content
	_source_loading = false


func _open_wikilink(target: String) -> void:
	if repository == null:
		return
	var note_id: String = repository.resolve_title(target)
	if not note_id.is_empty():
		_open_note(note_id, true)


func _create_relation(source_id: String, target_id: String) -> void:
	if repository != null and not repository.add_explicit_link(source_id, target_id):
		surface_error.emit(repository.get_last_error())


func _remove_relation(source_id: String, target_id: String) -> void:
	if repository != null and not repository.remove_explicit_link(source_id, target_id):
		surface_error.emit(repository.get_last_error())


func _on_asset_preview_requested(asset_id: String) -> void:
	asset_preview_requested.emit(asset_id)


func _on_content_loaded(note_id: String, content: String) -> void:
	if note_id == _current_note_id:
		_apply_content(note_id, content)


func _apply_content(note_id: String, content: String) -> void:
	if note_id != _current_note_id:
		return
	_content_loading = false
	_current_content = content
	_source_loading = true
	_source.text = content
	_source_loading = false
	_source_dirty = false
	_preview.set_markdown(content, false)


func _on_content_load_failed(note_id: String, message: String) -> void:
	if note_id != _current_note_id:
		return
	_content_loading = false
	surface_error.emit(message)


func _on_content_saved(note_id: String, _revision: int) -> void:
	if note_id == _current_note_id and not _source_dirty:
		_current_content = repository.peek_cached_content(note_id) if repository != null else _current_content


func _on_note_changed(note_id: String) -> void:
	if note_id == _current_note_id and repository != null:
		var note: Dictionary = repository.get_note(note_id)
		_title_label.text = str(note.get("display_name", NotLightL10n.text("notes.untitled")))
	_rebuild_tabs()
	_refresh_navigation()


func _on_notes_changed() -> void:
	var valid_tabs: PackedStringArray = PackedStringArray()
	for note_id: String in _tabs:
		if repository != null and repository.contains(note_id):
			valid_tabs.append(note_id)
	if valid_tabs.is_empty() and repository != null:
		var notes: Array[Dictionary] = repository.list_notes()
		if not notes.is_empty():
			valid_tabs.append(str(notes[0].get("id", "")))
	if valid_tabs != _tabs and not valid_tabs.is_empty():
		_tabs = valid_tabs
		_active_tab = clampi(_active_tab, 0, _tabs.size() - 1)
		_commit_workspace_state()
		_load_current_note(_tabs[_active_tab])
	_rebuild_tabs()
	_refresh_navigation()


func _on_folders_changed() -> void:
	_refresh_navigation()


func _on_locale_changed(_locale: String) -> void:
	_rebuild_tabs()
	_refresh_navigation()
	if _graph != null:
		_graph.queue_redraw()
	_refresh_graph_toolbar()


func _disconnect_repository() -> void:
	if repository == null:
		return
	if repository.note_content_loaded.is_connected(_on_content_loaded):
		repository.note_content_loaded.disconnect(_on_content_loaded)
	if repository.note_content_load_failed.is_connected(_on_content_load_failed):
		repository.note_content_load_failed.disconnect(_on_content_load_failed)
	if repository.note_content_saved.is_connected(_on_content_saved):
		repository.note_content_saved.disconnect(_on_content_saved)
	if repository.note_changed.is_connected(_on_note_changed):
		repository.note_changed.disconnect(_on_note_changed)
	if repository.notes_changed.is_connected(_on_notes_changed):
		repository.notes_changed.disconnect(_on_notes_changed)
	if repository.folders_changed.is_connected(_on_folders_changed):
		repository.folders_changed.disconnect(_on_folders_changed)
