# SPDX-License-Identifier: GPL-3.0-or-later
class_name HubScreen
extends Control

signal board_open_requested(board_id: String)
signal exit_requested

const SECTION_BOARDS: int = 0
const SECTION_LIBRARY: int = 1
const SECTION_MODULES: int = 2
const BOARD_PAGE_SIZE: int = 120

var repository: BoardRepository
var asset_library: AssetLibraryService
var note_repository: NoteRepository
var formula_render: FormulaRenderService
var app_audio: AppAudioService
var settings: AppSettingsStore
var portable_packages: NotLightPortablePackageService
var pdf_media: PdfMediaService
var pdf_optimizer: PdfOptimizationService
var module_registry: ModuleRegistry
var module_packages: ModulePackageService
var _section_nav: HubSectionNav
var _boards_page: Control
var _library_page: Control
var _modules_page: Control
var _create_button: Button
var _board_import_button: Button
var _search_edit: LineEdit
var _grid: GridContainer
var _empty_panel: PanelContainer
var _empty_title: Label
var _empty_description: Label
var _empty_create_button: Button
var _count_label: Label
var _boards_load_more_button: Button
var _visible_board_limit: int = BOARD_PAGE_SIZE
var _create_dialog: NameDialog
var _rename_dialog: NameDialog
var _delete_dialog: ConfirmActionDialog
var _settings_dialog: SettingsDialog
var _credits_dialog: CreditsDialog
var _about_dialog: ProjectAboutDialog
var _board_import_dialog: FileDialog
var _board_export_dialog: FileDialog
var _board_export_options_dialog: BoardExportOptionsDialog
var _asset_view: AssetLibraryView
var _asset_preview: AssetPreviewOverlay
var _notes_workspace: NoteWorkspaceOverlay
var _module_view: ModuleLibraryView
var _module_preview: ModulePreviewOverlay
var _pending_board_id: String = ""
var _pending_export_board_id: String = ""
var _pending_export_board_name: String = ""
var _pending_export_options: Dictionary = {}
var _all_boards: Array[Dictionary] = []
var _message_panel: PanelContainer
var _message_label: Label
var _message_timer: Timer
var _section: int = SECTION_BOARDS


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_build_dialogs()
	resized.connect(_update_grid_columns)
	_set_section(SECTION_BOARDS)
	NotLightL10n.connect_locale_changed(_on_locale_changed)


func configure(
	board_repository: BoardRepository,
	library_service: AssetLibraryService,
	app_settings: AppSettingsStore,
	image_cache: ImageAssetCache = null,
	pdf_service: PdfMediaService = null,
	video_media: VideoMediaService = null,
	audio_media: AudioMediaService = null,
	package_service: NotLightPortablePackageService = null,
	pdf_optimization_service: PdfOptimizationService = null,
	module_registry_service: ModuleRegistry = null,
	module_package_service: ModulePackageService = null,
	note_repository_service: NoteRepository = null,
	formula_service: FormulaRenderService = null,
	app_audio_service: AppAudioService = null
) -> void:
	repository = board_repository
	asset_library = library_service
	settings = app_settings
	portable_packages = package_service
	pdf_media = pdf_service
	pdf_optimizer = pdf_optimization_service
	module_registry = module_registry_service
	module_packages = module_package_service
	note_repository = note_repository_service
	formula_render = formula_service
	app_audio = app_audio_service
	if not repository.boards_changed.is_connected(_reload_boards):
		repository.boards_changed.connect(_reload_boards)
	if not repository.repository_error.is_connected(_show_error):
		repository.repository_error.connect(_show_error)
	if asset_library != null:
		_asset_view.configure(asset_library, image_cache, video_media, settings, audio_media, portable_packages, pdf_media, pdf_optimizer)
		if _asset_preview != null:
			_asset_preview.configure(asset_library, image_cache, video_media, audio_media, pdf_media)
	if _notes_workspace != null:
		_notes_workspace.configure(note_repository, false, formula_render, settings, asset_library, image_cache, video_media, audio_media, pdf_media, module_registry)
	if _module_view != null:
		_module_view.configure(module_registry, module_packages, repository)
	if _module_preview != null:
		_module_preview.configure(module_registry)
	if settings != null:
		_settings_dialog.configure(settings, asset_library, video_media, true, module_registry, app_audio, repository)
		if not settings.settings_error.is_connected(_show_error):
			settings.settings_error.connect(_show_error)
	var window: Window = get_window()
	if window != null and not window.files_dropped.is_connected(_on_files_dropped):
		window.files_dropped.connect(_on_files_dropped)
	_reload_boards()


func _exit_tree() -> void:
	var window: Window = get_window()
	if window != null and window.files_dropped.is_connected(_on_files_dropped):
		window.files_dropped.disconnect(_on_files_dropped)
	NotLightL10n.disconnect_locale_changed(_on_locale_changed)


func focus_create_board() -> void:
	_open_create_dialog()


func _unhandled_key_input(event: InputEvent) -> void:
	if (_asset_preview != null and _asset_preview.visible) or (_notes_workspace != null and _notes_workspace.visible) or (_board_export_options_dialog != null and _board_export_options_dialog.visible):
		return
	if event is not InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return
	if key_event.keycode == KEY_ESCAPE:
		if _settings_dialog.visible:
			_settings_dialog.close_dialog()
		else:
			_settings_dialog.open_dialog()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = NotLightTheme.semantic_color("background")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var ambient_phrases: HubAmbientPhraseLayer = HubAmbientPhraseLayer.new()
	ambient_phrases.name = "AmbientPhrases"
	add_child(ambient_phrases)

	var outer: MarginContainer = MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 46)
	outer.add_theme_constant_override("margin_top", 28)
	outer.add_theme_constant_override("margin_right", 46)
	outer.add_theme_constant_override("margin_bottom", 24)
	add_child(outer)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 22)
	outer.add_child(root)
	_build_header(root)

	var content_host: Control = Control.new()
	content_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content_host)
	_build_boards_page(content_host)
	_build_library_page(content_host)
	_build_modules_page(content_host)
	_build_message_panel()


func _build_header(parent: VBoxContainer) -> void:
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	parent.add_child(header)
	var brand: HBoxContainer = HBoxContainer.new()
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand.add_theme_constant_override("separation", 12)
	header.add_child(brand)
	var logo: TextureRect = TextureRect.new()
	logo.texture = load("res://assets/brand/notlight_internal_triad.svg") as Texture2D
	logo.custom_minimum_size = Vector2(46.0, 46.0)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	brand.add_child(logo)
	var brand_copy: VBoxContainer = VBoxContainer.new()
	brand_copy.add_theme_constant_override("separation", 0)
	brand.add_child(brand_copy)
	var title: Label = Label.new()
	NotLightL10n.bind_text(title, "app.name")
	title.theme_type_variation = "TitleLabel"
	brand_copy.add_child(title)
	var subtitle: Label = Label.new()
	NotLightL10n.bind_text(subtitle, "app.subtitle")
	subtitle.theme_type_variation = "CaptionLabel"
	brand_copy.add_child(subtitle)

	var spacer_left: Control = Control.new()
	spacer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer_left)
	_section_nav = HubSectionNav.new()
	_section_nav.name = "HubSectionNav"
	_section_nav.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_section_nav.section_selected.connect(_set_section)
	header.add_child(_section_nav)

	var spacer_right: Control = Control.new()
	spacer_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer_right)
	var about_button: Button = Button.new()
	NotLightL10n.bind_text(about_button, "about.title")
	NotLightL10n.bind_tooltip(about_button, "hub.about_tooltip")
	about_button.theme_type_variation = "GhostButton"
	about_button.custom_minimum_size = Vector2(112.0, 44.0)
	about_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	about_button.pressed.connect(func() -> void: _about_dialog.open_dialog())
	header.add_child(about_button)
	var credits_button: Button = Button.new()
	NotLightL10n.bind_text(credits_button, "credits.title")
	NotLightL10n.bind_tooltip(credits_button, "hub.credits_tooltip")
	credits_button.theme_type_variation = "GhostButton"
	credits_button.custom_minimum_size = Vector2(124.0, 44.0)
	credits_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	credits_button.pressed.connect(func() -> void: _credits_dialog.open_dialog())
	header.add_child(credits_button)
	var settings_button: Button = Button.new()
	settings_button.icon = load("res://assets/icons/settings.svg") as Texture2D
	NotLightL10n.bind_tooltip(settings_button, "hub.settings_tooltip")
	settings_button.theme_type_variation = "IconButton"
	settings_button.custom_minimum_size = Vector2(44.0, 44.0)
	settings_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	settings_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	settings_button.expand_icon = true
	settings_button.add_theme_constant_override("icon_max_width", 20)
	settings_button.pressed.connect(func() -> void: _settings_dialog.open_dialog())
	header.add_child(settings_button)
	var exit_button: Button = Button.new()
	exit_button.icon = load("res://assets/icons/close.svg") as Texture2D
	NotLightL10n.bind_tooltip(exit_button, "hub.exit_tooltip")
	exit_button.theme_type_variation = "IconButton"
	exit_button.custom_minimum_size = Vector2(44.0, 44.0)
	exit_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	exit_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	exit_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	exit_button.expand_icon = true
	exit_button.add_theme_constant_override("icon_max_width", 18)
	exit_button.pressed.connect(func() -> void: exit_requested.emit())
	header.add_child(exit_button)


func _build_boards_page(parent: Control) -> void:
	_boards_page = VBoxContainer.new()
	_boards_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	(_boards_page as VBoxContainer).add_theme_constant_override("separation", 18)
	parent.add_child(_boards_page)
	var page: VBoxContainer = _boards_page as VBoxContainer
	var intro: HBoxContainer = HBoxContainer.new()
	intro.add_theme_constant_override("separation", 22)
	page.add_child(intro)
	var copy: VBoxContainer = VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 5)
	intro.add_child(copy)
	var heading: Label = Label.new()
	NotLightL10n.bind_text(heading, "hub.boards.title")
	heading.theme_type_variation = "DisplayLabel"
	copy.add_child(heading)
	var description: Label = Label.new()
	NotLightL10n.bind_text(description, "hub.boards.description")
	description.theme_type_variation = "BodyMutedLabel"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(description)
	var board_actions: HBoxContainer = HBoxContainer.new()
	board_actions.add_theme_constant_override("separation", 8)
	intro.add_child(board_actions)
	_create_button = Button.new()
	NotLightL10n.bind_text(_create_button, "hub.boards.new")
	_create_button.theme_type_variation = "PrimaryButton"
	_create_button.custom_minimum_size = Vector2(166.0, 44.0)
	_create_button.pressed.connect(_open_create_dialog)
	board_actions.add_child(_create_button)

	_board_import_button = Button.new()
	NotLightL10n.bind_text(_board_import_button, "exchange.board.import")
	_board_import_button.icon = load("res://assets/icons/import.svg") as Texture2D
	NotLightL10n.bind_tooltip(_board_import_button, "exchange.board.import_help")
	_board_import_button.theme_type_variation = "GhostButton"
	_board_import_button.custom_minimum_size = Vector2(138.0, 44.0)
	_board_import_button.pressed.connect(_open_board_import_dialog)
	board_actions.add_child(_board_import_button)

	_search_edit = LineEdit.new()
	NotLightL10n.bind_placeholder_text(_search_edit, "hub.boards.search")
	_search_edit.clear_button_enabled = true
	_search_edit.right_icon = load("res://assets/icons/search.svg") as Texture2D
	_search_edit.custom_minimum_size = Vector2(350.0, 44.0)
	_search_edit.text_changed.connect(func(_text: String) -> void: _reset_board_paging_and_render())
	board_actions.add_child(_search_edit)
	var list_header: HBoxContainer = HBoxContainer.new()
	page.add_child(list_header)
	_count_label = Label.new()
	_count_label.theme_type_variation = "SectionLabel"
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_header.add_child(_count_label)
	var privacy: Label = Label.new()
	NotLightL10n.bind_text(privacy, "hub.boards.local")
	privacy.theme_type_variation = "CaptionLabel"
	list_header.add_child(privacy)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var margin: MarginContainer = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 12)
	scroll.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 14)
	margin.add_child(stack)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 18)
	stack.add_child(_grid)
	_boards_load_more_button = Button.new()
	NotLightL10n.bind_text(_boards_load_more_button, "common.show_more")
	NotLightL10n.bind_tooltip(_boards_load_more_button, "hub.boards.more_help")
	_boards_load_more_button.theme_type_variation = "GhostButton"
	_boards_load_more_button.custom_minimum_size = Vector2(0.0, 42.0)
	_boards_load_more_button.visible = false
	_boards_load_more_button.pressed.connect(_load_more_boards)
	stack.add_child(_boards_load_more_button)
	_empty_panel = PanelContainer.new()
	_empty_panel.theme_type_variation = "CardPanel"
	_empty_panel.custom_minimum_size = Vector2(0.0, 300.0)
	stack.add_child(_empty_panel)
	_build_empty_state(_empty_panel)


func _build_library_page(parent: Control) -> void:
	_library_page = VBoxContainer.new()
	_library_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	(_library_page as VBoxContainer).add_theme_constant_override("separation", 14)
	parent.add_child(_library_page)
	var page: VBoxContainer = _library_page as VBoxContainer
	var intro: VBoxContainer = VBoxContainer.new()
	intro.add_theme_constant_override("separation", 5)
	page.add_child(intro)
	var heading: Label = Label.new()
	NotLightL10n.bind_text(heading, "library.title")
	heading.theme_type_variation = "DisplayLabel"
	intro.add_child(heading)
	var description: Label = Label.new()
	NotLightL10n.bind_text(description, "library.description")
	description.theme_type_variation = "BodyMutedLabel"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_child(description)
	_asset_view = AssetLibraryView.new()
	_asset_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_asset_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_asset_view.error_requested.connect(_show_error)
	_asset_view.info_requested.connect(_show_info)
	_asset_view.asset_preview_requested.connect(_open_asset_preview)
	_asset_view.notes_graph_requested.connect(_open_notes_graph)
	page.add_child(_asset_view)


func _build_modules_page(parent: Control) -> void:
	_modules_page = VBoxContainer.new()
	_modules_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	(_modules_page as VBoxContainer).add_theme_constant_override("separation", 14)
	parent.add_child(_modules_page)
	var page: VBoxContainer = _modules_page as VBoxContainer
	var intro: HBoxContainer = HBoxContainer.new()
	intro.add_theme_constant_override("separation", 10)
	page.add_child(intro)
	var text_box: VBoxContainer = VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 5)
	intro.add_child(text_box)
	var heading: Label = Label.new()
	NotLightL10n.bind_text(heading, "hub.modules.title")
	heading.theme_type_variation = "DisplayLabel"
	text_box.add_child(heading)
	var description: Label = Label.new()
	NotLightL10n.bind_text(description, "hub.modules.description_beta")
	description.theme_type_variation = "BodyMutedLabel"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(description)
	_module_view = ModuleLibraryView.new()
	_module_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_module_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_module_view.error_requested.connect(_show_error)
	_module_view.info_requested.connect(_show_info)
	_module_view.module_preview_requested.connect(_open_module_preview)
	page.add_child(_module_view)


func _build_empty_state(panel: PanelContainer) -> void:
	var center: CenterContainer = CenterContainer.new()
	panel.add_child(center)
	var content: VBoxContainer = VBoxContainer.new()
	content.custom_minimum_size = Vector2(430.0, 0.0)
	content.add_theme_constant_override("separation", 12)
	center.add_child(content)
	var mark: Label = Label.new()
	mark.text = "＋"
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.add_theme_font_size_override("font_size", 44)
	mark.add_theme_color_override("font_color", NotLightTheme.semantic_color("accent"))
	content.add_child(mark)
	_empty_title = Label.new()
	NotLightL10n.bind_text(_empty_title, "hub.boards.empty_title")
	_empty_title.theme_type_variation = "TitleLabel"
	_empty_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_empty_title)
	_empty_description = Label.new()
	NotLightL10n.bind_text(_empty_description, "hub.boards.empty_description")
	_empty_description.theme_type_variation = "BodyMutedLabel"
	_empty_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_empty_description)
	_empty_create_button = Button.new()
	NotLightL10n.bind_text(_empty_create_button, "hub.boards.create")
	_empty_create_button.theme_type_variation = "PrimaryButton"
	_empty_create_button.custom_minimum_size = Vector2(200.0, 44.0)
	_empty_create_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_empty_create_button.pressed.connect(_open_create_dialog)
	content.add_child(_empty_create_button)


func _build_dialogs() -> void:
	_create_dialog = NameDialog.new()
	_create_dialog.submitted.connect(_create_board)
	add_child(_create_dialog)
	_rename_dialog = NameDialog.new()
	_rename_dialog.submitted.connect(_rename_board)
	add_child(_rename_dialog)
	_delete_dialog = ConfirmActionDialog.new()
	_delete_dialog.confirmed.connect(_delete_board)
	add_child(_delete_dialog)
	_settings_dialog = SettingsDialog.new()
	add_child(_settings_dialog)
	_about_dialog = ProjectAboutDialog.new()
	add_child(_about_dialog)
	_credits_dialog = CreditsDialog.new()
	add_child(_credits_dialog)
	_board_import_dialog = FileDialog.new()
	_board_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_board_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_board_import_dialog.use_native_dialog = true
	_board_import_dialog.filters = PackedStringArray(["*.notlight-board;%s;application/octet-stream" % NotLightL10n.text("file_filter.board_package")])
	_board_import_dialog.file_selected.connect(_on_board_package_selected)
	add_child(_board_import_dialog)
	_board_export_dialog = FileDialog.new()
	_board_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_board_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_board_export_dialog.use_native_dialog = true
	_board_export_dialog.filters = PackedStringArray(["*.notlight-board;%s;application/octet-stream" % NotLightL10n.text("file_filter.board_package")])
	_board_export_dialog.file_selected.connect(_on_board_export_path_selected)
	add_child(_board_export_dialog)
	_board_export_options_dialog = BoardExportOptionsDialog.new()
	_board_export_options_dialog.submitted.connect(_on_board_export_options_submitted)
	add_child(_board_export_options_dialog)
	_asset_preview = AssetPreviewOverlay.new()
	add_child(_asset_preview)
	_module_preview = ModulePreviewOverlay.new()
	add_child(_module_preview)
	_notes_workspace = NoteWorkspaceOverlay.new()
	_notes_workspace.error_requested.connect(_show_error)
	_notes_workspace.asset_preview_requested.connect(_open_asset_preview)
	add_child(_notes_workspace)


func _open_module_preview(module_id: String) -> void:
	if _module_preview == null or module_registry == null:
		return
	_module_preview.open_module(module_id)


func _open_asset_preview(asset_id: String) -> void:
	if asset_library != null and note_repository != null:
		var asset: Dictionary = asset_library.get_asset(asset_id)
		if int(asset.get("kind", AssetKinds.OTHER)) == AssetKinds.NOTE:
			_notes_workspace.open_note(asset_id)
			return
	if _asset_preview != null:
		_asset_preview.open_asset(asset_id)


func _open_notes_graph() -> void:
	if _notes_workspace != null:
		_notes_workspace.open_graph()


func _build_message_panel() -> void:
	_message_panel = PanelContainer.new()
	_message_panel.theme_type_variation = "FloatingPanel"
	_message_panel.visible = false
	_message_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_message_panel.position = Vector2(-260.0, -76.0)
	_message_panel.custom_minimum_size = Vector2(520.0, 50.0)
	add_child(_message_panel)
	_message_label = Label.new()
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_panel.add_child(_message_label)
	_message_timer = Timer.new()
	_message_timer.one_shot = true
	_message_timer.wait_time = 3.8
	_message_timer.timeout.connect(func() -> void: _message_panel.visible = false)
	add_child(_message_timer)



func _set_section(section: int) -> void:
	_section = clampi(section, SECTION_BOARDS, SECTION_MODULES)
	if _boards_page != null:
		_boards_page.visible = _section == SECTION_BOARDS
	if _library_page != null:
		_library_page.visible = _section == SECTION_LIBRARY
	if _modules_page != null:
		_modules_page.visible = _section == SECTION_MODULES
	if _section_nav != null:
		_section_nav.set_section(_section)
	if _section == SECTION_LIBRARY and _asset_view != null:
		_asset_view.focus_search()
	elif _section == SECTION_MODULES and _module_view != null:
		_module_view.focus_search()


func _reload_boards() -> void:
	if repository == null:
		return
	_all_boards = repository.list_boards()
	_visible_board_limit = _board_page_size()
	_render_boards()


func _board_page_size() -> int:
	if settings == null:
		return BOARD_PAGE_SIZE
	var budget: Dictionary = settings.get_performance_budget()
	return clampi(
		int(budget.get("materialized_ui_budget", BOARD_PAGE_SIZE)),
		40,
		AppSettingsStore.MAX_MATERIALIZED_UI_BUDGET
	)


func _render_boards() -> void:
	if repository == null or _grid == null:
		return
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var query: String = _search_edit.text.strip_edges().to_lower() if _search_edit != null else ""
	var matching: Array[Dictionary] = []
	for board_metadata: Dictionary in _all_boards:
		if not query.is_empty() and not str(board_metadata.get("name", "")).to_lower().contains(query):
			continue
		matching.append(board_metadata)
	var shown: int = mini(matching.size(), _visible_board_limit)
	for index: int in range(shown):
		var visible_metadata: Dictionary = matching[index]
		var card: BoardCard = BoardCard.new()
		card.open_requested.connect(func(board_id: String) -> void: board_open_requested.emit(board_id))
		card.rename_requested.connect(_open_rename_dialog)
		card.duplicate_requested.connect(_duplicate_board)
		card.export_requested.connect(_open_board_export_dialog)
		card.delete_requested.connect(_open_delete_dialog)
		_grid.add_child(card)
		card.configure(visible_metadata)
	var total_matching: int = matching.size()
	if query.is_empty():
		_count_label.text = (
			NotLightL10n.text("hub.boards.count", {"count": _all_boards.size()})
			if not _all_boards.is_empty()
			else NotLightL10n.text("hub.boards.none")
		)
	else:
		_count_label.text = NotLightL10n.text("hub.boards.found", {"count": total_matching})
	if _boards_load_more_button != null:
		_boards_load_more_button.visible = shown < total_matching
		_boards_load_more_button.text = NotLightL10n.text("common.show_more_remaining", {"count": maxi(0, total_matching - shown)})
	var show_empty: bool = total_matching == 0
	_empty_panel.visible = show_empty
	_grid.visible = not show_empty
	if show_empty:
		if _all_boards.is_empty():
			NotLightL10n.bind_text(_empty_title, "hub.boards.empty_title")
			NotLightL10n.bind_text(_empty_description, "hub.boards.empty_description")
			_empty_create_button.visible = true
		else:
			NotLightL10n.bind_text(_empty_title, "common.nothing_found")
			NotLightL10n.bind_text(_empty_description, "hub.boards.search_empty")
			_empty_create_button.visible = false
	_update_grid_columns()


func _reset_board_paging_and_render() -> void:
	_visible_board_limit = _board_page_size()
	_render_boards()


func _load_more_boards() -> void:
	_visible_board_limit += _board_page_size()
	_render_boards()


func _update_grid_columns() -> void:
	if _grid == null:
		return
	var available: float = maxf(320.0, size.x - 104.0)
	_grid.columns = clampi(int(floor((available + 18.0) / 338.0)), 1, 6)


func _open_board_import_dialog() -> void:
	if portable_packages == null:
		_show_error(NotLightL10n.text("exchange.error.unavailable"))
		return
	_board_import_dialog.title = NotLightL10n.text("exchange.board.import_title")
	_board_import_dialog.popup_centered_ratio(0.72)


func _on_board_package_selected(path: String) -> void:
	if portable_packages == null:
		return
	var result: Dictionary = portable_packages.import_board(path)
	if not bool(result.get("ok", false)):
		_show_error(str(result.get("error", portable_packages.get_last_error())))
		return
	_show_error(NotLightL10n.text("exchange.board.import_done", {
		"name": str(result.get("board_name", NotLightL10n.text("hub.board.untitled"))),
		"added": int(result.get("assets_added", 0)),
		"reused": int(result.get("assets_reused", 0)),
	}), false)


func _open_board_export_dialog(board_id: String, board_name: String) -> void:
	if portable_packages == null:
		_show_error(NotLightL10n.text("exchange.error.unavailable"))
		return
	var plan: Dictionary = portable_packages.get_board_export_plan(board_id)
	if not bool(plan.get("ok", false)):
		_show_error(str(plan.get("error", portable_packages.get_last_error())))
		return
	_pending_export_board_id = board_id
	_pending_export_board_name = board_name
	_pending_export_options = {}
	_board_export_options_dialog.open_dialog(board_name, plan)


func _on_board_export_options_submitted(options: Dictionary) -> void:
	if portable_packages == null or _pending_export_board_id.is_empty():
		return
	_pending_export_options = options.duplicate(true)
	_board_export_dialog.title = NotLightL10n.text("exchange.board.export_title")
	_board_export_dialog.current_file = "%s.notlight-board" % _safe_export_filename(_pending_export_board_name, "board")
	_board_export_dialog.popup_centered_ratio(0.72)


func _on_board_export_path_selected(path: String) -> void:
	if portable_packages == null or _pending_export_board_id.is_empty():
		return
	var destination: String = _ensure_extension(path, NotLightPortablePackageFormat.BOARD_EXTENSION)
	var result: Dictionary = portable_packages.export_board_profile(_pending_export_board_id, destination, _pending_export_options)
	_pending_export_board_id = ""
	_pending_export_board_name = ""
	_pending_export_options = {}
	if not bool(result.get("ok", false)):
		_show_error(str(result.get("error", portable_packages.get_last_error())))
		return
	_show_error(NotLightL10n.text("exchange.board.export_done_profile", {
		"name": str(result.get("board_name", "")),
		"embedded": int(result.get("embedded_asset_count", 0)),
		"external": int(result.get("external_asset_count", 0)),
	}), false)


func _safe_export_filename(value: String, fallback: String) -> String:
	var clean: String = value.strip_edges()
	var result: String = ""
	const FORBIDDEN: String = "\\/:*?\"<>|"
	for index: int in range(clean.length()):
		var character: String = clean.substr(index, 1)
		if FORBIDDEN.contains(character) or character.unicode_at(0) < 32:
			result += "_"
		else:
			result += character
	result = result.strip_edges().trim_suffix(".")
	return result.left(96) if not result.is_empty() else fallback


func _ensure_extension(path: String, extension: String) -> String:
	var suffix: String = ".%s" % extension.strip_edges().trim_prefix(".")
	return path if path.to_lower().ends_with(suffix.to_lower()) else path + suffix


func _open_create_dialog() -> void:
	_create_dialog.open_dialog(NotLightL10n.text("hub.board.create_title"), NotLightL10n.text("hub.board.create_help"), "", NotLightL10n.text("common.create"))


func _create_board(board_name: String) -> void:
	if repository == null:
		return
	var metadata: Dictionary = repository.create_board(board_name)
	if metadata.is_empty():
		_show_error(repository.get_last_error())
		return
	board_open_requested.emit(str(metadata.get("id", "")))


func _duplicate_board(board_id: String, current_name: String) -> void:
	if repository == null:
		return
	var copy_name: String = NotLightL10n.text("hub.board.copy_name", {"name": current_name})
	var result: Dictionary = repository.duplicate_board(board_id, copy_name)
	if result.is_empty():
		_show_error(repository.get_last_error())
		return
	_show_info(NotLightL10n.text("hub.board.duplicate_done", {"name": str(result.get("name", copy_name))}))


func _open_rename_dialog(board_id: String, current_name: String) -> void:
	_pending_board_id = board_id
	_rename_dialog.open_dialog(NotLightL10n.text("hub.board.rename_title"), NotLightL10n.text("hub.board.rename_help"), current_name, NotLightL10n.text("common.save"))


func _rename_board(clean_name: String) -> void:
	if repository == null:
		return
	var result: Dictionary = repository.rename_board(_pending_board_id, clean_name)
	if result.is_empty():
		_show_error(repository.get_last_error())


func _open_delete_dialog(board_id: String, current_name: String) -> void:
	_pending_board_id = board_id
	_delete_dialog.open_dialog(NotLightL10n.text("hub.board.delete_title"), NotLightL10n.text("hub.board.delete_help", {"name": current_name}), NotLightL10n.text("common.delete"), true)


func _delete_board() -> void:
	if repository != null and not repository.delete_board(_pending_board_id):
		_show_error(repository.get_last_error())


func _on_files_dropped(files: PackedStringArray) -> void:
	if _section != SECTION_MODULES or _module_view == null:
		return
	if _module_view.handle_external_files(files):
		get_viewport().set_input_as_handled()


func _on_locale_changed(_locale: String) -> void:
	NotLightL10n.refresh_tree(self)
	_render_boards()


func _show_info(message: String) -> void:
	_show_error(message, false)


func _show_error(message: String, danger: bool = true) -> void:
	if message.is_empty() or _message_panel == null:
		return
	_message_label.text = message
	_message_label.add_theme_color_override(
		"font_color",
		NotLightTheme.semantic_color("danger") if danger else NotLightTheme.semantic_color("text")
	)
	_message_panel.visible = true
	_message_timer.start()
