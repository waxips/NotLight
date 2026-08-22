# SPDX-License-Identifier: GPL-3.0-or-later
class_name PdfContextToolbar
extends PanelContainer

signal previous_page_requested
signal next_page_requested
signal page_requested(page_index: int)
signal rename_requested
signal duplicate_requested
signal delete_requested

const VIEWPORT_MARGIN: float = 12.0
const GAP: float = 10.0

var _name_label: Label
var _page_spin: SpinBox
var _page_count_label: Label
var _previous_button: Button
var _next_button: Button
var _anchor_rect: Rect2 = Rect2()
var _viewport_size: Vector2 = Vector2.ZERO
var _anchor_should_show: bool = false
var _updating_page: bool = false


func _ready() -> void:
	theme_type_variation = "FloatingPanel"
	visible = false
	z_index = 225
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func configure(display_name: String, available: bool, page_index: int, page_count: int) -> void:
	if _name_label == null:
		return
	var safe_count: int = maxi(1, page_count)
	var safe_page: int = clampi(page_index, 0, safe_count - 1)
	_name_label.text = display_name if not display_name.is_empty() else NotLightL10n.text("library.kind.pdf")
	_name_label.tooltip_text = _name_label.text if available else NotLightL10n.text("pdf.error.source_unavailable")
	_name_label.add_theme_color_override("font_color", NotLightTheme.semantic_color("text") if available else NotLightTheme.semantic_color("danger"))
	_updating_page = true
	_page_spin.min_value = 1.0
	_page_spin.max_value = float(safe_count)
	_page_spin.value = float(safe_page + 1)
	_page_count_label.text = NotLightL10n.text("ui.format.pdf_page_count") % safe_count
	_updating_page = false
	_previous_button.disabled = not available or safe_page <= 0
	_next_button.disabled = not available or safe_page >= safe_count - 1


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
	NotLightL10n.bind_text(type_label, "library.kind.pdf")
	NotLightL10n.bind_tooltip(type_label, "library.kind.pdf")
	type_label.theme_type_variation = "CaptionStrongLabel"
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	type_label.custom_minimum_size = Vector2(42.0, 36.0)
	type_label.add_theme_color_override("font_color", NotLightTheme.semantic_color("accent"))
	row.add_child(type_label)
	row.add_child(VSeparator.new())
	_name_label = Label.new()
	NotLightL10n.bind_text(_name_label, "library.kind.pdf")
	_name_label.theme_type_variation = "CaptionStrongLabel"
	_name_label.custom_minimum_size = Vector2(132.0, 36.0)
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_name_label)
	_previous_button = Button.new()
	_previous_button.text = "‹"
	NotLightL10n.bind_tooltip(_previous_button, "pdf.toolbar.previous")
	_previous_button.theme_type_variation = "GhostButton"
	_previous_button.custom_minimum_size = Vector2(36.0, 36.0)
	_previous_button.pressed.connect(func() -> void: previous_page_requested.emit())
	row.add_child(_previous_button)
	_page_spin = SpinBox.new()
	_page_spin.custom_minimum_size = Vector2(72.0, 36.0)
	_page_spin.step = 1.0
	_page_spin.rounded = true
	_page_spin.value_changed.connect(_on_page_value_changed)
	row.add_child(_page_spin)
	_page_count_label = Label.new()
	_page_count_label.text = NotLightL10n.text("ui.format.page_count_suffix") % 1
	_page_count_label.theme_type_variation = "CaptionLabel"
	_page_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_page_count_label.custom_minimum_size = Vector2(48.0, 36.0)
	row.add_child(_page_count_label)
	_next_button = Button.new()
	_next_button.text = "›"
	NotLightL10n.bind_tooltip(_next_button, "pdf.toolbar.next")
	_next_button.theme_type_variation = "GhostButton"
	_next_button.custom_minimum_size = Vector2(36.0, 36.0)
	_next_button.pressed.connect(func() -> void: next_page_requested.emit())
	row.add_child(_next_button)
	var rename_button: Button = Button.new()
	NotLightL10n.bind_text(rename_button, "common.rename")
	rename_button.theme_type_variation = "GhostButton"
	rename_button.custom_minimum_size = Vector2(122.0, 36.0)
	rename_button.pressed.connect(func() -> void: rename_requested.emit())
	row.add_child(rename_button)
	var duplicate_button: Button = Button.new()
	NotLightL10n.bind_text(duplicate_button, "audio.toolbar.duplicate")
	duplicate_button.theme_type_variation = "GhostButton"
	duplicate_button.custom_minimum_size = Vector2(92.0, 36.0)
	duplicate_button.pressed.connect(func() -> void: duplicate_requested.emit())
	row.add_child(duplicate_button)
	var delete_button: Button = Button.new()
	delete_button.icon = load("res://assets/icons/trash.svg") as Texture2D
	NotLightL10n.bind_tooltip(delete_button, "pdf.toolbar.delete")
	delete_button.theme_type_variation = "GhostDangerButton"
	delete_button.custom_minimum_size = Vector2(40.0, 36.0)
	delete_button.pressed.connect(func() -> void: delete_requested.emit())
	row.add_child(delete_button)


func _on_page_value_changed(value: float) -> void:
	if _updating_page:
		return
	page_requested.emit(maxi(0, int(round(value)) - 1))


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
