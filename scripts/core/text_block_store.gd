# SPDX-License-Identifier: GPL-3.0-or-later
class_name TextBlockStore
extends BoardDataStore

signal block_added(entity_id: int)
signal block_changed(entity_id: int)
signal block_removed(entity_id: int)
signal cleared

const STORE_ID: StringName = &"text_blocks"

# Legacy style identifiers are retained only so Stage 3.2 documents migrate cleanly.
const STYLE_PLAIN: int = 0
const STYLE_NOTE: int = 1
const STYLE_STICKY: int = 2
const STYLE_HEADING: int = 3

const DEFAULT_FONT_SIZE: float = 22.0
const MIN_FONT_SIZE: float = 10.0
const MAX_FONT_SIZE: float = 288.0
const DEFAULT_FONT_FAMILY: String = "Noto Sans"

const LAYOUT_AUTO_WIDTH: int = 0
const LAYOUT_FIXED_WIDTH: int = 1

const FONT_STYLE_BOLD: int = 1 << 0
const FONT_STYLE_ITALIC: int = 1 << 1
const FONT_STYLE_UNDERLINE: int = 1 << 2
const FONT_STYLE_STRIKETHROUGH: int = 1 << 3
const FONT_STYLE_ALL: int = FONT_STYLE_BOLD | FONT_STYLE_ITALIC | FONT_STYLE_UNDERLINE | FONT_STYLE_STRIKETHROUGH

const LIST_NONE: int = 0
const LIST_BULLET: int = 1
const LIST_NUMBERED: int = 2
const MAX_LIST_INDENT: int = 6

const COLOR_TEXT: Color = Color("#243129")
const COLOR_PLAIN: Color = Color(0.0, 0.0, 0.0, 0.0)
const COLOR_NOTE: Color = Color("#eef6ed")
const COLOR_STICKY: Color = Color("#fff3bf")
const COLOR_HEADING: Color = Color("#e5f1e8")

var entity_ids: PackedInt64Array = PackedInt64Array()
var texts: PackedStringArray = PackedStringArray()
var font_sizes: PackedFloat32Array = PackedFloat32Array()
var font_families: PackedStringArray = PackedStringArray()
var alignments: PackedInt32Array = PackedInt32Array()
var style_ids: PackedInt32Array = PackedInt32Array()
var layout_modes: PackedInt32Array = PackedInt32Array()
var background_colors: PackedColorArray = PackedColorArray()
var text_colors: PackedColorArray = PackedColorArray()
var base_style_flags: PackedInt32Array = PackedInt32Array()
var run_offsets: PackedInt32Array = PackedInt32Array()
var run_counts: PackedInt32Array = PackedInt32Array()
var paragraph_offsets: PackedInt32Array = PackedInt32Array()
var paragraph_counts: PackedInt32Array = PackedInt32Array()
var revisions: PackedInt64Array = PackedInt64Array()

# Append-only compact pools. A document mutation appends a replacement slice and updates
# the document offset/count. Old slices are compacted opportunistically, avoiding O(N)
# shifts across every text block during editing.
var _run_starts: PackedInt32Array = PackedInt32Array()
var _run_lengths: PackedInt32Array = PackedInt32Array()
var _run_flags: PackedInt32Array = PackedInt32Array()
var _run_colors: PackedColorArray = PackedColorArray()
var _paragraph_list_types: PackedInt32Array = PackedInt32Array()
var _paragraph_indents: PackedInt32Array = PackedInt32Array()
var _pool_garbage_runs: int = 0
var _pool_garbage_paragraphs: int = 0
var _pool_mutations_since_compaction: int = 0

var _index_by_id: Dictionary = {}
var _store_revision: int = 0


func _init() -> void:
	super(STORE_ID)


func add_block(
	entity_id: int,
	text: String = "",
	font_size: float = DEFAULT_FONT_SIZE,
	alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	style_id: int = STYLE_PLAIN,
	layout_mode: int = LAYOUT_AUTO_WIDTH,
	background_color: Color = Color.TRANSPARENT,
	text_color: Color = COLOR_TEXT,
	font_family: String = DEFAULT_FONT_FAMILY,
	style_flags: int = 0,
	style_runs: Array = [],
	paragraphs: Array = []
) -> bool:
	if entity_id <= 0 or _index_by_id.has(entity_id):
		return false
	var normalized_text: String = text.replace("\r", "")
	var safe_style: int = clampi(style_id, STYLE_PLAIN, STYLE_HEADING)
	var resolved_background: Color = background_color
	if resolved_background == Color.TRANSPARENT and safe_style != STYLE_PLAIN:
		resolved_background = default_background_for_style(safe_style)
	var index: int = entity_ids.size()
	entity_ids.append(entity_id)
	texts.append(normalized_text)
	font_sizes.append(clampf(font_size, MIN_FONT_SIZE, MAX_FONT_SIZE))
	font_families.append(_safe_font_family(font_family))
	alignments.append(clampi(int(alignment), HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_RIGHT))
	style_ids.append(STYLE_PLAIN)
	layout_modes.append(clampi(layout_mode, LAYOUT_AUTO_WIDTH, LAYOUT_FIXED_WIDTH))
	background_colors.append(resolved_background)
	text_colors.append(text_color)
	base_style_flags.append(style_flags & FONT_STYLE_ALL)
	run_offsets.append(0)
	run_counts.append(0)
	paragraph_offsets.append(0)
	paragraph_counts.append(0)
	revisions.append(1)
	_index_by_id[entity_id] = index
	_replace_runs(index, _sanitize_runs(normalized_text, style_runs, style_flags & FONT_STYLE_ALL, text_color))
	_replace_paragraphs(index, _sanitize_paragraphs(normalized_text, paragraphs))
	_store_revision += 1
	block_added.emit(entity_id)
	return true


func contains(entity_id: int) -> bool:
	return _index_by_id.has(entity_id)


func size() -> int:
	return entity_ids.size()


func get_index(entity_id: int) -> int:
	return int(_index_by_id.get(entity_id, -1))


func get_text(entity_id: int) -> String:
	var index: int = get_index(entity_id)
	return texts[index] if index >= 0 else ""


func get_font_size(entity_id: int) -> float:
	var index: int = get_index(entity_id)
	return float(font_sizes[index]) if index >= 0 else DEFAULT_FONT_SIZE


func get_font_family(entity_id: int) -> String:
	var index: int = get_index(entity_id)
	return font_families[index] if index >= 0 else DEFAULT_FONT_FAMILY


func get_alignment(entity_id: int) -> HorizontalAlignment:
	var index: int = get_index(entity_id)
	if index < 0:
		return HORIZONTAL_ALIGNMENT_LEFT
	return int(alignments[index]) as HorizontalAlignment


func get_style_id(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	return int(style_ids[index]) if index >= 0 else STYLE_PLAIN


func get_layout_mode(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	return int(layout_modes[index]) if index >= 0 else LAYOUT_AUTO_WIDTH


func get_background_color(entity_id: int) -> Color:
	var index: int = get_index(entity_id)
	return background_colors[index] if index >= 0 else COLOR_PLAIN


func get_text_color(entity_id: int) -> Color:
	var index: int = get_index(entity_id)
	return text_colors[index] if index >= 0 else COLOR_TEXT


func get_base_style_flags(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	return int(base_style_flags[index]) if index >= 0 else 0


func get_revision(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	return int(revisions[index]) if index >= 0 else 0


func get_store_revision() -> int:
	return _store_revision


func get_style_runs(entity_id: int) -> Array[Dictionary]:
	var index: int = get_index(entity_id)
	if index < 0:
		return []
	return _runs_for_index(index)


func get_paragraphs(entity_id: int) -> Array[Dictionary]:
	var index: int = get_index(entity_id)
	if index < 0:
		return []
	return _paragraphs_for_index(index)


func get_paragraph_list_type(entity_id: int, paragraph_index: int) -> int:
	var index: int = get_index(entity_id)
	if index < 0 or paragraph_index < 0 or paragraph_index >= int(paragraph_counts[index]):
		return LIST_NONE
	return int(_paragraph_list_types[int(paragraph_offsets[index]) + paragraph_index])


func get_paragraph_indent(entity_id: int, paragraph_index: int) -> int:
	var index: int = get_index(entity_id)
	if index < 0 or paragraph_index < 0 or paragraph_index >= int(paragraph_counts[index]):
		return 0
	return int(_paragraph_indents[int(paragraph_offsets[index]) + paragraph_index])


func get_style_at(entity_id: int, character_offset: int) -> Dictionary:
	var index: int = get_index(entity_id)
	if index < 0:
		return {"flags": 0, "color": COLOR_TEXT}
	return _style_at_index(index, character_offset)


func get_record(entity_id: int) -> Dictionary:
	var index: int = get_index(entity_id)
	if index < 0:
		return {}
	return {
		"entity_id": str(entity_ids[index]),
		"text": texts[index],
		"font_size": float(font_sizes[index]),
		"font_family": font_families[index],
		"alignment": int(alignments[index]),
		"style_id": STYLE_PLAIN,
		"layout_mode": int(layout_modes[index]),
		"background_color": background_colors[index].to_html(true),
		"text_color": text_colors[index].to_html(true),
		"base_style_flags": int(base_style_flags[index]),
		"style_runs": _runs_for_index(index),
		"paragraphs": _paragraphs_for_index(index),
	}


func capture_record(entity_id: int) -> Dictionary:
	return get_record(entity_id)


func restore_record(record: Dictionary) -> bool:
	var entity_id: int = int(str(record.get("entity_id", "0")))
	if entity_id <= 0:
		return false
	var legacy_style: int = clampi(int(record.get("style_id", STYLE_PLAIN)), STYLE_PLAIN, STYLE_HEADING)
	var background_color: Color = _parse_color(
		record.get("background_color", ""),
		default_background_for_style(legacy_style)
	)
	var text_color: Color = _parse_color(record.get("text_color", ""), COLOR_TEXT)
	var raw_runs: Array = record.get("style_runs", []) as Array
	var raw_paragraphs: Array = record.get("paragraphs", []) as Array
	return add_block(
		entity_id,
		str(record.get("text", "")),
		float(record.get("font_size", DEFAULT_FONT_SIZE)),
		clampi(int(record.get("alignment", HORIZONTAL_ALIGNMENT_LEFT)), HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_RIGHT) as HorizontalAlignment,
		STYLE_PLAIN,
		clampi(int(record.get("layout_mode", LAYOUT_AUTO_WIDTH)), LAYOUT_AUTO_WIDTH, LAYOUT_FIXED_WIDTH),
		background_color,
		text_color,
		str(record.get("font_family", DEFAULT_FONT_FAMILY)),
		int(record.get("base_style_flags", 0)),
		raw_runs,
		raw_paragraphs
	)


func remap_record(record: Dictionary, id_map: Dictionary) -> Dictionary:
	var remapped: Dictionary = record.duplicate(true)
	var old_entity_id: int = int(str(record.get("entity_id", "0")))
	if old_entity_id > 0 and id_map.has(old_entity_id):
		remapped["entity_id"] = str(int(id_map[old_entity_id]))
	return remapped


func set_text(entity_id: int, value: String) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var normalized_value: String = value.replace("\r", "")
	if texts[index] == normalized_value:
		return true
	var previous_text: String = texts[index]
	var previous_runs: Array[Dictionary] = _runs_for_index(index)
	var next_runs: Array[Dictionary] = _remap_runs_after_text_edit(
		previous_text,
		normalized_value,
		previous_runs,
		int(base_style_flags[index]),
		text_colors[index]
	)
	var previous_paragraphs: Array[Dictionary] = _paragraphs_for_index(index)
	texts[index] = normalized_value
	_replace_runs(index, next_runs)
	_replace_paragraphs(index, _resize_paragraphs_for_text(normalized_value, previous_paragraphs))
	_touch(index, entity_id)
	return true


func set_font_size(entity_id: int, value: float) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var safe_value: float = clampf(value, MIN_FONT_SIZE, MAX_FONT_SIZE)
	if is_equal_approx(float(font_sizes[index]), safe_value):
		return true
	font_sizes[index] = safe_value
	_touch(index, entity_id)
	return true


func set_font_family(entity_id: int, value: String) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var safe_value: String = _safe_font_family(value)
	if font_families[index] == safe_value:
		return true
	font_families[index] = safe_value
	_touch(index, entity_id)
	return true


func set_alignment(entity_id: int, value: HorizontalAlignment) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var safe_value: int = clampi(int(value), HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_RIGHT)
	if int(alignments[index]) == safe_value:
		return true
	alignments[index] = safe_value
	_touch(index, entity_id)
	return true


func set_layout_mode(entity_id: int, layout_mode: int) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var safe_mode: int = clampi(layout_mode, LAYOUT_AUTO_WIDTH, LAYOUT_FIXED_WIDTH)
	if int(layout_modes[index]) == safe_mode:
		return true
	layout_modes[index] = safe_mode
	_touch(index, entity_id)
	return true


func set_style(entity_id: int, _style_id: int, _update_default_background: bool = true) -> bool:
	# Stage 3.3 intentionally removes Sticky/Heading as separate object modes.
	# Keeping this compatibility method avoids breaking older command payloads.
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	if int(style_ids[index]) != STYLE_PLAIN:
		style_ids[index] = STYLE_PLAIN
		_touch(index, entity_id)
	return true


func set_background_color(entity_id: int, background_color: Color) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	if background_colors[index] == background_color:
		return true
	background_colors[index] = background_color
	_touch(index, entity_id)
	return true


func set_colors(entity_id: int, background_color: Color, text_color: Color) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var changed: bool = false
	if background_colors[index] != background_color:
		background_colors[index] = background_color
		changed = true
	if text_colors[index] != text_color:
		text_colors[index] = text_color
		var runs: Array[Dictionary] = _runs_for_index(index)
		for run: Dictionary in runs:
			run["color"] = text_color.to_html(true)
		_replace_runs(index, runs)
		changed = true
	if changed:
		_touch(index, entity_id)
	return true


func set_base_style_flags(entity_id: int, flags: int, apply_to_all_text: bool = true) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var safe_flags: int = flags & FONT_STYLE_ALL
	var changed: bool = int(base_style_flags[index]) != safe_flags
	base_style_flags[index] = safe_flags
	if apply_to_all_text and not texts[index].is_empty():
		var runs: Array[Dictionary] = _runs_for_index(index)
		for run: Dictionary in runs:
			run["flags"] = safe_flags
		_replace_runs(index, runs)
		changed = true
	if changed:
		_touch(index, entity_id)
	return true


func apply_style_flag_range(entity_id: int, start: int, end: int, flag: int, enabled: bool) -> bool:
	var index: int = get_index(entity_id)
	if index < 0 or (flag & FONT_STYLE_ALL) == 0:
		return false
	var text_length: int = texts[index].length()
	var range_start: int = clampi(mini(start, end), 0, text_length)
	var range_end: int = clampi(maxi(start, end), 0, text_length)
	if range_start == range_end:
		var next_base: int = int(base_style_flags[index])
		if enabled:
			next_base |= flag
		else:
			next_base &= ~flag
		base_style_flags[index] = next_base & FONT_STYLE_ALL
		_touch(index, entity_id)
		return true
	var runs: Array[Dictionary] = _split_runs_at(_runs_for_index(index), range_start, range_end)
	for run: Dictionary in runs:
		var run_start: int = int(run.get("start", 0))
		var run_end: int = run_start + int(run.get("length", 0))
		if run_end <= range_start or run_start >= range_end:
			continue
		var run_flags_value: int = int(run.get("flags", 0))
		if enabled:
			run_flags_value |= flag
		else:
			run_flags_value &= ~flag
		run["flags"] = run_flags_value & FONT_STYLE_ALL
	_replace_runs(index, _coalesce_runs(runs))
	_touch(index, entity_id)
	return true


func apply_style_range(entity_id: int, start: int, end: int, flags: int, color: Color) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var text_length: int = texts[index].length()
	var range_start: int = clampi(mini(start, end), 0, text_length)
	var range_end: int = clampi(maxi(start, end), 0, text_length)
	if range_start >= range_end:
		return false
	var safe_flags: int = flags & FONT_STYLE_ALL
	var runs: Array[Dictionary] = _split_runs_at(_runs_for_index(index), range_start, range_end)
	var changed: bool = false
	for run: Dictionary in runs:
		var run_start: int = int(run.get("start", 0))
		var run_end: int = run_start + int(run.get("length", 0))
		if run_end <= range_start or run_start >= range_end:
			continue
		if int(run.get("flags", 0)) != safe_flags or _parse_color(run.get("color", ""), text_colors[index]) != color:
			run["flags"] = safe_flags
			run["color"] = color.to_html(true)
			changed = true
	if not changed:
		return true
	_replace_runs(index, _coalesce_runs(runs))
	_touch(index, entity_id)
	return true


func apply_text_color_range(entity_id: int, start: int, end: int, color: Color) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var text_length: int = texts[index].length()
	var range_start: int = clampi(mini(start, end), 0, text_length)
	var range_end: int = clampi(maxi(start, end), 0, text_length)
	if range_start == range_end:
		text_colors[index] = color
		_touch(index, entity_id)
		return true
	var runs: Array[Dictionary] = _split_runs_at(_runs_for_index(index), range_start, range_end)
	for run: Dictionary in runs:
		var run_start: int = int(run.get("start", 0))
		var run_end: int = run_start + int(run.get("length", 0))
		if run_end > range_start and run_start < range_end:
			run["color"] = color.to_html(true)
	_replace_runs(index, _coalesce_runs(runs))
	_touch(index, entity_id)
	return true


func set_paragraph_list_type(entity_id: int, paragraph_indices: PackedInt32Array, list_type: int) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var safe_type: int = clampi(list_type, LIST_NONE, LIST_NUMBERED)
	var paragraphs: Array[Dictionary] = _paragraphs_for_index(index)
	var changed: bool = false
	for paragraph_index: int in paragraph_indices:
		if paragraph_index < 0 or paragraph_index >= paragraphs.size():
			continue
		if int(paragraphs[paragraph_index].get("list_type", LIST_NONE)) != safe_type:
			paragraphs[paragraph_index]["list_type"] = safe_type
			if safe_type == LIST_NONE:
				paragraphs[paragraph_index]["indent"] = 0
			changed = true
	if changed:
		_replace_paragraphs(index, paragraphs)
		_touch(index, entity_id)
	return true


func adjust_paragraph_indent(entity_id: int, paragraph_indices: PackedInt32Array, delta: int) -> bool:
	var index: int = get_index(entity_id)
	if index < 0 or delta == 0:
		return false
	var paragraphs: Array[Dictionary] = _paragraphs_for_index(index)
	var changed: bool = false
	for paragraph_index: int in paragraph_indices:
		if paragraph_index < 0 or paragraph_index >= paragraphs.size():
			continue
		if int(paragraphs[paragraph_index].get("list_type", LIST_NONE)) == LIST_NONE:
			continue
		var previous: int = int(paragraphs[paragraph_index].get("indent", 0))
		var next: int = clampi(previous + delta, 0, MAX_LIST_INDENT)
		if previous != next:
			paragraphs[paragraph_index]["indent"] = next
			changed = true
	if changed:
		_replace_paragraphs(index, paragraphs)
		_touch(index, entity_id)
	return true


func apply_record(entity_id: int, record: Dictionary) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		var restored: Dictionary = record.duplicate(true)
		restored["entity_id"] = str(entity_id)
		return restore_record(restored)
	var next_text: String = str(record.get("text", texts[index])).replace("\r", "")
	var next_font_size: float = clampf(float(record.get("font_size", font_sizes[index])), MIN_FONT_SIZE, MAX_FONT_SIZE)
	var next_font_family: String = _safe_font_family(str(record.get("font_family", font_families[index])))
	var next_alignment: int = clampi(int(record.get("alignment", alignments[index])), HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_RIGHT)
	var next_layout_mode: int = clampi(int(record.get("layout_mode", layout_modes[index])), LAYOUT_AUTO_WIDTH, LAYOUT_FIXED_WIDTH)
	var next_background: Color = _parse_color(record.get("background_color", ""), background_colors[index])
	var next_text_color: Color = _parse_color(record.get("text_color", ""), text_colors[index])
	var next_base_flags: int = int(record.get("base_style_flags", base_style_flags[index])) & FONT_STYLE_ALL
	var raw_runs: Array = record.get("style_runs", _runs_for_index(index)) as Array
	var raw_paragraphs: Array = record.get("paragraphs", _paragraphs_for_index(index)) as Array
	var next_runs: Array[Dictionary] = _sanitize_runs(next_text, raw_runs, next_base_flags, next_text_color)
	var next_paragraphs: Array[Dictionary] = _sanitize_paragraphs(next_text, raw_paragraphs)
	var changed: bool = (
		texts[index] != next_text
		or not is_equal_approx(float(font_sizes[index]), next_font_size)
		or font_families[index] != next_font_family
		or int(alignments[index]) != next_alignment
		or int(layout_modes[index]) != next_layout_mode
		or background_colors[index] != next_background
		or text_colors[index] != next_text_color
		or int(base_style_flags[index]) != next_base_flags
		or _runs_for_index(index) != next_runs
		or _paragraphs_for_index(index) != next_paragraphs
	)
	if not changed:
		return true
	texts[index] = next_text
	font_sizes[index] = next_font_size
	font_families[index] = next_font_family
	alignments[index] = next_alignment
	style_ids[index] = STYLE_PLAIN
	layout_modes[index] = next_layout_mode
	background_colors[index] = next_background
	text_colors[index] = next_text_color
	base_style_flags[index] = next_base_flags
	_replace_runs(index, next_runs)
	_replace_paragraphs(index, next_paragraphs)
	_touch(index, entity_id)
	return true


func remove(entity_id: int) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	_pool_garbage_runs += int(run_counts[index])
	_pool_garbage_paragraphs += int(paragraph_counts[index])
	var last_index: int = entity_ids.size() - 1
	if index != last_index:
		var moved_id: int = int(entity_ids[last_index])
		entity_ids[index] = entity_ids[last_index]
		texts[index] = texts[last_index]
		font_sizes[index] = font_sizes[last_index]
		font_families[index] = font_families[last_index]
		alignments[index] = alignments[last_index]
		style_ids[index] = style_ids[last_index]
		layout_modes[index] = layout_modes[last_index]
		background_colors[index] = background_colors[last_index]
		text_colors[index] = text_colors[last_index]
		base_style_flags[index] = base_style_flags[last_index]
		run_offsets[index] = run_offsets[last_index]
		run_counts[index] = run_counts[last_index]
		paragraph_offsets[index] = paragraph_offsets[last_index]
		paragraph_counts[index] = paragraph_counts[last_index]
		revisions[index] = revisions[last_index]
		_index_by_id[moved_id] = index
	entity_ids.resize(last_index)
	texts.resize(last_index)
	font_sizes.resize(last_index)
	font_families.resize(last_index)
	alignments.resize(last_index)
	style_ids.resize(last_index)
	layout_modes.resize(last_index)
	background_colors.resize(last_index)
	text_colors.resize(last_index)
	base_style_flags.resize(last_index)
	run_offsets.resize(last_index)
	run_counts.resize(last_index)
	paragraph_offsets.resize(last_index)
	paragraph_counts.resize(last_index)
	revisions.resize(last_index)
	_index_by_id.erase(entity_id)
	_store_revision += 1
	_maybe_compact_pools(true)
	block_removed.emit(entity_id)
	return true


func clear() -> void:
	entity_ids = PackedInt64Array()
	texts = PackedStringArray()
	font_sizes = PackedFloat32Array()
	font_families = PackedStringArray()
	alignments = PackedInt32Array()
	style_ids = PackedInt32Array()
	layout_modes = PackedInt32Array()
	background_colors = PackedColorArray()
	text_colors = PackedColorArray()
	base_style_flags = PackedInt32Array()
	run_offsets = PackedInt32Array()
	run_counts = PackedInt32Array()
	paragraph_offsets = PackedInt32Array()
	paragraph_counts = PackedInt32Array()
	revisions = PackedInt64Array()
	_run_starts = PackedInt32Array()
	_run_lengths = PackedInt32Array()
	_run_flags = PackedInt32Array()
	_run_colors = PackedColorArray()
	_paragraph_list_types = PackedInt32Array()
	_paragraph_indents = PackedInt32Array()
	_pool_garbage_runs = 0
	_pool_garbage_paragraphs = 0
	_pool_mutations_since_compaction = 0
	_index_by_id.clear()
	_store_revision += 1
	cleared.emit()


func serialize() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.resize(entity_ids.size())
	for index: int in range(entity_ids.size()):
		result[index] = get_record(int(entity_ids[index]))
	return result


func deserialize(records: Array) -> void:
	clear()
	for raw_record: Variant in records:
		if raw_record is Dictionary:
			restore_record(raw_record as Dictionary)
	_store_revision = 0


func create_render_snapshot(
	visible_entity_ids: PackedInt64Array,
	transforms: BoardTransformStore,
	lod: BoardRenderPolicy.LodLevel,
	editing_entity_id: int = 0
) -> Dictionary:
	var count: int = visible_entity_ids.size()
	var snapshot_ids: PackedInt64Array = PackedInt64Array()
	var snapshot_texts: PackedStringArray = PackedStringArray()
	var rect_values: PackedFloat32Array = PackedFloat32Array()
	var snapshot_font_sizes: PackedFloat32Array = PackedFloat32Array()
	var snapshot_font_families: PackedStringArray = PackedStringArray()
	var snapshot_alignments: PackedInt32Array = PackedInt32Array()
	var snapshot_styles: PackedInt32Array = PackedInt32Array()
	var snapshot_backgrounds: PackedColorArray = PackedColorArray()
	var snapshot_text_colors: PackedColorArray = PackedColorArray()
	var snapshot_base_flags: PackedInt32Array = PackedInt32Array()
	var snapshot_run_offsets: PackedInt32Array = PackedInt32Array()
	var snapshot_run_counts: PackedInt32Array = PackedInt32Array()
	var snapshot_run_starts: PackedInt32Array = PackedInt32Array()
	var snapshot_run_lengths: PackedInt32Array = PackedInt32Array()
	var snapshot_run_flags: PackedInt32Array = PackedInt32Array()
	var snapshot_run_colors: PackedColorArray = PackedColorArray()
	var snapshot_paragraph_offsets: PackedInt32Array = PackedInt32Array()
	var snapshot_paragraph_counts: PackedInt32Array = PackedInt32Array()
	var snapshot_paragraph_types: PackedInt32Array = PackedInt32Array()
	var snapshot_paragraph_indents: PackedInt32Array = PackedInt32Array()
	var snapshot_revisions: PackedInt64Array = PackedInt64Array()
	for entity_id: int in visible_entity_ids:
		var source_index: int = get_index(entity_id)
		if source_index < 0 or not transforms.contains(entity_id):
			continue
		var bounds: Rect2 = transforms.get_bounds(entity_id)
		snapshot_ids.append(entity_id)
		snapshot_texts.append("" if entity_id == editing_entity_id else texts[source_index])
		rect_values.append(bounds.position.x)
		rect_values.append(bounds.position.y)
		rect_values.append(bounds.size.x)
		rect_values.append(bounds.size.y)
		snapshot_font_sizes.append(font_sizes[source_index])
		snapshot_font_families.append(font_families[source_index])
		snapshot_alignments.append(alignments[source_index])
		snapshot_styles.append(STYLE_PLAIN)
		snapshot_backgrounds.append(Color.TRANSPARENT if entity_id == editing_entity_id else background_colors[source_index])
		snapshot_text_colors.append(text_colors[source_index])
		snapshot_base_flags.append(base_style_flags[source_index])
		snapshot_run_offsets.append(snapshot_run_starts.size())
		var source_run_offset: int = int(run_offsets[source_index])
		var source_run_count: int = int(run_counts[source_index])
		snapshot_run_counts.append(source_run_count)
		for local_run: int in range(source_run_count):
			var source_run: int = source_run_offset + local_run
			snapshot_run_starts.append(_run_starts[source_run])
			snapshot_run_lengths.append(_run_lengths[source_run])
			snapshot_run_flags.append(_run_flags[source_run])
			snapshot_run_colors.append(_run_colors[source_run])
		snapshot_paragraph_offsets.append(snapshot_paragraph_types.size())
		var source_paragraph_offset: int = int(paragraph_offsets[source_index])
		var source_paragraph_count: int = int(paragraph_counts[source_index])
		snapshot_paragraph_counts.append(source_paragraph_count)
		for local_paragraph: int in range(source_paragraph_count):
			var source_paragraph: int = source_paragraph_offset + local_paragraph
			snapshot_paragraph_types.append(_paragraph_list_types[source_paragraph])
			snapshot_paragraph_indents.append(_paragraph_indents[source_paragraph])
		snapshot_revisions.append(revisions[source_index] + transforms.get_revision(entity_id))
	return {
		"entity_ids": snapshot_ids,
		"texts": snapshot_texts,
		"rect_values": rect_values,
		"font_sizes": snapshot_font_sizes,
		"font_families": snapshot_font_families,
		"alignments": snapshot_alignments,
		"style_ids": snapshot_styles,
		"background_colors": snapshot_backgrounds,
		"text_colors": snapshot_text_colors,
		"base_style_flags": snapshot_base_flags,
		"run_offsets": snapshot_run_offsets,
		"run_counts": snapshot_run_counts,
		"run_starts": snapshot_run_starts,
		"run_lengths": snapshot_run_lengths,
		"run_flags": snapshot_run_flags,
		"run_colors": snapshot_run_colors,
		"paragraph_offsets": snapshot_paragraph_offsets,
		"paragraph_counts": snapshot_paragraph_counts,
		"paragraph_types": snapshot_paragraph_types,
		"paragraph_indents": snapshot_paragraph_indents,
		"revisions": snapshot_revisions,
		"lod": int(lod),
		"count": snapshot_ids.size(),
	}


static func default_background_for_style(style_id: int) -> Color:
	match style_id:
		STYLE_STICKY:
			return COLOR_STICKY
		STYLE_HEADING:
			return COLOR_HEADING
		STYLE_NOTE:
			return COLOR_NOTE
		_:
			return COLOR_PLAIN


static func paragraph_count_for_text(text: String) -> int:
	return text.count("\n") + 1


static func paragraph_index_for_offset(text: String, character_offset: int) -> int:
	var safe_offset: int = clampi(character_offset, 0, text.length())
	var paragraph_index: int = 0
	for index: int in range(safe_offset):
		if text.substr(index, 1) == "\n":
			paragraph_index += 1
	return paragraph_index


func _touch(index: int, entity_id: int) -> void:
	revisions[index] = revisions[index] + 1
	_store_revision += 1
	_maybe_compact_pools()
	block_changed.emit(entity_id)


func _replace_runs(index: int, runs: Array[Dictionary]) -> void:
	_pool_garbage_runs += int(run_counts[index])
	_pool_mutations_since_compaction += 1
	var offset: int = _run_starts.size()
	run_offsets[index] = offset
	run_counts[index] = runs.size()
	for run: Dictionary in runs:
		_run_starts.append(int(run.get("start", 0)))
		_run_lengths.append(maxi(0, int(run.get("length", 0))))
		_run_flags.append(int(run.get("flags", 0)) & FONT_STYLE_ALL)
		_run_colors.append(_parse_color(run.get("color", ""), text_colors[index]))


func _replace_paragraphs(index: int, paragraphs: Array[Dictionary]) -> void:
	_pool_garbage_paragraphs += int(paragraph_counts[index])
	_pool_mutations_since_compaction += 1
	var offset: int = _paragraph_list_types.size()
	paragraph_offsets[index] = offset
	paragraph_counts[index] = paragraphs.size()
	for paragraph: Dictionary in paragraphs:
		_paragraph_list_types.append(clampi(int(paragraph.get("list_type", LIST_NONE)), LIST_NONE, LIST_NUMBERED))
		_paragraph_indents.append(clampi(int(paragraph.get("indent", 0)), 0, MAX_LIST_INDENT))


func _runs_for_index(index: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var offset: int = int(run_offsets[index])
	var count: int = int(run_counts[index])
	for local_index: int in range(count):
		var source_index: int = offset + local_index
		result.append({
			"start": int(_run_starts[source_index]),
			"length": int(_run_lengths[source_index]),
			"flags": int(_run_flags[source_index]),
			"color": _run_colors[source_index].to_html(true),
		})
	return result


func _paragraphs_for_index(index: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var offset: int = int(paragraph_offsets[index])
	var count: int = int(paragraph_counts[index])
	for local_index: int in range(count):
		var source_index: int = offset + local_index
		result.append({
			"list_type": int(_paragraph_list_types[source_index]),
			"indent": int(_paragraph_indents[source_index]),
		})
	return result


func _style_at_index(index: int, character_offset: int) -> Dictionary:
	var text_length: int = texts[index].length()
	if text_length <= 0:
		return {
			"flags": int(base_style_flags[index]),
			"color": text_colors[index],
		}
	var safe_offset: int = clampi(character_offset, 0, text_length - 1)
	var offset: int = int(run_offsets[index])
	var count: int = int(run_counts[index])
	for local_index: int in range(count):
		var source_index: int = offset + local_index
		var run_start: int = int(_run_starts[source_index])
		var run_end: int = run_start + int(_run_lengths[source_index])
		if safe_offset >= run_start and safe_offset < run_end:
			return {
				"flags": int(_run_flags[source_index]),
				"color": _run_colors[source_index],
			}
	return {
		"flags": int(base_style_flags[index]),
		"color": text_colors[index],
	}


func _sanitize_runs(
	text: String,
	raw_runs: Array,
	fallback_flags: int,
	fallback_color: Color
) -> Array[Dictionary]:
	var text_length: int = text.length()
	if text_length <= 0:
		return []
	var candidates: Array[Dictionary] = []
	for raw_run: Variant in raw_runs:
		if raw_run is not Dictionary:
			continue
		var source: Dictionary = raw_run as Dictionary
		var start: int = clampi(int(source.get("start", 0)), 0, text_length)
		var length: int = clampi(int(source.get("length", 0)), 0, text_length - start)
		if length <= 0:
			continue
		candidates.append({
			"start": start,
			"length": length,
			"flags": int(source.get("flags", fallback_flags)) & FONT_STYLE_ALL,
			"color": _parse_color(source.get("color", ""), fallback_color).to_html(true),
		})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("start", 0)) < int(b.get("start", 0)))
	var result: Array[Dictionary] = []
	var cursor: int = 0
	for candidate: Dictionary in candidates:
		var start: int = int(candidate.get("start", 0))
		var end: int = mini(text_length, start + int(candidate.get("length", 0)))
		if end <= cursor:
			continue
		if start > cursor:
			result.append(_make_run(cursor, start - cursor, fallback_flags, fallback_color))
		start = maxi(start, cursor)
		result.append({
			"start": start,
			"length": end - start,
			"flags": int(candidate.get("flags", fallback_flags)) & FONT_STYLE_ALL,
			"color": str(candidate.get("color", fallback_color.to_html(true))),
		})
		cursor = end
	if cursor < text_length:
		result.append(_make_run(cursor, text_length - cursor, fallback_flags, fallback_color))
	if result.is_empty():
		result.append(_make_run(0, text_length, fallback_flags, fallback_color))
	return _coalesce_runs(result)


func _sanitize_paragraphs(text: String, raw_paragraphs: Array) -> Array[Dictionary]:
	var target_count: int = paragraph_count_for_text(text)
	var result: Array[Dictionary] = []
	for index: int in range(target_count):
		var list_type: int = LIST_NONE
		var indent: int = 0
		if index < raw_paragraphs.size() and raw_paragraphs[index] is Dictionary:
			var source: Dictionary = raw_paragraphs[index] as Dictionary
			list_type = clampi(int(source.get("list_type", LIST_NONE)), LIST_NONE, LIST_NUMBERED)
			indent = clampi(int(source.get("indent", 0)), 0, MAX_LIST_INDENT)
		result.append({"list_type": list_type, "indent": indent})
	return result


func _resize_paragraphs_for_text(text: String, previous: Array[Dictionary]) -> Array[Dictionary]:
	var target_count: int = paragraph_count_for_text(text)
	var result: Array[Dictionary] = []
	for index: int in range(target_count):
		if index < previous.size():
			result.append(previous[index].duplicate(true))
		elif not result.is_empty():
			var inherited: Dictionary = result[result.size() - 1].duplicate(true)
			result.append(inherited)
		else:
			result.append({"list_type": LIST_NONE, "indent": 0})
	return result


func _remap_runs_after_text_edit(
	old_text: String,
	new_text: String,
	old_runs: Array[Dictionary],
	fallback_flags: int,
	fallback_color: Color
) -> Array[Dictionary]:
	if new_text.is_empty():
		return []
	if old_text.is_empty() or old_runs.is_empty():
		return [_make_run(0, new_text.length(), fallback_flags, fallback_color)]
	var prefix: int = _common_prefix_length(old_text, new_text)
	var suffix: int = _common_suffix_length(old_text, new_text, prefix)
	var old_replace_end: int = old_text.length() - suffix
	var new_replace_end: int = new_text.length() - suffix
	var inserted_length: int = maxi(0, new_replace_end - prefix)
	var delta: int = new_text.length() - old_text.length()
	var insertion_style: Dictionary = _style_from_run_array(old_runs, maxi(0, prefix - 1), fallback_flags, fallback_color)
	if prefix < old_text.length():
		insertion_style = _style_from_run_array(old_runs, prefix, fallback_flags, fallback_color)
	var result: Array[Dictionary] = []
	for run: Dictionary in old_runs:
		var run_start: int = int(run.get("start", 0))
		var run_end: int = run_start + int(run.get("length", 0))
		var before_end: int = mini(run_end, prefix)
		if before_end > run_start:
			result.append({
				"start": run_start,
				"length": before_end - run_start,
				"flags": int(run.get("flags", fallback_flags)),
				"color": str(run.get("color", fallback_color.to_html(true))),
			})
	if inserted_length > 0:
		result.append({
			"start": prefix,
			"length": inserted_length,
			"flags": int(insertion_style.get("flags", fallback_flags)),
			"color": _parse_color(insertion_style.get("color", ""), fallback_color).to_html(true),
		})
	for run: Dictionary in old_runs:
		var run_start: int = int(run.get("start", 0))
		var run_end: int = run_start + int(run.get("length", 0))
		var suffix_start: int = maxi(run_start, old_replace_end)
		if run_end <= suffix_start:
			continue
		result.append({
			"start": suffix_start + delta,
			"length": run_end - suffix_start,
			"flags": int(run.get("flags", fallback_flags)),
			"color": str(run.get("color", fallback_color.to_html(true))),
		})
	return _sanitize_runs(new_text, result, fallback_flags, fallback_color)


func _split_runs_at(runs: Array[Dictionary], first: int, second: int) -> Array[Dictionary]:
	var split_points: PackedInt32Array = PackedInt32Array([first, second])
	var result: Array[Dictionary] = []
	for run: Dictionary in runs:
		var run_start: int = int(run.get("start", 0))
		var run_end: int = run_start + int(run.get("length", 0))
		var cursor: int = run_start
		for split_point: int in split_points:
			if split_point > cursor and split_point < run_end:
				result.append({
					"start": cursor,
					"length": split_point - cursor,
					"flags": int(run.get("flags", 0)),
					"color": str(run.get("color", COLOR_TEXT.to_html(true))),
				})
				cursor = split_point
		if cursor < run_end:
			result.append({
				"start": cursor,
				"length": run_end - cursor,
				"flags": int(run.get("flags", 0)),
				"color": str(run.get("color", COLOR_TEXT.to_html(true))),
			})
	return result


func _coalesce_runs(runs: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for run: Dictionary in runs:
		if int(run.get("length", 0)) <= 0:
			continue
		if result.is_empty():
			result.append(run.duplicate(true))
			continue
		var previous: Dictionary = result[result.size() - 1]
		var previous_end: int = int(previous.get("start", 0)) + int(previous.get("length", 0))
		if (
			previous_end == int(run.get("start", 0))
			and int(previous.get("flags", 0)) == int(run.get("flags", 0))
			and str(previous.get("color", "")) == str(run.get("color", ""))
		):
			previous["length"] = int(previous.get("length", 0)) + int(run.get("length", 0))
			result[result.size() - 1] = previous
		else:
			result.append(run.duplicate(true))
	return result


func _style_from_run_array(
	runs: Array[Dictionary],
	character_offset: int,
	fallback_flags: int,
	fallback_color: Color
) -> Dictionary:
	for run: Dictionary in runs:
		var start: int = int(run.get("start", 0))
		var end: int = start + int(run.get("length", 0))
		if character_offset >= start and character_offset < end:
			return {
				"flags": int(run.get("flags", fallback_flags)),
				"color": _parse_color(run.get("color", ""), fallback_color),
			}
	return {"flags": fallback_flags, "color": fallback_color}


func _common_prefix_length(a: String, b: String) -> int:
	var limit: int = mini(a.length(), b.length())
	var result: int = 0
	while result < limit and a.substr(result, 1) == b.substr(result, 1):
		result += 1
	return result


func _common_suffix_length(a: String, b: String, prefix: int) -> int:
	var max_suffix: int = mini(a.length(), b.length()) - prefix
	var result: int = 0
	while (
		result < max_suffix
		and a.substr(a.length() - result - 1, 1) == b.substr(b.length() - result - 1, 1)
	):
		result += 1
	return result


func _make_run(start: int, length: int, flags: int, color: Color) -> Dictionary:
	return {
		"start": start,
		"length": length,
		"flags": flags & FONT_STYLE_ALL,
		"color": color.to_html(true),
	}


func _maybe_compact_pools(force_check: bool = false) -> void:
	if not force_check and _pool_mutations_since_compaction < 128:
		return
	_pool_mutations_since_compaction = 0
	var live_runs: int = 0
	var live_paragraphs: int = 0
	for count: int in run_counts:
		live_runs += count
	for count: int in paragraph_counts:
		live_paragraphs += count
	if _pool_garbage_runs > maxi(256, live_runs) or _pool_garbage_paragraphs > maxi(256, live_paragraphs):
		_compact_pools()


func _compact_pools() -> void:
	var next_run_starts: PackedInt32Array = PackedInt32Array()
	var next_run_lengths: PackedInt32Array = PackedInt32Array()
	var next_run_flags: PackedInt32Array = PackedInt32Array()
	var next_run_colors: PackedColorArray = PackedColorArray()
	var next_paragraph_types: PackedInt32Array = PackedInt32Array()
	var next_paragraph_indents: PackedInt32Array = PackedInt32Array()
	for index: int in range(entity_ids.size()):
		var old_run_offset: int = int(run_offsets[index])
		var run_count: int = int(run_counts[index])
		run_offsets[index] = next_run_starts.size()
		for local_run: int in range(run_count):
			var source_run: int = old_run_offset + local_run
			next_run_starts.append(_run_starts[source_run])
			next_run_lengths.append(_run_lengths[source_run])
			next_run_flags.append(_run_flags[source_run])
			next_run_colors.append(_run_colors[source_run])
		var old_paragraph_offset: int = int(paragraph_offsets[index])
		var paragraph_count: int = int(paragraph_counts[index])
		paragraph_offsets[index] = next_paragraph_types.size()
		for local_paragraph: int in range(paragraph_count):
			var source_paragraph: int = old_paragraph_offset + local_paragraph
			next_paragraph_types.append(_paragraph_list_types[source_paragraph])
			next_paragraph_indents.append(_paragraph_indents[source_paragraph])
	_run_starts = next_run_starts
	_run_lengths = next_run_lengths
	_run_flags = next_run_flags
	_run_colors = next_run_colors
	_paragraph_list_types = next_paragraph_types
	_paragraph_indents = next_paragraph_indents
	_pool_garbage_runs = 0
	_pool_garbage_paragraphs = 0
	_pool_mutations_since_compaction = 0


func _safe_font_family(value: String) -> String:
	var stripped: String = value.strip_edges()
	return DEFAULT_FONT_FAMILY if stripped.is_empty() else stripped


func _parse_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value as Color
	var text: String = str(value)
	if text.is_empty() or not Color.html_is_valid(text):
		return fallback
	return Color(text)
