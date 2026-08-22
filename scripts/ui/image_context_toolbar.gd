# SPDX-License-Identifier: GPL-3.0-or-later
class_name ImageContextToolbar
extends PanelContainer

signal rename_requested
signal duplicate_requested
signal delete_requested

const VIEWPORT_MARGIN: float = 12.0
const GAP: float = 10.0

var _name_label: Label
var _anchor_rect: Rect2 = Rect2()
var _viewport_size: Vector2 = Vector2.ZERO
var _anchor_should_show: bool = false


func _ready() -> void:
	theme_type_variation = "FloatingPanel"
	visible = false
	z_index = 225
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func configure(display_name: String, available: bool) -> void:
	if _name_label == null:
		return
	_name_label.text = display_name if not display_name.is_empty() else NotLightL10n.text("asset.kind.image")
	_name_label.tooltip_text = _name_label.text if available else NotLightL10n.text("runtime.ui.image_context_toolbar.efd0ede548")
	_name_label.add_theme_color_override(
		"font_color",
		NotLightTheme.semantic_color("text") if available else NotLightTheme.semantic_color("danger")
	)


func set_toolbar_anchor(screen_rect: Rect2, viewport_size: Vector2, should_show: bool) -> void:
	_anchor_rect = screen_rect
	_viewport_size = viewport_size
	_anchor_should_show = should_show
	_apply_visibility()


func _build_ui() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	add_child(row)

	var type_label: Label = Label.new()
	type_label.text = "▧"
	NotLightL10n.bind_tooltip(type_label, "asset.kind.image")
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	type_label.custom_minimum_size = Vector2(34.0, 36.0)
	type_label.add_theme_font_size_override("font_size", 18)
	row.add_child(type_label)

	var separator: VSeparator = VSeparator.new()
	row.add_child(separator)

	_name_label = Label.new()
	NotLightL10n.bind_text(_name_label, "asset.kind.image")
	_name_label.theme_type_variation = "CaptionStrongLabel"
	_name_label.custom_minimum_size = Vector2(150.0, 36.0)
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_name_label)

	var rename_button: Button = Button.new()
	NotLightL10n.bind_text(rename_button, "common.rename")
	NotLightL10n.bind_tooltip(rename_button, "audio.toolbar.rename_help")
	rename_button.theme_type_variation = "GhostButton"
	rename_button.custom_minimum_size = Vector2(126.0, 36.0)
	rename_button.pressed.connect(func() -> void: rename_requested.emit())
	row.add_child(rename_button)

	var duplicate_button: Button = Button.new()
	NotLightL10n.bind_text(duplicate_button, "audio.toolbar.duplicate")
	NotLightL10n.bind_tooltip(duplicate_button, "runtime.ui.image_context_toolbar.c22dcdef2d")
	duplicate_button.theme_type_variation = "GhostButton"
	duplicate_button.custom_minimum_size = Vector2(96.0, 36.0)
	duplicate_button.pressed.connect(func() -> void: duplicate_requested.emit())
	row.add_child(duplicate_button)

	var delete_button: Button = Button.new()
	delete_button.icon = load("res://assets/icons/trash.svg") as Texture2D
	NotLightL10n.bind_tooltip(delete_button, "audio.toolbar.delete_help")
	delete_button.theme_type_variation = "GhostDangerButton"
	delete_button.custom_minimum_size = Vector2(40.0, 36.0)
	delete_button.pressed.connect(func() -> void: delete_requested.emit())
	row.add_child(delete_button)


func _apply_visibility() -> void:
	visible = _anchor_should_show
	if not visible:
		return
	var wanted_size: Vector2 = get_combined_minimum_size()
	var x: float = _anchor_rect.get_center().x - wanted_size.x * 0.5
	var y: float = _anchor_rect.position.y - wanted_size.y - GAP
	if y < VIEWPORT_MARGIN:
		y = _anchor_rect.end.y + GAP
	x = clampf(x, VIEWPORT_MARGIN, maxf(VIEWPORT_MARGIN, _viewport_size.x - wanted_size.x - VIEWPORT_MARGIN))
	y = clampf(y, VIEWPORT_MARGIN, maxf(VIEWPORT_MARGIN, _viewport_size.y - wanted_size.y - VIEWPORT_MARGIN))
	position = Vector2(x, y)
	size = wanted_size
