# SPDX-License-Identifier: GPL-3.0-or-later
class_name MicrophonePermissionDialog
extends Window

signal allow_requested
signal decline_requested
signal system_settings_requested

const DEFAULT_DIALOG_SIZE: Vector2i = Vector2i(620, 420)
const MIN_DIALOG_SIZE: Vector2i = Vector2i(540, 320)
const PARENT_SIZE_RATIO: float = 0.94

var _title_label: Label
var _body_label: Label
var _privacy_label: Label
var _system_button: Button
var _allow_button: Button


func _init() -> void:
	visible = false


func _ready() -> void:
	size = DEFAULT_DIALOG_SIZE
	min_size = MIN_DIALOG_SIZE
	max_size = Vector2i.ZERO
	unresizable = true
	borderless = true
	transient = true
	exclusive = true
	close_requested.connect(_decline)
	_build_ui()


func open_dialog(system_settings_available: bool, audio_input_enabled: bool) -> void:
	if _system_button != null:
		_system_button.visible = system_settings_available
	if _privacy_label != null:
		_privacy_label.text = (
			NotLightL10n.text("voice.permission.project_input_warning")
			if not audio_input_enabled
			else NotLightL10n.text("voice.permission.privacy_note")
		)
	popup_centered_clamped(DEFAULT_DIALOG_SIZE, PARENT_SIZE_RATIO)
	if _allow_button != null:
		_allow_button.grab_focus()


func _build_ui() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.theme = NotLightTheme.create_theme()
	panel.theme_type_variation = "SettingsModalPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	panel.add_child(content)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	content.add_child(header)

	var icon_panel: PanelContainer = PanelContainer.new()
	icon_panel.theme_type_variation = "SettingsMarkPanel"
	icon_panel.custom_minimum_size = Vector2(46.0, 46.0)
	header.add_child(icon_panel)
	var icon: Label = Label.new()
	icon.text = "●"
	NotLightL10n.bind_tooltip(icon, "voice.permission.title")
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_theme_color_override("font_color", NotLightTheme.semantic_color("accent"))
	icon_panel.add_child(icon)

	_title_label = Label.new()
	NotLightL10n.bind_text(_title_label, "voice.permission.title")
	_title_label.theme_type_variation = "TitleLabel"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(_title_label)

	var close_button: Button = Button.new()
	close_button.text = "×"
	NotLightL10n.bind_tooltip(close_button, "common.cancel")
	close_button.theme_type_variation = "IconButton"
	close_button.custom_minimum_size = Vector2(40.0, 40.0)
	close_button.pressed.connect(_decline)
	header.add_child(close_button)

	var body_scroll: ScrollContainer = ScrollContainer.new()
	body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content.add_child(body_scroll)

	var body_stack: VBoxContainer = VBoxContainer.new()
	body_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_stack.add_theme_constant_override("separation", 12)
	body_scroll.add_child(body_stack)

	_body_label = Label.new()
	NotLightL10n.bind_text(_body_label, "voice.permission.body")
	_body_label.theme_type_variation = "BodyMutedLabel"
	_body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_stack.add_child(_body_label)

	var privacy_panel: PanelContainer = PanelContainer.new()
	privacy_panel.theme_type_variation = "SoftPanel"
	body_stack.add_child(privacy_panel)
	_privacy_label = Label.new()
	_privacy_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_privacy_label.theme_type_variation = "CaptionLabel"
	_privacy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	privacy_panel.add_child(_privacy_label)

	var actions: HBoxContainer = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 9)
	content.add_child(actions)

	_system_button = Button.new()
	NotLightL10n.bind_text(_system_button, "voice.permission.open_system_settings")
	NotLightL10n.bind_tooltip(_system_button, "voice.permission.open_system_settings_help")
	_system_button.theme_type_variation = "GhostButton"
	_system_button.custom_minimum_size = Vector2(188.0, 42.0)
	_system_button.pressed.connect(func() -> void: system_settings_requested.emit())
	actions.add_child(_system_button)

	var decline_button: Button = Button.new()
	NotLightL10n.bind_text(decline_button, "voice.permission.not_now")
	decline_button.theme_type_variation = "GhostButton"
	decline_button.custom_minimum_size = Vector2(104.0, 42.0)
	decline_button.pressed.connect(_decline)
	actions.add_child(decline_button)

	_allow_button = Button.new()
	NotLightL10n.bind_text(_allow_button, "voice.permission.allow")
	_allow_button.theme_type_variation = "PrimaryButton"
	_allow_button.custom_minimum_size = Vector2(160.0, 42.0)
	_allow_button.pressed.connect(_allow)
	actions.add_child(_allow_button)


func _allow() -> void:
	hide()
	allow_requested.emit()


func _decline() -> void:
	hide()
	decline_requested.emit()
