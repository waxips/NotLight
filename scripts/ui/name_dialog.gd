# SPDX-License-Identifier: GPL-3.0-or-later
class_name NameDialog
extends Window

signal submitted(value: String)

const DEFAULT_DIALOG_SIZE: Vector2i = Vector2i(580, 390)
const MIN_DIALOG_SIZE: Vector2i = Vector2i(420, 300)
const PARENT_SIZE_RATIO: float = 0.94

var _heading: Label
var _helper: Label
var _edit: LineEdit
var _confirm_button: Button
var _allow_empty_submission: bool = false


func _init() -> void:
	visible = false


func _ready() -> void:
	# Wrapped localized helper text must never push the action row outside the
	# window. The helper therefore owns the flexible/scrollable part of the dialog
	# while the title, input and actions stay pinned and reachable.
	size = DEFAULT_DIALOG_SIZE
	min_size = MIN_DIALOG_SIZE
	max_size = Vector2i.ZERO
	unresizable = true
	borderless = true
	transient = true
	exclusive = true
	close_requested.connect(hide)
	_build_ui()


func open_dialog(
	dialog_title: String,
	helper_text: String,
	initial_value: String,
	action_text: String,
	allow_empty: bool = false
) -> void:
	title = dialog_title
	_heading.text = dialog_title
	_helper.text = helper_text
	_edit.text = initial_value
	_confirm_button.text = action_text
	_allow_empty_submission = allow_empty
	# Clamp against the parent window instead of relying on a fixed popup size.
	# On smaller displays the helper becomes scrollable instead of clipping the
	# Save/Cancel row below the viewport.
	popup_centered_clamped(DEFAULT_DIALOG_SIZE, PARENT_SIZE_RATIO)
	_edit.select_all()
	_edit.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.theme = NotLightTheme.create_theme()
	panel.theme_type_variation = "SettingsModalPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 13)
	panel.add_child(content)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	content.add_child(header)

	_heading = Label.new()
	_heading.theme_type_variation = "TitleLabel"
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(_heading)

	var close_button: Button = Button.new()
	close_button.text = "×"
	NotLightL10n.bind_tooltip(close_button, "common.cancel")
	close_button.theme_type_variation = "IconButton"
	close_button.custom_minimum_size = Vector2(40.0, 40.0)
	close_button.pressed.connect(hide)
	header.add_child(close_button)

	var helper_scroll: ScrollContainer = ScrollContainer.new()
	helper_scroll.custom_minimum_size = Vector2(0.0, 64.0)
	helper_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	helper_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	helper_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	helper_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	helper_scroll.follow_focus = true
	content.add_child(helper_scroll)

	var helper_margin: MarginContainer = MarginContainer.new()
	helper_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	helper_margin.add_theme_constant_override("margin_right", 6)
	helper_scroll.add_child(helper_margin)

	_helper = Label.new()
	_helper.theme_type_variation = "BodyMutedLabel"
	_helper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_helper.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	helper_margin.add_child(_helper)

	_edit = LineEdit.new()
	_edit.max_length = 120
	_edit.custom_minimum_size = Vector2(0.0, 48.0)
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.clear_button_enabled = true
	_edit.text_submitted.connect(func(_value: String) -> void: _submit())
	content.add_child(_edit)

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
	NotLightL10n.bind_text(_confirm_button, "common.save")
	_confirm_button.theme_type_variation = "PrimaryButton"
	_confirm_button.custom_minimum_size = Vector2(132.0, 42.0)
	_confirm_button.pressed.connect(_submit)
	actions.add_child(_confirm_button)


func _submit() -> void:
	var value: String = _edit.text.strip_edges()
	if value.is_empty() and not _allow_empty_submission:
		_edit.grab_focus()
		return
	hide()
	submitted.emit(value)
