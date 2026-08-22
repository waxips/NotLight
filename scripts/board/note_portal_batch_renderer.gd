# SPDX-License-Identifier: GPL-3.0-or-later
class_name NotePortalBatchRenderer
extends Node2D

const TITLE_FONT_SIZE: int = 18
const HEADING_FONT_SIZES: PackedInt32Array = [22, 20, 18, 16, 15, 14]
const BODY_FONT_SIZE: int = 13
const CODE_FONT_SIZE: int = 12
const META_FONT_SIZE: int = 11
const ACCENT_STRIP_WIDTH: float = 5.0
const INNER_PADDING: float = 16.0
const BODY_MIN_SCREEN_WIDTH: float = 150.0
const BODY_MIN_SCREEN_HEIGHT: float = 96.0
const FOOTER_MIN_SCREEN_HEIGHT: float = 150.0
const DETAIL_MIN_ZOOM: float = 0.30
const FULL_DETAIL_MIN_ZOOM: float = 0.16
const MAX_RENDER_RUNS: int = 72
const FULL_MAX_RENDER_RUNS: int = 192
const RUN_GAP: float = 7.0
const CODE_PADDING: float = 9.0
const QUOTE_PADDING: float = 8.0
const TABLE_CELL_HEIGHT: float = 24.0
const MAX_FORMULA_REQUESTS_PER_DRAW: int = 8
const FULL_MAX_FORMULA_REQUESTS_PER_DRAW: int = 32

var _entity_ids: PackedInt64Array = PackedInt64Array()
var _bounds: Array[Rect2] = []
var _titles: PackedStringArray = PackedStringArray()
var _previews: Array[Array] = []
var _missing: PackedByteArray = PackedByteArray()
var _view_modes: PackedInt32Array = PackedInt32Array()
var _hidden_entity_ids: Dictionary = {}
var _live_entity_ids: Dictionary = {}
var _font: Font
var _zoom: float = 1.0
var _formula_service: FormulaRenderService
var _formula_requests_remaining: int = 0
var _full_render: bool = false


func _ready() -> void:
	_font = ThemeDB.fallback_font


func rebuild(
	runtime: BoardRuntime,
	repository: NoteRepository,
	formula_service: FormulaRenderService,
	candidate_ids: PackedInt64Array,
	max_visible: int,
	zoom: float,
	full_render: bool,
	focus_world: Vector2 = Vector2.ZERO
) -> void:
	_entity_ids = PackedInt64Array()
	_bounds = []
	_titles = PackedStringArray()
	_previews = []
	_missing = PackedByteArray()
	_view_modes = PackedInt32Array()
	_zoom = maxf(zoom, 0.001)
	_full_render = full_render
	_formula_service = formula_service
	if runtime == null:
		queue_redraw()
		return
	var ids: Array[int] = []
	for entity_id: int in candidate_ids:
		if (
			runtime.model.note_portals.contains(entity_id)
			and runtime.model.transforms.is_visible(entity_id)
			and runtime.model.contains(entity_id)
		):
			ids.append(entity_id)
	var limit: int = maxi(1, max_visible)
	if ids.size() > limit:
		ids.sort_custom(func(left_id: int, right_id: int) -> bool:
			var left_distance: float = runtime.model.get_entity_bounds(left_id).get_center().distance_squared_to(focus_world)
			var right_distance: float = runtime.model.get_entity_bounds(right_id).get_center().distance_squared_to(focus_world)
			if not is_equal_approx(left_distance, right_distance):
				return left_distance < right_distance
			return left_id < right_id
		)
		ids.resize(limit)
	ids.sort_custom(func(left_id: int, right_id: int) -> bool:
		var left_z: int = runtime.model.get_entity_z_order(left_id)
		var right_z: int = runtime.model.get_entity_z_order(right_id)
		return left_z < right_z if left_z != right_z else left_id < right_id
	)
	for entity_id: int in ids:
		var note_id: String = runtime.model.note_portals.get_note_id(entity_id)
		var note: Dictionary = repository.get_note(note_id) if repository != null else {}
		var is_missing: bool = note.is_empty()
		_entity_ids.append(entity_id)
		_bounds.append(runtime.model.get_entity_bounds(entity_id))
		_titles.append(
			NotLightL10n.text("notes.portal.missing")
			if is_missing
			else str(note.get("display_name", NotLightL10n.text("notes.untitled")))
		)
		_previews.append([] if is_missing or repository == null else repository.peek_board_preview(note_id))
		_missing.append(1 if is_missing else 0)
		_view_modes.append(runtime.model.note_portals.get_view_mode(entity_id))
	queue_redraw()


func set_hidden_entity_ids(hidden_entity_ids: Dictionary) -> void:
	_hidden_entity_ids = hidden_entity_ids.duplicate()
	queue_redraw()


func set_live_entity_ids(live_entity_ids: Dictionary) -> void:
	_live_entity_ids = live_entity_ids.duplicate()
	queue_redraw()


func _draw() -> void:
	_formula_requests_remaining = FULL_MAX_FORMULA_REQUESTS_PER_DRAW if _full_render else MAX_FORMULA_REQUESTS_PER_DRAW
	if _font == null:
		_font = ThemeDB.fallback_font
	for index: int in range(_entity_ids.size()):
		var entity_id: int = int(_entity_ids[index])
		if _hidden_entity_ids.has(entity_id) or _live_entity_ids.has(entity_id):
			continue
		_draw_portal(index)


func _draw_portal(index: int) -> void:
	var bounds: Rect2 = _bounds[index]
	if not bounds.has_area():
		return
	var screen_size: Vector2 = bounds.size * _zoom
	var is_missing: bool = int(_missing[index]) != 0
	var surface: Color = NotLightTheme.semantic_color("surface")
	var border: Color = NotLightTheme.semantic_color("danger") if is_missing else NotLightTheme.semantic_color("border_strong")
	var accent: Color = NotLightTheme.semantic_color("danger") if is_missing else NotLightTheme.semantic_color("accent")
	draw_rect(bounds, surface, true)
	draw_rect(bounds, border, false, maxf(1.0 / _zoom, 1.0), true)
	draw_rect(Rect2(bounds.position, Vector2(ACCENT_STRIP_WIDTH, bounds.size.y)), accent, true)
	if screen_size.x < 72.0 or screen_size.y < 38.0:
		return
	var left: float = bounds.position.x + INNER_PADDING + ACCENT_STRIP_WIDTH
	var width: float = maxf(1.0, bounds.size.x - INNER_PADDING * 2.0 - ACCENT_STRIP_WIDTH)
	var view_mode: int = int(_view_modes[index]) if index < _view_modes.size() else NotePortalStore.VIEW_PREVIEW
	_draw_header(index, left, width, bounds, view_mode)
	var detail_min_zoom: float = FULL_DETAIL_MIN_ZOOM if _full_render else DETAIL_MIN_ZOOM
	var min_screen_width: float = 96.0 if _full_render else BODY_MIN_SCREEN_WIDTH
	var min_screen_height: float = 64.0 if _full_render else BODY_MIN_SCREEN_HEIGHT
	if _zoom < detail_min_zoom or screen_size.x < min_screen_width or screen_size.y < min_screen_height:
		return
	var body_top: float = bounds.position.y + (79.0 if view_mode == NotePortalStore.VIEW_WORKSPACE else 62.0)
	var footer_space: float = 28.0 if screen_size.y >= FOOTER_MIN_SCREEN_HEIGHT else 8.0
	var body_bottom: float = bounds.end.y - footer_space
	if body_bottom <= body_top + 8.0:
		return
	if is_missing:
		_draw_wrapped_text(NotLightL10n.text("notes.portal.missing_hint"), Vector2(left, body_top), width, body_bottom, BODY_FONT_SIZE, NotLightTheme.semantic_color("danger"))
	else:
		_draw_markdown_preview(_previews[index], Rect2(left, body_top, width, body_bottom - body_top))
	if screen_size.y >= FOOTER_MIN_SCREEN_HEIGHT:
		draw_string(
			_font,
			Vector2(left, bounds.end.y - 14.0),
			NotLightL10n.text("notes.portal.footer"),
			HORIZONTAL_ALIGNMENT_LEFT,
			width,
			META_FONT_SIZE,
			Color(NotLightTheme.semantic_color("text_muted"), 0.82)
		)


func _draw_header(index: int, left: float, width: float, bounds: Rect2, view_mode: int) -> void:
	var title_y: float = bounds.position.y + 30.0
	draw_string(
		_font,
		Vector2(left, title_y),
		_titles[index],
		HORIZONTAL_ALIGNMENT_LEFT,
		width,
		TITLE_FONT_SIZE,
		NotLightTheme.semantic_color("text")
	)
	if view_mode == NotePortalStore.VIEW_WORKSPACE:
		var tab_y: float = bounds.position.y + 40.0
		var tab_height: float = 25.0
		var tab_width: float = minf(190.0, maxf(78.0, width * 0.42))
		var tab_rect: Rect2 = Rect2(left, tab_y, tab_width, tab_height)
		draw_rect(tab_rect, NotLightTheme.semantic_color("accent_soft"), true)
		draw_line(Vector2(tab_rect.position.x, tab_rect.end.y), Vector2(tab_rect.end.x, tab_rect.end.y), NotLightTheme.semantic_color("accent"), 2.0)
		draw_string(_font, Vector2(tab_rect.position.x + 9.0, tab_rect.position.y + 17.0), _titles[index], HORIZONTAL_ALIGNMENT_LEFT, tab_rect.size.x - 18.0, 11, NotLightTheme.semantic_color("accent"))
		var graph_x: float = tab_rect.end.x + 10.0
		draw_string(_font, Vector2(graph_x, tab_rect.position.y + 17.0), NotLightL10n.text("notes.mode.graph"), HORIZONTAL_ALIGNMENT_LEFT, maxf(1.0, width - (graph_x - left)), 11, NotLightTheme.semantic_color("text_muted"))
		draw_line(Vector2(left, bounds.position.y + 72.0), Vector2(left + width, bounds.position.y + 72.0), Color(NotLightTheme.semantic_color("border"), 0.85), 1.0)
	else:
		draw_line(Vector2(left, bounds.position.y + 46.0), Vector2(left + width, bounds.position.y + 46.0), Color(NotLightTheme.semantic_color("border"), 0.85), 1.0)


func _draw_markdown_preview(preview: Array, rect: Rect2) -> void:
	if preview.is_empty():
		_draw_wrapped_text(NotLightL10n.text("notes.portal.open_hint"), rect.position, rect.size.x, rect.end.y, BODY_FONT_SIZE, NotLightTheme.semantic_color("text_muted"))
		return
	var y: float = rect.position.y
	var rendered_runs: int = 0
	var render_run_budget: int = FULL_MAX_RENDER_RUNS if _full_render else MAX_RENDER_RUNS
	for raw_run: Variant in preview:
		if rendered_runs >= render_run_budget or y >= rect.end.y - 12.0:
			break
		if raw_run is not Dictionary:
			continue
		var run: Dictionary = raw_run as Dictionary
		var kind: String = str(run.get("kind", "paragraph"))
		if kind == "rule":
			draw_line(Vector2(rect.position.x, y + 4.0), Vector2(rect.end.x, y + 4.0), NotLightTheme.semantic_color("border"), 1.0)
			y += 13.0
		elif kind == "heading":
			var level: int = clampi(int(run.get("level", 1)), 1, HEADING_FONT_SIZES.size())
			var font_size: int = int(HEADING_FONT_SIZES[level - 1])
			y = _draw_wrapped_text(str(run.get("text", "")), Vector2(rect.position.x, y), rect.size.x, rect.end.y, font_size, NotLightTheme.semantic_color("text"), true) + RUN_GAP
		elif kind == "quote" or kind == "callout":
			var text: String = str(run.get("text", ""))
			var callout: bool = kind == "callout"
			var title: String = str(run.get("title", ""))
			var title_height: float = 20.0 if callout else 0.0
			var quote_height: float = _estimate_wrapped_height(text, rect.size.x - QUOTE_PADDING * 2.0 - 4.0, BODY_FONT_SIZE) + QUOTE_PADDING * 2.0 + title_height
			quote_height = minf(quote_height, maxf(0.0, rect.end.y - y))
			if quote_height > 6.0:
				var quote_rect: Rect2 = Rect2(rect.position.x, y, rect.size.x, quote_height)
				draw_rect(quote_rect, NotLightTheme.semantic_color("surface_alt"), true)
				draw_rect(Rect2(quote_rect.position, Vector2(3.0, quote_rect.size.y)), NotLightTheme.semantic_color("accent"), true)
				var text_y: float = y + QUOTE_PADDING
				if callout:
					draw_string(_font, Vector2(rect.position.x + QUOTE_PADDING + 4.0, text_y + 12.0), title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - QUOTE_PADDING * 2.0 - 4.0, META_FONT_SIZE, NotLightTheme.semantic_color("accent"))
					text_y += title_height
				y = _draw_wrapped_text(text, Vector2(rect.position.x + QUOTE_PADDING + 4.0, text_y), rect.size.x - QUOTE_PADDING * 2.0 - 4.0, quote_rect.end.y, BODY_FONT_SIZE, NotLightTheme.semantic_color("text_muted")) + RUN_GAP
		elif kind == "code":
			y = _draw_code_run(run, Rect2(rect.position.x, y, rect.size.x, maxf(0.0, rect.end.y - y))) + RUN_GAP
		elif kind == "math":
			y = _draw_math_run(run, Rect2(rect.position.x, y, rect.size.x, maxf(0.0, rect.end.y - y))) + RUN_GAP
		elif kind == "embed":
			y = _draw_embed_run(run, Rect2(rect.position.x, y, rect.size.x, maxf(0.0, rect.end.y - y))) + RUN_GAP
		elif kind == "table":
			y = _draw_table_run(run, Rect2(rect.position.x, y, rect.size.x, maxf(0.0, rect.end.y - y))) + RUN_GAP
		elif kind == "task":
			var checked: bool = bool(run.get("checked", false))
			var marker: String = "✓" if checked else "□"
			var marker_color: Color = NotLightTheme.semantic_color("accent") if checked else NotLightTheme.semantic_color("text_muted")
			draw_string(_font, Vector2(rect.position.x, y + 13.0), marker, HORIZONTAL_ALIGNMENT_LEFT, 18.0, BODY_FONT_SIZE, marker_color)
			y = _draw_wrapped_text(str(run.get("text", "")), Vector2(rect.position.x + 22.0, y), maxf(1.0, rect.size.x - 22.0), rect.end.y, BODY_FONT_SIZE, NotLightTheme.semantic_color("text_muted") if checked else NotLightTheme.semantic_color("text")) + 3.0
		elif kind == "list":
			var marker: String = str(run.get("marker", "•"))
			draw_string(_font, Vector2(rect.position.x, y + 13.0), marker, HORIZONTAL_ALIGNMENT_LEFT, 24.0, BODY_FONT_SIZE, NotLightTheme.semantic_color("accent"))
			y = _draw_wrapped_text(str(run.get("text", "")), Vector2(rect.position.x + 26.0, y), maxf(1.0, rect.size.x - 26.0), rect.end.y, BODY_FONT_SIZE, NotLightTheme.semantic_color("text")) + 3.0
		else:
			y = _draw_wrapped_text(str(run.get("text", "")), Vector2(rect.position.x, y), rect.size.x, rect.end.y, BODY_FONT_SIZE, NotLightTheme.semantic_color("text")) + RUN_GAP
		rendered_runs += 1


func _draw_embed_run(run: Dictionary, rect: Rect2) -> float:
	if rect.size.y <= 10.0:
		return rect.position.y
	var height: float = minf(48.0, rect.size.y)
	var box: Rect2 = Rect2(rect.position, Vector2(rect.size.x, height))
	draw_rect(box, Color(NotLightTheme.semantic_color("accent_soft"), 0.30), true)
	draw_rect(box, Color(NotLightTheme.semantic_color("accent"), 0.32), false, 1.0)
	draw_circle(Vector2(box.position.x + 18.0, box.position.y + box.size.y * 0.5), 5.0, NotLightTheme.semantic_color("accent"))
	var label: String = str(run.get("text", NotLightL10n.text("notes.embed.inline_placeholder"))).strip_edges()
	draw_string(
		_font,
		Vector2(box.position.x + 32.0, box.position.y + 29.0),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		maxf(1.0, box.size.x - 42.0),
		BODY_FONT_SIZE,
		NotLightTheme.semantic_color("text")
	)
	return box.end.y


func _draw_code_run(run: Dictionary, rect: Rect2) -> float:
	if rect.size.y <= 10.0:
		return rect.position.y
	var language: String = str(run.get("language", "")).strip_edges()
	var text: String = str(run.get("text", ""))
	var lines: PackedStringArray = text.split("\n", true)
	var visible_line_count: int = mini(lines.size(), 9)
	var desired_height: float = CODE_PADDING * 2.0 + 18.0 + float(maxi(1, visible_line_count)) * 18.0
	var height: float = minf(desired_height, rect.size.y)
	var box: Rect2 = Rect2(rect.position, Vector2(rect.size.x, height))
	draw_rect(box, NotLightTheme.semantic_color("surface_alt"), true)
	draw_rect(box, NotLightTheme.semantic_color("border"), false, 1.0)
	if not language.is_empty():
		draw_string(_font, Vector2(box.position.x + CODE_PADDING, box.position.y + 15.0), language, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - CODE_PADDING * 2.0, META_FONT_SIZE, NotLightTheme.semantic_color("text_muted"))
	var line_y: float = box.position.y + 34.0
	for line_index: int in range(visible_line_count):
		if line_y > box.end.y - 6.0:
			break
		draw_string(_font, Vector2(box.position.x + CODE_PADDING, line_y), lines[line_index], HORIZONTAL_ALIGNMENT_LEFT, box.size.x - CODE_PADDING * 2.0, CODE_FONT_SIZE, NotLightTheme.semantic_color("text"))
		line_y += 18.0
	return box.end.y


func _draw_math_run(run: Dictionary, rect: Rect2) -> float:
	if rect.size.y <= 10.0:
		return rect.position.y
	var source: String = str(run.get("text", "")).strip_edges()
	var height: float = minf(72.0, rect.size.y)
	var box: Rect2 = Rect2(rect.position, Vector2(rect.size.x, height))
	draw_rect(box, Color(NotLightTheme.semantic_color("accent_soft"), 0.28), true)
	draw_rect(box, Color(NotLightTheme.semantic_color("accent"), 0.26), false, 1.0)
	var texture: Texture2D = null
	if _formula_service != null and _formula_requests_remaining > 0 and not source.is_empty():
		_formula_requests_remaining -= 1
		var record: Dictionary = {
			"source_latex": source,
			"display_mode": FormulaStore.DISPLAY_BLOCK,
			"font_scale": FormulaStore.DEFAULT_FONT_SCALE,
			"foreground": NotLightTheme.semantic_color("text"),
		}
		var desired_extent: float = maxf(180.0, minf(1024.0, box.size.x * _zoom))
		texture = _formula_service.request_texture(record, desired_extent)
	if texture != null:
		var fitted: Rect2 = _fit_texture_rect(texture, box.grow(-10.0))
		draw_texture_rect(texture, fitted, false, NotLightTheme.semantic_color("text"))
	else:
		draw_string(_font, Vector2(box.position.x + 10.0, box.position.y + 18.0), NotLightL10n.text("notes.math.badge"), HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 20.0, META_FONT_SIZE, NotLightTheme.semantic_color("accent"))
		var fallback: String = source.replace("\n", " ").left(220)
		draw_string(_font, Vector2(box.position.x + 10.0, box.position.y + 47.0), fallback, HORIZONTAL_ALIGNMENT_CENTER, box.size.x - 20.0, BODY_FONT_SIZE, NotLightTheme.semantic_color("text"))
	return box.end.y


func _fit_texture_rect(texture: Texture2D, bounds: Rect2) -> Rect2:
	var source_size: Vector2 = texture.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0 or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return bounds
	var scale_value: float = minf(bounds.size.x / source_size.x, bounds.size.y / source_size.y)
	var fitted_size: Vector2 = source_size * scale_value
	return Rect2(bounds.get_center() - fitted_size * 0.5, fitted_size)


func _draw_table_run(run: Dictionary, rect: Rect2) -> float:
	var raw_rows: Variant = run.get("rows", [])
	if raw_rows is not Array or (raw_rows as Array).is_empty() or rect.size.y <= TABLE_CELL_HEIGHT:
		return rect.position.y
	var rows: Array = raw_rows as Array
	var column_count: int = 1
	for raw_row: Variant in rows:
		if raw_row is PackedStringArray:
			column_count = maxi(column_count, (raw_row as PackedStringArray).size())
		elif raw_row is Array:
			column_count = maxi(column_count, (raw_row as Array).size())
	column_count = clampi(column_count, 1, 5)
	var cell_width: float = rect.size.x / float(column_count)
	var y: float = rect.position.y
	for row_index: int in range(rows.size()):
		if y + TABLE_CELL_HEIGHT > rect.end.y:
			break
		var row_rect: Rect2 = Rect2(rect.position.x, y, rect.size.x, TABLE_CELL_HEIGHT)
		if row_index == 0:
			draw_rect(row_rect, NotLightTheme.semantic_color("accent_soft"), true)
		else:
			draw_rect(row_rect, NotLightTheme.semantic_color("surface"), true)
		var values: PackedStringArray = _row_values(rows[row_index])
		for column: int in range(column_count):
			var cell_x: float = rect.position.x + cell_width * float(column)
			draw_rect(Rect2(cell_x, y, cell_width, TABLE_CELL_HEIGHT), NotLightTheme.semantic_color("border"), false, 1.0)
			if column < values.size():
				draw_string(_font, Vector2(cell_x + 6.0, y + 16.0), values[column], HORIZONTAL_ALIGNMENT_LEFT, maxf(1.0, cell_width - 12.0), META_FONT_SIZE, NotLightTheme.semantic_color("text"))
		y += TABLE_CELL_HEIGHT
	return y


func _row_values(raw_row: Variant) -> PackedStringArray:
	if raw_row is PackedStringArray:
		return raw_row as PackedStringArray
	var output: PackedStringArray = PackedStringArray()
	if raw_row is Array:
		for raw_value: Variant in raw_row as Array:
			output.append(str(raw_value))
	return output


func _draw_wrapped_text(
	text: String,
	position: Vector2,
	width: float,
	bottom: float,
	font_size: int,
	color: Color,
	strong: bool = false
) -> float:
	if text.is_empty() or width <= 1.0:
		return position.y
	var lines: PackedStringArray = _wrap_text(text, width, font_size)
	var line_height: float = float(font_size) * (1.32 if strong else 1.38)
	var y: float = position.y
	for line: String in lines:
		if y + line_height > bottom:
			break
		draw_string(_font, Vector2(position.x, y + float(font_size)), line, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, color)
		y += line_height
	return y


func _estimate_wrapped_height(text: String, width: float, font_size: int) -> float:
	return float(maxi(1, _wrap_text(text, width, font_size).size())) * float(font_size) * 1.38


func _wrap_text(text: String, width: float, font_size: int) -> PackedStringArray:
	var output: PackedStringArray = PackedStringArray()
	var source_lines: PackedStringArray = text.replace("\r", "").split("\n", true)
	for source_line: String in source_lines:
		if source_line.is_empty():
			output.append("")
			continue
		var words: PackedStringArray = source_line.split(" ", false)
		var current: String = ""
		for word: String in words:
			var candidate: String = word if current.is_empty() else current + " " + word
			if _font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x <= width or current.is_empty():
				current = candidate
			else:
				output.append(current)
				current = word
		if not current.is_empty():
			output.append(current)
	return output
