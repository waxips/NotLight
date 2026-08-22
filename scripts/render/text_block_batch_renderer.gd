# SPDX-License-Identifier: GPL-3.0-or-later
class_name TextBlockBatchRenderer
extends Node2D

signal plan_applied(rect_count: int, text_count: int)

var _multimesh_instance: MultiMeshInstance2D
var _multimesh: MultiMesh
var _font_registry: TextFontRegistry = TextFontRegistry.new()
var _entity_ids: PackedInt64Array = PackedInt64Array()
var _rect_values: PackedFloat32Array = PackedFloat32Array()
var _background_colors: PackedColorArray = PackedColorArray()
var _text_entity_ids: PackedInt64Array = PackedInt64Array()
var _text_rects: PackedFloat32Array = PackedFloat32Array()
var _text_font_sizes: PackedFloat32Array = PackedFloat32Array()
var _text_font_families: PackedStringArray = PackedStringArray()
var _text_alignments: PackedInt32Array = PackedInt32Array()
var _text_colors: PackedColorArray = PackedColorArray()
var _text_base_style_flags: PackedInt32Array = PackedInt32Array()
var _text_run_offsets: PackedInt32Array = PackedInt32Array()
var _text_run_counts: PackedInt32Array = PackedInt32Array()
var _run_starts: PackedInt32Array = PackedInt32Array()
var _run_lengths: PackedInt32Array = PackedInt32Array()
var _run_flags: PackedInt32Array = PackedInt32Array()
var _run_colors: PackedColorArray = PackedColorArray()
var _line_offsets: PackedInt32Array = PackedInt32Array()
var _line_counts: PackedInt32Array = PackedInt32Array()
var _lines: PackedStringArray = PackedStringArray()
var _line_starts: PackedInt32Array = PackedInt32Array()
var _line_lengths: PackedInt32Array = PackedInt32Array()
var _line_prefixes: PackedStringArray = PackedStringArray()
var _line_indents: PackedFloat32Array = PackedFloat32Array()
var _text_index_by_entity_id: Dictionary = {}
var _block_index_by_entity_id: Dictionary = {}
var _background_style_cache: Dictionary = {}
var _hidden_entity_ids: Dictionary = {}
var _rect_count: int = 0
var _text_count: int = 0
var _lod: int = int(BoardRenderPolicy.LodLevel.FULL)


func _ready() -> void:
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = true
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2.ONE
	_multimesh.mesh = mesh
	_multimesh_instance = MultiMeshInstance2D.new()
	_multimesh_instance.name = "TextBlockBackgrounds"
	_multimesh_instance.multimesh = _multimesh
	_multimesh_instance.show_behind_parent = true
	var image: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_multimesh_instance.texture = ImageTexture.create_from_image(image)
	var background_shader: Shader = load("res://assets/shaders/text_block_background.gdshader") as Shader
	if background_shader != null:
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = background_shader
		_multimesh_instance.material = material
	else:
		push_warning(NotLightL10n.text("runtime.render.text_shader_fallback"))
	add_child(_multimesh_instance)


func apply_plan(plan: Dictionary) -> void:
	_entity_ids = (plan.get("entity_ids", PackedInt64Array()) as PackedInt64Array).duplicate()
	_rect_values = (plan.get("rect_values", PackedFloat32Array()) as PackedFloat32Array).duplicate()
	_background_colors = (plan.get("background_colors", PackedColorArray()) as PackedColorArray).duplicate()
	_rect_count = mini(int(plan.get("rect_count", 0)), _entity_ids.size())
	_lod = int(plan.get("lod", int(BoardRenderPolicy.LodLevel.FULL)))
	var use_retained_full_render: bool = _lod <= int(BoardRenderPolicy.LodLevel.MEDIUM)
	_multimesh_instance.visible = not use_retained_full_render
	if use_retained_full_render:
		_multimesh.visible_instance_count = 0
	else:
		_update_backgrounds(_rect_values, _background_colors, _rect_count)
		_apply_multimesh_hidden_colors()

	_text_entity_ids = (plan.get("text_entity_ids", PackedInt64Array()) as PackedInt64Array).duplicate()
	_text_rects = (plan.get("text_rects", PackedFloat32Array()) as PackedFloat32Array).duplicate()
	_text_font_sizes = (plan.get("text_font_sizes", PackedFloat32Array()) as PackedFloat32Array).duplicate()
	_text_font_families = (plan.get("text_font_families", PackedStringArray()) as PackedStringArray).duplicate()
	_text_alignments = (plan.get("text_alignments", PackedInt32Array()) as PackedInt32Array).duplicate()
	_text_colors = (plan.get("text_colors", PackedColorArray()) as PackedColorArray).duplicate()
	_text_base_style_flags = (plan.get("text_base_style_flags", PackedInt32Array()) as PackedInt32Array).duplicate()
	_text_run_offsets = (plan.get("text_run_offsets", PackedInt32Array()) as PackedInt32Array).duplicate()
	_text_run_counts = (plan.get("text_run_counts", PackedInt32Array()) as PackedInt32Array).duplicate()
	_run_starts = (plan.get("run_starts", PackedInt32Array()) as PackedInt32Array).duplicate()
	_run_lengths = (plan.get("run_lengths", PackedInt32Array()) as PackedInt32Array).duplicate()
	_run_flags = (plan.get("run_flags", PackedInt32Array()) as PackedInt32Array).duplicate()
	_run_colors = (plan.get("run_colors", PackedColorArray()) as PackedColorArray).duplicate()
	_line_offsets = (plan.get("line_offsets", PackedInt32Array()) as PackedInt32Array).duplicate()
	_line_counts = (plan.get("line_counts", PackedInt32Array()) as PackedInt32Array).duplicate()
	_lines = (plan.get("lines", PackedStringArray()) as PackedStringArray).duplicate()
	_line_starts = (plan.get("line_starts", PackedInt32Array()) as PackedInt32Array).duplicate()
	_line_lengths = (plan.get("line_lengths", PackedInt32Array()) as PackedInt32Array).duplicate()
	_line_prefixes = (plan.get("line_prefixes", PackedStringArray()) as PackedStringArray).duplicate()
	_line_indents = (plan.get("line_indents", PackedFloat32Array()) as PackedFloat32Array).duplicate()
	_text_count = mini(int(plan.get("text_count", 0)), _text_entity_ids.size())
	_rebuild_block_lookup()
	_rebuild_text_lookup()
	queue_redraw()
	plan_applied.emit(_rect_count, _text_count)


func set_hidden_entity_ids(hidden_ids: Dictionary) -> void:
	_hidden_entity_ids = hidden_ids.duplicate()
	_apply_multimesh_hidden_colors()
	queue_redraw()


func clear() -> void:
	if _multimesh != null:
		_multimesh.instance_count = 0
		_multimesh.visible_instance_count = 0
	if _multimesh_instance != null:
		_multimesh_instance.visible = false
	_entity_ids = PackedInt64Array()
	_rect_values = PackedFloat32Array()
	_background_colors = PackedColorArray()
	_text_entity_ids = PackedInt64Array()
	_text_rects = PackedFloat32Array()
	_text_font_sizes = PackedFloat32Array()
	_text_font_families = PackedStringArray()
	_text_alignments = PackedInt32Array()
	_text_colors = PackedColorArray()
	_text_base_style_flags = PackedInt32Array()
	_text_run_offsets = PackedInt32Array()
	_text_run_counts = PackedInt32Array()
	_run_starts = PackedInt32Array()
	_run_lengths = PackedInt32Array()
	_run_flags = PackedInt32Array()
	_run_colors = PackedColorArray()
	_line_offsets = PackedInt32Array()
	_line_counts = PackedInt32Array()
	_lines = PackedStringArray()
	_line_starts = PackedInt32Array()
	_line_lengths = PackedInt32Array()
	_line_prefixes = PackedStringArray()
	_line_indents = PackedFloat32Array()
	_text_index_by_entity_id.clear()
	_block_index_by_entity_id.clear()
	_rect_count = 0
	_text_count = 0
	queue_redraw()


func _update_backgrounds(
	rect_values: PackedFloat32Array,
	background_colors: PackedColorArray,
	count: int
) -> void:
	if count <= 0:
		_multimesh.instance_count = 0
		_multimesh.visible_instance_count = 0
		return
	if _multimesh.instance_count != count:
		_multimesh.visible_instance_count = 0
		_multimesh.instance_count = count
	_multimesh.visible_instance_count = count
	for index: int in range(count):
		var rect_index: int = index * 4
		if rect_index + 3 >= rect_values.size():
			continue
		var rect: Rect2 = Rect2(
			Vector2(rect_values[rect_index], rect_values[rect_index + 1]),
			Vector2(rect_values[rect_index + 2], rect_values[rect_index + 3])
		)
		var transform: Transform2D = Transform2D.IDENTITY
		transform.x = Vector2(rect.size.x, 0.0)
		transform.y = Vector2(0.0, rect.size.y)
		transform.origin = rect.position + rect.size * 0.5
		_multimesh.set_instance_transform_2d(index, transform)
		var color: Color = background_colors[index] if index < background_colors.size() else Color.TRANSPARENT
		_multimesh.set_instance_color(index, color)
		_multimesh.set_instance_custom_data(index, Color(rect.size.x, rect.size.y, 0.0, 0.0))


func _apply_multimesh_hidden_colors() -> void:
	if _multimesh == null or _lod <= int(BoardRenderPolicy.LodLevel.MEDIUM):
		return
	var count: int = mini(_rect_count, _entity_ids.size())
	for index: int in range(count):
		var color: Color = _background_colors[index] if index < _background_colors.size() else Color.TRANSPARENT
		if _hidden_entity_ids.has(int(_entity_ids[index])):
			color = Color.TRANSPARENT
		_multimesh.set_instance_color(index, color)


func _rebuild_block_lookup() -> void:
	_block_index_by_entity_id.clear()
	for index: int in range(_rect_count):
		_block_index_by_entity_id[int(_entity_ids[index])] = index


func _rebuild_text_lookup() -> void:
	_text_index_by_entity_id.clear()
	for index: int in range(_text_count):
		_text_index_by_entity_id[int(_text_entity_ids[index])] = index


func _draw() -> void:
	if _lod <= int(BoardRenderPolicy.LodLevel.MEDIUM):
		_draw_full_blocks_in_z_order()
	else:
		_draw_text_previews()


func _draw_full_blocks_in_z_order() -> void:
	for block_index: int in range(_rect_count):
		var entity_id: int = int(_entity_ids[block_index])
		if _hidden_entity_ids.has(entity_id):
			continue
		var rect: Rect2 = _rect_at(_rect_values, block_index)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var background: Color = _background_colors[block_index] if block_index < _background_colors.size() else Color.TRANSPARENT
		if background.a > 0.001:
			draw_style_box(_style_for_background(background), rect)
		var text_index: int = int(_text_index_by_entity_id.get(entity_id, -1))
		if text_index >= 0:
			_draw_text_at_index(text_index, rect, background)


func _draw_text_previews() -> void:
	for text_index: int in range(_text_count):
		var entity_id: int = int(_text_entity_ids[text_index])
		if _hidden_entity_ids.has(entity_id):
			continue
		var rect: Rect2 = _rect_at(_text_rects, text_index)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var block_index: int = _find_block_index(entity_id)
		var background: Color = _background_colors[block_index] if block_index >= 0 and block_index < _background_colors.size() else Color.TRANSPARENT
		_draw_text_at_index(text_index, rect, background)


func _draw_text_at_index(text_index: int, rect: Rect2, background: Color) -> void:
	var font_size: float = _text_font_sizes[text_index] if text_index < _text_font_sizes.size() else TextBlockStore.DEFAULT_FONT_SIZE
	var font_size_int: int = clampi(int(round(font_size)), 8, 512)
	var family: String = _text_font_families[text_index] if text_index < _text_font_families.size() else TextBlockStore.DEFAULT_FONT_FAMILY
	var alignment: HorizontalAlignment = (int(_text_alignments[text_index]) as HorizontalAlignment) if text_index < _text_alignments.size() else HORIZONTAL_ALIGNMENT_LEFT
	var base_color: Color = _text_colors[text_index] if text_index < _text_colors.size() else TextBlockStore.COLOR_TEXT
	var base_flags: int = int(_text_base_style_flags[text_index]) if text_index < _text_base_style_flags.size() else 0
	var line_offset: int = int(_line_offsets[text_index]) if text_index < _line_offsets.size() else 0
	var line_count: int = int(_line_counts[text_index]) if text_index < _line_counts.size() else 0
	var padding: Vector2 = TextLayoutUtils.padding_for_background(background)
	var draw_width: float = maxf(1.0, rect.size.x - padding.x * 2.0)
	var baseline_y: float = rect.position.y + padding.y + font_size
	for local_line_index: int in range(line_count):
		var line_index: int = line_offset + local_line_index
		if line_index < 0 or line_index >= _lines.size():
			continue
		var line_text: String = _lines[line_index]
		var line_start: int = int(_line_starts[line_index]) if line_index < _line_starts.size() else 0
		var line_length: int = int(_line_lengths[line_index]) if line_index < _line_lengths.size() else line_text.length()
		var prefix: String = _line_prefixes[line_index] if line_index < _line_prefixes.size() else ""
		var indent: float = float(_line_indents[line_index]) if line_index < _line_indents.size() else 0.0
		var spans: Array[Dictionary] = _line_spans(text_index, line_text, line_start, line_length, base_flags, base_color)
		var content_width: float = _measure_spans(spans, family, font_size_int)
		var prefix_flags: int = base_flags
		var prefix_color: Color = base_color
		if not spans.is_empty():
			prefix_flags = int(spans[0].get("flags", base_flags))
			prefix_color = spans[0].get("color", base_color) as Color
		var prefix_font: Font = _font_registry.get_font(family, prefix_flags)
		var prefix_width: float = 0.0
		var marker_gap: float = 0.0
		if not prefix.is_empty():
			prefix_width = prefix_font.get_string_size(prefix, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size_int).x
			marker_gap = font_size * TextLayoutUtils.LIST_MARKER_GAP_FACTOR
		var base_indent: float = maxf(0.0, indent - prefix_width - marker_gap) if not prefix.is_empty() else indent
		var group_width: float = base_indent + prefix_width + marker_gap + content_width if not prefix.is_empty() else indent + content_width
		var align_offset: float = _alignment_offset(alignment, draw_width, group_width)
		var line_x: float = rect.position.x + padding.x + align_offset + base_indent
		if not prefix.is_empty():
			draw_string(prefix_font, Vector2(line_x, baseline_y), prefix, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size_int, prefix_color)
			line_x += prefix_width + marker_gap
		else:
			line_x += maxf(0.0, indent - base_indent)
		_draw_spans(spans, family, font_size_int, Vector2(line_x, baseline_y))
		baseline_y += TextLayoutUtils.line_height(font_size)


func _line_spans(
	text_index: int,
	line_text: String,
	line_start: int,
	line_length: int,
	base_flags: int,
	base_color: Color
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if line_text.is_empty():
		return result
	var source_length: int = mini(line_length, line_text.length())
	var line_end: int = line_start + source_length
	var cursor: int = line_start
	var run_offset: int = int(_text_run_offsets[text_index]) if text_index < _text_run_offsets.size() else 0
	var run_count: int = int(_text_run_counts[text_index]) if text_index < _text_run_counts.size() else 0
	for local_run_index: int in range(run_count):
		var run_index: int = run_offset + local_run_index
		if run_index < 0 or run_index >= _run_starts.size():
			continue
		var run_start: int = int(_run_starts[run_index])
		var run_end: int = run_start + int(_run_lengths[run_index])
		if run_end <= line_start or run_start >= line_end:
			continue
		var segment_start: int = maxi(cursor, maxi(line_start, run_start))
		if segment_start > cursor:
			_append_span(result, line_text.substr(cursor - line_start, segment_start - cursor), base_flags, base_color)
		var segment_end: int = mini(line_end, run_end)
		if segment_end > segment_start:
			_append_span(
				result,
				line_text.substr(segment_start - line_start, segment_end - segment_start),
				int(_run_flags[run_index]) if run_index < _run_flags.size() else base_flags,
				_run_colors[run_index] if run_index < _run_colors.size() else base_color
			)
			cursor = segment_end
	if cursor < line_end:
		_append_span(result, line_text.substr(cursor - line_start, line_end - cursor), base_flags, base_color)
	if line_text.length() > source_length:
		var suffix: String = line_text.substr(source_length)
		var flags: int = int(result[result.size() - 1].get("flags", base_flags)) if not result.is_empty() else base_flags
		var color: Color = base_color
		if not result.is_empty():
			color = result[result.size() - 1].get("color", base_color) as Color
		_append_span(result, suffix, flags, color)
	if result.is_empty():
		_append_span(result, line_text, base_flags, base_color)
	return result


func _append_span(result: Array[Dictionary], text: String, flags: int, color: Color) -> void:
	if text.is_empty():
		return
	if not result.is_empty():
		var previous: Dictionary = result[result.size() - 1]
		if int(previous.get("flags", 0)) == flags and (previous.get("color", Color.WHITE) as Color) == color:
			previous["text"] = str(previous.get("text", "")) + text
			return
	result.append({"text": text, "flags": flags, "color": color})


func _measure_spans(spans: Array[Dictionary], family: String, font_size: int) -> float:
	var width: float = 0.0
	for span: Dictionary in spans:
		var font: Font = _font_registry.get_font(family, int(span.get("flags", 0)))
		width += font.get_string_size(str(span.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	return width


func _draw_spans(spans: Array[Dictionary], family: String, font_size: int, start_position: Vector2) -> void:
	var x: float = start_position.x
	for span: Dictionary in spans:
		var text: String = str(span.get("text", ""))
		if text.is_empty():
			continue
		var flags: int = int(span.get("flags", 0))
		var color: Color = span.get("color", TextBlockStore.COLOR_TEXT) as Color
		var font: Font = _font_registry.get_font(family, flags)
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		draw_string(font, Vector2(x, start_position.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
		if (flags & TextBlockStore.FONT_STYLE_UNDERLINE) != 0:
			var underline_y: float = start_position.y + font.get_underline_position(font_size)
			var underline_width: float = maxf(1.0, font.get_underline_thickness(font_size))
			draw_line(Vector2(x, underline_y), Vector2(x + width, underline_y), color, underline_width, true)
		if (flags & TextBlockStore.FONT_STYLE_STRIKETHROUGH) != 0:
			var strike_y: float = start_position.y - font.get_ascent(font_size) * 0.34
			var strike_width: float = maxf(1.0, font.get_underline_thickness(font_size))
			draw_line(Vector2(x, strike_y), Vector2(x + width, strike_y), color, strike_width, true)
		x += width


func _alignment_offset(alignment: HorizontalAlignment, available_width: float, content_width: float) -> float:
	match alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			return maxf(0.0, (available_width - content_width) * 0.5)
		HORIZONTAL_ALIGNMENT_RIGHT:
			return maxf(0.0, available_width - content_width)
		_:
			return 0.0


func _find_block_index(entity_id: int) -> int:
	return int(_block_index_by_entity_id.get(entity_id, -1))


func _rect_at(values: PackedFloat32Array, index: int) -> Rect2:
	var rect_index: int = index * 4
	if rect_index + 3 >= values.size():
		return Rect2()
	return Rect2(
		Vector2(values[rect_index], values[rect_index + 1]),
		Vector2(values[rect_index + 2], values[rect_index + 3])
	)


func _style_for_background(background: Color) -> StyleBoxFlat:
	var key: String = background.to_html(true)
	var existing: Variant = _background_style_cache.get(key)
	if existing is StyleBoxFlat:
		return existing as StyleBoxFlat
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = background.darkened(0.14)
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	_background_style_cache[key] = style
	return style
