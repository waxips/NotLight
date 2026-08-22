# SPDX-License-Identifier: GPL-3.0-or-later
class_name NotLightTheme
extends RefCounted

const COLOR_CANVAS: Color = Color("#f8f6ec")
const COLOR_SURFACE: Color = Color("#fffef8")
const COLOR_SURFACE_ALT: Color = Color("#f1f0e6")
const COLOR_TEXT: Color = Color("#202a24")
const COLOR_TEXT_MUTED: Color = Color("#687269")
const COLOR_PRIMARY: Color = Color("#237f52")
const COLOR_PRIMARY_HOVER: Color = Color("#1d6f47")
const COLOR_PRIMARY_SOFT: Color = Color("#dff1e5")
const COLOR_BORDER: Color = Color("#d9dcd2")
const COLOR_BORDER_STRONG: Color = Color("#bdc4ba")
const COLOR_DANGER: Color = Color("#b84a45")
const COLOR_DANGER_SOFT: Color = Color("#f7e5e2")
const COLOR_WARNING: Color = Color("#946018")
const COLOR_WARNING_SOFT: Color = Color("#f7edda")
const COLOR_SHADOW: Color = Color(0.12, 0.17, 0.14, 0.12)
const COLOR_DISABLED_TEXT: Color = Color("#929a93")
const SLIDER_GRABBER: Texture2D = preload("res://assets/icons/slider_grabber.svg")
const SLIDER_GRABBER_HOVER: Texture2D = preload("res://assets/icons/slider_grabber_hover.svg")


static var _active_palette: Dictionary = NotLightPalette.default_palette()


static func semantic_color(key: String) -> Color:
	return NotLightPalette.color(_active_palette, key, COLOR_TEXT)


static func create_theme(palette: Dictionary = {}) -> Theme:
	_active_palette = NotLightPalette.sanitize_custom(palette) if not palette.is_empty() else NotLightPalette.default_palette()
	var result: Theme = Theme.new()
	result.default_font_size = 15
	_configure_labels(result)
	_configure_buttons(result)
	_configure_panels(result)
	_configure_inputs(result)
	_configure_ranges(result)
	_configure_scrollbars(result)
	_configure_dialogs(result)
	_configure_tooltips(result)
	return result


static func _configure_labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", semantic_color("text"))
	theme.set_color("font_shadow_color", "Label", Color.TRANSPARENT)
	theme.set_font_size("font_size", "Label", 15)

	# Plain RichTextLabel is used by About/Credits dialogs. Give it the same
	# semantic foreground as normal labels so body text stays readable on the
	# light settings/modal surface.
	theme.set_color("default_color", "RichTextLabel", semantic_color("text"))
	theme.set_color("font_selected_color", "RichTextLabel", semantic_color("text"))
	theme.set_color("selection_color", "RichTextLabel", Color(semantic_color("accent"), 0.22))

	_add_variation(theme, &"DisplayLabel", &"Label")
	theme.set_font_size("font_size", "DisplayLabel", 34)
	theme.set_color("font_color", "DisplayLabel", semantic_color("text"))

	_add_variation(theme, &"TitleLabel", &"Label")
	theme.set_font_size("font_size", "TitleLabel", 22)
	theme.set_color("font_color", "TitleLabel", semantic_color("text"))

	_add_variation(theme, &"SectionLabel", &"Label")
	theme.set_font_size("font_size", "SectionLabel", 18)
	theme.set_color("font_color", "SectionLabel", semantic_color("text"))

	_add_variation(theme, &"BodyMutedLabel", &"Label")
	theme.set_font_size("font_size", "BodyMutedLabel", 14)
	theme.set_color("font_color", "BodyMutedLabel", semantic_color("text_muted"))

	_add_variation(theme, &"CaptionLabel", &"Label")
	theme.set_font_size("font_size", "CaptionLabel", 12)
	theme.set_color("font_color", "CaptionLabel", semantic_color("text_muted"))

	_add_variation(theme, &"CaptionStrongLabel", &"Label")
	theme.set_font_size("font_size", "CaptionStrongLabel", 12)
	theme.set_color("font_color", "CaptionStrongLabel", semantic_color("text"))

	_add_variation(theme, &"OnPrimaryLabel", &"Label")
	theme.set_color("font_color", "OnPrimaryLabel", semantic_color("text_on_accent"))

	_add_variation(theme, &"EyebrowLabel", &"Label")
	theme.set_font_size("font_size", "EyebrowLabel", 11)
	theme.set_color("font_color", "EyebrowLabel", semantic_color("text_muted"))
	theme.set_constant("outline_size", "EyebrowLabel", 0)


	_add_variation(theme, &"VideoOverlayLabel", &"Label")
	theme.set_font_size("font_size", "VideoOverlayLabel", 12)
	theme.set_color("font_color", "VideoOverlayLabel", Color("#f8fbf8"))

	_add_variation(theme, &"VideoOverlayMutedLabel", &"Label")
	theme.set_font_size("font_size", "VideoOverlayMutedLabel", 11)
	theme.set_color("font_color", "VideoOverlayMutedLabel", Color("#cbd6ce"))

	_add_variation(theme, &"AssetKindLabel", &"Label")
	theme.set_font_size("font_size", "AssetKindLabel", 17)
	theme.set_color("font_color", "AssetKindLabel", semantic_color("accent"))

	_add_variation(theme, &"SettingsSectionTitleLabel", &"Label")
	theme.set_font_size("font_size", "SettingsSectionTitleLabel", 16)
	theme.set_color("font_color", "SettingsSectionTitleLabel", semantic_color("text"))

	_add_variation(theme, &"SettingsRowTitleLabel", &"Label")
	theme.set_font_size("font_size", "SettingsRowTitleLabel", 14)
	theme.set_color("font_color", "SettingsRowTitleLabel", semantic_color("text"))

	_add_variation(theme, &"SettingsValueLabel", &"Label")
	theme.set_font_size("font_size", "SettingsValueLabel", 12)
	theme.set_color("font_color", "SettingsValueLabel", semantic_color("accent"))
	var value_pill: StyleBoxFlat = _box(semantic_color("accent_soft"), semantic_color("border_strong"), 1, 99, 99, 99, 99)
	value_pill.content_margin_left = 10.0
	value_pill.content_margin_right = 10.0
	value_pill.content_margin_top = 4.0
	value_pill.content_margin_bottom = 4.0
	theme.set_stylebox("normal", "SettingsValueLabel", value_pill)


static func _configure_buttons(theme: Theme) -> void:
	var normal: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border"), 1, 12, 12, 12, 12)
	var hover: StyleBoxFlat = _box(_surface_hover(), semantic_color("border_strong"), 1, 12, 12, 12, 12)
	var pressed: StyleBoxFlat = _box(_surface_pressed(), semantic_color("accent"), 1, 12, 12, 12, 12)
	var focus: StyleBoxFlat = _box(Color.TRANSPARENT, semantic_color("accent"), 2, 12, 12, 12, 12)
	var disabled: StyleBoxFlat = _box(semantic_color("surface_alt"), semantic_color("border"), 1, 12, 12, 12, 12)

	_set_button_styles(theme, &"Button", normal, hover, pressed, focus, disabled)
	_set_button_colors(theme, &"Button", semantic_color("text"), semantic_color("text"), semantic_color("accent"), semantic_color("text"), semantic_color("disabled_text"))
	theme.set_font_size("font_size", "Button", 14)
	theme.set_constant("outline_size", "Button", 0)
	theme.set_constant("h_separation", "Button", 8)

	_add_variation(theme, &"PrimaryButton", &"Button")
	_set_button_styles(
		theme,
		&"PrimaryButton",
		_box(semantic_color("accent"), semantic_color("accent"), 1, 13, 13, 13, 13),
		_box(semantic_color("accent_hover"), semantic_color("accent_hover"), 1, 13, 13, 13, 13),
		_box(_accent_pressed(), _accent_pressed(), 1, 13, 13, 13, 13),
		_box(Color.TRANSPARENT, semantic_color("accent_soft"), 3, 13, 13, 13, 13),
		disabled
	)
	_set_button_colors(theme, &"PrimaryButton", semantic_color("text_on_accent"), semantic_color("text_on_accent"), semantic_color("text_on_accent"), semantic_color("text_on_accent"), semantic_color("disabled_text"))
	theme.set_font_size("font_size", "PrimaryButton", 15)

	_add_variation(theme, &"GhostButton", &"Button")
	_set_button_styles(
		theme,
		&"GhostButton",
		_box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 10, 10, 10, 10),
		_box(_surface_hover(), Color.TRANSPARENT, 0, 10, 10, 10, 10),
		_box(_surface_pressed(), Color.TRANSPARENT, 0, 10, 10, 10, 10),
		focus,
		disabled
	)
	_set_button_colors(theme, &"GhostButton", semantic_color("text"), semantic_color("text"), semantic_color("accent"), semantic_color("text"), semantic_color("disabled_text"))

	_add_variation(theme, &"DangerButton", &"Button")
	_set_button_styles(
		theme,
		&"DangerButton",
		_box(semantic_color("danger_soft"), Color("#e8c7c2"), 1, 12, 12, 12, 12),
		_box(Color("#f2d7d3"), Color("#dca9a2"), 1, 12, 12, 12, 12),
		_box(Color("#ebc6c1"), Color("#d1948c"), 1, 12, 12, 12, 12),
		focus,
		disabled
	)
	_set_button_colors(theme, &"DangerButton", semantic_color("danger"), Color("#933832"), Color("#7f2e29"), semantic_color("danger"), semantic_color("disabled_text"))

	_add_variation(theme, &"IconButton", &"Button")
	_set_button_styles(
		theme,
		&"IconButton",
		_box(semantic_color("surface"), semantic_color("border"), 1, 11, 11, 11, 11),
		_box(_surface_hover(), semantic_color("border_strong"), 1, 11, 11, 11, 11),
		_box(semantic_color("accent_soft"), semantic_color("accent"), 1, 11, 11, 11, 11),
		focus,
		disabled
	)
	_set_button_colors(theme, &"IconButton", semantic_color("text"), semantic_color("text"), semantic_color("accent"), semantic_color("text"), semantic_color("disabled_text"))
	theme.set_color("icon_normal_color", "IconButton", semantic_color("text"))
	theme.set_color("icon_hover_color", "IconButton", semantic_color("accent"))
	theme.set_color("icon_pressed_color", "IconButton", semantic_color("accent"))
	theme.set_color("icon_disabled_color", "IconButton", semantic_color("disabled_text"))
	theme.set_font_size("font_size", "IconButton", 18)

	# Text-only compact icon used by the PDF rail action. Keeping this separate
	# from IconButton prevents three glyphs plus the standard 24 px horizontal
	# content margins from increasing the minimum width of the entire tool rail.
	_add_variation(theme, &"CompactRailTextButton", &"Button")
	var compact_rail_normal: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border"), 1, 11, 11, 11, 11)
	var compact_rail_hover: StyleBoxFlat = _box(_surface_hover(), semantic_color("border_strong"), 1, 11, 11, 11, 11)
	var compact_rail_pressed: StyleBoxFlat = _box(semantic_color("accent_soft"), semantic_color("accent"), 1, 11, 11, 11, 11)
	var compact_rail_boxes: Array[StyleBoxFlat] = [compact_rail_normal, compact_rail_hover, compact_rail_pressed]
	for compact_box: StyleBoxFlat in compact_rail_boxes:
		compact_box.content_margin_left = 5.0
		compact_box.content_margin_right = 5.0
		compact_box.content_margin_top = 7.0
		compact_box.content_margin_bottom = 7.0
	_set_button_styles(theme, &"CompactRailTextButton", compact_rail_normal, compact_rail_hover, compact_rail_pressed, focus, disabled)
	_set_button_colors(theme, &"CompactRailTextButton", semantic_color("text"), semantic_color("text"), semantic_color("accent"), semantic_color("text"), semantic_color("disabled_text"))
	theme.set_font_size("font_size", "CompactRailTextButton", 13)

	_add_variation(theme, &"DangerIconButton", &"Button")
	_set_button_styles(
		theme,
		&"DangerIconButton",
		_box(semantic_color("surface"), semantic_color("border"), 1, 11, 11, 11, 11),
		_box(semantic_color("danger_soft"), Color("#e8c7c2"), 1, 11, 11, 11, 11),
		_box(Color("#f0d0cc"), Color("#dba8a1"), 1, 11, 11, 11, 11),
		focus,
		disabled
	)
	_set_button_colors(theme, &"DangerIconButton", semantic_color("danger"), Color("#933832"), Color("#7f2e29"), semantic_color("danger"), semantic_color("disabled_text"))
	theme.set_color("icon_normal_color", "DangerIconButton", semantic_color("danger"))
	theme.set_color("icon_hover_color", "DangerIconButton", Color("#933832"))
	theme.set_color("icon_pressed_color", "DangerIconButton", Color("#7f2e29"))
	theme.set_color("icon_disabled_color", "DangerIconButton", Color("#b8aaa8"))
	theme.set_font_size("font_size", "DangerIconButton", 18)

	_add_variation(theme, &"ToolButton", &"Button")
	_set_button_styles(
		theme,
		&"ToolButton",
		_box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 11, 11, 11, 11),
		_box(_surface_hover(), Color.TRANSPARENT, 0, 11, 11, 11, 11),
		_box(semantic_color("accent_soft"), semantic_color("accent"), 1, 11, 11, 11, 11),
		focus,
		disabled
	)
	_set_button_colors(theme, &"ToolButton", semantic_color("text"), semantic_color("accent"), semantic_color("accent"), semantic_color("text"), semantic_color("disabled_text"))
	theme.set_color("icon_normal_color", "ToolButton", semantic_color("text"))
	theme.set_color("icon_hover_color", "ToolButton", semantic_color("accent"))
	theme.set_color("icon_pressed_color", "ToolButton", semantic_color("accent"))
	theme.set_color("icon_disabled_color", "ToolButton", semantic_color("disabled_text"))
	theme.set_font_size("font_size", "ToolButton", 18)

	_add_variation(theme, &"VideoOverlayButton", &"Button")
	_set_button_styles(
		theme,
		&"VideoOverlayButton",
		_box(Color(0.10, 0.14, 0.12, 0.78), Color(0.76, 0.82, 0.78, 0.20), 1, 8, 8, 8, 8),
		_box(Color(0.20, 0.30, 0.24, 0.96), Color("#8fc7a6"), 1, 8, 8, 8, 8),
		_box(Color("#237f52"), Color("#a8dfbd"), 1, 8, 8, 8, 8),
		_box(Color.TRANSPARENT, Color("#b9e7ca"), 2, 8, 8, 8, 8),
		disabled
	)
	_set_button_colors(theme, &"VideoOverlayButton", Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color("#98a39b"))
	theme.set_font_size("font_size", "VideoOverlayButton", 13)

	_add_variation(theme, &"VideoOverlayPrimaryButton", &"Button")
	_set_button_styles(
		theme,
		&"VideoOverlayPrimaryButton",
		_box(semantic_color("accent"), semantic_color("accent"), 1, 8, 8, 8, 8),
		_box(Color("#2b9664"), Color("#9cdbb5"), 1, 8, 8, 8, 8),
		_box(Color("#175f3c"), Color("#9cdbb5"), 1, 8, 8, 8, 8),
		_box(Color.TRANSPARENT, Color("#b9e7ca"), 2, 8, 8, 8, 8),
		disabled
	)
	_set_button_colors(theme, &"VideoOverlayPrimaryButton", Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color("#98a39b"))

	_add_variation(theme, &"SettingsNavButton", &"Button")
	_set_button_styles(
		theme,
		&"SettingsNavButton",
		_box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 11, 11, 11, 11),
		_box(_surface_hover(), Color.TRANSPARENT, 0, 11, 11, 11, 11),
		_box(semantic_color("accent_soft"), Color("#bddac7"), 1, 11, 11, 11, 11),
		_box(Color.TRANSPARENT, Color("#86bd99"), 2, 11, 11, 11, 11),
		disabled
	)
	_set_button_colors(theme, &"SettingsNavButton", semantic_color("text_muted"), semantic_color("text"), semantic_color("accent"), semantic_color("text"), semantic_color("disabled_text"))
	theme.set_font_size("font_size", "SettingsNavButton", 14)

	for type_name: StringName in [&"OptionButton", &"CheckButton", &"CheckBox"]:
		theme.set_color("font_color", type_name, semantic_color("text"))
		theme.set_color("font_hover_color", type_name, semantic_color("text"))
		theme.set_color("font_pressed_color", type_name, semantic_color("text"))
		theme.set_color("font_focus_color", type_name, semantic_color("text"))
		theme.set_color("font_disabled_color", type_name, semantic_color("disabled_text"))

	_add_variation(theme, &"GhostDangerButton", &"Button")
	_set_button_styles(
		theme,
		&"GhostDangerButton",
		_box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 10, 10, 10, 10),
		_box(semantic_color("danger_soft"), Color.TRANSPARENT, 0, 10, 10, 10, 10),
		_box(Color("#f0d0cc"), Color.TRANSPARENT, 0, 10, 10, 10, 10),
		focus,
		disabled
	)
	_set_button_colors(theme, &"GhostDangerButton", semantic_color("danger"), Color("#933832"), Color("#7f2e29"), semantic_color("danger"), semantic_color("disabled_text"))

	_add_variation(theme, &"HubNavButton", &"Button")
	var hub_nav_normal: StyleBoxFlat = _box(semantic_color("surface"), Color(semantic_color("border"), 0.92), 1, 13, 13, 13, 13)
	hub_nav_normal.shadow_color = Color(0.07, 0.12, 0.08, 0.06)
	hub_nav_normal.shadow_size = 3
	hub_nav_normal.shadow_offset = Vector2(0.0, 1.0)
	var hub_nav_hover: StyleBoxFlat = _box(semantic_color("surface_alt"), Color(semantic_color("border_strong"), 0.95), 1, 13, 13, 13, 13)
	var hub_nav_pressed: StyleBoxFlat = _box(semantic_color("accent_soft"), Color(semantic_color("accent"), 0.62), 1, 13, 13, 13, 13)
	hub_nav_pressed.shadow_color = Color(0.05, 0.22, 0.12, 0.09)
	hub_nav_pressed.shadow_size = 4
	hub_nav_pressed.shadow_offset = Vector2(0.0, 1.0)
	_set_button_styles(
		theme,
		&"HubNavButton",
		hub_nav_normal,
		hub_nav_hover,
		hub_nav_pressed,
		focus,
		disabled
	)
	_set_button_colors(theme, &"HubNavButton", semantic_color("text_muted"), semantic_color("text"), semantic_color("accent"), semantic_color("text"), semantic_color("disabled_text"))
	theme.set_font_size("font_size", "HubNavButton", 14)

	_add_variation(theme, &"AssetFolderButton", &"Button")
	_set_button_styles(
		theme,
		&"AssetFolderButton",
		_box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 9, 9, 9, 9),
		_box(Color("#ecefe7"), Color.TRANSPARENT, 0, 9, 9, 9, 9),
		_box(semantic_color("accent_soft"), Color("#b9d9c4"), 1, 9, 9, 9, 9),
		focus,
		disabled
	)
	_set_button_colors(theme, &"AssetFolderButton", semantic_color("text"), semantic_color("text"), semantic_color("accent"), semantic_color("text"), semantic_color("disabled_text"))

	_add_variation(theme, &"TagButton", &"Button")
	_set_button_styles(
		theme,
		&"TagButton",
		_box(semantic_color("accent_soft"), Color.TRANSPARENT, 0, 99, 99, 99, 99),
		_box(semantic_color("accent_soft").lightened(0.05), semantic_color("accent"), 1, 99, 99, 99, 99),
		_box(semantic_color("accent_soft").darkened(0.03), semantic_color("accent"), 1, 99, 99, 99, 99),
		_box(Color.TRANSPARENT, semantic_color("accent"), 2, 99, 99, 99, 99),
		disabled
	)
	_set_button_colors(theme, &"TagButton", semantic_color("accent"), semantic_color("accent"), semantic_color("accent"), semantic_color("accent"), semantic_color("disabled_text"))
	theme.set_font_size("font_size", "TagButton", 13)


static func _configure_panels(theme: Theme) -> void:
	theme.set_stylebox("panel", "Panel", _box(semantic_color("surface"), semantic_color("border"), 1, 16, 16, 16, 16))
	theme.set_stylebox("panel", "PanelContainer", _box(semantic_color("surface"), semantic_color("border"), 1, 16, 16, 16, 16))

	_add_variation(theme, &"CardPanel", &"PanelContainer")
	var card: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border"), 1, 20, 20, 20, 20)
	card.shadow_color = COLOR_SHADOW
	card.shadow_size = 10
	card.shadow_offset = Vector2(0.0, 4.0)
	card.content_margin_left = 18.0
	card.content_margin_right = 18.0
	card.content_margin_top = 18.0
	card.content_margin_bottom = 18.0
	theme.set_stylebox("panel", "CardPanel", card)

	_add_variation(theme, &"FloatingPanel", &"PanelContainer")
	var floating: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border"), 1, 16, 16, 16, 16)
	floating.shadow_color = Color(0.08, 0.13, 0.10, 0.16)
	floating.shadow_size = 12
	floating.shadow_offset = Vector2(0.0, 5.0)
	floating.content_margin_left = 10.0
	floating.content_margin_right = 10.0
	floating.content_margin_top = 9.0
	floating.content_margin_bottom = 9.0
	theme.set_stylebox("panel", "FloatingPanel", floating)

	_add_variation(theme, &"LibraryDrawerPanel", &"PanelContainer")
	var library_drawer: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border"), 1, 22, 22, 22, 22)
	# A smaller centered shadow stays soft around all rounded corners and does
	# not get visibly guillotined by the viewport edge.
	library_drawer.shadow_color = Color(0.06, 0.11, 0.08, 0.10)
	library_drawer.shadow_size = 11
	library_drawer.shadow_offset = Vector2(0.0, 4.0)
	library_drawer.content_margin_left = 16.0
	library_drawer.content_margin_right = 16.0
	library_drawer.content_margin_top = 16.0
	library_drawer.content_margin_bottom = 16.0
	theme.set_stylebox("panel", "LibraryDrawerPanel", library_drawer)

	_add_variation(theme, &"DrawingPalettePanel", &"PanelContainer")
	var drawing_palette: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border_strong"), 1, 18, 18, 18, 18)
	drawing_palette.shadow_color = Color(0.06, 0.11, 0.08, 0.15)
	drawing_palette.shadow_size = 14
	drawing_palette.shadow_offset = Vector2(0.0, 5.0)
	drawing_palette.content_margin_left = 0.0
	drawing_palette.content_margin_right = 0.0
	drawing_palette.content_margin_top = 0.0
	drawing_palette.content_margin_bottom = 0.0
	theme.set_stylebox("panel", "DrawingPalettePanel", drawing_palette)

	_add_variation(theme, &"ContextToolbarPanel", &"PanelContainer")
	var context_toolbar: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border_strong"), 1, 13, 13, 13, 13)
	context_toolbar.shadow_color = Color(0.05, 0.10, 0.07, 0.14)
	context_toolbar.shadow_size = 10
	context_toolbar.shadow_offset = Vector2(0.0, 4.0)
	context_toolbar.content_margin_left = 8.0
	context_toolbar.content_margin_right = 8.0
	context_toolbar.content_margin_top = 7.0
	context_toolbar.content_margin_bottom = 7.0
	theme.set_stylebox("panel", "ContextToolbarPanel", context_toolbar)

	_add_variation(theme, &"AudioPlayerCardPanel", &"PanelContainer")
	var audio_card: StyleBoxFlat = _box(semantic_color("surface"), Color(semantic_color("accent"), 0.58), 2, 14, 14, 14, 14)
	audio_card.shadow_color = Color(0.04, 0.09, 0.06, 0.16)
	audio_card.shadow_size = 10
	audio_card.shadow_offset = Vector2(0.0, 4.0)
	audio_card.content_margin_left = 0.0
	audio_card.content_margin_right = 0.0
	audio_card.content_margin_top = 0.0
	audio_card.content_margin_bottom = 0.0
	theme.set_stylebox("panel", "AudioPlayerCardPanel", audio_card)

	_add_variation(theme, &"VideoPlayerCardPanel", &"PanelContainer")
	var video_card: StyleBoxFlat = _box(Color("#141a16"), Color(semantic_color("accent"), 0.72), 2, 12, 12, 12, 12)
	video_card.shadow_color = Color(0.02, 0.04, 0.03, 0.28)
	video_card.shadow_size = 10
	video_card.shadow_offset = Vector2(0.0, 4.0)
	video_card.content_margin_left = 0.0
	video_card.content_margin_right = 0.0
	video_card.content_margin_top = 0.0
	video_card.content_margin_bottom = 0.0
	theme.set_stylebox("panel", "VideoPlayerCardPanel", video_card)

	_add_variation(theme, &"VideoOverlayBar", &"PanelContainer")
	var video_bar: StyleBoxFlat = _box(Color(0.055, 0.075, 0.064, 0.90), Color(0.80, 0.87, 0.82, 0.18), 1, 9, 9, 9, 9)
	video_bar.content_margin_left = 7.0
	video_bar.content_margin_right = 7.0
	video_bar.content_margin_top = 4.0
	video_bar.content_margin_bottom = 4.0
	theme.set_stylebox("panel", "VideoOverlayBar", video_bar)

	_add_variation(theme, &"VideoExpandedPlayerPanel", &"PanelContainer")
	var expanded_video: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border_strong"), 1, 18, 18, 18, 18)
	expanded_video.shadow_color = Color(0.04, 0.08, 0.06, 0.24)
	expanded_video.shadow_size = 18
	expanded_video.shadow_offset = Vector2(0.0, 7.0)
	expanded_video.content_margin_left = 0.0
	expanded_video.content_margin_right = 0.0
	expanded_video.content_margin_top = 0.0
	expanded_video.content_margin_bottom = 0.0
	theme.set_stylebox("panel", "VideoExpandedPlayerPanel", expanded_video)

	_add_variation(theme, &"VideoViewportPanel", &"PanelContainer")
	var video_viewport: StyleBoxFlat = _box(Color("#101612"), Color("#52665a"), 1, 11, 11, 11, 11)
	video_viewport.content_margin_left = 0.0
	video_viewport.content_margin_right = 0.0
	video_viewport.content_margin_top = 0.0
	video_viewport.content_margin_bottom = 0.0
	theme.set_stylebox("panel", "VideoViewportPanel", video_viewport)

	_add_variation(theme, &"SoftPanel", &"PanelContainer")
	var soft: StyleBoxFlat = _box(semantic_color("surface_alt"), semantic_color("border"), 1, 14, 14, 14, 14)
	soft.content_margin_left = 14.0
	soft.content_margin_right = 14.0
	soft.content_margin_top = 12.0
	soft.content_margin_bottom = 12.0
	theme.set_stylebox("panel", "SoftPanel", soft)

	_add_variation(theme, &"SavePill", &"PanelContainer")
	var pill: StyleBoxFlat = _box(semantic_color("accent_soft"), semantic_color("border"), 1, 99, 99, 99, 99)
	pill.content_margin_left = 12.0
	pill.content_margin_right = 12.0
	pill.content_margin_top = 7.0
	pill.content_margin_bottom = 7.0
	theme.set_stylebox("panel", "SavePill", pill)

	_add_variation(theme, &"SettingsModalPanel", &"PanelContainer")
	var settings_modal: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border_strong"), 1, 26, 26, 26, 26)
	settings_modal.shadow_color = Color(0.03, 0.07, 0.05, 0.30)
	settings_modal.shadow_size = 28
	settings_modal.shadow_offset = Vector2(0.0, 10.0)
	settings_modal.content_margin_left = 26.0
	settings_modal.content_margin_right = 26.0
	settings_modal.content_margin_top = 24.0
	settings_modal.content_margin_bottom = 22.0
	theme.set_stylebox("panel", "SettingsModalPanel", settings_modal)

	_add_variation(theme, &"SettingsMarkPanel", &"PanelContainer")
	var settings_mark: StyleBoxFlat = _box(semantic_color("accent_soft"), Color("#bddcc8"), 1, 13, 13, 13, 13)
	settings_mark.content_margin_left = 0.0
	settings_mark.content_margin_right = 0.0
	settings_mark.content_margin_top = 0.0
	settings_mark.content_margin_bottom = 0.0
	theme.set_stylebox("panel", "SettingsMarkPanel", settings_mark)

	_add_variation(theme, &"SettingsNavPanel", &"PanelContainer")
	var settings_nav: StyleBoxFlat = _box(semantic_color("surface_alt"), semantic_color("border"), 1, 16, 16, 16, 16)
	settings_nav.content_margin_left = 12.0
	settings_nav.content_margin_right = 12.0
	settings_nav.content_margin_top = 14.0
	settings_nav.content_margin_bottom = 14.0
	theme.set_stylebox("panel", "SettingsNavPanel", settings_nav)

	_add_variation(theme, &"SettingsSectionPanel", &"PanelContainer")
	var settings_section: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border"), 1, 16, 16, 16, 16)
	settings_section.content_margin_left = 16.0
	settings_section.content_margin_right = 16.0
	settings_section.content_margin_top = 14.0
	settings_section.content_margin_bottom = 14.0
	theme.set_stylebox("panel", "SettingsSectionPanel", settings_section)

	_add_variation(theme, &"SettingsSliderPanel", &"PanelContainer")
	var settings_slider: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border"), 1, 12, 12, 12, 12)
	settings_slider.content_margin_left = 12.0
	settings_slider.content_margin_right = 12.0
	settings_slider.content_margin_top = 10.0
	settings_slider.content_margin_bottom = 10.0
	theme.set_stylebox("panel", "SettingsSliderPanel", settings_slider)

	_add_variation(theme, &"SettingsTogglePanel", &"PanelContainer")
	var settings_toggle: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border"), 1, 13, 13, 13, 13)
	settings_toggle.content_margin_left = 14.0
	settings_toggle.content_margin_right = 14.0
	settings_toggle.content_margin_top = 13.0
	settings_toggle.content_margin_bottom = 13.0
	theme.set_stylebox("panel", "SettingsTogglePanel", settings_toggle)

	_add_variation(theme, &"SettingsInfoPanel", &"PanelContainer")
	var settings_info: StyleBoxFlat = _box(semantic_color("accent_soft"), semantic_color("border"), 1, 13, 13, 13, 13)
	settings_info.content_margin_left = 14.0
	settings_info.content_margin_right = 14.0
	settings_info.content_margin_top = 12.0
	settings_info.content_margin_bottom = 12.0
	theme.set_stylebox("panel", "SettingsInfoPanel", settings_info)

	_add_variation(theme, &"HubNavPanel", &"PanelContainer")
	var hub_nav: StyleBoxFlat = _box(semantic_color("surface_alt"), semantic_color("border"), 1, 13, 13, 13, 13)
	hub_nav.content_margin_left = 4.0
	hub_nav.content_margin_right = 4.0
	hub_nav.content_margin_top = 4.0
	hub_nav.content_margin_bottom = 4.0
	theme.set_stylebox("panel", "HubNavPanel", hub_nav)

	_add_variation(theme, &"GridPreviewPanel", &"PanelContainer")
	var grid_preview: StyleBoxFlat = _box(semantic_color("board_background"), semantic_color("border"), 1, 12, 12, 12, 12)
	grid_preview.content_margin_left = 0.0
	grid_preview.content_margin_right = 0.0
	grid_preview.content_margin_top = 0.0
	grid_preview.content_margin_bottom = 0.0
	theme.set_stylebox("panel", "GridPreviewPanel", grid_preview)

	_add_variation(theme, &"AssetCardPanel", &"PanelContainer")
	var asset_card: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border"), 1, 16, 16, 16, 16)
	asset_card.shadow_color = Color(0.08, 0.12, 0.09, 0.08)
	asset_card.shadow_size = 7
	asset_card.shadow_offset = Vector2(0.0, 3.0)
	asset_card.content_margin_left = 13.0
	asset_card.content_margin_right = 13.0
	asset_card.content_margin_top = 13.0
	asset_card.content_margin_bottom = 13.0
	theme.set_stylebox("panel", "AssetCardPanel", asset_card)

	_add_variation(theme, &"AssetCardSelectedPanel", &"PanelContainer")
	var asset_card_selected: StyleBoxFlat = asset_card.duplicate() as StyleBoxFlat
	asset_card_selected.border_color = semantic_color("accent")
	asset_card_selected.set_border_width_all(2)
	asset_card_selected.shadow_color = Color(0.05, 0.22, 0.12, 0.14)
	theme.set_stylebox("panel", "AssetCardSelectedPanel", asset_card_selected)

	_add_variation(theme, &"AssetInspectorPanel", &"PanelContainer")
	var inspector: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border_strong"), 1, 16, 16, 16, 16)
	inspector.content_margin_left = 0.0
	inspector.content_margin_right = 0.0
	inspector.content_margin_top = 0.0
	inspector.content_margin_bottom = 0.0
	theme.set_stylebox("panel", "AssetInspectorPanel", inspector)

	_add_variation(theme, &"AssetPreviewPanel", &"PanelContainer")
	var asset_preview: StyleBoxFlat = _box(semantic_color("surface_alt"), semantic_color("border"), 1, 12, 12, 12, 12)
	theme.set_stylebox("panel", "AssetPreviewPanel", asset_preview)

	_add_variation(theme, &"AssetFolderPanel", &"PanelContainer")
	var asset_folder: StyleBoxFlat = _box(semantic_color("surface_alt"), semantic_color("border"), 1, 16, 16, 16, 16)
	asset_folder.content_margin_left = 12.0
	asset_folder.content_margin_right = 12.0
	asset_folder.content_margin_top = 12.0
	asset_folder.content_margin_bottom = 12.0
	theme.set_stylebox("panel", "AssetFolderPanel", asset_folder)

	_add_variation(theme, &"AssetImportPanel", &"PanelContainer")
	var asset_import: StyleBoxFlat = _box(semantic_color("accent_soft"), semantic_color("border"), 1, 12, 12, 12, 12)
	asset_import.content_margin_left = 12.0
	asset_import.content_margin_right = 12.0
	asset_import.content_margin_top = 9.0
	asset_import.content_margin_bottom = 9.0
	theme.set_stylebox("panel", "AssetImportPanel", asset_import)

	_add_variation(theme, &"SaveStatusDot", &"PanelContainer")
	var save_dot: StyleBoxFlat = _box(Color("#f3f5ed"), Color("#dce1d8"), 1, 99, 99, 99, 99)
	theme.set_stylebox("panel", "SaveStatusDot", save_dot)


	# Notes are a core surface, so preview/editor chrome is defined at Theme level
	# instead of carrying an foreign palette inside individual controls.
	_add_variation(theme, &"NoteWorkspacePanel", &"PanelContainer")
	var note_workspace: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border_strong"), 1, 24, 24, 24, 24)
	note_workspace.shadow_color = Color(0.03, 0.07, 0.05, 0.28)
	note_workspace.shadow_size = 24
	note_workspace.shadow_offset = Vector2(0.0, 8.0)
	note_workspace.content_margin_left = 0.0
	note_workspace.content_margin_right = 0.0
	note_workspace.content_margin_top = 0.0
	note_workspace.content_margin_bottom = 0.0
	theme.set_stylebox("panel", "NoteWorkspacePanel", note_workspace)

	_add_variation(theme, &"NotePreviewBlockPanel", &"PanelContainer")
	var note_block: StyleBoxFlat = _box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 9, 9, 9, 9)
	note_block.content_margin_left = 8.0
	note_block.content_margin_right = 8.0
	note_block.content_margin_top = 5.0
	note_block.content_margin_bottom = 5.0
	theme.set_stylebox("panel", "NotePreviewBlockPanel", note_block)

	_add_variation(theme, &"NoteQuotePanel", &"PanelContainer")
	var note_quote: StyleBoxFlat = _box(semantic_color("surface_alt"), semantic_color("accent"), 0, 7, 7, 7, 7)
	note_quote.border_width_left = 4
	note_quote.content_margin_left = 14.0
	note_quote.content_margin_right = 12.0
	note_quote.content_margin_top = 10.0
	note_quote.content_margin_bottom = 10.0
	theme.set_stylebox("panel", "NoteQuotePanel", note_quote)

	_add_variation(theme, &"NoteCodeBlockPanel", &"PanelContainer")
	var note_code_block: StyleBoxFlat = _box(semantic_color("surface_alt"), semantic_color("border_strong"), 1, 12, 12, 12, 12)
	note_code_block.content_margin_left = 10.0
	note_code_block.content_margin_right = 10.0
	note_code_block.content_margin_top = 8.0
	note_code_block.content_margin_bottom = 10.0
	theme.set_stylebox("panel", "NoteCodeBlockPanel", note_code_block)

	_add_variation(theme, &"NoteTableHeaderPanel", &"PanelContainer")
	var note_table_header: StyleBoxFlat = _box(semantic_color("accent_soft"), semantic_color("border"), 1, 5, 5, 5, 5)
	note_table_header.content_margin_left = 10.0
	note_table_header.content_margin_right = 10.0
	note_table_header.content_margin_top = 8.0
	note_table_header.content_margin_bottom = 8.0
	theme.set_stylebox("panel", "NoteTableHeaderPanel", note_table_header)

	_add_variation(theme, &"NoteTableCellPanel", &"PanelContainer")
	var note_table_cell: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border"), 1, 5, 5, 5, 5)
	note_table_cell.content_margin_left = 10.0
	note_table_cell.content_margin_right = 10.0
	note_table_cell.content_margin_top = 8.0
	note_table_cell.content_margin_bottom = 8.0
	theme.set_stylebox("panel", "NoteTableCellPanel", note_table_cell)

	_add_variation(theme, &"NoteSidebarPanel", &"PanelContainer")
	var note_sidebar: StyleBoxFlat = _box(semantic_color("surface_alt"), semantic_color("border"), 0, 18, 18, 18, 18)
	note_sidebar.border_width_right = 1
	note_sidebar.content_margin_left = 12.0
	note_sidebar.content_margin_right = 12.0
	note_sidebar.content_margin_top = 12.0
	note_sidebar.content_margin_bottom = 12.0
	theme.set_stylebox("panel", "NoteSidebarPanel", note_sidebar)

	_add_variation(theme, &"NoteInsetPanel", &"PanelContainer")
	var note_inset: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border"), 1, 12, 12, 12, 12)
	note_inset.content_margin_left = 10.0
	note_inset.content_margin_right = 10.0
	note_inset.content_margin_top = 9.0
	note_inset.content_margin_bottom = 9.0
	theme.set_stylebox("panel", "NoteInsetPanel", note_inset)

	_add_variation(theme, &"NoteGraphToolbarPanel", &"PanelContainer")
	var note_graph_toolbar: StyleBoxFlat = _box(Color(semantic_color("surface"), 0.96), semantic_color("border"), 1, 14, 14, 14, 14)
	note_graph_toolbar.shadow_color = Color(0.03, 0.07, 0.05, 0.12)
	note_graph_toolbar.shadow_size = 8
	note_graph_toolbar.shadow_offset = Vector2(0.0, 3.0)
	note_graph_toolbar.content_margin_left = 10.0
	note_graph_toolbar.content_margin_right = 10.0
	note_graph_toolbar.content_margin_top = 8.0
	note_graph_toolbar.content_margin_bottom = 8.0
	theme.set_stylebox("panel", "NoteGraphToolbarPanel", note_graph_toolbar)

	_add_variation(theme, &"NoteBoardWorkspacePanel", &"PanelContainer")
	var note_board_workspace: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border_strong"), 1, 14, 14, 14, 14)
	note_board_workspace.content_margin_left = 0.0
	note_board_workspace.content_margin_right = 0.0
	note_board_workspace.content_margin_top = 0.0
	note_board_workspace.content_margin_bottom = 0.0
	theme.set_stylebox("panel", "NoteBoardWorkspacePanel", note_board_workspace)

	_add_variation(theme, &"NoteBoardWorkspaceTopbar", &"PanelContainer")
	var note_board_topbar: StyleBoxFlat = _box(semantic_color("surface_alt"), semantic_color("border"), 0, 12, 12, 0, 0)
	note_board_topbar.border_width_bottom = 1
	note_board_topbar.content_margin_left = 10.0
	note_board_topbar.content_margin_right = 10.0
	note_board_topbar.content_margin_top = 7.0
	note_board_topbar.content_margin_bottom = 5.0
	theme.set_stylebox("panel", "NoteBoardWorkspaceTopbar", note_board_topbar)

	_add_variation(theme, &"NoteBoardWorkspaceSidebar", &"PanelContainer")
	var note_board_sidebar: StyleBoxFlat = _box(semantic_color("surface_alt"), semantic_color("border"), 0, 0, 0, 0, 0)
	note_board_sidebar.border_width_right = 1
	note_board_sidebar.content_margin_left = 8.0
	note_board_sidebar.content_margin_right = 8.0
	note_board_sidebar.content_margin_top = 8.0
	note_board_sidebar.content_margin_bottom = 8.0
	theme.set_stylebox("panel", "NoteBoardWorkspaceSidebar", note_board_sidebar)

	_add_variation(theme, &"NoteTabButton", &"Button")
	var note_tab_normal: StyleBoxFlat = _box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 8, 8, 0, 0)
	var note_tab_hover: StyleBoxFlat = _box(semantic_color("surface"), Color.TRANSPARENT, 0, 8, 8, 0, 0)
	var note_tab_focus: StyleBoxFlat = _box(Color.TRANSPARENT, Color(semantic_color("accent"), 0.38), 1, 8, 8, 0, 0)
	_set_button_styles(theme, &"NoteTabButton", note_tab_normal, note_tab_hover, note_tab_hover, note_tab_focus, note_tab_normal)
	_set_button_colors(theme, &"NoteTabButton", semantic_color("text_muted"), semantic_color("text"), semantic_color("text"), semantic_color("text"), semantic_color("disabled_text"))
	theme.set_font_size("font_size", "NoteTabButton", 12)

	_add_variation(theme, &"NoteActiveTabButton", &"Button")
	var note_active_tab: StyleBoxFlat = _box(semantic_color("accent_soft"), Color.TRANSPARENT, 0, 8, 8, 0, 0)
	note_active_tab.border_width_bottom = 2
	note_active_tab.border_color = semantic_color("accent")
	_set_button_styles(theme, &"NoteActiveTabButton", note_active_tab, note_active_tab, note_active_tab, note_tab_focus, note_active_tab)
	_set_button_colors(theme, &"NoteActiveTabButton", semantic_color("accent"), semantic_color("accent"), semantic_color("accent"), semantic_color("accent"), semantic_color("disabled_text"))
	theme.set_font_size("font_size", "NoteActiveTabButton", 12)

	_add_variation(theme, &"NoteResourceEmbedPanel", &"PanelContainer")
	var note_resource_embed: StyleBoxFlat = _box(semantic_color("surface_alt"), Color(semantic_color("border"), 0.86), 1, 12, 12, 12, 12)
	note_resource_embed.content_margin_left = 12.0
	note_resource_embed.content_margin_right = 12.0
	note_resource_embed.content_margin_top = 10.0
	note_resource_embed.content_margin_bottom = 10.0
	theme.set_stylebox("panel", "NoteResourceEmbedPanel", note_resource_embed)

	_add_variation(theme, &"NoteEmbeddedMediaFrame", &"PanelContainer")
	var note_embed_frame: StyleBoxFlat = _box(semantic_color("surface"), Color(semantic_color("border_strong"), 0.74), 1, 10, 10, 10, 10)
	note_embed_frame.content_margin_left = 4.0
	note_embed_frame.content_margin_right = 4.0
	note_embed_frame.content_margin_top = 4.0
	note_embed_frame.content_margin_bottom = 4.0
	theme.set_stylebox("panel", "NoteEmbeddedMediaFrame", note_embed_frame)

	_add_variation(theme, &"NoteFormulaPanel", &"PanelContainer")
	var note_formula: StyleBoxFlat = _box(Color(semantic_color("accent_soft"), 0.48), Color(semantic_color("accent"), 0.32), 1, 12, 12, 12, 12)
	note_formula.content_margin_left = 12.0
	note_formula.content_margin_right = 12.0
	note_formula.content_margin_top = 10.0
	note_formula.content_margin_bottom = 10.0
	theme.set_stylebox("panel", "NoteFormulaPanel", note_formula)

	_add_variation(theme, &"NoteDragPreviewPanel", &"PanelContainer")
	var note_drag_preview: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("accent"), 1, 10, 10, 10, 10)
	note_drag_preview.shadow_color = Color(0.03, 0.07, 0.05, 0.16)
	note_drag_preview.shadow_size = 8
	note_drag_preview.content_margin_left = 10.0
	note_drag_preview.content_margin_right = 10.0
	note_drag_preview.content_margin_top = 7.0
	note_drag_preview.content_margin_bottom = 7.0
	theme.set_stylebox("panel", "NoteDragPreviewPanel", note_drag_preview)

	_add_variation(theme, &"NoteRichText", &"RichTextLabel")
	# Use native SystemFont weight/italic matching instead of simulated
	# FontVariation emboldening. Godot 4.4 documents that simulated emboldening
	# can create self-intersecting outlines (especially problematic with MSDF);
	# real system-font style selection avoids the white glyph artifacts seen in
	# Cyrillic/Latin bold text while keeping system fallback coverage.
	var note_font_names: PackedStringArray = PackedStringArray(["Noto Sans", "Segoe UI", "Arial", "sans-serif"])
	var note_base_font: SystemFont = SystemFont.new()
	note_base_font.font_names = note_font_names
	note_base_font.font_weight = 400
	note_base_font.allow_system_fallback = true
	var note_bold_font: SystemFont = SystemFont.new()
	note_bold_font.font_names = note_font_names
	note_bold_font.font_weight = 700
	note_bold_font.allow_system_fallback = true
	var note_italic_font: SystemFont = SystemFont.new()
	note_italic_font.font_names = note_font_names
	note_italic_font.font_weight = 400
	note_italic_font.font_italic = true
	note_italic_font.allow_system_fallback = true
	var note_bold_italic_font: SystemFont = SystemFont.new()
	note_bold_italic_font.font_names = note_font_names
	note_bold_italic_font.font_weight = 700
	note_bold_italic_font.font_italic = true
	note_bold_italic_font.allow_system_fallback = true
	theme.set_font("normal_font", "NoteRichText", note_base_font)
	theme.set_font("bold_font", "NoteRichText", note_bold_font)
	theme.set_font("italics_font", "NoteRichText", note_italic_font)
	theme.set_font("bold_italics_font", "NoteRichText", note_bold_italic_font)
	theme.set_color("default_color", "NoteRichText", semantic_color("text"))
	theme.set_color("font_selected_color", "NoteRichText", semantic_color("text"))
	theme.set_color("selection_color", "NoteRichText", Color(semantic_color("accent"), 0.22))
	theme.set_color("table_border", "NoteRichText", semantic_color("border"))
	theme.set_color("table_even_row_bg", "NoteRichText", Color(semantic_color("surface_alt"), 0.54))
	theme.set_color("table_odd_row_bg", "NoteRichText", semantic_color("surface"))
	theme.set_font_size("normal_font_size", "NoteRichText", 15)
	theme.set_font_size("bold_font_size", "NoteRichText", 15)
	theme.set_font_size("italics_font_size", "NoteRichText", 15)
	theme.set_font_size("bold_italics_font_size", "NoteRichText", 15)
	theme.set_font_size("mono_font_size", "NoteRichText", 14)
	theme.set_constant("line_separation", "NoteRichText", 3)
	theme.set_constant("table_h_separation", "NoteRichText", 1)
	theme.set_constant("table_v_separation", "NoteRichText", 1)
	var note_rich_normal: StyleBoxFlat = _box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 0, 0, 0)
	theme.set_stylebox("normal", "NoteRichText", note_rich_normal)

	# ItemList and Tree have opaque gray defaults in the engine theme. Notes owns
	# dedicated variations so library navigation remains visually native to NotLight.
	_add_variation(theme, &"NoteItemList", &"ItemList")
	var note_list_panel: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border"), 1, 11, 11, 11, 11)
	note_list_panel.content_margin_left = 5.0
	note_list_panel.content_margin_right = 5.0
	note_list_panel.content_margin_top = 5.0
	note_list_panel.content_margin_bottom = 5.0
	var note_list_hovered: StyleBoxFlat = _box(semantic_color("surface_alt"), Color.TRANSPARENT, 0, 8, 8, 8, 8)
	var note_list_selected: StyleBoxFlat = _box(semantic_color("accent_soft"), Color(semantic_color("accent"), 0.28), 1, 8, 8, 8, 8)
	var note_list_focus: StyleBoxFlat = _box(Color.TRANSPARENT, Color(semantic_color("accent"), 0.36), 1, 11, 11, 11, 11)
	theme.set_stylebox("panel", "NoteItemList", note_list_panel)
	theme.set_stylebox("hovered", "NoteItemList", note_list_hovered)
	theme.set_stylebox("selected", "NoteItemList", note_list_selected)
	theme.set_stylebox("selected_focus", "NoteItemList", note_list_selected)
	theme.set_stylebox("focus", "NoteItemList", note_list_focus)
	theme.set_color("font_color", "NoteItemList", semantic_color("text"))
	theme.set_color("font_hovered_color", "NoteItemList", semantic_color("text"))
	theme.set_color("font_selected_color", "NoteItemList", semantic_color("accent"))
	theme.set_color("font_hovered_selected_color", "NoteItemList", semantic_color("accent"))
	theme.set_font_size("font_size", "NoteItemList", 14)
	theme.set_constant("v_separation", "NoteItemList", 5)
	theme.set_constant("line_separation", "NoteItemList", 4)

	_add_variation(theme, &"NoteFolderTree", &"Tree")
	var note_tree_panel: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border"), 1, 11, 11, 11, 11)
	note_tree_panel.content_margin_left = 6.0
	note_tree_panel.content_margin_right = 6.0
	note_tree_panel.content_margin_top = 6.0
	note_tree_panel.content_margin_bottom = 6.0
	var note_tree_hovered: StyleBoxFlat = _box(semantic_color("surface_alt"), Color.TRANSPARENT, 0, 7, 7, 7, 7)
	var note_tree_selected: StyleBoxFlat = _box(semantic_color("accent_soft"), Color.TRANSPARENT, 0, 7, 7, 7, 7)
	theme.set_stylebox("panel", "NoteFolderTree", note_tree_panel)
	theme.set_stylebox("hovered", "NoteFolderTree", note_tree_hovered)
	theme.set_stylebox("hovered_dimmed", "NoteFolderTree", note_tree_hovered)
	theme.set_stylebox("selected", "NoteFolderTree", note_tree_selected)
	theme.set_stylebox("selected_focus", "NoteFolderTree", note_tree_selected)
	theme.set_stylebox("focus", "NoteFolderTree", note_list_focus)
	theme.set_color("font_color", "NoteFolderTree", semantic_color("text"))
	theme.set_color("font_hovered_color", "NoteFolderTree", semantic_color("text"))
	theme.set_color("font_selected_color", "NoteFolderTree", semantic_color("accent"))
	theme.set_color("font_hovered_selected_color", "NoteFolderTree", semantic_color("accent"))
	theme.set_color("children_hl_line_color", "NoteFolderTree", Color(semantic_color("border_strong"), 0.55))
	theme.set_color("relationship_line_color", "NoteFolderTree", Color(semantic_color("border_strong"), 0.46))
	theme.set_font_size("font_size", "NoteFolderTree", 13)
	theme.set_constant("v_separation", "NoteFolderTree", 5)
	theme.set_constant("draw_relationship_lines", "NoteFolderTree", 1)
	theme.set_constant("relationship_line_width", "NoteFolderTree", 1)

	_add_variation(theme, &"NoteNavigationTree", &"Tree")
	var note_navigation_panel: StyleBoxFlat = _box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 8, 8, 8, 8)
	var note_navigation_hovered: StyleBoxFlat = _box(Color(semantic_color("surface"), 0.86), Color.TRANSPARENT, 0, 7, 7, 7, 7)
	var note_navigation_selected: StyleBoxFlat = _box(semantic_color("accent_soft"), Color.TRANSPARENT, 0, 7, 7, 7, 7)
	var note_navigation_focus: StyleBoxFlat = _box(Color.TRANSPARENT, Color(semantic_color("accent"), 0.34), 1, 9, 9, 9, 9)
	theme.set_stylebox("panel", "NoteNavigationTree", note_navigation_panel)
	theme.set_stylebox("hovered", "NoteNavigationTree", note_navigation_hovered)
	theme.set_stylebox("hovered_dimmed", "NoteNavigationTree", note_navigation_hovered)
	theme.set_stylebox("selected", "NoteNavigationTree", note_navigation_selected)
	theme.set_stylebox("selected_focus", "NoteNavigationTree", note_navigation_selected)
	theme.set_stylebox("focus", "NoteNavigationTree", note_navigation_focus)
	theme.set_color("font_color", "NoteNavigationTree", semantic_color("text"))
	theme.set_color("font_hovered_color", "NoteNavigationTree", semantic_color("text"))
	theme.set_color("font_selected_color", "NoteNavigationTree", semantic_color("accent"))
	theme.set_color("font_hovered_selected_color", "NoteNavigationTree", semantic_color("accent"))
	theme.set_color("relationship_line_color", "NoteNavigationTree", Color(semantic_color("border_strong"), 0.46))
	theme.set_color("children_hl_line_color", "NoteNavigationTree", Color(semantic_color("border_strong"), 0.55))
	theme.set_color("drop_position_color", "NoteNavigationTree", semantic_color("accent"))
	theme.set_font_size("font_size", "NoteNavigationTree", 14)
	theme.set_constant("v_separation", "NoteNavigationTree", 3)
	theme.set_constant("draw_relationship_lines", "NoteNavigationTree", 1)
	theme.set_constant("relationship_line_width", "NoteNavigationTree", 1)
	theme.set_constant("draw_guides", "NoteNavigationTree", 0)

	_add_variation(theme, &"AssetFolderTree", &"Tree")
	var asset_folder_panel: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border"), 1, 11, 11, 11, 11)
	asset_folder_panel.content_margin_left = 5.0
	asset_folder_panel.content_margin_right = 5.0
	asset_folder_panel.content_margin_top = 5.0
	asset_folder_panel.content_margin_bottom = 5.0
	var asset_folder_hovered: StyleBoxFlat = _box(semantic_color("surface_alt"), Color.TRANSPARENT, 0, 7, 7, 7, 7)
	var asset_folder_selected: StyleBoxFlat = _box(semantic_color("accent_soft"), Color(semantic_color("accent"), 0.28), 1, 7, 7, 7, 7)
	var asset_folder_focus: StyleBoxFlat = _box(Color.TRANSPARENT, Color(semantic_color("accent"), 0.32), 1, 11, 11, 11, 11)
	theme.set_stylebox("panel", "AssetFolderTree", asset_folder_panel)
	theme.set_stylebox("hovered", "AssetFolderTree", asset_folder_hovered)
	theme.set_stylebox("hovered_dimmed", "AssetFolderTree", asset_folder_hovered)
	theme.set_stylebox("selected", "AssetFolderTree", asset_folder_selected)
	theme.set_stylebox("selected_focus", "AssetFolderTree", asset_folder_selected)
	theme.set_stylebox("focus", "AssetFolderTree", asset_folder_focus)
	theme.set_color("font_color", "AssetFolderTree", semantic_color("text"))
	theme.set_color("font_hovered_color", "AssetFolderTree", semantic_color("text"))
	theme.set_color("font_selected_color", "AssetFolderTree", semantic_color("accent"))
	theme.set_color("font_hovered_selected_color", "AssetFolderTree", semantic_color("accent"))
	theme.set_color("relationship_line_color", "AssetFolderTree", Color(semantic_color("border_strong"), 0.42))
	theme.set_color("children_hl_line_color", "AssetFolderTree", Color(semantic_color("border_strong"), 0.50))
	theme.set_color("drop_position_color", "AssetFolderTree", semantic_color("accent"))
	theme.set_font_size("font_size", "AssetFolderTree", 14)
	theme.set_constant("v_separation", "AssetFolderTree", 3)
	theme.set_constant("draw_relationship_lines", "AssetFolderTree", 1)
	theme.set_constant("relationship_line_width", "AssetFolderTree", 1)
	theme.set_constant("draw_guides", "AssetFolderTree", 0)


static func _configure_inputs(theme: Theme) -> void:
	var normal: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border"), 1, 12, 12, 12, 12)
	normal.content_margin_left = 14.0
	normal.content_margin_right = 14.0
	normal.content_margin_top = 10.0
	normal.content_margin_bottom = 10.0
	var focus: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	focus.border_color = semantic_color("accent")
	focus.set_border_width_all(2)
	var read_only: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	read_only.bg_color = semantic_color("surface_alt")
	theme.set_stylebox("normal", "LineEdit", normal)
	theme.set_stylebox("focus", "LineEdit", focus)
	theme.set_stylebox("read_only", "LineEdit", read_only)
	theme.set_color("font_color", "LineEdit", semantic_color("text"))
	theme.set_color("font_uneditable_color", "LineEdit", semantic_color("text_muted"))
	theme.set_color("font_placeholder_color", "LineEdit", semantic_color("text_muted"))
	theme.set_color("caret_color", "LineEdit", semantic_color("accent"))
	theme.set_color("selection_color", "LineEdit", Color(0.25, 0.61, 0.40, 0.25))
	theme.set_font_size("font_size", "LineEdit", 15)

	# TextEdit is left untouched globally because the board uses text editors for
	# document content. The Resource Inspector gets a dedicated surface that
	# matches NotLight inputs instead of the engine's opaque gray default.
	_add_variation(theme, &"InspectorTextEdit", &"TextEdit")
	var inspector_text_normal: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border"), 1, 12, 12, 12, 12)
	inspector_text_normal.content_margin_left = 12.0
	inspector_text_normal.content_margin_right = 12.0
	inspector_text_normal.content_margin_top = 10.0
	inspector_text_normal.content_margin_bottom = 10.0
	var inspector_text_focus: StyleBoxFlat = inspector_text_normal.duplicate() as StyleBoxFlat
	inspector_text_focus.border_color = semantic_color("accent")
	inspector_text_focus.set_border_width_all(2)
	var inspector_text_read_only: StyleBoxFlat = inspector_text_normal.duplicate() as StyleBoxFlat
	inspector_text_read_only.bg_color = semantic_color("surface_alt")
	theme.set_stylebox("normal", "InspectorTextEdit", inspector_text_normal)
	theme.set_stylebox("focus", "InspectorTextEdit", inspector_text_focus)
	theme.set_stylebox("read_only", "InspectorTextEdit", inspector_text_read_only)
	theme.set_color("font_color", "InspectorTextEdit", semantic_color("text"))
	theme.set_color("font_readonly_color", "InspectorTextEdit", semantic_color("text_muted"))
	theme.set_color("font_placeholder_color", "InspectorTextEdit", semantic_color("text_muted"))
	theme.set_color("caret_color", "InspectorTextEdit", semantic_color("accent"))
	theme.set_color("selection_color", "InspectorTextEdit", Color(0.25, 0.61, 0.40, 0.22))
	theme.set_font_size("font_size", "InspectorTextEdit", 14)

	# Formula input is code-like content, but it should still feel native to NotLight
	# instead of falling back to Godot's opaque gray TextEdit. Keep it visually
	# distinct from prose editors with a slightly warmer surface and stronger focus.
	_add_variation(theme, &"FormulaSourceEdit", &"TextEdit")
	var formula_normal: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border_strong"), 1, 13, 13, 13, 13)
	formula_normal.content_margin_left = 14.0
	formula_normal.content_margin_right = 14.0
	formula_normal.content_margin_top = 12.0
	formula_normal.content_margin_bottom = 12.0
	var formula_focus: StyleBoxFlat = formula_normal.duplicate() as StyleBoxFlat
	formula_focus.border_color = semantic_color("accent")
	formula_focus.set_border_width_all(2)
	formula_focus.shadow_color = Color(0.13, 0.42, 0.27, 0.08)
	formula_focus.shadow_size = 5
	var formula_read_only: StyleBoxFlat = formula_normal.duplicate() as StyleBoxFlat
	formula_read_only.bg_color = semantic_color("surface_alt")
	theme.set_stylebox("normal", "FormulaSourceEdit", formula_normal)
	theme.set_stylebox("focus", "FormulaSourceEdit", formula_focus)
	theme.set_stylebox("read_only", "FormulaSourceEdit", formula_read_only)
	theme.set_color("font_color", "FormulaSourceEdit", semantic_color("text"))
	theme.set_color("font_readonly_color", "FormulaSourceEdit", semantic_color("text_muted"))
	theme.set_color("font_placeholder_color", "FormulaSourceEdit", Color(semantic_color("text_muted"), 0.72))
	theme.set_color("caret_color", "FormulaSourceEdit", semantic_color("accent"))
	theme.set_color("selection_color", "FormulaSourceEdit", Color(0.25, 0.61, 0.40, 0.22))
	theme.set_color("current_line_color", "FormulaSourceEdit", Color(semantic_color("accent_soft"), 0.28))
	theme.set_font_size("font_size", "FormulaSourceEdit", 15)


	_add_variation(theme, &"NoteInlineMarkdownEdit", &"TextEdit")
	var note_inline_normal: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("accent"), 1, 10, 10, 10, 10)
	note_inline_normal.content_margin_left = 12.0
	note_inline_normal.content_margin_right = 12.0
	note_inline_normal.content_margin_top = 10.0
	note_inline_normal.content_margin_bottom = 10.0
	var note_inline_focus: StyleBoxFlat = note_inline_normal.duplicate() as StyleBoxFlat
	note_inline_focus.set_border_width_all(2)
	theme.set_stylebox("normal", "NoteInlineMarkdownEdit", note_inline_normal)
	theme.set_stylebox("focus", "NoteInlineMarkdownEdit", note_inline_focus)
	theme.set_stylebox("read_only", "NoteInlineMarkdownEdit", note_inline_normal)
	theme.set_color("font_color", "NoteInlineMarkdownEdit", semantic_color("text"))
	theme.set_color("font_readonly_color", "NoteInlineMarkdownEdit", semantic_color("text_muted"))
	theme.set_color("caret_color", "NoteInlineMarkdownEdit", semantic_color("accent"))
	theme.set_color("selection_color", "NoteInlineMarkdownEdit", Color(semantic_color("accent"), 0.20))
	theme.set_font_size("font_size", "NoteInlineMarkdownEdit", 15)

	_add_variation(theme, &"NoteCodeEdit", &"CodeEdit")
	var note_code_normal: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border"), 1, 9, 9, 9, 9)
	note_code_normal.content_margin_left = 10.0
	note_code_normal.content_margin_right = 10.0
	note_code_normal.content_margin_top = 8.0
	note_code_normal.content_margin_bottom = 8.0
	var note_code_focus: StyleBoxFlat = note_code_normal.duplicate() as StyleBoxFlat
	note_code_focus.border_color = semantic_color("accent")
	note_code_focus.set_border_width_all(2)
	theme.set_stylebox("normal", "NoteCodeEdit", note_code_normal)
	theme.set_stylebox("focus", "NoteCodeEdit", note_code_focus)
	theme.set_stylebox("read_only", "NoteCodeEdit", note_code_normal)
	theme.set_color("font_color", "NoteCodeEdit", semantic_color("text"))
	theme.set_color("font_readonly_color", "NoteCodeEdit", semantic_color("text_muted"))
	theme.set_color("caret_color", "NoteCodeEdit", semantic_color("accent"))
	theme.set_color("selection_color", "NoteCodeEdit", Color(semantic_color("accent"), 0.20))
	theme.set_color("current_line_color", "NoteCodeEdit", Color(semantic_color("accent_soft"), 0.34))
	theme.set_color("line_number_color", "NoteCodeEdit", Color(semantic_color("text_muted"), 0.66))
	theme.set_font_size("font_size", "NoteCodeEdit", 14)

	_add_variation(theme, &"SettingsOptionButton", &"OptionButton")
	var option_normal: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border"), 1, 12, 12, 12, 12)
	var option_hover: StyleBoxFlat = _box(_surface_hover(), semantic_color("border_strong"), 1, 12, 12, 12, 12)
	var option_pressed: StyleBoxFlat = _box(semantic_color("accent_soft"), Color("#a9ceb6"), 1, 12, 12, 12, 12)
	var option_focus: StyleBoxFlat = _box(Color.TRANSPARENT, semantic_color("accent"), 2, 12, 12, 12, 12)
	var option_disabled: StyleBoxFlat = _box(semantic_color("surface_alt"), semantic_color("border"), 1, 12, 12, 12, 12)
	_set_button_styles(theme, &"SettingsOptionButton", option_normal, option_hover, option_pressed, option_focus, option_disabled)
	_set_button_colors(theme, &"SettingsOptionButton", semantic_color("text"), semantic_color("text"), semantic_color("accent"), semantic_color("text"), semantic_color("disabled_text"))
	theme.set_font_size("font_size", "SettingsOptionButton", 14)

	theme.set_color("font_color", "PopupMenu", semantic_color("text"))
	theme.set_color("font_hover_color", "PopupMenu", semantic_color("text"))
	theme.set_stylebox("panel", "PopupMenu", _box(semantic_color("surface"), semantic_color("border"), 1, 12, 12, 12, 12))
	theme.set_stylebox("hover", "PopupMenu", _box(semantic_color("accent_soft"), Color.TRANSPARENT, 0, 8, 8, 8, 8))


static func _configure_ranges(theme: Theme) -> void:
	var progress_bg: StyleBoxFlat = _box(semantic_color("surface_alt"), Color.TRANSPARENT, 0, 99, 99, 99, 99)
	var progress_fill: StyleBoxFlat = _box(semantic_color("accent"), Color.TRANSPARENT, 0, 99, 99, 99, 99)
	theme.set_stylebox("background", "ProgressBar", progress_bg)
	theme.set_stylebox("fill", "ProgressBar", progress_fill)
	theme.set_color("font_color", "ProgressBar", semantic_color("text"))

	# All sliders share the same NotLight track/fill/grabber language. Keeping this
	# at Theme level prevents video, drawing and settings controls from drifting
	# into separate visual styles.
	var slider: StyleBoxFlat = _box(semantic_color("surface_alt"), Color.TRANSPARENT, 0, 99, 99, 99, 99)
	slider.content_margin_top = 3.0
	slider.content_margin_bottom = 3.0
	var grabber_area: StyleBoxFlat = _box(semantic_color("accent"), Color.TRANSPARENT, 0, 99, 99, 99, 99)
	grabber_area.content_margin_top = 3.0
	grabber_area.content_margin_bottom = 3.0
	theme.set_stylebox("slider", "HSlider", slider)
	theme.set_stylebox("grabber_area", "HSlider", grabber_area)
	theme.set_stylebox("grabber_area_highlight", "HSlider", grabber_area)
	theme.set_icon("grabber", "HSlider", SLIDER_GRABBER)
	theme.set_icon("grabber_highlight", "HSlider", SLIDER_GRABBER_HOVER)
	theme.set_icon("grabber_disabled", "HSlider", SLIDER_GRABBER)
	theme.set_constant("center_grabber", "HSlider", 1)


static func _configure_scrollbars(theme: Theme) -> void:
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	theme.set_stylebox("scroll", "VScrollBar", empty)
	theme.set_stylebox("scroll_focus", "VScrollBar", empty)
	theme.set_stylebox("grabber", "VScrollBar", _box(Color("#c7cec5"), Color.TRANSPARENT, 0, 99, 99, 99, 99))
	theme.set_stylebox("grabber_highlight", "VScrollBar", _box(Color("#a7b3a8"), Color.TRANSPARENT, 0, 99, 99, 99, 99))
	theme.set_stylebox("grabber_pressed", "VScrollBar", _box(semantic_color("accent"), Color.TRANSPARENT, 0, 99, 99, 99, 99))
	theme.set_constant("minimum_grab_thickness", "VScrollBar", 8)

	# Reading/Notes side panes use the same semantic colors but a slightly narrower
	# floating thumb, so long knowledge documents feel integrated instead of using
	# the platform/default scrollbar skin.
	_add_variation(theme, &"NoteScrollBar", &"VScrollBar")
	theme.set_stylebox("scroll", "NoteScrollBar", empty)
	theme.set_stylebox("scroll_focus", "NoteScrollBar", empty)
	theme.set_stylebox("grabber", "NoteScrollBar", _box(Color(semantic_color("text_muted"), 0.30), Color.TRANSPARENT, 0, 99, 99, 99, 99))
	theme.set_stylebox("grabber_highlight", "NoteScrollBar", _box(Color(semantic_color("accent"), 0.56), Color.TRANSPARENT, 0, 99, 99, 99, 99))
	theme.set_stylebox("grabber_pressed", "NoteScrollBar", _box(semantic_color("accent"), Color.TRANSPARENT, 0, 99, 99, 99, 99))
	theme.set_constant("minimum_grab_thickness", "NoteScrollBar", 7)


static func _configure_dialogs(theme: Theme) -> void:
	var dialog_panel: StyleBoxFlat = _box(semantic_color("surface"), semantic_color("border"), 1, 20, 20, 20, 20)
	dialog_panel.shadow_color = Color(0.05, 0.10, 0.07, 0.24)
	dialog_panel.shadow_size = 18
	dialog_panel.content_margin_left = 8.0
	dialog_panel.content_margin_right = 8.0
	dialog_panel.content_margin_top = 8.0
	dialog_panel.content_margin_bottom = 8.0
	theme.set_stylebox("panel", "Window", dialog_panel)


static func _configure_tooltips(theme: Theme) -> void:
	var panel: StyleBoxFlat = _box(Color("#27322b"), Color.TRANSPARENT, 0, 9, 9, 9, 9)
	panel.content_margin_left = 10.0
	panel.content_margin_right = 10.0
	panel.content_margin_top = 7.0
	panel.content_margin_bottom = 7.0
	theme.set_stylebox("panel", "TooltipPanel", panel)
	theme.set_color("font_color", "TooltipLabel", Color.WHITE)
	theme.set_font_size("font_size", "TooltipLabel", 13)


static func _set_button_styles(
	theme: Theme,
	type_name: StringName,
	normal: StyleBox,
	hover: StyleBox,
	pressed: StyleBox,
	focus: StyleBox,
	disabled: StyleBox
) -> void:
	theme.set_stylebox("normal", type_name, normal)
	theme.set_stylebox("hover", type_name, hover)
	theme.set_stylebox("pressed", type_name, pressed)
	theme.set_stylebox("hover_pressed", type_name, pressed)
	theme.set_stylebox("focus", type_name, focus)
	theme.set_stylebox("disabled", type_name, disabled)


static func _set_button_colors(
	theme: Theme,
	type_name: StringName,
	normal: Color,
	hover: Color,
	pressed: Color,
	focus: Color,
	disabled: Color
) -> void:
	theme.set_color("font_color", type_name, normal)
	theme.set_color("font_hover_color", type_name, hover)
	theme.set_color("font_pressed_color", type_name, pressed)
	theme.set_color("font_hover_pressed_color", type_name, pressed)
	theme.set_color("font_focus_color", type_name, focus)
	theme.set_color("font_disabled_color", type_name, disabled)


static func _add_variation(theme: Theme, variation: StringName, base: StringName) -> void:
	theme.set_type_variation(variation, base)



static func _surface_hover() -> Color:
	return semantic_color("surface").lerp(semantic_color("accent"), 0.06)


static func _surface_pressed() -> Color:
	return semantic_color("surface").lerp(semantic_color("accent"), 0.12)


static func _accent_pressed() -> Color:
	var accent: Color = semantic_color("accent")
	return accent.darkened(0.12) if accent.get_luminance() > 0.35 else accent.lightened(0.12)

static func _box(
	background: Color,
	border: Color,
	border_width: int,
	radius_tl: int,
	radius_tr: int,
	radius_br: int,
	radius_bl: int
) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.border_width_left = border_width
	box.border_width_top = border_width
	box.border_width_right = border_width
	box.border_width_bottom = border_width
	box.corner_radius_top_left = radius_tl
	box.corner_radius_top_right = radius_tr
	box.corner_radius_bottom_right = radius_br
	box.corner_radius_bottom_left = radius_bl
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 9.0
	box.content_margin_bottom = 9.0
	return box
