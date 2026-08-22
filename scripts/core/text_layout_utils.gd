# SPDX-License-Identifier: GPL-3.0-or-later
class_name TextLayoutUtils
extends RefCounted

# The layout module deliberately stays independent from Font/TextServer resources so it can
# run inside TextBlockRenderWorker. Widths are conservative estimates; the main-thread
# renderer uses the actual SystemFont for glyph drawing.
const PLAIN_PADDING: Vector2 = Vector2(3.0, 2.0)
const BACKGROUND_PADDING: Vector2 = Vector2(14.0, 10.0)
const AVERAGE_GLYPH_WIDTH_FACTOR: float = 0.54
const SPACE_WIDTH_FACTOR: float = 0.30
const NARROW_GLYPH_FACTOR: float = 0.30
const WIDE_GLYPH_FACTOR: float = 0.78
const BOLD_WIDTH_FACTOR: float = 1.035
const ITALIC_WIDTH_FACTOR: float = 1.012
const LINE_HEIGHT_FACTOR: float = 1.14
const LIST_MARKER_GAP_FACTOR: float = 0.48
const LIST_INDENT_FACTOR: float = 1.25
const DEFAULT_MAXIMUM_LINES: int = 256
const AUTO_WIDTH_LIMIT: float = 760.0
const DEFAULT_MINIMUM_SIZE: Vector2 = Vector2(40.0, 28.0)


static func padding_for_background(background: Color) -> Vector2:
	return BACKGROUND_PADDING if background.a > 0.001 else PLAIN_PADDING


static func padding_for_record(record: Dictionary) -> Vector2:
	return padding_for_background(_color_from_variant(record.get("background_color", ""), Color.TRANSPARENT))


static func padding_for_style(style_id: int) -> Vector2:
	# Stage 3.2 compatibility only. Stage 3.3 represents sticky-like appearance as
	# background styling rather than an object mode.
	return PLAIN_PADDING if style_id == TextBlockStore.STYLE_PLAIN else BACKGROUND_PADDING


static func line_height(font_size: float) -> float:
	return maxf(1.0, font_size * LINE_HEIGHT_FACTOR)


static func available_text_width(total_width: float, style_id: int) -> float:
	var padding: Vector2 = padding_for_style(style_id)
	return maxf(8.0, total_width - padding.x * 2.0)


static func available_text_width_for_record(total_width: float, record: Dictionary) -> float:
	var padding: Vector2 = padding_for_record(record)
	return maxf(8.0, total_width - padding.x * 2.0)


static func estimate_text_width(source: String, font_size: float, style_flags: int = 0) -> float:
	var width: float = 0.0
	for index: int in range(source.length()):
		width += _estimated_character_width(source.substr(index, 1), font_size, style_flags)
	return width


static func estimate_rich_range_width(
	text: String,
	start: int,
	length: int,
	font_size: float,
	style_runs: Array,
	base_style_flags: int = 0
) -> float:
	var safe_start: int = clampi(start, 0, text.length())
	var safe_end: int = clampi(safe_start + maxi(0, length), safe_start, text.length())
	if safe_start >= safe_end:
		return 0.0
	var width: float = 0.0
	var cursor: int = safe_start
	for raw_run: Variant in style_runs:
		if raw_run is not Dictionary:
			continue
		var run: Dictionary = raw_run as Dictionary
		var run_start: int = int(run.get("start", 0))
		var run_end: int = run_start + maxi(0, int(run.get("length", 0)))
		if run_end <= safe_start:
			continue
		if run_start >= safe_end:
			break
		var segment_start: int = maxi(cursor, maxi(safe_start, run_start))
		if segment_start > cursor:
			width += estimate_text_width(text.substr(cursor, segment_start - cursor), font_size, base_style_flags)
		var segment_end: int = mini(safe_end, run_end)
		if segment_end > segment_start:
			width += estimate_text_width(
				text.substr(segment_start, segment_end - segment_start),
				font_size,
				int(run.get("flags", base_style_flags))
			)
			cursor = segment_end
		if cursor >= safe_end:
			break
	if cursor < safe_end:
		width += estimate_text_width(text.substr(cursor, safe_end - cursor), font_size, base_style_flags)
	return width


static func list_indent_width(font_size: float, indent: int) -> float:
	return float(clampi(indent, 0, TextBlockStore.MAX_LIST_INDENT)) * font_size * LIST_INDENT_FACTOR


static func list_marker(paragraph_index: int, paragraphs: Array) -> String:
	if paragraph_index < 0 or paragraph_index >= paragraphs.size() or paragraphs[paragraph_index] is not Dictionary:
		return ""
	var paragraph: Dictionary = paragraphs[paragraph_index] as Dictionary
	var list_type: int = int(paragraph.get("list_type", TextBlockStore.LIST_NONE))
	if list_type == TextBlockStore.LIST_BULLET:
		return "•"
	if list_type == TextBlockStore.LIST_NUMBERED:
		return NotLightL10n.text("ui.format.numbered_list_marker") % _number_for_paragraph(paragraph_index, paragraphs)
	return ""


static func wrap_text(
	text: String,
	available_width: float,
	font_size: float,
	maximum_lines: int = DEFAULT_MAXIMUM_LINES
) -> PackedStringArray:
	var rich: Dictionary = wrap_text_rich(text, available_width, font_size, [], maximum_lines, [], 0)
	return rich.get("lines", PackedStringArray()) as PackedStringArray


static func wrap_text_rich(
	text: String,
	available_width: float,
	font_size: float,
	paragraphs: Array,
	maximum_lines: int = DEFAULT_MAXIMUM_LINES,
	style_runs: Array = [],
	base_style_flags: int = 0
) -> Dictionary:
	var safe_text: String = text.replace("\r", "")
	var safe_width: float = maxf(8.0, available_width)
	var safe_maximum_lines: int = maxi(1, maximum_lines)
	var normalized_paragraphs: Array = _normalized_paragraphs(safe_text, paragraphs)
	var lines: PackedStringArray = PackedStringArray()
	var starts: PackedInt32Array = PackedInt32Array()
	var lengths: PackedInt32Array = PackedInt32Array()
	var prefixes: PackedStringArray = PackedStringArray()
	var indents: PackedFloat32Array = PackedFloat32Array()
	var paragraph_indices: PackedInt32Array = PackedInt32Array()
	var paragraph_strings: PackedStringArray = safe_text.split("\n", true)
	var global_offset: int = 0
	var truncated: bool = false

	for paragraph_index: int in range(paragraph_strings.size()):
		if lines.size() >= safe_maximum_lines:
			truncated = true
			break
		var paragraph_text: String = paragraph_strings[paragraph_index]
		var paragraph_meta: Dictionary = normalized_paragraphs[paragraph_index] as Dictionary
		var indent_level: int = int(paragraph_meta.get("indent", 0))
		var marker: String = list_marker(paragraph_index, normalized_paragraphs)
		var base_indent: float = list_indent_width(font_size, indent_level)
		var marker_space: float = 0.0
		if not marker.is_empty():
			marker_space = estimate_text_width(marker, font_size, base_style_flags) + font_size * LIST_MARKER_GAP_FACTOR
		var content_indent: float = base_indent + marker_space
		var paragraph_width: float = maxf(8.0, safe_width - content_indent)
		var paragraph_ranges: Array[Vector2i] = _wrap_paragraph_ranges(
			paragraph_text,
			global_offset,
			paragraph_width,
			font_size,
			safe_maximum_lines - lines.size(),
			style_runs,
			base_style_flags
		)
		if paragraph_ranges.is_empty():
			paragraph_ranges.append(Vector2i(0, 0))
		for local_line_index: int in range(paragraph_ranges.size()):
			if lines.size() >= safe_maximum_lines:
				truncated = true
				break
			var character_range: Vector2i = paragraph_ranges[local_line_index]
			var line_text: String = paragraph_text.substr(character_range.x, character_range.y)
			lines.append(line_text)
			starts.append(global_offset + character_range.x)
			lengths.append(character_range.y)
			prefixes.append(marker if local_line_index == 0 else "")
			indents.append(content_indent)
			paragraph_indices.append(paragraph_index)
		global_offset += paragraph_text.length()
		if paragraph_index < paragraph_strings.size() - 1:
			global_offset += 1
		if truncated:
			break

	if lines.is_empty():
		lines.append("")
		starts.append(0)
		lengths.append(0)
		prefixes.append("")
		indents.append(0.0)
		paragraph_indices.append(0)

	if truncated and not lines.is_empty():
		var last_index: int = lines.size() - 1
		var last_line: String = lines[last_index].trim_suffix("…")
		var line_indent: float = float(indents[last_index])
		var source_start: int = int(starts[last_index])
		while (
			last_line.length() > 1
			and estimate_rich_range_width(safe_text, source_start, last_line.length(), font_size, style_runs, base_style_flags)
				+ estimate_text_width("…", font_size, base_style_flags)
				> maxf(8.0, safe_width - line_indent)
		):
			last_line = last_line.left(last_line.length() - 1)
		lines[last_index] = last_line + "…"
		lengths[last_index] = mini(int(lengths[last_index]), last_line.length())

	return {
		"lines": lines,
		"starts": starts,
		"lengths": lengths,
		"prefixes": prefixes,
		"indents": indents,
		"paragraph_indices": paragraph_indices,
		"paragraphs": normalized_paragraphs,
		"truncated": truncated,
	}


static func fitted_height(
	text: String,
	width: float,
	font_size: float,
	style_id: int,
	minimum_height: float = 0.0
) -> float:
	var record: Dictionary = {
		"text": text,
		"font_size": font_size,
		"style_id": style_id,
		"background_color": TextBlockStore.default_background_for_style(style_id).to_html(true),
		"paragraphs": [],
		"style_runs": [],
		"base_style_flags": 0,
	}
	return fitted_height_for_record(record, width, minimum_height)


static func fitted_height_for_record(record: Dictionary, width: float, minimum_height: float = 0.0) -> float:
	var font_size: float = clampf(
		float(record.get("font_size", TextBlockStore.DEFAULT_FONT_SIZE)),
		TextBlockStore.MIN_FONT_SIZE,
		TextBlockStore.MAX_FONT_SIZE
	)
	var padding: Vector2 = padding_for_record(record)
	var wrapped: Dictionary = wrap_text_rich(
		str(record.get("text", "")),
		maxf(8.0, width - padding.x * 2.0),
		font_size,
		record.get("paragraphs", []) as Array,
		DEFAULT_MAXIMUM_LINES,
		record.get("style_runs", []) as Array,
		int(record.get("base_style_flags", 0))
	)
	var lines: PackedStringArray = wrapped.get("lines", PackedStringArray()) as PackedStringArray
	var text_height: float = float(maxi(lines.size(), 1)) * line_height(font_size)
	return maxf(minimum_height, ceilf(text_height + padding.y * 2.0))


static func natural_width(
	text: String,
	font_size: float,
	style_id: int,
	minimum_width: float,
	maximum_width: float = AUTO_WIDTH_LIMIT
) -> float:
	var record: Dictionary = {
		"text": text,
		"font_size": font_size,
		"style_id": style_id,
		"background_color": TextBlockStore.default_background_for_style(style_id).to_html(true),
		"paragraphs": [],
		"style_runs": [],
		"base_style_flags": 0,
	}
	return natural_width_for_record(record, minimum_width, maximum_width)


static func natural_width_for_record(
	record: Dictionary,
	minimum_width: float,
	maximum_width: float = AUTO_WIDTH_LIMIT
) -> float:
	var text: String = str(record.get("text", "")).replace("\r", "")
	var font_size: float = clampf(
		float(record.get("font_size", TextBlockStore.DEFAULT_FONT_SIZE)),
		TextBlockStore.MIN_FONT_SIZE,
		TextBlockStore.MAX_FONT_SIZE
	)
	var base_flags: int = int(record.get("base_style_flags", 0))
	var style_runs: Array = record.get("style_runs", []) as Array
	var paragraphs: Array = _normalized_paragraphs(text, record.get("paragraphs", []) as Array)
	var padding: Vector2 = padding_for_record(record)
	var widest: float = 0.0
	var paragraph_strings: PackedStringArray = text.split("\n", true)
	var global_offset: int = 0
	for index: int in range(paragraph_strings.size()):
		var paragraph: Dictionary = paragraphs[index] as Dictionary
		var marker: String = list_marker(index, paragraphs)
		var indent_width: float = list_indent_width(font_size, int(paragraph.get("indent", 0)))
		if not marker.is_empty():
			indent_width += estimate_text_width(marker, font_size, base_flags) + font_size * LIST_MARKER_GAP_FACTOR
		var paragraph_text: String = paragraph_strings[index]
		widest = maxf(
			widest,
			indent_width + estimate_rich_range_width(
				text,
				global_offset,
				paragraph_text.length(),
				font_size,
				style_runs,
				base_flags
			)
		)
		global_offset += paragraph_text.length()
		if index < paragraph_strings.size() - 1:
			global_offset += 1
	if text.is_empty():
		widest = font_size * 4.0
	return clampf(ceilf(widest + padding.x * 2.0), minimum_width, maxf(minimum_width, maximum_width))


static func fitted_size(
	text: String,
	current_width: float,
	font_size: float,
	style_id: int,
	layout_mode: int,
	minimum_size: Vector2
) -> Vector2:
	var record: Dictionary = {
		"text": text,
		"font_size": font_size,
		"style_id": style_id,
		"layout_mode": layout_mode,
		"background_color": TextBlockStore.default_background_for_style(style_id).to_html(true),
		"paragraphs": [],
		"style_runs": [],
		"base_style_flags": 0,
	}
	return fitted_size_for_record(record, current_width, minimum_size)


static func fitted_size_for_record(record: Dictionary, current_width: float, minimum_size: Vector2) -> Vector2:
	var width: float = maxf(current_width, minimum_size.x)
	var layout_mode: int = int(record.get("layout_mode", TextBlockStore.LAYOUT_AUTO_WIDTH))
	if layout_mode == TextBlockStore.LAYOUT_AUTO_WIDTH:
		width = natural_width_for_record(record, minimum_size.x)
	var height: float = fitted_height_for_record(record, width, minimum_size.y)
	return Vector2(width, height)


static func fit_bounds_to_content(
	bounds: Rect2,
	text: String,
	font_size: float,
	style_id: int,
	layout_mode: int,
	minimum_size: Vector2 = DEFAULT_MINIMUM_SIZE
) -> Rect2:
	var record: Dictionary = {
		"text": text,
		"font_size": font_size,
		"style_id": style_id,
		"layout_mode": layout_mode,
		"background_color": TextBlockStore.default_background_for_style(style_id).to_html(true),
		"paragraphs": [],
		"style_runs": [],
		"base_style_flags": 0,
	}
	return fit_record_bounds(bounds, record, minimum_size)


static func fit_record_bounds(
	bounds: Rect2,
	record: Dictionary,
	minimum_size: Vector2 = DEFAULT_MINIMUM_SIZE
) -> Rect2:
	var fitted: Rect2 = bounds
	fitted.size = fitted_size_for_record(record, fitted.size.x, minimum_size)
	return fitted


static func fit_bounds_height(
	bounds: Rect2,
	text: String,
	font_size: float,
	style_id: int,
	minimum_height: float = 0.0
) -> Rect2:
	var record: Dictionary = {
		"text": text,
		"font_size": font_size,
		"style_id": style_id,
		"background_color": TextBlockStore.default_background_for_style(style_id).to_html(true),
		"paragraphs": [],
		"style_runs": [],
		"base_style_flags": 0,
	}
	var fitted: Rect2 = bounds
	fitted.size.y = fitted_height_for_record(record, fitted.size.x, minimum_height)
	return fitted


static func paragraph_indices_for_character_range(text: String, start: int, end: int) -> PackedInt32Array:
	var safe_start: int = clampi(mini(start, end), 0, text.length())
	var safe_end: int = clampi(maxi(start, end), 0, text.length())
	var first: int = TextBlockStore.paragraph_index_for_offset(text, safe_start)
	var last_offset: int = safe_end
	if safe_end > safe_start:
		last_offset = safe_end - 1
	var last: int = TextBlockStore.paragraph_index_for_offset(text, last_offset)
	var result: PackedInt32Array = PackedInt32Array()
	for paragraph_index: int in range(first, last + 1):
		result.append(paragraph_index)
	return result


static func _wrap_paragraph_ranges(
	paragraph: String,
	global_offset: int,
	available_width: float,
	font_size: float,
	maximum_lines: int,
	style_runs: Array,
	base_style_flags: int
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if maximum_lines <= 0:
		return result
	if paragraph.is_empty():
		result.append(Vector2i(0, 0))
		return result
	var cursor: int = 0
	while cursor < paragraph.length() and result.size() < maximum_lines:
		while cursor < paragraph.length() and paragraph.substr(cursor, 1) == " ":
			cursor += 1
		if cursor >= paragraph.length():
			break
		var remaining_length: int = paragraph.length() - cursor
		if _estimate_paragraph_range_width(
			paragraph,
			cursor,
			remaining_length,
			global_offset,
			font_size,
			style_runs,
			base_style_flags
		) <= available_width:
			result.append(Vector2i(cursor, remaining_length))
			cursor = paragraph.length()
			break
		var fit_count: int = _maximum_prefix_that_fits_rich(
			paragraph,
			cursor,
			remaining_length,
			global_offset,
			available_width,
			font_size,
			style_runs,
			base_style_flags
		)
		fit_count = clampi(fit_count, 1, remaining_length)
		var split_count: int = fit_count
		for local_index: int in range(fit_count - 1, 0, -1):
			if paragraph.substr(cursor + local_index, 1) == " ":
				split_count = local_index
				break
		var line_length: int = maxi(1, split_count)
		while line_length > 0 and paragraph.substr(cursor + line_length - 1, 1) == " ":
			line_length -= 1
		if line_length <= 0:
			line_length = fit_count
		result.append(Vector2i(cursor, line_length))
		cursor += maxi(split_count, 1)
	if result.is_empty():
		result.append(Vector2i(0, 0))
	return result


static func _maximum_prefix_that_fits_rich(
	paragraph: String,
	paragraph_cursor: int,
	remaining_length: int,
	global_offset: int,
	available_width: float,
	font_size: float,
	style_runs: Array,
	base_style_flags: int
) -> int:
	var low: int = 1
	var high: int = maxi(1, remaining_length)
	var best: int = 1
	while low <= high:
		var middle: int = int((low + high) / 2)
		var width: float = _estimate_paragraph_range_width(
			paragraph,
			paragraph_cursor,
			middle,
			global_offset,
			font_size,
			style_runs,
			base_style_flags
		)
		if width <= available_width:
			best = middle
			low = middle + 1
		else:
			high = middle - 1
	return best


static func _estimate_paragraph_range_width(
	paragraph: String,
	paragraph_start: int,
	length: int,
	global_offset: int,
	font_size: float,
	style_runs: Array,
	base_style_flags: int
) -> float:
	var width: float = 0.0
	var safe_end: int = mini(paragraph.length(), paragraph_start + maxi(0, length))
	for local_index: int in range(paragraph_start, safe_end):
		var global_character_offset: int = global_offset + local_index
		var flags: int = _flags_at(style_runs, global_character_offset, base_style_flags)
		width += _estimated_character_width(paragraph.substr(local_index, 1), font_size, flags)
	return width


static func _flags_at(style_runs: Array, character_offset: int, fallback: int) -> int:
	for raw_run: Variant in style_runs:
		if raw_run is not Dictionary:
			continue
		var run: Dictionary = raw_run as Dictionary
		var start: int = int(run.get("start", 0))
		var finish: int = start + maxi(0, int(run.get("length", 0)))
		if character_offset >= start and character_offset < finish:
			return int(run.get("flags", fallback))
	return fallback


static func _number_for_paragraph(paragraph_index: int, paragraphs: Array) -> int:
	if paragraph_index < 0 or paragraph_index >= paragraphs.size() or paragraphs[paragraph_index] is not Dictionary:
		return 1
	var paragraph: Dictionary = paragraphs[paragraph_index] as Dictionary
	var indent: int = int(paragraph.get("indent", 0))
	var count: int = 1
	var index: int = paragraph_index - 1
	while index >= 0:
		if paragraphs[index] is not Dictionary:
			break
		var previous: Dictionary = paragraphs[index] as Dictionary
		var previous_type: int = int(previous.get("list_type", TextBlockStore.LIST_NONE))
		var previous_indent: int = int(previous.get("indent", 0))
		if previous_type != TextBlockStore.LIST_NUMBERED or previous_indent != indent:
			break
		count += 1
		index -= 1
	return count


static func _normalized_paragraphs(text: String, source: Array) -> Array:
	var count: int = TextBlockStore.paragraph_count_for_text(text.replace("\r", ""))
	var result: Array = []
	for index: int in range(count):
		var list_type: int = TextBlockStore.LIST_NONE
		var indent: int = 0
		if index < source.size() and source[index] is Dictionary:
			var paragraph: Dictionary = source[index] as Dictionary
			list_type = clampi(
				int(paragraph.get("list_type", TextBlockStore.LIST_NONE)),
				TextBlockStore.LIST_NONE,
				TextBlockStore.LIST_NUMBERED
			)
			indent = clampi(int(paragraph.get("indent", 0)), 0, TextBlockStore.MAX_LIST_INDENT)
		result.append({"list_type": list_type, "indent": indent})
	return result


static func _estimated_character_width(character: String, font_size: float, style_flags: int) -> float:
	var width: float
	if character == " " or character == "\t":
		width = font_size * SPACE_WIDTH_FACTOR
	elif character in "ilI.,'`!:;|":
		width = font_size * NARROW_GLYPH_FACTOR
	elif character in "MW@#%&ЖШЩЮЫ":
		width = font_size * WIDE_GLYPH_FACTOR
	else:
		width = font_size * AVERAGE_GLYPH_WIDTH_FACTOR
	if (style_flags & TextBlockStore.FONT_STYLE_BOLD) != 0:
		width *= BOLD_WIDTH_FACTOR
	if (style_flags & TextBlockStore.FONT_STYLE_ITALIC) != 0:
		width *= ITALIC_WIDTH_FACTOR
	return width


static func _color_from_variant(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value as Color
	var encoded: String = str(value)
	if encoded.is_empty() or not Color.html_is_valid(encoded):
		return fallback
	return Color(encoded)
