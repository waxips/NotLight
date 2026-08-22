# SPDX-License-Identifier: GPL-3.0-or-later
class_name CreditsDialog
extends Control

var _title_label: Label
var _subtitle_label: Label
var _body_label: RichTextLabel
var _license_label: Label


func _init() -> void:
	visible = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_as_relative = false
	z_index = 1000
	_build_ui()
	NotLightL10n.connect_locale_changed(_on_locale_changed)
	_refresh_copy()
	visible = false


func open_dialog() -> void:
	_refresh_copy()
	visible = true


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
	scrim.color = Color(0.055, 0.075, 0.062, 0.48)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(_on_scrim_input)
	add_child(scrim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.theme_type_variation = "SettingsModalPanel"
	panel.custom_minimum_size = Vector2(650.0, 480.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)
	var mark: Label = Label.new()
	mark.text = "♡"
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.custom_minimum_size = Vector2(42.0, 42.0)
	mark.add_theme_font_size_override("font_size", 24)
	mark.add_theme_color_override("font_color", NotLightTheme.semantic_color("accent"))
	header.add_child(mark)
	var copy: VBoxContainer = VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(copy)
	_title_label = Label.new()
	_title_label.theme_type_variation = "TitleLabel"
	copy.add_child(_title_label)
	_subtitle_label = Label.new()
	_subtitle_label.theme_type_variation = "BodyMutedLabel"
	copy.add_child(_subtitle_label)
	var close_button: Button = Button.new()
	close_button.text = "×"
	close_button.theme_type_variation = "IconButton"
	close_button.custom_minimum_size = Vector2(42.0, 42.0)
	close_button.pressed.connect(close_dialog)
	header.add_child(close_button)
	root.add_child(HSeparator.new())
	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = true
	_body_label.fit_content = false
	_body_label.scroll_active = true
	_body_label.selection_enabled = true
	_body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_label.custom_minimum_size = Vector2(0.0, 300.0)
	root.add_child(_body_label)
	_license_label = Label.new()
	_license_label.theme_type_variation = "CaptionLabel"
	_license_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_license_label)


func _refresh_copy() -> void:
	if _title_label == null:
		return
	NotLightL10n.bind_text(_title_label, "credits.title")
	NotLightL10n.bind_text(_subtitle_label, "credits.subtitle")
	NotLightL10n.bind_text(_body_label, "credits.body")
	NotLightL10n.bind_text(_license_label, "credits.license_note")


func _on_locale_changed(_locale: String) -> void:
	_refresh_copy()


func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		close_dialog()
