# SPDX-License-Identifier: GPL-3.0-or-later
class_name GridIntensityPreview
extends Control

const PREVIEW_SPACING: float = 22.0
const PREVIEW_MAJOR_STEP: int = 4

var _intensity: int = int(AppSettingsStore.GridIntensity.BALANCED)


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 88.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)
	queue_redraw()


func set_intensity(value: int) -> void:
	var clean: int = clampi(value, int(AppSettingsStore.GridIntensity.SOFT), int(AppSettingsStore.GridIntensity.EXPRESSIVE))
	if _intensity == clean:
		return
	_intensity = clean
	queue_redraw()


func refresh_palette() -> void:
	queue_redraw()


func _draw() -> void:
	var background: Color = NotLightTheme.semantic_color("board_background")
	var grid_color: Color = NotLightTheme.semantic_color("board_grid")
	var text_muted: Color = NotLightTheme.semantic_color("text_muted")
	var border: Color = NotLightTheme.semantic_color("border")
	var minimum_delta: float = 0.11
	var contrast_mix: float = 0.38
	var minor_alpha: float = 0.44
	var major_alpha: float = 0.68
	var minor_radius: float = 1.35
	var major_radius: float = 1.90
	match _intensity:
		AppSettingsStore.GridIntensity.SOFT:
			minimum_delta = 0.085
			contrast_mix = 0.28
			minor_alpha = 0.28
			major_alpha = 0.46
			minor_radius = 1.05
			major_radius = 1.55
		AppSettingsStore.GridIntensity.EXPRESSIVE:
			minimum_delta = 0.16
			contrast_mix = 0.62
			minor_alpha = 0.72
			major_alpha = 0.88
			minor_radius = 1.75
			major_radius = 2.40
		_:
			pass
	if absf(grid_color.get_luminance() - background.get_luminance()) < minimum_delta:
		grid_color = grid_color.lerp(text_muted, contrast_mix)

	draw_rect(Rect2(Vector2.ZERO, size), background, true)
	if size.x <= 1.0 or size.y <= 1.0:
		return
	var inset: float = maxf(major_radius + 2.0, 4.0)
	var origin: Vector2 = Vector2(inset + PREVIEW_SPACING * 0.5, inset + PREVIEW_SPACING * 0.5)
	var drawable_end: Vector2 = size - Vector2.ONE * inset
	if origin.x <= drawable_end.x and origin.y <= drawable_end.y:
		var column_count: int = int(floor((drawable_end.x - origin.x) / PREVIEW_SPACING)) + 1
		var row_count: int = int(floor((drawable_end.y - origin.y) / PREVIEW_SPACING)) + 1
		for row: int in range(maxi(row_count, 0)):
			for column: int in range(maxi(column_count, 0)):
				var is_major: bool = column % PREVIEW_MAJOR_STEP == 0 and row % PREVIEW_MAJOR_STEP == 0
				var alpha: float = major_alpha if is_major else minor_alpha
				var radius: float = major_radius if is_major else minor_radius
				var point: Vector2 = origin + Vector2(float(column) * PREVIEW_SPACING, float(row) * PREVIEW_SPACING)
				draw_circle(point, radius, Color(grid_color.r, grid_color.g, grid_color.b, alpha), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(border.r, border.g, border.b, 0.82), false, 1.0, true)
