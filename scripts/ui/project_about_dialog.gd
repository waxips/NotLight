# SPDX-License-Identifier: GPL-3.0-or-later
class_name ProjectAboutDialog
extends Control

var _title_label: Label
var _subtitle_label: Label
var _body_label: RichTextLabel
var _footer_label: Label


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
	panel.custom_minimum_size = Vector2(700.0, 520.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)

	var mark_panel: PanelContainer = PanelContainer.new()
	mark_panel.theme_type_variation = "SaveStatusDot"
	mark_panel.custom_minimum_size = Vector2(44.0, 44.0)
	header.add_child(mark_panel)
	var mark: TextureRect = TextureRect.new()
	mark.texture = load("res://assets/brand/notlight_internal_triad.svg") as Texture2D
	mark.custom_minimum_size = Vector2(36.0, 36.0)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark_panel.add_child(mark)

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
	close_button.icon = load("res://assets/icons/close.svg") as Texture2D
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
	_body_label.meta_underlined = true
	_body_label.meta_clicked.connect(_on_body_meta_clicked)
	_body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_label.custom_minimum_size = Vector2(0.0, 330.0)
	root.add_child(_body_label)

	_footer_label = Label.new()
	_footer_label.theme_type_variation = "CaptionLabel"
	_footer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_footer_label)


func _refresh_copy() -> void:
	if _title_label == null:
		return
	NotLightL10n.bind_text(_title_label, "about.title")
	NotLightL10n.bind_text(_subtitle_label, "about.subtitle")
	_body_label.text = _linkify_web_urls(NotLightL10n.text("about.body"))
	NotLightL10n.bind_text(_footer_label, "about.footer")


func _linkify_web_urls(bbcode: String) -> String:
	# Localization copy stays easy to edit: plain HTTP(S) URLs are converted
	# to RichTextLabel URL tags at display time. If the copy later contains
	# hand-authored [url] markup, leave it untouched rather than nesting tags.
	if bbcode.contains("[url"):
		return bbcode
	var url_pattern: RegEx = RegEx.new()
	if url_pattern.compile("(https?://[^\\s\\[\\]<>]+)") != OK:
		return bbcode
	return url_pattern.sub(bbcode, "[url=$1]$1[/url]", true)


func _on_body_meta_clicked(meta: Variant) -> void:
	var target: String = str(meta).strip_edges()
	var lower: String = target.to_lower()
	if lower.begins_with("https://") or lower.begins_with("http://"):
		OS.shell_open(target)


func _on_locale_changed(_locale: String) -> void:
	_refresh_copy()


func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		close_dialog()
