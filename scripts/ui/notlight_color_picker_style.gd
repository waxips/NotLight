# SPDX-License-Identifier: GPL-3.0-or-later
class_name NotLightColorPickerStyle
extends RefCounted

const COMPACT_MINIMUM_SIZE: Vector2 = Vector2(264.0, 286.0)


static func configure_picker(picker: ColorPicker, allow_alpha: bool, advanced: bool) -> void:
	if picker == null:
		return
	picker.edit_alpha = allow_alpha
	picker.deferred_mode = true
	picker.presets_visible = false
	picker.can_add_swatches = false
	picker.sampler_visible = false
	picker.color_modes_visible = advanced
	picker.sliders_visible = advanced
	picker.hex_visible = advanced
	picker.picker_shape = ColorPicker.SHAPE_HSV_RECTANGLE
	picker.add_theme_constant_override("sv_width", 216)
	picker.add_theme_constant_override("sv_height", 168)
	picker.add_theme_constant_override("margin", 6)
	picker.custom_minimum_size = COMPACT_MINIMUM_SIZE


static func configure_button_popup(button: ColorPickerButton, viewport_height: float, allow_alpha: bool = false) -> void:
	if button == null:
		return
	configure_picker(button.get_picker(), allow_alpha, true)
	var popup: PopupPanel = button.get_popup()
	if popup != null:
		var usable_height: int = maxi(330, int(viewport_height) - 48)
		popup.min_size = Vector2i(280, 304)
		popup.max_size = Vector2i(344, mini(450, usable_height))
