# SPDX-License-Identifier: GPL-3.0-or-later
class_name AssetFolderPickerDialog
extends Control

signal submitted(folder_id: String)

var _panel: PanelContainer
var _option: OptionButton
var _folder_ids: Array[String] = []


func _init() -> void:
	visible = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_as_relative = false
	z_index = 1100
	_build_ui()
	visible = false


func open_dialog(folders: Array[Dictionary], current_folder_id: String) -> void:
	_folder_ids.clear()
	_option.clear()
	_option.add_item(NotLightL10n.text("library.no_folder"))
	_folder_ids.append("")
	var selected_index: int = 0
	for folder: Dictionary in folders:
		var folder_id: String = str(folder.get("id", ""))
		if folder_id.is_empty():
			continue
		_option.add_item(str(folder.get("display_path", folder.get("name", NotLightL10n.text("notes.folder.unnamed")))))
		_folder_ids.append(folder_id)
		if folder_id == current_folder_id:
			selected_index = _folder_ids.size() - 1
	_option.select(selected_index)
	visible = true
	_option.grab_focus()


func close_dialog() -> void:
	visible = false


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or event is not InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
		close_dialog()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var scrim: ColorRect = ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.055, 0.075, 0.062, 0.42)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(_on_scrim_input)
	add_child(scrim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	_panel.theme_type_variation = "SettingsModalPanel"
	_panel.custom_minimum_size = Vector2(430.0, 220.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_panel)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	_panel.add_child(root)
	var title: Label = Label.new()
	NotLightL10n.bind_text(title, "runtime.ui.asset_folder_picker_dialog.d464c6750e")
	title.theme_type_variation = "TitleLabel"
	root.add_child(title)
	var description: Label = Label.new()
	NotLightL10n.bind_text(description, "runtime.ui.asset_folder_picker_dialog.43576de7f9")
	description.theme_type_variation = "BodyMutedLabel"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(description)
	_option = OptionButton.new()
	_option.theme_type_variation = "SettingsOptionButton"
	_option.custom_minimum_size = Vector2(0.0, 44.0)
	root.add_child(_option)
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 8)
	root.add_child(actions)
	var cancel: Button = Button.new()
	NotLightL10n.bind_text(cancel, "common.cancel")
	cancel.theme_type_variation = "GhostButton"
	cancel.pressed.connect(close_dialog)
	actions.add_child(cancel)
	var apply: Button = Button.new()
	NotLightL10n.bind_text(apply, "library.bulk.move")
	apply.theme_type_variation = "PrimaryButton"
	apply.pressed.connect(_submit)
	actions.add_child(apply)


func _submit() -> void:
	var index: int = _option.selected
	if index < 0 or index >= _folder_ids.size():
		return
	var folder_id: String = _folder_ids[index]
	visible = false
	submitted.emit(folder_id)


func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			close_dialog()
