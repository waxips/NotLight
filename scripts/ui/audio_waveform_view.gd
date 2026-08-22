# SPDX-License-Identifier: GPL-3.0-or-later
class_name AudioWaveformView
extends Control

var _texture: Texture2D
var _progress: float = 0.0
var _playing: bool = false
var _compact: bool = false
var _last_queued_progress: float = -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	queue_redraw()


func set_waveform(texture: Texture2D) -> void:
	if _texture == texture:
		return
	_texture = texture
	queue_redraw()


func set_playback_progress(value: float, playing: bool) -> void:
	var clean_progress: float = clampf(value, 0.0, 1.0)
	var progress_changed: bool = not is_equal_approx(_progress, clean_progress)
	var playing_changed: bool = _playing != playing
	_progress = clean_progress
	_playing = playing
	# Playback position may update every process frame, but the waveform only needs
	# a redraw when the playhead has moved a visible fraction of a pixel. This
	# keeps several simultaneous audio cards inexpensive without making the
	# progress animation look less smooth. Pausing or seeking still commits exactly,
	# while an idle paused card does not redraw every frame.
	var drawable_width: float = maxf(1.0, size.x - (8.0 if _compact else 20.0))
	var pixel_delta: float = absf(clean_progress - _last_queued_progress) * drawable_width
	var should_redraw: bool = (
		playing_changed
		or _last_queued_progress < 0.0
		or (playing and pixel_delta >= 0.45)
		or (not playing and progress_changed)
	)
	if should_redraw:
		_last_queued_progress = clean_progress
		queue_redraw()


func set_compact(value: bool) -> void:
	if _compact == value:
		return
	_compact = value
	queue_redraw()


func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	var accent: Color = NotLightTheme.semantic_color("accent")
	var background: Color = NotLightTheme.semantic_color("accent_soft")
	var muted: Color = NotLightTheme.semantic_color("text_muted")
	var surface: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(surface, Color(background, 0.58), true)

	var padding_x: float = 4.0 if _compact else 10.0
	var padding_y: float = 3.0 if _compact else 7.0
	var wave_rect: Rect2 = Rect2(
		Vector2(padding_x, padding_y),
		Vector2(maxf(1.0, size.x - padding_x * 2.0), maxf(1.0, size.y - padding_y * 2.0))
	)
	var center_y: float = wave_rect.get_center().y
	if _progress > 0.001:
		var played_background: Rect2 = Rect2(
			wave_rect.position,
			Vector2(wave_rect.size.x * _progress, wave_rect.size.y)
		)
		draw_rect(played_background, Color(accent, 0.075 if _compact else 0.10), true)
	draw_line(
		Vector2(wave_rect.position.x, center_y),
		Vector2(wave_rect.end.x, center_y),
		Color(accent, 0.14),
		1.0,
		true
	)

	if _texture != null and _texture.get_width() > 0 and _texture.get_height() > 0:
		# The generated waveform is white-on-alpha. Tint the complete shape softly,
		# then redraw only the already played source region with the stronger accent.
		draw_texture_rect(_texture, wave_rect, false, Color(muted, 0.42))
		if _progress > 0.001:
			var played_width: float = wave_rect.size.x * _progress
			var source_width: float = float(_texture.get_width()) * _progress
			var played_rect: Rect2 = Rect2(wave_rect.position, Vector2(played_width, wave_rect.size.y))
			var source_rect: Rect2 = Rect2(Vector2.ZERO, Vector2(source_width, float(_texture.get_height())))
			draw_texture_rect_region(_texture, played_rect, source_rect, Color(accent, 0.94))
	else:
		_draw_placeholder_wave(wave_rect, accent)

	if _progress > 0.001 and _progress < 0.999:
		var playhead_x: float = wave_rect.position.x + wave_rect.size.x * _progress
		var playhead_alpha: float = 0.88 if _playing else 0.60
		draw_line(
			Vector2(playhead_x, wave_rect.position.y),
			Vector2(playhead_x, wave_rect.end.y),
			Color(accent, playhead_alpha),
			1.4 if not _compact else 1.0,
			true
		)
		if not _compact and _playing:
			draw_circle(Vector2(playhead_x, center_y), 2.4, Color(accent, 0.98))


func _draw_placeholder_wave(rect: Rect2, accent: Color) -> void:
	if rect.size.x < 4.0 or rect.size.y < 4.0:
		return
	var bar_count: int = clampi(int(rect.size.x / (5.0 if _compact else 8.0)), 8, 72)
	var step: float = rect.size.x / float(bar_count)
	var center_y: float = rect.get_center().y
	for index: int in range(bar_count):
		var phase: float = float(index) * 0.73
		var envelope: float = 0.30 + absf(sin(phase) * cos(phase * 0.37)) * 0.55
		var half_height: float = maxf(1.0, rect.size.y * 0.44 * envelope)
		var x: float = rect.position.x + (float(index) + 0.5) * step
		var normalized_x: float = (float(index) + 0.5) / float(bar_count)
		var bar_alpha: float = 0.88 if normalized_x <= _progress else 0.24
		draw_line(
			Vector2(x, center_y - half_height),
			Vector2(x, center_y + half_height),
			Color(accent, bar_alpha),
			maxf(1.0, step * 0.28),
			true
		)
