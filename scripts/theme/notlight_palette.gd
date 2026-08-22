# SPDX-License-Identifier: GPL-3.0-or-later
class_name NotLightPalette
extends RefCounted

const PRESET_DEFAULT: String = "notlight_default"
const PRESET_HIGH_CONTRAST: String = "high_contrast"
const PRESET_CUSTOM: String = "custom"

const SEMANTIC_KEYS: Array[String] = [
	"background",
	"surface",
	"surface_alt",
	"text",
	"text_muted",
	"accent",
	"accent_hover",
	"accent_soft",
	"text_on_accent",
	"border",
	"border_strong",
	"danger",
	"danger_soft",
	"warning",
	"warning_soft",
	"disabled_text",
	"board_background",
	"board_grid",
]


static func preset_ids() -> Array[String]:
	return [PRESET_DEFAULT, PRESET_HIGH_CONTRAST, PRESET_CUSTOM]


static func default_palette() -> Dictionary:
	return {
		"background": "#f8f6ec",
		"surface": "#fffef8",
		"surface_alt": "#f1f0e6",
		"text": "#202a24",
		"text_muted": "#687269",
		"accent": "#237f52",
		"accent_hover": "#1d6f47",
		"accent_soft": "#dff1e5",
		"text_on_accent": "#ffffff",
		"border": "#d9dcd2",
		"border_strong": "#bdc4ba",
		"danger": "#b84a45",
		"danger_soft": "#f7e5e2",
		"warning": "#946018",
		"warning_soft": "#f7edda",
		"disabled_text": "#929a93",
		"board_background": "#f8f6ec",
		"board_grid": "#a9c8b2",
	}


static func high_contrast_palette() -> Dictionary:
	return {
		"background": "#ffffff",
		"surface": "#ffffff",
		"surface_alt": "#f1f3f1",
		"text": "#101311",
		"text_muted": "#454d47",
		"accent": "#006b3c",
		"accent_hover": "#00542f",
		"accent_soft": "#d7f6e4",
		"text_on_accent": "#ffffff",
		"border": "#8b958e",
		"border_strong": "#5e6962",
		"danger": "#9d241e",
		"danger_soft": "#ffe0dd",
		"warning": "#6f4700",
		"warning_soft": "#fff0c9",
		"disabled_text": "#687069",
		"board_background": "#ffffff",
		"board_grid": "#9ab0a0",
	}


static func preset(preset_id: String) -> Dictionary:
	match preset_id:
		PRESET_HIGH_CONTRAST:
			return high_contrast_palette()
		_:
			return default_palette()


static func sanitize_custom(source: Dictionary, base_preset: String = PRESET_DEFAULT) -> Dictionary:
	var result: Dictionary = preset(base_preset)
	for key: String in SEMANTIC_KEYS:
		if not source.has(key):
			continue
		var value: String = str(source.get(key, "")).strip_edges()
		if Color.html_is_valid(value):
			result[key] = Color(value).to_html(false)
	return _derive_related_colors(result)


static func effective(preset_id: String, custom: Dictionary) -> Dictionary:
	if preset_id == PRESET_CUSTOM:
		return sanitize_custom(custom, PRESET_DEFAULT)
	return _derive_related_colors(preset(preset_id))


static func color(palette: Dictionary, key: String, fallback: Color = Color.WHITE) -> Color:
	var value: String = str(palette.get(key, ""))
	return Color(value) if Color.html_is_valid(value) else fallback


static func _derive_related_colors(source: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	var accent: Color = color(result, "accent", Color("#237f52"))
	var background: Color = color(result, "background", Color("#f8f6ec"))
	var surface: Color = color(result, "surface", Color("#fffef8"))
	var text: Color = color(result, "text", Color("#202a24"))
	var danger: Color = color(result, "danger", Color("#b84a45"))
	var warning: Color = color(result, "warning", Color("#946018"))
	result["accent_hover"] = _mix_for_hover(accent, background).to_html(false)
	result["accent_soft"] = accent.lerp(surface, 0.82).to_html(false)
	result["text_on_accent"] = _best_contrast_text(accent).to_html(false)
	result["danger_soft"] = danger.lerp(surface, 0.84).to_html(false)
	result["warning_soft"] = warning.lerp(surface, 0.82).to_html(false)
	result["disabled_text"] = text.lerp(background, 0.52).to_html(false)
	return result


static func _mix_for_hover(accent: Color, background: Color) -> Color:
	var background_luminance: float = background.get_luminance()
	return accent.darkened(0.12) if background_luminance > 0.5 else accent.lightened(0.12)


static func _best_contrast_text(background: Color) -> Color:
	# WCAG-style relative luminance approximation is enough for choosing one
	# of the two stable foreground anchors used by NotLight controls.
	return Color("#102018") if background.get_luminance() > 0.62 else Color.WHITE
