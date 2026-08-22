# SPDX-License-Identifier: GPL-3.0-or-later
class_name ConfirmActionDialog
extends Window

signal confirmed

const DEFAULT_DIALOG_SIZE: Vector2i = Vector2i(520, 310)
const MIN_DIALOG_SIZE: Vector2i = Vector2i(380, 240)
const PARENT_SIZE_RATIO: float = 0.94

var _heading: Label
var _message: Label
var _confirm_button: Button


func _init() -> void:
	# Window.visible defaults to true; keep transient dialogs hidden before they
	# enter the tree so no empty native/embedded frame is rendered on startup.
	visible = false


func _ready() -> void:
	size = DEFAULT_DIALOG_SIZE
	min_size = MIN_DIALOG_SIZE
	max_size = Vector2i.ZERO
	unresizable = true
	borderless = true
	transient = true
	exclusive = true
	close_requested.connect(hide)
	_build_ui()


func open_dialog(dialog_title: String, message: String, action_text: String, dangerous: bool = false) -> void:
	title = dialog_title
	_heading.text = dialog_title
	_message.text = message
	_confirm_button.text = action_text
	_confirm_button.theme_type_variation = "DangerButton" if dangerous else "PrimaryButton"
	popup_centered_clamped(DEFAULT_DIALOG_SIZE, PARENT_SIZE_RATIO)


func _build_ui() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.theme = NotLightTheme.create_theme()
	panel.theme_type_variation = "CardPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	_heading = Label.new()
	_heading.theme_type_variation = "TitleLabel"
	_heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(_heading)

	var message_scroll: ScrollContainer = ScrollContainer.new()
	message_scroll.custom_minimum_size = Vector2(0.0, 92.0)
	message_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	message_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	message_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content.add_child(message_scroll)

	var message_margin: MarginContainer = MarginContainer.new()
	message_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_margin.add_theme_constant_override("margin_right", 6)
	message_scroll.add_child(message_margin)

	_message = Label.new()
	_message.theme_type_variation = "BodyMutedLabel"
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_margin.add_child(_message)

	var actions: HBoxContainer = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 9)
	content.add_child(actions)

	var cancel_button: Button = Button.new()
	NotLightL10n.bind_text(cancel_button, "common.cancel")
	cancel_button.theme_type_variation = "GhostButton"
	cancel_button.custom_minimum_size = Vector2(108.0, 42.0)
	cancel_button.pressed.connect(hide)
	actions.add_child(cancel_button)

	_confirm_button = Button.new()
	_confirm_button.custom_minimum_size = Vector2(126.0, 42.0)
	_confirm_button.pressed.connect(func() -> void:
		hide()
		confirmed.emit()
	)
	actions.add_child(_confirm_button)
