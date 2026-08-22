# SPDX-License-Identifier: GPL-3.0-or-later
class_name FormulaStore
extends BoardDataStore

signal formula_added(entity_id: int)
signal formula_changed(entity_id: int)
signal formula_removed(entity_id: int)
signal cleared

const STORE_ID: StringName = &"formulas"
const DISPLAY_INLINE: int = 0
const DISPLAY_BLOCK: int = 1
const DEFAULT_DISPLAY_MODE: int = DISPLAY_BLOCK
const DEFAULT_FONT_SCALE: float = 1.0
const MIN_FONT_SCALE: float = 0.5
const MAX_FONT_SCALE: float = 3.0
const DEFAULT_FOREGROUND: Color = Color("#26372d")
const MAX_SOURCE_LENGTH: int = 8192

var entity_ids: PackedInt64Array = PackedInt64Array()
var source_latex: PackedStringArray = PackedStringArray()
var display_modes: PackedByteArray = PackedByteArray()
var font_scales: PackedFloat32Array = PackedFloat32Array()
var foregrounds: PackedColorArray = PackedColorArray()
var revisions: PackedInt64Array = PackedInt64Array()

var _index_by_id: Dictionary = {}
var _store_revision: int = 0


func _init() -> void:
	super(STORE_ID)


func add_formula(
	entity_id: int,
	source: String,
	display_mode: int = DEFAULT_DISPLAY_MODE,
	font_scale: float = DEFAULT_FONT_SCALE,
	foreground: Color = DEFAULT_FOREGROUND
) -> bool:
	if entity_id <= 0 or _index_by_id.has(entity_id):
		return false
	var index: int = entity_ids.size()
	entity_ids.append(entity_id)
	source_latex.append(normalize_source(source))
	display_modes.append(normalize_display_mode(display_mode))
	font_scales.append(clampf(font_scale, MIN_FONT_SCALE, MAX_FONT_SCALE))
	foregrounds.append(foreground)
	revisions.append(1)
	_index_by_id[entity_id] = index
	_store_revision += 1
	formula_added.emit(entity_id)
	return true


func contains(entity_id: int) -> bool:
	return _index_by_id.has(entity_id)


func size() -> int:
	return entity_ids.size()


func get_index(entity_id: int) -> int:
	return int(_index_by_id.get(entity_id, -1))


func get_source(entity_id: int) -> String:
	var index: int = get_index(entity_id)
	return source_latex[index] if index >= 0 else ""


func get_display_mode(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	return int(display_modes[index]) if index >= 0 else DEFAULT_DISPLAY_MODE


func get_font_scale(entity_id: int) -> float:
	var index: int = get_index(entity_id)
	return float(font_scales[index]) if index >= 0 else DEFAULT_FONT_SCALE


func get_foreground(entity_id: int) -> Color:
	var index: int = get_index(entity_id)
	return foregrounds[index] if index >= 0 else DEFAULT_FOREGROUND


func get_revision(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	return int(revisions[index]) if index >= 0 else 0


func get_store_revision() -> int:
	return _store_revision


func get_record(entity_id: int) -> Dictionary:
	var index: int = get_index(entity_id)
	if index < 0:
		return {}
	return {
		"entity_id": str(entity_ids[index]),
		"source_latex": source_latex[index],
		"display_mode": int(display_modes[index]),
		"font_scale": float(font_scales[index]),
		"foreground": foregrounds[index].to_html(true),
	}


func capture_record(entity_id: int) -> Dictionary:
	return get_record(entity_id)


func apply_record(entity_id: int, record: Dictionary) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var next_source: String = normalize_source(str(record.get("source_latex", source_latex[index])))
	var next_mode: int = normalize_display_mode(int(record.get("display_mode", int(display_modes[index]))))
	var next_scale: float = clampf(float(record.get("font_scale", float(font_scales[index]))), MIN_FONT_SCALE, MAX_FONT_SCALE)
	var next_color: Color = _color_from_variant(record.get("foreground", foregrounds[index]), foregrounds[index])
	if (
		source_latex[index] == next_source
		and int(display_modes[index]) == next_mode
		and is_equal_approx(float(font_scales[index]), next_scale)
		and foregrounds[index] == next_color
	):
		return true
	source_latex[index] = next_source
	display_modes[index] = next_mode
	font_scales[index] = next_scale
	foregrounds[index] = next_color
	_touch(index, entity_id)
	return true


func restore_record(record: Dictionary) -> bool:
	var entity_id: int = int(str(record.get("entity_id", "0")))
	if entity_id <= 0:
		return false
	return add_formula(
		entity_id,
		str(record.get("source_latex", "")),
		int(record.get("display_mode", DEFAULT_DISPLAY_MODE)),
		float(record.get("font_scale", DEFAULT_FONT_SCALE)),
		_color_from_variant(record.get("foreground", DEFAULT_FOREGROUND), DEFAULT_FOREGROUND)
	)


func remap_record(record: Dictionary, id_map: Dictionary) -> Dictionary:
	var remapped: Dictionary = record.duplicate(true)
	var old_entity_id: int = int(str(record.get("entity_id", "0")))
	if old_entity_id > 0 and id_map.has(old_entity_id):
		remapped["entity_id"] = str(int(id_map[old_entity_id]))
	return remapped


func remove(entity_id: int) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var last_index: int = entity_ids.size() - 1
	if index != last_index:
		entity_ids[index] = entity_ids[last_index]
		source_latex[index] = source_latex[last_index]
		display_modes[index] = display_modes[last_index]
		font_scales[index] = font_scales[last_index]
		foregrounds[index] = foregrounds[last_index]
		revisions[index] = revisions[last_index]
		_index_by_id[int(entity_ids[index])] = index
	entity_ids.resize(last_index)
	source_latex.resize(last_index)
	display_modes.resize(last_index)
	font_scales.resize(last_index)
	foregrounds.resize(last_index)
	revisions.resize(last_index)
	_index_by_id.erase(entity_id)
	_store_revision += 1
	formula_removed.emit(entity_id)
	return true


func clear() -> void:
	if entity_ids.is_empty():
		return
	entity_ids = PackedInt64Array()
	source_latex = PackedStringArray()
	display_modes = PackedByteArray()
	font_scales = PackedFloat32Array()
	foregrounds = PackedColorArray()
	revisions = PackedInt64Array()
	_index_by_id.clear()
	_store_revision += 1
	cleared.emit()


func serialize() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entity_id: int in entity_ids:
		result.append(get_record(entity_id))
	return result


func deserialize(records: Array) -> void:
	clear()
	for raw_record: Variant in records:
		if raw_record is Dictionary:
			restore_record(raw_record as Dictionary)
	_store_revision = 0


static func normalize_source(source: String) -> String:
	var normalized: String = source.replace("\r\n", "\n").replace("\r", "\n")
	var bytes: PackedByteArray = normalized.to_utf8_buffer()
	var contains_nul: bool = false
	for value: int in bytes:
		if value == 0:
			contains_nul = true
			break
	if not contains_nul:
		return normalized.left(MAX_SOURCE_LENGTH)
	var clean_bytes: PackedByteArray = PackedByteArray()
	clean_bytes.resize(bytes.size())
	var write_index: int = 0
	for value: int in bytes:
		if value == 0:
			continue
		clean_bytes[write_index] = value
		write_index += 1
	clean_bytes.resize(write_index)
	return clean_bytes.get_string_from_utf8().left(MAX_SOURCE_LENGTH)


static func normalize_display_mode(value: int) -> int:
	return DISPLAY_INLINE if value == DISPLAY_INLINE else DISPLAY_BLOCK


func _touch(index: int, entity_id: int) -> void:
	revisions[index] = int(revisions[index]) + 1
	_store_revision += 1
	formula_changed.emit(entity_id)


static func _color_from_variant(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value as Color
	return Color.from_string(str(value).strip_edges(), fallback)
