# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardThumbnail
extends Control

var board_seed: int = 1
var _background_style: StyleBoxFlat
var _note_style: StyleBoxFlat
var _card_style: StyleBoxFlat


func configure(board_id: String) -> void:
	board_seed = abs(board_id.hash())
	queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(280, 132)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_create_styles()


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	draw_style_box(_background_style, rect)
	_draw_grid()
	_draw_decorations()


func _draw_grid() -> void:
	var spacing: float = 18.0
	var dot_color: Color = Color(0.18, 0.31, 0.23, 0.12)
	var y: float = 12.0
	while y < size.y:
		var x: float = 12.0
		while x < size.x:
			draw_circle(Vector2(x, y), 1.0, dot_color)
			x += spacing
		y += spacing


func _draw_decorations() -> void:
	var accent_index: int = board_seed % 3
	var accents: Array[Color] = [Color("#237f52"), Color("#a26c32"), Color("#596d9c")]
	var accent: Color = accents[accent_index]
	_note_style.bg_color = _color_with_alpha(accent, 0.14)
	_note_style.border_color = _color_with_alpha(accent, 0.30)

	var shift: float = float(board_seed % 20)
	var first_rect: Rect2 = Rect2(Vector2(24.0 + shift, 24.0), Vector2(112.0, 66.0))
	draw_style_box(_note_style, first_rect)
	draw_line(first_rect.position + Vector2(15.0, 19.0), first_rect.position + Vector2(85.0, 19.0), _color_with_alpha(accent, 0.64), 2.0, true)
	draw_line(first_rect.position + Vector2(15.0, 31.0), first_rect.position + Vector2(72.0, 31.0), _color_with_alpha(accent, 0.38), 2.0, true)
	draw_line(first_rect.position + Vector2(15.0, 43.0), first_rect.position + Vector2(91.0, 43.0), _color_with_alpha(accent, 0.24), 2.0, true)

	var second_rect: Rect2 = Rect2(Vector2(size.x - 126.0, 32.0 + float(board_seed % 10)), Vector2(98.0, 72.0))
	draw_style_box(_card_style, second_rect)
	draw_line(second_rect.position + Vector2(15.0, 20.0), second_rect.position + Vector2(75.0, 20.0), Color(0.20, 0.25, 0.21, 0.55), 2.0, true)
	draw_line(second_rect.position + Vector2(15.0, 33.0), second_rect.position + Vector2(66.0, 33.0), Color(0.20, 0.25, 0.21, 0.30), 2.0, true)
	draw_line(second_rect.position + Vector2(15.0, 46.0), second_rect.position + Vector2(78.0, 46.0), Color(0.20, 0.25, 0.21, 0.18), 2.0, true)


func _create_styles() -> void:
	_background_style = StyleBoxFlat.new()
	_background_style.bg_color = Color("#f1f3e9")
	_background_style.border_color = Color("#e0e3d8")
	_background_style.set_border_width_all(1)
	_background_style.set_corner_radius_all(14)

	_note_style = StyleBoxFlat.new()
	_note_style.set_border_width_all(1)
	_note_style.set_corner_radius_all(10)

	_card_style = StyleBoxFlat.new()
	_card_style.bg_color = Color(1.0, 0.995, 0.95, 0.95)
	_card_style.border_color = Color(0.26, 0.31, 0.27, 0.16)
	_card_style.set_border_width_all(1)
	_card_style.set_corner_radius_all(12)
	_card_style.shadow_color = Color(0.08, 0.12, 0.09, 0.10)
	_card_style.shadow_size = 5
	_card_style.shadow_offset = Vector2(0, 2)


func _color_with_alpha(color: Color, alpha: float) -> Color:
	var result: Color = color
	result.a = alpha
	return result
