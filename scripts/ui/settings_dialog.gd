# SPDX-License-Identifier: GPL-3.0-or-later
class_name SettingsDialog
extends Control

const PAGE_CONTROLS: int = 0
const PAGE_INTERFACE: int = 1
const PAGE_AUDIO: int = 2
const PAGE_PERFORMANCE: int = 3
const PAGE_STORAGE: int = 4
const PAGE_DEVELOPER: int = 5
const STORAGE_TARGET_LIBRARY: int = 0
const STORAGE_TARGET_MODULES: int = 1

var settings: AppSettingsStore
var library: AssetLibraryService
var video_media: VideoMediaService
var module_registry: ModuleRegistry
var app_audio: AppAudioService
var allow_performance_edit: bool = true

var _modal_panel: PanelContainer
var _nav_buttons: Array[Button] = []
var _pages: Array[VBoxContainer] = []
var _current_page: int = PAGE_CONTROLS
var _input_mode: OptionButton
var _mode_help: Label
var _camera_slider: HSlider
var _camera_value: Label
var _zoom_slider: HSlider
var _zoom_value: Label
var _speed_slider: HSlider
var _speed_value: Label
var _locale_option: OptionButton
var _window_option: OptionButton
var _tool_hints_check: CheckBox
var _audio_master_check: CheckBox
var _audio_master_slider: HSlider
var _audio_master_value: Label
var _background_music_check: CheckBox
var _background_music_slider: HSlider
var _background_music_value: Label
var _background_music_option: OptionButton
var _background_music_status: Label
var _palette_option: OptionButton
var _grid_intensity_option: OptionButton
var _grid_intensity_preview: GridIntensityPreview
var _palette_color_buttons: Dictionary = {}
var _palette_custom_box: VBoxContainer
var _palette_preset_name: LineEdit
var _palette_save_preset_button: Button
var _palette_delete_preset_button: Button
var _performance_profile_option: OptionButton
var _drawing_quality_option: OptionButton
var _performance_lock_note: PanelContainer
var _board_budget_spin: SpinBox
var _ui_budget_spin: SpinBox
var _video_budget_spin: SpinBox
var _module_budget_spin: SpinBox
var _note_workspace_budget_spin: SpinBox
var _full_note_card_render_check: CheckBox
var _note_embed_live_budget_spin: SpinBox
var _note_embed_rich_preview_check: CheckBox
var _prefer_maximum_fps_check: CheckBox
var _texture_budget_spin: SpinBox
var _monitor_checks: Dictionary = {}
var _monitor_interval: OptionButton
var _developer_diagnostics_check: CheckBox
var _library_path_label: Label
var _storage_status_label: Label
var _module_path_label: Label
var _module_storage_status_label: Label
var _compression_cpu_option: OptionButton
var _auto_optimize_video_check: CheckBox
var _folder_dialog: FileDialog
var _storage_dialog_target: int = STORAGE_TARGET_LIBRARY
var _syncing: bool = false


func _init() -> void:
	visible = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	z_as_relative = false
	z_index = 1000
	_build_all()
	resized.connect(_fit_modal_to_viewport)
	NotLightL10n.connect_locale_changed(_on_locale_changed)
	call_deferred("_fit_modal_to_viewport")
	visible = false


func configure(
	settings_store: AppSettingsStore,
	library_service: AssetLibraryService = null,
	media_service: VideoMediaService = null,
	performance_editable: bool = true,
	module_registry_service: ModuleRegistry = null,
	app_audio_service: AppAudioService = null
) -> void:
	settings = settings_store
	library = library_service
	video_media = media_service
	module_registry = module_registry_service
	if app_audio != null and app_audio.bundled_tracks_changed.is_connected(_on_bundled_tracks_changed):
		app_audio.bundled_tracks_changed.disconnect(_on_bundled_tracks_changed)
	if app_audio != null and app_audio.library_tracks_changed.is_connected(_on_library_tracks_changed):
		app_audio.library_tracks_changed.disconnect(_on_library_tracks_changed)
	app_audio = app_audio_service
	if app_audio != null and not app_audio.bundled_tracks_changed.is_connected(_on_bundled_tracks_changed):
		app_audio.bundled_tracks_changed.connect(_on_bundled_tracks_changed)
	if app_audio != null and not app_audio.library_tracks_changed.is_connected(_on_library_tracks_changed):
		app_audio.library_tracks_changed.connect(_on_library_tracks_changed)
	allow_performance_edit = performance_editable
	if settings != null and not settings.settings_changed.is_connected(_on_settings_changed):
		settings.settings_changed.connect(_on_settings_changed)
	if settings != null:
		_refresh(settings.get_snapshot())


func open_dialog(page: int = PAGE_CONTROLS) -> void:
	if app_audio != null:
		app_audio.refresh_bundled_tracks()
	if settings != null:
		_refresh(settings.get_snapshot())
	_show_page(clampi(page, PAGE_CONTROLS, PAGE_DEVELOPER))
	visible = true
	if not _nav_buttons.is_empty():
		_nav_buttons[_current_page].grab_focus()


func close_dialog() -> void:
	visible = false


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or event is not InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
		close_dialog()
		get_viewport().set_input_as_handled()


func _build_all() -> void:
	_clear_ui()
	_build_ui()
	_build_folder_dialog()


func _clear_ui() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_nav_buttons.clear()
	_pages.clear()
	_palette_color_buttons.clear()
	_palette_preset_name = null
	_palette_save_preset_button = null
	_palette_delete_preset_button = null
	_monitor_checks.clear()
	_developer_diagnostics_check = null
	_modal_panel = null
	_folder_dialog = null
	_grid_intensity_preview = null
	_audio_master_check = null
	_audio_master_slider = null
	_audio_master_value = null
	_background_music_check = null
	_background_music_slider = null
	_background_music_value = null
	_background_music_option = null
	_background_music_status = null


func _build_ui() -> void:
	var scrim: ColorRect = ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.055, 0.075, 0.062, 0.48)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(_on_scrim_input)
	add_child(scrim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_modal_panel = PanelContainer.new()
	_modal_panel.theme_type_variation = "SettingsModalPanel"
	_modal_panel.custom_minimum_size = Vector2(760.0, 560.0)
	_modal_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_modal_panel)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	_modal_panel.add_child(root)
	_build_header(root)

	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	root.add_child(body)
	_build_navigation(body)
	_build_pages(body)
	_build_footer(root)


func _build_header(parent: VBoxContainer) -> void:
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	parent.add_child(header)
	var mark: PanelContainer = PanelContainer.new()
	mark.theme_type_variation = "SettingsMarkPanel"
	mark.custom_minimum_size = Vector2(44.0, 44.0)
	header.add_child(mark)
	var mark_label: Label = Label.new()
	mark_label.text = "⚙"
	mark_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark_label.add_theme_font_size_override("font_size", 20)
	mark_label.add_theme_color_override("font_color", NotLightTheme.semantic_color("accent"))
	mark.add_child(mark_label)
	var title_box: VBoxContainer = VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 2)
	header.add_child(title_box)
	var title_label: Label = Label.new()
	NotLightL10n.bind_text(title_label, "settings.title")
	title_label.theme_type_variation = "TitleLabel"
	title_box.add_child(title_label)
	var subtitle: Label = Label.new()
	NotLightL10n.bind_text(subtitle, "settings.subtitle")
	subtitle.theme_type_variation = "BodyMutedLabel"
	title_box.add_child(subtitle)
	var close_button: Button = Button.new()
	close_button.text = "×"
	close_button.tooltip_text = NotLightL10n.text("ui.format.close_escape") % NotLightL10n.text("common.close")
	close_button.theme_type_variation = "IconButton"
	close_button.custom_minimum_size = Vector2(42.0, 42.0)
	close_button.add_theme_font_size_override("font_size", 22)
	close_button.pressed.connect(close_dialog)
	header.add_child(close_button)
	var separator: HSeparator = HSeparator.new()
	separator.custom_minimum_size = Vector2(0.0, 18.0)
	parent.add_child(separator)


func _build_navigation(parent: HBoxContainer) -> void:
	var navigation: PanelContainer = PanelContainer.new()
	navigation.theme_type_variation = "SettingsNavPanel"
	navigation.custom_minimum_size = Vector2(216.0, 0.0)
	navigation.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(navigation)
	var nav_box: VBoxContainer = VBoxContainer.new()
	nav_box.add_theme_constant_override("separation", 7)
	navigation.add_child(nav_box)
	var caption: Label = Label.new()
	NotLightL10n.bind_text(caption, "settings.sections")
	caption.theme_type_variation = "EyebrowLabel"
	nav_box.add_child(caption)
	var group: ButtonGroup = ButtonGroup.new()
	_add_nav_button(nav_box, group, PAGE_CONTROLS, "⌁", NotLightL10n.text("settings.nav.controls"))
	_add_nav_button(nav_box, group, PAGE_INTERFACE, "◫", NotLightL10n.text("settings.nav.interface"))
	_add_nav_button(nav_box, group, PAGE_AUDIO, "♪", NotLightL10n.text("settings.nav.audio"))
	_add_nav_button(nav_box, group, PAGE_PERFORMANCE, "⌁", NotLightL10n.text("settings.nav.performance"))
	_add_nav_button(nav_box, group, PAGE_STORAGE, "▣", NotLightL10n.text("settings.nav.storage"))
	_add_nav_button(nav_box, group, PAGE_DEVELOPER, "</>", NotLightL10n.text("settings.nav.developer"))
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav_box.add_child(spacer)
	var local_note: Label = Label.new()
	NotLightL10n.bind_text(local_note, "settings.local_note")
	local_note.theme_type_variation = "CaptionLabel"
	local_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nav_box.add_child(local_note)


func _add_nav_button(parent: VBoxContainer, group: ButtonGroup, page: int, icon_text: String, label_text: String) -> void:
	var button: Button = Button.new()
	button.text = NotLightL10n.text("ui.format.nav_icon_label") % [icon_text, label_text]
	button.theme_type_variation = "SettingsNavButton"
	button.toggle_mode = true
	button.button_group = group
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0.0, 44.0)
	button.pressed.connect(func() -> void: _show_page(page))
	parent.add_child(button)
	_nav_buttons.append(button)


func _build_pages(parent: HBoxContainer) -> void:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	parent.add_child(scroll)
	var page_margin: MarginContainer = MarginContainer.new()
	page_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_margin.add_theme_constant_override("margin_right", 8)
	page_margin.add_theme_constant_override("margin_bottom", 4)
	scroll.add_child(page_margin)
	var page_stack: VBoxContainer = VBoxContainer.new()
	page_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_margin.add_child(page_stack)
	for page_index: int in range(6):
		var page: VBoxContainer = VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation", 12)
		page_stack.add_child(page)
		_pages.append(page)
	_build_controls_page(_pages[PAGE_CONTROLS])
	_build_interface_page(_pages[PAGE_INTERFACE])
	_build_audio_page(_pages[PAGE_AUDIO])
	_build_performance_page(_pages[PAGE_PERFORMANCE])
	_build_storage_page(_pages[PAGE_STORAGE])
	_build_developer_page(_pages[PAGE_DEVELOPER])


func _build_controls_page(parent: VBoxContainer) -> void:
	_add_page_heading(parent, NotLightL10n.text("settings.controls.title"), NotLightL10n.text("settings.controls.description"))
	var input_section: VBoxContainer = _make_section(parent, NotLightL10n.text("settings.input.title"), NotLightL10n.text("settings.input.description"))
	var mode_panel: PanelContainer = _make_row_panel(input_section)
	var mode_row: HBoxContainer = HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 14)
	mode_panel.add_child(mode_row)
	var mode_text: VBoxContainer = _make_text_column(mode_row, NotLightL10n.text("settings.input.primary"), "")
	_mode_help = mode_text.get_child(1) as Label
	_input_mode = OptionButton.new()
	_input_mode.theme_type_variation = "SettingsOptionButton"
	_input_mode.fit_to_longest_item = false
	_input_mode.custom_minimum_size = Vector2(180.0, 38.0)
	_input_mode.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_input_mode.add_item(NotLightL10n.text("settings.input.trackpad"), int(AppSettingsStore.InputMode.TRACKPAD))
	_input_mode.add_item(NotLightL10n.text("settings.input.mouse"), int(AppSettingsStore.InputMode.MOUSE))
	_input_mode.item_selected.connect(_on_input_mode_selected)
	mode_row.add_child(_input_mode)
	var camera_section: VBoxContainer = _make_section(parent, NotLightL10n.text("settings.camera.title"), NotLightL10n.text("settings.camera.description"))
	var camera_row: Dictionary = _add_slider_row(camera_section, NotLightL10n.text("settings.camera.pan"), NotLightL10n.text("settings.camera.pan_help"), 0.25, 3.0, 0.05)
	_camera_slider = camera_row.get("slider") as HSlider
	_camera_value = camera_row.get("value") as Label
	_camera_slider.value_changed.connect(_on_camera_sensitivity_changed)
	var zoom_row: Dictionary = _add_slider_row(camera_section, NotLightL10n.text("settings.camera.zoom"), NotLightL10n.text("settings.camera.zoom_help"), 0.25, 3.0, 0.05)
	_zoom_slider = zoom_row.get("slider") as HSlider
	_zoom_value = zoom_row.get("value") as Label
	_zoom_slider.value_changed.connect(_on_zoom_sensitivity_changed)
	var speed_row: Dictionary = _add_slider_row(camera_section, NotLightL10n.text("settings.camera.smooth"), NotLightL10n.text("settings.camera.smooth_help"), 3.0, 30.0, 0.5)
	_speed_slider = speed_row.get("slider") as HSlider
	_speed_value = speed_row.get("value") as Label
	_speed_slider.value_changed.connect(_on_camera_speed_changed)


func _build_interface_page(parent: VBoxContainer) -> void:
	_add_page_heading(parent, NotLightL10n.text("settings.interface.title"), NotLightL10n.text("settings.interface.description"))
	var language_section: VBoxContainer = _make_section(parent, NotLightL10n.text("settings.language.title"), NotLightL10n.text("settings.language.description"))
	_locale_option = _add_option_row(language_section, NotLightL10n.text("settings.language.current"), "")
	for locale_code: String in NotLightL10n.available_locales():
		_locale_option.add_item(NotLightL10n.locale_label(locale_code))
		_locale_option.set_item_metadata(_locale_option.item_count - 1, locale_code)
	_locale_option.item_selected.connect(_on_locale_selected)
	var window_section: VBoxContainer = _make_section(parent, NotLightL10n.text("settings.window.title"), NotLightL10n.text("settings.window.description"))
	_window_option = _add_option_row(window_section, NotLightL10n.text("settings.window.mode"), "")
	_window_option.add_item(NotLightL10n.text("settings.window.windowed"), int(AppSettingsStore.WindowModePreference.WINDOWED))
	_window_option.add_item(NotLightL10n.text("settings.window.maximized"), int(AppSettingsStore.WindowModePreference.MAXIMIZED))
	_window_option.add_item(NotLightL10n.text("settings.window.fullscreen"), int(AppSettingsStore.WindowModePreference.FULLSCREEN))
	_window_option.item_selected.connect(_on_window_mode_selected)
	var helper_section: VBoxContainer = _make_section(parent, NotLightL10n.text("settings.interface.helpers_title"), NotLightL10n.text("settings.interface.helpers_description"))
	_tool_hints_check = _add_toggle_row(
		helper_section,
		NotLightL10n.text("settings.interface.tool_hints"),
		NotLightL10n.text("settings.interface.tool_hints_help")
	)
	_tool_hints_check.toggled.connect(_on_tool_hints_toggled)
	var grid_section: VBoxContainer = _make_section(parent, NotLightL10n.text("settings.grid_density.title"), NotLightL10n.text("settings.grid_density.description"))
	_grid_intensity_option = _add_option_row(grid_section, NotLightL10n.text("settings.grid_density.intensity"), NotLightL10n.text("settings.grid_density.help"))
	_grid_intensity_option.add_item(NotLightL10n.text("settings.grid_density.soft"), int(AppSettingsStore.GridIntensity.SOFT))
	_grid_intensity_option.add_item(NotLightL10n.text("settings.grid_density.balanced"), int(AppSettingsStore.GridIntensity.BALANCED))
	_grid_intensity_option.add_item(NotLightL10n.text("settings.grid_density.expressive"), int(AppSettingsStore.GridIntensity.EXPRESSIVE))
	_grid_intensity_option.item_selected.connect(_on_grid_intensity_selected)
	var grid_preview_panel: PanelContainer = PanelContainer.new()
	grid_preview_panel.theme_type_variation = "GridPreviewPanel"
	grid_preview_panel.custom_minimum_size = Vector2(0.0, 92.0)
	grid_preview_panel.clip_contents = true
	grid_section.add_child(grid_preview_panel)
	_grid_intensity_preview = GridIntensityPreview.new()
	grid_preview_panel.add_child(_grid_intensity_preview)
	var palette_section: VBoxContainer = _make_section(parent, NotLightL10n.text("settings.palette.title"), NotLightL10n.text("settings.palette.description"))
	_palette_option = _add_option_row(palette_section, NotLightL10n.text("settings.palette.preset"), NotLightL10n.text("settings.palette.preset_help"))
	_rebuild_palette_options(NotLightPalette.PRESET_DEFAULT)
	_palette_option.item_selected.connect(_on_palette_selected)
	_palette_custom_box = VBoxContainer.new()
	_palette_custom_box.add_theme_constant_override("separation", 8)
	palette_section.add_child(_palette_custom_box)
	var hint: Label = Label.new()
	NotLightL10n.bind_text(hint, "settings.palette.custom_hint")
	hint.theme_type_variation = "CaptionLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_palette_custom_box.add_child(hint)

	var preset_panel: PanelContainer = _make_row_panel(palette_section)
	var preset_root: VBoxContainer = VBoxContainer.new()
	preset_root.add_theme_constant_override("separation", 8)
	preset_panel.add_child(preset_root)
	var preset_title: Label = Label.new()
	NotLightL10n.bind_text(preset_title, "settings.palette.saved_title")
	preset_title.theme_type_variation = "SettingsRowTitleLabel"
	preset_root.add_child(preset_title)
	var preset_help: Label = Label.new()
	NotLightL10n.bind_text(preset_help, "settings.palette.saved_help")
	preset_help.theme_type_variation = "CaptionLabel"
	preset_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preset_root.add_child(preset_help)
	var preset_actions: HBoxContainer = HBoxContainer.new()
	preset_actions.add_theme_constant_override("separation", 8)
	preset_root.add_child(preset_actions)
	_palette_preset_name = LineEdit.new()
	NotLightL10n.bind_placeholder_text(_palette_preset_name, "settings.palette.saved_name_placeholder")
	_palette_preset_name.max_length = AppSettingsStore.MAX_USER_PALETTE_NAME_LENGTH
	_palette_preset_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_palette_preset_name.text_submitted.connect(_on_palette_preset_name_submitted)
	preset_actions.add_child(_palette_preset_name)
	_palette_save_preset_button = Button.new()
	NotLightL10n.bind_text(_palette_save_preset_button, "settings.palette.save_preset")
	_palette_save_preset_button.theme_type_variation = "PrimaryButton"
	_palette_save_preset_button.pressed.connect(_on_save_palette_preset_pressed)
	preset_actions.add_child(_palette_save_preset_button)
	_palette_delete_preset_button = Button.new()
	NotLightL10n.bind_text(_palette_delete_preset_button, "settings.palette.delete_preset")
	_palette_delete_preset_button.theme_type_variation = "GhostDangerButton"
	_palette_delete_preset_button.pressed.connect(_on_delete_palette_preset_pressed)
	preset_actions.add_child(_palette_delete_preset_button)

	var color_defs: Array[Dictionary] = [
		{"key":"background", "label":"settings.palette.background"},
		{"key":"surface", "label":"settings.palette.surface"},
		{"key":"accent", "label":"settings.palette.accent"},
		{"key":"text", "label":"settings.palette.text"},
		{"key":"text_muted", "label":"settings.palette.muted"},
		{"key":"border", "label":"settings.palette.border"},
		{"key":"danger", "label":"settings.palette.danger"},
		{"key":"board_background", "label":"settings.palette.board"},
		{"key":"board_grid", "label":"settings.palette.grid"},
	]
	for definition: Dictionary in color_defs:
		_add_palette_color_row(_palette_custom_box, str(definition.get("key", "")), NotLightL10n.text(str(definition.get("label", ""))))


func _build_audio_page(parent: VBoxContainer) -> void:
	_add_page_heading(parent, NotLightL10n.text("settings.audio.title"), NotLightL10n.text("settings.audio.description"))
	var master_section: VBoxContainer = _make_section(
		parent,
		NotLightL10n.text("settings.audio.master_title"),
		NotLightL10n.text("settings.audio.master_description")
	)
	_audio_master_check = _add_toggle_row(
		master_section,
		NotLightL10n.text("settings.audio.master_enabled"),
		NotLightL10n.text("settings.audio.master_enabled_help")
	)
	_audio_master_check.toggled.connect(_on_audio_master_toggled)
	var master_volume_row: Dictionary = _add_slider_row(
		master_section,
		NotLightL10n.text("settings.audio.master_volume"),
		NotLightL10n.text("settings.audio.master_volume_help"),
		0.0,
		1.0,
		0.01
	)
	_audio_master_slider = master_volume_row.get("slider") as HSlider
	_audio_master_value = master_volume_row.get("value") as Label
	_audio_master_slider.value_changed.connect(_on_audio_master_volume_changed)

	var music_section: VBoxContainer = _make_section(
		parent,
		NotLightL10n.text("settings.audio.background_title"),
		NotLightL10n.text("settings.audio.background_description")
	)
	_background_music_check = _add_toggle_row(
		music_section,
		NotLightL10n.text("settings.audio.background_enabled"),
		NotLightL10n.text("settings.audio.background_enabled_help")
	)
	_background_music_check.toggled.connect(_on_background_music_toggled)
	var music_volume_row: Dictionary = _add_slider_row(
		music_section,
		NotLightL10n.text("settings.audio.background_volume"),
		NotLightL10n.text("settings.audio.background_volume_help"),
		0.0,
		1.0,
		0.01
	)
	_background_music_slider = music_volume_row.get("slider") as HSlider
	_background_music_value = music_volume_row.get("value") as Label
	_background_music_slider.value_changed.connect(_on_background_music_volume_changed)
	_background_music_option = _add_option_row(
		music_section,
		NotLightL10n.text("settings.audio.background_track"),
		NotLightL10n.text("settings.audio.background_track_help")
	)
	_background_music_option.item_selected.connect(_on_background_music_track_selected)
	var status_panel: PanelContainer = _make_row_panel(music_section)
	_background_music_status = Label.new()
	_background_music_status.theme_type_variation = "CaptionLabel"
	_background_music_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_panel.add_child(_background_music_status)
	_rebuild_background_music_options("", "")



func _build_performance_page(parent: VBoxContainer) -> void:
	_add_page_heading(parent, NotLightL10n.text("settings.performance.title"), NotLightL10n.text("settings.performance.description"))
	_performance_lock_note = PanelContainer.new()
	_performance_lock_note.theme_type_variation = "SettingsInfoPanel"
	_performance_lock_note.visible = not allow_performance_edit
	parent.add_child(_performance_lock_note)
	var lock_text: Label = Label.new()
	lock_text.text = NotLightL10n.text("ui.format.locked_label") % NotLightL10n.text("settings.performance.locked")
	lock_text.theme_type_variation = "BodyMutedLabel"
	lock_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_performance_lock_note.add_child(lock_text)
	var budget_section: VBoxContainer = _make_section(parent, NotLightL10n.text("settings.performance.profile"), NotLightL10n.text("settings.performance.profile_help"))
	_performance_profile_option = _add_option_row(budget_section, NotLightL10n.text("settings.performance.profile"), "")
	_performance_profile_option.add_item(NotLightL10n.text("settings.performance.profile_auto"), int(AppSettingsStore.PerformanceProfile.AUTO))
	_performance_profile_option.add_item(NotLightL10n.text("settings.performance.profile_eco"), int(AppSettingsStore.PerformanceProfile.ECO))
	_performance_profile_option.add_item(NotLightL10n.text("settings.performance.profile_balanced"), int(AppSettingsStore.PerformanceProfile.BALANCED))
	_performance_profile_option.add_item(NotLightL10n.text("settings.performance.profile_fast"), int(AppSettingsStore.PerformanceProfile.PERFORMANCE))
	_performance_profile_option.add_item(NotLightL10n.text("settings.performance.profile_custom"), int(AppSettingsStore.PerformanceProfile.CUSTOM))
	_performance_profile_option.item_selected.connect(_on_performance_profile_selected)
	_drawing_quality_option = _add_option_row(budget_section, NotLightL10n.text("settings.performance.drawing_quality"), NotLightL10n.text("settings.performance.drawing_quality_help"))
	_drawing_quality_option.add_item(NotLightL10n.text("settings.performance.drawing_quality_eco"), int(AppSettingsStore.DrawingQuality.ECO))
	_drawing_quality_option.add_item(NotLightL10n.text("settings.performance.drawing_quality_balanced"), int(AppSettingsStore.DrawingQuality.BALANCED))
	_drawing_quality_option.add_item(NotLightL10n.text("settings.performance.drawing_quality_high"), int(AppSettingsStore.DrawingQuality.HIGH))
	_drawing_quality_option.add_item(NotLightL10n.text("settings.performance.drawing_quality_ultra"), int(AppSettingsStore.DrawingQuality.ULTRA))
	_drawing_quality_option.item_selected.connect(_on_drawing_quality_selected)
	_board_budget_spin = _add_spin_row(budget_section, NotLightL10n.text("settings.performance.board_budget"), NotLightL10n.text("settings.performance.board_budget_help"), AppSettingsStore.MIN_BOARD_OBJECT_BUDGET, AppSettingsStore.MAX_BOARD_OBJECT_BUDGET, 500)
	_board_budget_spin.value_changed.connect(_on_board_budget_changed)
	_ui_budget_spin = _add_spin_row(budget_section, NotLightL10n.text("settings.performance.materialized_ui"), NotLightL10n.text("settings.performance.materialized_ui_help"), AppSettingsStore.MIN_MATERIALIZED_UI_BUDGET, AppSettingsStore.MAX_MATERIALIZED_UI_BUDGET, 8)
	_ui_budget_spin.value_changed.connect(_on_ui_budget_changed)
	_video_budget_spin = _add_spin_row(budget_section, NotLightL10n.text("settings.performance.video_players"), NotLightL10n.text("settings.performance.video_players_help"), AppSettingsStore.MIN_VIDEO_PLAYERS, AppSettingsStore.MAX_VIDEO_PLAYERS, 1)
	_video_budget_spin.value_changed.connect(_on_video_budget_changed)
	_module_budget_spin = _add_spin_row(budget_section, NotLightL10n.text("settings.performance.module_surfaces"), NotLightL10n.text("settings.performance.module_surfaces_help"), AppSettingsStore.MIN_MODULE_SURFACES, AppSettingsStore.MAX_MODULE_SURFACES, 1)
	_module_budget_spin.value_changed.connect(_on_module_budget_changed)
	_note_workspace_budget_spin = _add_spin_row(
		budget_section,
		NotLightL10n.text("settings.performance.note_workspace_surfaces"),
		NotLightL10n.text("settings.performance.note_workspace_surfaces_help"),
		AppSettingsStore.MIN_NOTE_WORKSPACE_SURFACES,
		AppSettingsStore.MAX_NOTE_WORKSPACE_SURFACES,
		1
	)
	_note_workspace_budget_spin.value_changed.connect(_on_note_workspace_budget_changed)
	_full_note_card_render_check = _add_toggle_row(
		budget_section,
		NotLightL10n.text("settings.performance.full_note_card_render"),
		NotLightL10n.text("settings.performance.full_note_card_render_help")
	)
	_full_note_card_render_check.toggled.connect(_on_full_note_card_render_toggled)
	_note_embed_live_budget_spin = _add_spin_row(
		budget_section,
		NotLightL10n.text("settings.performance.note_embed_live_media"),
		NotLightL10n.text("settings.performance.note_embed_live_media_help"),
		AppSettingsStore.MIN_NOTE_EMBED_LIVE_MEDIA,
		AppSettingsStore.MAX_NOTE_EMBED_LIVE_MEDIA,
		1
	)
	_note_embed_live_budget_spin.value_changed.connect(_on_note_embed_live_budget_changed)
	_note_embed_rich_preview_check = _add_toggle_row(
		budget_section,
		NotLightL10n.text("settings.performance.note_embed_rich_preview"),
		NotLightL10n.text("settings.performance.note_embed_rich_preview_help")
	)
	_note_embed_rich_preview_check.toggled.connect(_on_note_embed_rich_preview_toggled)
	_texture_budget_spin = _add_spin_row(budget_section, NotLightL10n.text("settings.performance.texture_cache"), NotLightL10n.text("settings.performance.texture_cache_help"), AppSettingsStore.MIN_TEXTURE_CACHE_MB, AppSettingsStore.MAX_TEXTURE_CACHE_MB, 64)
	_texture_budget_spin.suffix = NotLightL10n.text("settings.units.memory_suffix")
	_texture_budget_spin.value_changed.connect(_on_texture_budget_changed)
	var frame_rate_section: VBoxContainer = _make_section(
		parent,
		NotLightL10n.text("settings.performance.frame_rate_title"),
		NotLightL10n.text("settings.performance.frame_rate_description")
	)
	_prefer_maximum_fps_check = _add_toggle_row(
		frame_rate_section,
		NotLightL10n.text("settings.performance.prefer_maximum_fps"),
		NotLightL10n.text("settings.performance.prefer_maximum_fps_help")
	)
	_prefer_maximum_fps_check.toggled.connect(_on_prefer_maximum_fps_toggled)
	var monitor_section: VBoxContainer = _make_section(parent, NotLightL10n.text("settings.monitors.title"), NotLightL10n.text("settings.monitors.description"))
	_add_monitor_toggle(monitor_section, "fps", NotLightL10n.text("settings.monitors.fps"), true)
	_add_monitor_toggle(monitor_section, "ram", NotLightL10n.text("settings.monitors.ram"), true)
	_add_monitor_toggle(monitor_section, "cpu", NotLightL10n.text("settings.monitors.cpu"), OS.get_name() == "Windows")
	_add_monitor_toggle(monitor_section, "gpu", NotLightL10n.text("settings.monitors.gpu"), false)
	_add_monitor_toggle(monitor_section, "vram", NotLightL10n.text("settings.monitors.vram"), true)
	_add_monitor_toggle(monitor_section, "battery", NotLightL10n.text("settings.monitors.battery"), OS.get_name() == "Windows")
	_monitor_interval = _add_option_row(monitor_section, NotLightL10n.text("settings.monitors.interval"), "")
	for value: float in [0.5, 1.0, 2.0, 5.0]:
		_monitor_interval.add_item(NotLightL10n.text("ui.format.seconds_one_decimal") % value)
		_monitor_interval.set_item_metadata(_monitor_interval.item_count - 1, value)
	_monitor_interval.item_selected.connect(_on_monitor_interval_selected)


func _build_storage_page(parent: VBoxContainer) -> void:
	_add_page_heading(parent, NotLightL10n.text("settings.storage.title"), NotLightL10n.text("settings.storage.description"))
	var storage_section: VBoxContainer = _make_section(parent, NotLightL10n.text("settings.storage.library"), NotLightL10n.text("settings.storage.library_help"))
	var location_panel: PanelContainer = _make_row_panel(storage_section)
	var location_root: VBoxContainer = VBoxContainer.new()
	location_root.add_theme_constant_override("separation", 8)
	location_panel.add_child(location_root)
	var location_title: Label = Label.new()
	NotLightL10n.bind_text(location_title, "settings.storage.current")
	location_title.theme_type_variation = "SettingsRowTitleLabel"
	location_root.add_child(location_title)
	_library_path_label = Label.new()
	_library_path_label.theme_type_variation = "CaptionLabel"
	_library_path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	location_root.add_child(_library_path_label)
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	location_root.add_child(buttons)
	var choose_button: Button = Button.new()
	NotLightL10n.bind_text(choose_button, "settings.storage.choose")
	choose_button.theme_type_variation = "PrimaryButton"
	choose_button.pressed.connect(_choose_library_location)
	buttons.add_child(choose_button)
	var open_button: Button = Button.new()
	NotLightL10n.bind_text(open_button, "settings.storage.open")
	open_button.theme_type_variation = "GhostButton"
	open_button.pressed.connect(_open_library_folder)
	buttons.add_child(open_button)
	_storage_status_label = Label.new()
	_storage_status_label.theme_type_variation = "CaptionLabel"
	_storage_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	location_root.add_child(_storage_status_label)

	var module_section: VBoxContainer = _make_section(parent, NotLightL10n.text("settings.storage.modules"), NotLightL10n.text("settings.storage.modules_help"))
	var module_panel: PanelContainer = _make_row_panel(module_section)
	var module_root: VBoxContainer = VBoxContainer.new()
	module_root.add_theme_constant_override("separation", 8)
	module_panel.add_child(module_root)
	var module_title: Label = Label.new()
	NotLightL10n.bind_text(module_title, "settings.storage.current")
	module_title.theme_type_variation = "SettingsRowTitleLabel"
	module_root.add_child(module_title)
	_module_path_label = Label.new()
	_module_path_label.theme_type_variation = "CaptionLabel"
	_module_path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	module_root.add_child(_module_path_label)
	var module_buttons: HBoxContainer = HBoxContainer.new()
	module_buttons.add_theme_constant_override("separation", 8)
	module_root.add_child(module_buttons)
	var module_choose_button: Button = Button.new()
	NotLightL10n.bind_text(module_choose_button, "settings.storage.choose")
	module_choose_button.theme_type_variation = "PrimaryButton"
	module_choose_button.pressed.connect(_choose_module_location)
	module_buttons.add_child(module_choose_button)
	var module_open_button: Button = Button.new()
	NotLightL10n.bind_text(module_open_button, "settings.storage.open")
	module_open_button.theme_type_variation = "GhostButton"
	module_open_button.pressed.connect(_open_module_folder)
	module_buttons.add_child(module_open_button)
	_module_storage_status_label = Label.new()
	_module_storage_status_label.theme_type_variation = "CaptionLabel"
	_module_storage_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	module_root.add_child(_module_storage_status_label)

	var cpu_section: VBoxContainer = _make_section(parent, NotLightL10n.text("settings.storage.video"), NotLightL10n.text("settings.storage.video_help"))
	_compression_cpu_option = _add_option_row(cpu_section, NotLightL10n.text("settings.storage.cpu_load"), NotLightL10n.text("settings.storage.cpu_help"))
	_compression_cpu_option.add_item(NotLightL10n.text("settings.storage.eco"), int(AppSettingsStore.CompressionCpuMode.ECO))
	_compression_cpu_option.add_item(NotLightL10n.text("settings.storage.balanced"), int(AppSettingsStore.CompressionCpuMode.BALANCED))
	_compression_cpu_option.add_item(NotLightL10n.text("settings.storage.maximum"), int(AppSettingsStore.CompressionCpuMode.MAXIMUM))
	_compression_cpu_option.item_selected.connect(_on_compression_cpu_selected)
	_auto_optimize_video_check = _add_toggle_row(cpu_section, NotLightL10n.text("settings.storage.auto_video"), NotLightL10n.text("settings.storage.auto_video_help"))
	_auto_optimize_video_check.toggled.connect(_on_auto_optimize_video_toggled)


func _build_developer_page(parent: VBoxContainer) -> void:
	_add_page_heading(parent, NotLightL10n.text("settings.developer.title"), NotLightL10n.text("settings.developer.description"))
	var diagnostics_section: VBoxContainer = _make_section(
		parent,
		NotLightL10n.text("settings.developer.diagnostics_title"),
		NotLightL10n.text("settings.developer.diagnostics_description")
	)
	_developer_diagnostics_check = _add_toggle_row(
		diagnostics_section,
		NotLightL10n.text("settings.developer.diagnostics_toggle"),
		NotLightL10n.text("settings.developer.diagnostics_help")
	)
	_developer_diagnostics_check.toggled.connect(_on_developer_diagnostics_toggled)
	var note_panel: PanelContainer = _make_row_panel(diagnostics_section)
	var note: Label = Label.new()
	NotLightL10n.bind_text(note, "settings.developer.diagnostics_note")
	note.theme_type_variation = "CaptionLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_panel.add_child(note)


func _build_footer(parent: VBoxContainer) -> void:
	var separator: HSeparator = HSeparator.new()
	separator.custom_minimum_size = Vector2(0.0, 18.0)
	parent.add_child(separator)
	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	parent.add_child(footer)
	var status: Label = Label.new()
	NotLightL10n.bind_text(status, "settings.footer.auto_save")
	status.theme_type_variation = "CaptionLabel"
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(status)
	var reset_button: Button = Button.new()
	NotLightL10n.bind_text(reset_button, "common.reset")
	reset_button.theme_type_variation = "GhostButton"
	reset_button.custom_minimum_size = Vector2(104.0, 42.0)
	reset_button.pressed.connect(_on_reset_pressed)
	footer.add_child(reset_button)
	var done_button: Button = Button.new()
	NotLightL10n.bind_text(done_button, "common.done")
	done_button.theme_type_variation = "PrimaryButton"
	done_button.custom_minimum_size = Vector2(116.0, 42.0)
	done_button.pressed.connect(close_dialog)
	footer.add_child(done_button)


func _build_folder_dialog() -> void:
	_folder_dialog = FileDialog.new()
	_folder_dialog.title = NotLightL10n.text("settings.storage.choose")
	_folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_folder_dialog.use_native_dialog = true
	_folder_dialog.dir_selected.connect(_on_storage_directory_selected)
	add_child(_folder_dialog)


func _add_page_heading(parent: VBoxContainer, title_text: String, description_text: String) -> void:
	var title: Label = Label.new()
	title.text = title_text
	title.theme_type_variation = "SectionLabel"
	parent.add_child(title)
	var description: Label = Label.new()
	description.text = description_text
	description.theme_type_variation = "BodyMutedLabel"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(description)


func _make_section(parent: VBoxContainer, title_text: String, description_text: String) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.theme_type_variation = "SettingsSectionPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var section: VBoxContainer = VBoxContainer.new()
	section.add_theme_constant_override("separation", 10)
	panel.add_child(section)
	var title: Label = Label.new()
	title.text = title_text
	title.theme_type_variation = "SettingsSectionTitleLabel"
	section.add_child(title)
	if not description_text.is_empty():
		var description: Label = Label.new()
		description.text = description_text
		description.theme_type_variation = "CaptionLabel"
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		section.add_child(description)
	return section


func _make_row_panel(parent: VBoxContainer) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.theme_type_variation = "SettingsSliderPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	return panel


func _make_text_column(parent: HBoxContainer, title_text: String, description_text: String) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	parent.add_child(box)
	var title: Label = Label.new()
	title.text = title_text
	title.theme_type_variation = "SettingsRowTitleLabel"
	box.add_child(title)
	var description: Label = Label.new()
	description.text = description_text
	description.theme_type_variation = "CaptionLabel"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(description)
	return box


func _add_option_row(parent: VBoxContainer, title_text: String, description_text: String) -> OptionButton:
	var panel: PanelContainer = _make_row_panel(parent)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	_make_text_column(row, title_text, description_text)
	var option: OptionButton = OptionButton.new()
	option.theme_type_variation = "SettingsOptionButton"
	# Keep long translated labels / media titles from changing the modal width.
	# OptionButton otherwise derives its minimum width from the longest popup item.
	option.fit_to_longest_item = false
	option.custom_minimum_size = Vector2(190.0, 38.0)
	option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(option)
	return option


func _add_toggle_row(parent: VBoxContainer, title_text: String, description_text: String) -> CheckBox:
	var panel: PanelContainer = _make_row_panel(parent)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	_make_text_column(row, title_text, description_text)
	var check: CheckBox = CheckBox.new()
	check.text = ""
	check.custom_minimum_size = Vector2(44.0, 38.0)
	row.add_child(check)
	return check


func _add_slider_row(parent: VBoxContainer, label_text: String, description_text: String, minimum: float, maximum: float, step: float) -> Dictionary:
	var panel: PanelContainer = _make_row_panel(parent)
	var row: VBoxContainer = VBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var heading: HBoxContainer = HBoxContainer.new()
	heading.add_theme_constant_override("separation", 10)
	row.add_child(heading)
	_make_text_column(heading, label_text, description_text)
	var value_label: Label = Label.new()
	value_label.theme_type_variation = "SettingsValueLabel"
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.custom_minimum_size = Vector2(70.0, 30.0)
	heading.add_child(value_label)
	var slider: HSlider = HSlider.new()
	slider.scrollable = false
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	return {"slider": slider, "value": value_label}


func _add_spin_row(parent: VBoxContainer, title_text: String, description_text: String, minimum: int, maximum: int, step: int) -> SpinBox:
	var panel: PanelContainer = _make_row_panel(parent)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	_make_text_column(row, title_text, description_text)
	var spin: SpinBox = SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.custom_minimum_size = Vector2(160.0, 42.0)
	spin.update_on_text_changed = false
	row.add_child(spin)
	return spin


func _add_monitor_toggle(parent: VBoxContainer, key: String, title_text: String, supported: bool) -> void:
	var description: String = "" if supported else NotLightL10n.text("settings.monitors.unsupported")
	var check: CheckBox = _add_toggle_row(parent, title_text, description)
	check.disabled = not supported
	check.toggled.connect(_on_monitor_toggled.bind(key))
	_monitor_checks[key] = check


func _add_palette_color_row(parent: VBoxContainer, key: String, title_text: String) -> void:
	var panel: PanelContainer = _make_row_panel(parent)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	_make_text_column(row, title_text, key)
	var picker: ColorPickerButton = ColorPickerButton.new()
	picker.edit_alpha = false
	picker.custom_minimum_size = Vector2(92.0, 38.0)
	picker.picker_created.connect(_configure_compact_color_picker.bind(picker))
	picker.color_changed.connect(_on_palette_color_changed.bind(key))
	row.add_child(picker)
	_palette_color_buttons[key] = picker



func _configure_compact_color_picker(button: ColorPickerButton) -> void:
	NotLightColorPickerStyle.configure_button_popup(button, size.y, false)


func _fit_modal_to_viewport() -> void:
	if _modal_panel == null:
		return
	var safe_width: float = maxf(560.0, size.x - 36.0)
	var safe_height: float = maxf(480.0, size.y - 36.0)
	_modal_panel.custom_minimum_size = Vector2(minf(920.0, safe_width), minf(650.0, safe_height))

func _rebuild_palette_options(selected_id: String) -> void:
	if _palette_option == null:
		return
	_palette_option.clear()
	_palette_option.add_item(NotLightL10n.text("settings.palette.default"))
	_palette_option.set_item_metadata(_palette_option.item_count - 1, NotLightPalette.PRESET_DEFAULT)
	_palette_option.add_item(NotLightL10n.text("settings.palette.high_contrast"))
	_palette_option.set_item_metadata(_palette_option.item_count - 1, NotLightPalette.PRESET_HIGH_CONTRAST)
	_palette_option.add_item(NotLightL10n.text("settings.palette.custom"))
	_palette_option.set_item_metadata(_palette_option.item_count - 1, NotLightPalette.PRESET_CUSTOM)
	if settings != null:
		var presets: Array[Dictionary] = settings.list_user_palette_presets()
		if not presets.is_empty():
			_palette_option.add_separator(NotLightL10n.text("settings.palette.saved_group"))
		for record: Dictionary in presets:
			_palette_option.add_item(str(record.get("name", NotLightL10n.text("settings.palette.saved_unnamed"))))
			_palette_option.set_item_metadata(_palette_option.item_count - 1, str(record.get("id", "")))
	_select_item_by_metadata(_palette_option, selected_id)


func _show_page(page: int) -> void:
	_current_page = clampi(page, PAGE_CONTROLS, PAGE_DEVELOPER)
	for index: int in range(_pages.size()):
		_pages[index].visible = index == _current_page
	for index: int in range(_nav_buttons.size()):
		_nav_buttons[index].button_pressed = index == _current_page


func _refresh(snapshot: Dictionary) -> void:
	if _input_mode == null:
		return
	_syncing = true
	var input_mode_value: int = int(snapshot.get("input_mode", int(AppSettingsStore.InputMode.TRACKPAD)))
	_select_item_by_id(_input_mode, input_mode_value)
	_mode_help.text = NotLightL10n.text("settings.input.trackpad_help") if input_mode_value == int(AppSettingsStore.InputMode.TRACKPAD) else NotLightL10n.text("settings.input.mouse_help")
	_camera_slider.value = float(snapshot.get("camera_sensitivity", 1.0))
	_zoom_slider.value = float(snapshot.get("zoom_sensitivity", 1.0))
	_speed_slider.value = float(snapshot.get("camera_speed", 9.5))
	var locale_value: String = str(snapshot.get("locale", AppSettingsStore.DEFAULT_LOCALE))
	_select_item_by_metadata(_locale_option, locale_value)
	_select_item_by_id(_window_option, int(snapshot.get("window_mode", int(AppSettingsStore.WindowModePreference.MAXIMIZED))))
	if _tool_hints_check != null:
		_tool_hints_check.button_pressed = bool(snapshot.get("show_tool_hints", true))
	var grid_intensity_value: int = int(snapshot.get("grid_intensity", int(AppSettingsStore.GridIntensity.BALANCED)))
	_select_item_by_id(_grid_intensity_option, grid_intensity_value)
	if _grid_intensity_preview != null:
		_grid_intensity_preview.set_intensity(grid_intensity_value)
		_grid_intensity_preview.refresh_palette()
	var palette_value: String = str(snapshot.get("palette_id", NotLightPalette.PRESET_DEFAULT))
	_rebuild_palette_options(palette_value)
	_palette_custom_box.visible = palette_value == NotLightPalette.PRESET_CUSTOM
	if _palette_delete_preset_button != null:
		_palette_delete_preset_button.disabled = settings == null or not settings.is_user_palette_preset(palette_value)
	var effective_palette: Dictionary = settings.get_effective_palette() if settings != null else NotLightPalette.default_palette()
	for raw_key: Variant in _palette_color_buttons.keys():
		var key: String = str(raw_key)
		var picker: ColorPickerButton = _palette_color_buttons[key] as ColorPickerButton
		picker.color = NotLightPalette.color(effective_palette, key)
	if _audio_master_check != null:
		_audio_master_check.button_pressed = bool(snapshot.get("audio_master_enabled", true))
	if _audio_master_slider != null:
		_audio_master_slider.value = float(snapshot.get("audio_master_volume", AppSettingsStore.DEFAULT_AUDIO_MASTER_VOLUME))
	if _background_music_check != null:
		_background_music_check.button_pressed = bool(snapshot.get("background_music_enabled", false))
	if _background_music_slider != null:
		_background_music_slider.value = float(snapshot.get("background_music_volume", AppSettingsStore.DEFAULT_BACKGROUND_MUSIC_VOLUME))
	_rebuild_background_music_options(
		str(snapshot.get("background_music_track", "")),
		str(snapshot.get("background_music_asset_id", ""))
	)
	_update_audio_editability(snapshot)
	_select_item_by_id(_performance_profile_option, int(snapshot.get("performance_profile", int(AppSettingsStore.PerformanceProfile.AUTO))))
	var profile_value: int = int(snapshot.get("performance_profile", int(AppSettingsStore.PerformanceProfile.AUTO)))
	var displayed_quality: int = int(snapshot.get("custom_drawing_quality", int(AppSettingsStore.DrawingQuality.HIGH))) if profile_value == int(AppSettingsStore.PerformanceProfile.CUSTOM) else int(snapshot.get("effective_drawing_quality", int(AppSettingsStore.DrawingQuality.HIGH)))
	_select_item_by_id(_drawing_quality_option, displayed_quality)
	_board_budget_spin.value = int(snapshot.get("custom_board_object_budget", 12000))
	_ui_budget_spin.value = int(snapshot.get("custom_materialized_ui_budget", 96))
	_video_budget_spin.value = int(snapshot.get("custom_active_video_players", 10))
	_module_budget_spin.value = int(snapshot.get("custom_active_module_surfaces", 3))
	_note_workspace_budget_spin.value = int(snapshot.get("custom_active_note_workspace_surfaces", AppSettingsStore.DEFAULT_NOTE_WORKSPACE_SURFACES))
	_full_note_card_render_check.button_pressed = bool(snapshot.get("custom_full_note_card_render", false))
	_note_embed_live_budget_spin.value = int(snapshot.get("custom_note_embed_live_media", AppSettingsStore.DEFAULT_NOTE_EMBED_LIVE_MEDIA))
	_note_embed_rich_preview_check.button_pressed = bool(snapshot.get("custom_note_embed_rich_preview", true))
	_texture_budget_spin.value = int(snapshot.get("custom_texture_cache_mb", 512))
	_prefer_maximum_fps_check.button_pressed = bool(snapshot.get("prefer_maximum_fps", false))
	_update_performance_editability(int(snapshot.get("performance_profile", int(AppSettingsStore.PerformanceProfile.AUTO))))
	for key: String in ["fps", "ram", "cpu", "gpu", "vram", "battery"]:
		var check: CheckBox = _monitor_checks.get(key) as CheckBox
		if check != null:
			check.button_pressed = bool(snapshot.get("show_%s" % key, key == "fps"))
	_select_item_by_metadata(_monitor_interval, float(snapshot.get("monitor_interval_seconds", 1.0)))
	if _developer_diagnostics_check != null:
		_developer_diagnostics_check.button_pressed = bool(snapshot.get("developer_diagnostics_enabled", false))
	if _library_path_label != null:
		var root_path: String = str(snapshot.get("library_root", AppSettingsStore.DEFAULT_LIBRARY_ROOT))
		_library_path_label.text = ProjectSettings.globalize_path(root_path) if root_path.begins_with("user://") or root_path.begins_with("res://") else root_path
	if _module_path_label != null:
		var module_root_path: String = str(snapshot.get("module_root", AppSettingsStore.DEFAULT_MODULE_ROOT))
		_module_path_label.text = ProjectSettings.globalize_path(module_root_path) if module_root_path.begins_with("user://") or module_root_path.begins_with("res://") else module_root_path
	_select_item_by_id(_compression_cpu_option, int(snapshot.get("compression_cpu_mode", int(AppSettingsStore.CompressionCpuMode.ECO))))
	_auto_optimize_video_check.button_pressed = bool(snapshot.get("auto_optimize_video", false))
	_update_value_labels()
	_syncing = false


func _rebuild_background_music_options(selected_path: String, selected_asset_id: String) -> void:
	if _background_music_option == null:
		return
	_background_music_option.clear()
	_background_music_option.add_item(NotLightL10n.text("settings.audio.background_auto"))
	_background_music_option.set_item_metadata(0, {"source": "auto", "value": ""})
	var bundled_tracks: Array[Dictionary] = []
	var library_tracks: Array[Dictionary] = []
	if app_audio != null:
		bundled_tracks = app_audio.get_bundled_tracks()
		library_tracks = app_audio.get_library_tracks()
	for record: Dictionary in bundled_tracks:
		var path: String = str(record.get("path", ""))
		var name: String = str(record.get("name", NotLightL10n.text("settings.audio.background_unnamed")))
		_background_music_option.add_item(NotLightL10n.text("settings.audio.background_bundled_item", {"name": name}))
		_background_music_option.set_item_metadata(
			_background_music_option.item_count - 1,
			{"source": "bundled", "value": path}
		)
	for record: Dictionary in library_tracks:
		var asset_id: String = str(record.get("asset_id", ""))
		var name: String = str(record.get("name", NotLightL10n.text("settings.audio.background_unnamed")))
		_background_music_option.add_item(NotLightL10n.text("settings.audio.background_library_item", {"name": name}))
		_background_music_option.set_item_metadata(
			_background_music_option.item_count - 1,
			{"source": "library", "value": asset_id}
		)
	var selected: bool = false
	if not selected_asset_id.is_empty():
		selected = _select_background_music_metadata("library", selected_asset_id)
		if not selected:
			_background_music_option.add_item(NotLightL10n.text("settings.audio.background_library_missing_item"))
			_background_music_option.set_item_metadata(
				_background_music_option.item_count - 1,
				{"source": "library", "value": selected_asset_id}
			)
			_background_music_option.select(_background_music_option.item_count - 1)
			selected = true
	elif not selected_path.is_empty():
		selected = _select_background_music_metadata("bundled", selected_path)
		if not selected:
			_background_music_option.add_item(NotLightL10n.text("settings.audio.background_bundled_missing_item"))
			_background_music_option.set_item_metadata(
				_background_music_option.item_count - 1,
				{"source": "bundled", "value": selected_path}
			)
			_background_music_option.select(_background_music_option.item_count - 1)
			selected = true
	if not selected:
		_background_music_option.select(0)
	if _background_music_status != null:
		if bundled_tracks.is_empty() and library_tracks.is_empty():
			NotLightL10n.bind_text(_background_music_status, "settings.audio.background_missing")
		else:
			_background_music_status.text = NotLightL10n.text(
				"settings.audio.background_found",
				{"bundled": bundled_tracks.size(), "library": library_tracks.size()}
			)


func _select_background_music_metadata(source: String, value: String) -> bool:
	if _background_music_option == null:
		return false
	for index: int in range(_background_music_option.item_count):
		var metadata: Variant = _background_music_option.get_item_metadata(index)
		if metadata is not Dictionary:
			continue
		var record: Dictionary = metadata as Dictionary
		if str(record.get("source", "")) == source and str(record.get("value", "")) == value:
			_background_music_option.select(index)
			return true
	return false


func _update_audio_editability(snapshot: Dictionary) -> void:
	var master_enabled: bool = bool(snapshot.get("audio_master_enabled", true))
	var music_enabled: bool = bool(snapshot.get("background_music_enabled", false))
	var track_count: int = 0
	if app_audio != null:
		track_count = app_audio.get_bundled_tracks().size() + app_audio.get_library_tracks().size()
	var has_explicit_selection: bool = (
		not str(snapshot.get("background_music_track", "")).strip_edges().is_empty()
		or not str(snapshot.get("background_music_asset_id", "")).strip_edges().is_empty()
	)
	if _audio_master_slider != null:
		_audio_master_slider.editable = master_enabled
	if _background_music_check != null:
		_background_music_check.disabled = not master_enabled
	if _background_music_slider != null:
		_background_music_slider.editable = master_enabled and music_enabled
	if _background_music_option != null:
		_background_music_option.disabled = (
			not master_enabled
			or not music_enabled
			or (track_count <= 0 and not has_explicit_selection)
		)


func _update_performance_editability(profile: int) -> void:
	var custom_enabled: bool = allow_performance_edit and profile == int(AppSettingsStore.PerformanceProfile.CUSTOM)
	_performance_profile_option.disabled = not allow_performance_edit
	_drawing_quality_option.disabled = not custom_enabled
	_board_budget_spin.editable = custom_enabled
	_ui_budget_spin.editable = custom_enabled
	_video_budget_spin.editable = custom_enabled
	_module_budget_spin.editable = custom_enabled
	_note_workspace_budget_spin.editable = custom_enabled
	_full_note_card_render_check.disabled = not custom_enabled
	_note_embed_live_budget_spin.editable = custom_enabled
	_note_embed_rich_preview_check.disabled = not custom_enabled
	_texture_budget_spin.editable = custom_enabled
	_prefer_maximum_fps_check.disabled = not allow_performance_edit
	if _performance_lock_note != null:
		_performance_lock_note.visible = not allow_performance_edit


func _select_item_by_id(option: OptionButton, id: int) -> void:
	if option == null:
		return
	for index: int in range(option.item_count):
		if option.get_item_id(index) == id:
			option.select(index)
			return


func _select_item_by_metadata(option: OptionButton, value: Variant) -> void:
	if option == null:
		return
	for index: int in range(option.item_count):
		if option.get_item_metadata(index) == value:
			option.select(index)
			return


func _update_value_labels() -> void:
	_camera_value.text = NotLightL10n.text("ui.format.scale_two_decimals") % _camera_slider.value
	_zoom_value.text = NotLightL10n.text("ui.format.scale_two_decimals") % _zoom_slider.value
	_speed_value.text = NotLightL10n.text("ui.format.number_one_decimal") % _speed_slider.value
	if _audio_master_value != null and _audio_master_slider != null:
		_audio_master_value.text = NotLightL10n.text("ui.format.percent_int") % roundi(_audio_master_slider.value * 100.0)
	if _background_music_value != null and _background_music_slider != null:
		_background_music_value.text = NotLightL10n.text("ui.format.percent_int") % roundi(_background_music_slider.value * 100.0)


func _on_locale_changed(_locale_code: String) -> void:
	var was_visible: bool = visible
	var page: int = _current_page
	_build_all()
	if settings != null:
		_refresh(settings.get_snapshot())
	_show_page(page)
	visible = was_visible


func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			close_dialog()
			accept_event()


func _on_input_mode_selected(index: int) -> void:
	if not _syncing and settings != null:
		settings.set_input_mode(_input_mode.get_item_id(index))


func _on_camera_sensitivity_changed(value: float) -> void:
	_update_value_labels()
	if not _syncing and settings != null:
		settings.set_camera_sensitivity(value)


func _on_zoom_sensitivity_changed(value: float) -> void:
	_update_value_labels()
	if not _syncing and settings != null:
		settings.set_zoom_sensitivity(value)


func _on_camera_speed_changed(value: float) -> void:
	_update_value_labels()
	if not _syncing and settings != null:
		settings.set_camera_speed(value)


func _on_locale_selected(index: int) -> void:
	if not _syncing and settings != null:
		settings.set_locale(str(_locale_option.get_item_metadata(index)))


func _on_window_mode_selected(index: int) -> void:
	if not _syncing and settings != null:
		settings.set_window_mode(_window_option.get_item_id(index))


func _on_tool_hints_toggled(value: bool) -> void:
	if not _syncing and settings != null:
		settings.set_show_tool_hints(value)


func _on_audio_master_toggled(value: bool) -> void:
	if not _syncing and settings != null:
		settings.set_audio_master_enabled(value)


func _on_audio_master_volume_changed(value: float) -> void:
	_update_value_labels()
	if not _syncing and settings != null:
		settings.set_audio_master_volume(value)
		if app_audio != null:
			app_audio.apply_live_levels()


func _on_background_music_toggled(value: bool) -> void:
	if not _syncing and settings != null:
		settings.set_background_music_enabled(value)


func _on_background_music_volume_changed(value: float) -> void:
	_update_value_labels()
	if not _syncing and settings != null:
		settings.set_background_music_volume(value)
		if app_audio != null:
			app_audio.apply_live_levels()


func _on_background_music_track_selected(index: int) -> void:
	if _syncing or settings == null or _background_music_option == null:
		return
	var metadata: Variant = _background_music_option.get_item_metadata(index)
	if metadata is not Dictionary:
		return
	var record: Dictionary = metadata as Dictionary
	var source: String = str(record.get("source", ""))
	var value: String = str(record.get("value", ""))
	match source:
		"library":
			settings.set_background_music_asset_id(value)
		"bundled":
			settings.set_background_music_track(value)
		_:
			settings.clear_background_music_selection()


func _on_bundled_tracks_changed(_tracks: Array[Dictionary]) -> void:
	if settings != null:
		_refresh(settings.get_snapshot())


func _on_library_tracks_changed(_tracks: Array[Dictionary]) -> void:
	if settings != null:
		_refresh(settings.get_snapshot())



func _on_grid_intensity_selected(index: int) -> void:
	var intensity_value: int = _grid_intensity_option.get_item_id(index)
	if _grid_intensity_preview != null:
		_grid_intensity_preview.set_intensity(intensity_value)
	if not _syncing and settings != null:
		settings.set_grid_intensity(intensity_value)


func _on_palette_selected(index: int) -> void:
	if not _syncing and settings != null:
		settings.set_palette_id(str(_palette_option.get_item_metadata(index)))


func _on_palette_color_changed(color: Color, key: String) -> void:
	if not _syncing and settings != null:
		settings.set_custom_palette_color(key, color)


func _on_palette_preset_name_submitted(_value: String) -> void:
	_on_save_palette_preset_pressed()


func _on_save_palette_preset_pressed() -> void:
	if _syncing or settings == null or _palette_preset_name == null:
		return
	var preset_id: String = settings.save_user_palette_preset(_palette_preset_name.text)
	if preset_id.is_empty():
		_palette_preset_name.grab_focus()
		return
	_palette_preset_name.clear()
	_rebuild_palette_options(preset_id)


func _on_delete_palette_preset_pressed() -> void:
	if _syncing or settings == null or _palette_option == null:
		return
	var selected_id: String = str(_palette_option.get_item_metadata(_palette_option.selected))
	if settings.delete_user_palette_preset(selected_id):
		_rebuild_palette_options(NotLightPalette.PRESET_DEFAULT)


func _on_drawing_quality_selected(index: int) -> void:
	if _syncing or settings == null or not allow_performance_edit:
		return
	settings.set_custom_drawing_quality(_drawing_quality_option.get_item_id(index))


func _on_performance_profile_selected(index: int) -> void:
	if _syncing or settings == null or not allow_performance_edit:
		return
	settings.set_performance_profile(_performance_profile_option.get_item_id(index))


func _on_board_budget_changed(value: float) -> void:
	if not _syncing and settings != null and allow_performance_edit:
		settings.set_custom_board_object_budget(int(value))


func _on_ui_budget_changed(value: float) -> void:
	if not _syncing and settings != null and allow_performance_edit:
		settings.set_custom_materialized_ui_budget(int(value))


func _on_video_budget_changed(value: float) -> void:
	if not _syncing and settings != null and allow_performance_edit:
		settings.set_custom_active_video_players(int(value))


func _on_module_budget_changed(value: float) -> void:
	if not _syncing and settings != null and allow_performance_edit:
		settings.set_custom_active_module_surfaces(int(value))


func _on_note_workspace_budget_changed(value: float) -> void:
	if not _syncing and settings != null and allow_performance_edit:
		settings.set_custom_active_note_workspace_surfaces(int(value))


func _on_full_note_card_render_toggled(value: bool) -> void:
	if not _syncing and settings != null and allow_performance_edit:
		settings.set_custom_full_note_card_render(value)


func _on_note_embed_live_budget_changed(value: float) -> void:
	if not _syncing and settings != null and allow_performance_edit:
		settings.set_custom_note_embed_live_media(int(value))


func _on_note_embed_rich_preview_toggled(value: bool) -> void:
	if not _syncing and settings != null and allow_performance_edit:
		settings.set_custom_note_embed_rich_preview(value)


func _on_texture_budget_changed(value: float) -> void:
	if not _syncing and settings != null and allow_performance_edit:
		settings.set_custom_texture_cache_mb(int(value))


func _on_prefer_maximum_fps_toggled(value: bool) -> void:
	if not _syncing and settings != null and allow_performance_edit:
		settings.set_prefer_maximum_fps(value)


func _on_monitor_toggled(value: bool, key: String) -> void:
	if _syncing or settings == null:
		return
	match key:
		"fps": settings.set_show_fps(value)
		"ram": settings.set_show_ram(value)
		"cpu": settings.set_show_cpu(value)
		"gpu": settings.set_show_gpu(value)
		"vram": settings.set_show_vram(value)
		"battery": settings.set_show_battery(value)


func _on_monitor_interval_selected(index: int) -> void:
	if not _syncing and settings != null:
		settings.set_monitor_interval(float(_monitor_interval.get_item_metadata(index)))


func _on_developer_diagnostics_toggled(value: bool) -> void:
	if not _syncing and settings != null:
		settings.set_developer_diagnostics_enabled(value)


func _on_compression_cpu_selected(index: int) -> void:
	if not _syncing and settings != null:
		settings.set_compression_cpu_mode(_compression_cpu_option.get_item_id(index))


func _on_auto_optimize_video_toggled(value: bool) -> void:
	if not _syncing and settings != null:
		settings.set_auto_optimize_video(value)


func _choose_library_location() -> void:
	_storage_dialog_target = STORAGE_TARGET_LIBRARY
	if _folder_dialog != null:
		_folder_dialog.title = NotLightL10n.text("settings.storage.choose_library")
		_folder_dialog.popup_centered_ratio(0.72)


func _choose_module_location() -> void:
	_storage_dialog_target = STORAGE_TARGET_MODULES
	if _folder_dialog != null:
		_folder_dialog.title = NotLightL10n.text("settings.storage.choose_modules")
		_folder_dialog.popup_centered_ratio(0.72)


func _open_library_folder() -> void:
	if settings == null:
		return
	_open_storage_path(settings.library_root)


func _open_module_folder() -> void:
	if settings == null:
		return
	_open_storage_path(settings.module_root)


func _open_storage_path(raw_path: String) -> void:
	var path: String = raw_path.strip_edges()
	if path.is_empty():
		return
	if path.begins_with("user://") or path.begins_with("res://"):
		path = ProjectSettings.globalize_path(path)
	OS.shell_open(path)


func _on_storage_directory_selected(path: String) -> void:
	if _storage_dialog_target == STORAGE_TARGET_MODULES:
		_prepare_module_storage(path)
	else:
		_prepare_library_storage(path)


func _prepare_library_storage(path: String) -> void:
	if library == null or settings == null or _storage_status_label == null:
		return
	if library.has_pending_imports():
		NotLightL10n.bind_text(_storage_status_label, "settings.storage.wait_import")
		return
	if video_media != null and video_media.is_optimizing():
		NotLightL10n.bind_text(_storage_status_label, "settings.storage.wait_video")
		return
	NotLightL10n.bind_text(_storage_status_label, "settings.storage.copying")
	var result: Dictionary = library.prepare_external_library(path)
	if not bool(result.get("ok", false)):
		_storage_status_label.text = str(result.get("error", NotLightL10n.text("settings.storage.prepare_failed")))
		return
	var new_root: String = str(result.get("root", ""))
	var copied_files: int = int(result.get("copied_files", 0))
	if bool(result.get("same_location", false)):
		NotLightL10n.bind_text(_storage_status_label, "settings.storage.same_location")
	elif bool(result.get("existing", false)):
		_storage_status_label.text = NotLightL10n.text("settings.storage.existing_found_restart", {"path": new_root})
	else:
		_storage_status_label.text = NotLightL10n.text("settings.storage.copy_done_restart", {"count": copied_files, "path": new_root})


func _prepare_module_storage(path: String) -> void:
	if module_registry == null or settings == null or _module_storage_status_label == null:
		return
	NotLightL10n.bind_text(_module_storage_status_label, "settings.storage.copying_modules")
	var result: Dictionary = module_registry.prepare_external_modules(path)
	if not bool(result.get("ok", false)):
		_module_storage_status_label.text = str(result.get("error", NotLightL10n.text("settings.storage.prepare_modules_failed")))
		return
	var new_root: String = str(result.get("root", ""))
	var copied_files: int = int(result.get("copied_files", 0))
	if bool(result.get("same_location", false)):
		NotLightL10n.bind_text(_module_storage_status_label, "settings.storage.same_location")
	elif bool(result.get("existing", false)):
		_module_storage_status_label.text = NotLightL10n.text("settings.storage.modules_existing_restart", {"path": new_root})
	else:
		_module_storage_status_label.text = NotLightL10n.text("settings.storage.modules_copy_done_restart", {"count": copied_files, "path": new_root})


func _on_reset_pressed() -> void:
	if settings != null:
		settings.reset_defaults(true, not allow_performance_edit)


func _on_settings_changed(snapshot: Dictionary) -> void:
	_refresh(snapshot)
