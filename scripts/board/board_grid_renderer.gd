# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardGridRenderer
extends ColorRect

const GRID_SHADER: Shader = preload("res://assets/shaders/dot_grid.gdshader")
const BASE_GRID_SIZE: float = 32.0

var _grid_material: ShaderMaterial
var _last_camera_position: Vector2 = Vector2(INF, INF)
var _last_zoom: float = -1.0
var _last_viewport_size: Vector2 = Vector2.ZERO
var _intensity: int = int(AppSettingsStore.GridIntensity.BALANCED)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color.WHITE
	z_as_relative = false
	z_index = -100
	_grid_material = ShaderMaterial.new()
	_grid_material.shader = GRID_SHADER
	material = _grid_material
	refresh_palette()


func set_intensity(value: int) -> void:
	var clean: int = clampi(value, int(AppSettingsStore.GridIntensity.SOFT), int(AppSettingsStore.GridIntensity.EXPRESSIVE))
	if _intensity == clean:
		return
	_intensity = clean
	refresh_palette()


func refresh_palette() -> void:
	if _grid_material == null:
		return
	var background: Color = NotLightTheme.semantic_color("board_background")
	var grid: Color = NotLightTheme.semantic_color("board_grid")
	var accent: Color = NotLightTheme.semantic_color("accent")
	var text: Color = NotLightTheme.semantic_color("text_muted")
	# Custom palettes may accidentally choose a grid color that is almost equal
	# to the board background. Preserve the requested hue, but guarantee a
	# mode-specific contrast floor. "Expressive" is intentionally strong enough
	# to read like a real dotted notebook canvas instead of decorative noise.
	var minimum_luminance_delta: float = 0.11
	var contrast_mix: float = 0.38
	var minor_alpha: float = 0.44
	var major_alpha: float = 0.68
	var dot_scale: float = 1.12
	match _intensity:
		AppSettingsStore.GridIntensity.SOFT:
			minimum_luminance_delta = 0.085
			contrast_mix = 0.28
			minor_alpha = 0.26
			major_alpha = 0.44
			dot_scale = 0.94
		AppSettingsStore.GridIntensity.EXPRESSIVE:
			minimum_luminance_delta = 0.16
			contrast_mix = 0.62
			minor_alpha = 0.72
			major_alpha = 0.88
			dot_scale = 1.42
		_:
			pass
	if absf(grid.get_luminance() - background.get_luminance()) < minimum_luminance_delta:
		grid = grid.lerp(text, contrast_mix)
	_grid_material.set_shader_parameter("background_color", background)
	_grid_material.set_shader_parameter("minor_dot_color", Color(grid.r, grid.g, grid.b, minor_alpha))
	_grid_material.set_shader_parameter("major_dot_color", Color(grid.r, grid.g, grid.b, major_alpha))
	_grid_material.set_shader_parameter("origin_color", Color(accent.r, accent.g, accent.b, 0.38))
	_grid_material.set_shader_parameter("dot_scale", dot_scale)


func set_view(camera_position: Vector2, zoom_value: float, viewport_size: Vector2) -> void:
	if _grid_material == null:
		return
	if not camera_position.is_equal_approx(_last_camera_position):
		_last_camera_position = camera_position
		_grid_material.set_shader_parameter("camera_position", camera_position)
	if not is_equal_approx(zoom_value, _last_zoom):
		_last_zoom = zoom_value
		_grid_material.set_shader_parameter("zoom", zoom_value)
		_grid_material.set_shader_parameter("grid_world_size", _compute_grid_world_size(zoom_value))
	if not viewport_size.is_equal_approx(_last_viewport_size):
		_last_viewport_size = viewport_size
		_grid_material.set_shader_parameter("viewport_size", viewport_size)


func _compute_grid_world_size(zoom_value: float) -> float:
	var grid_world_size: float = BASE_GRID_SIZE
	var screen_spacing: float = grid_world_size * maxf(zoom_value, 0.001)
	while screen_spacing < 14.0:
		grid_world_size *= 4.0
		screen_spacing = grid_world_size * zoom_value
	while screen_spacing > 150.0:
		grid_world_size *= 0.5
		screen_spacing = grid_world_size * zoom_value
	return grid_world_size
