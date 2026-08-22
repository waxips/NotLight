# SPDX-License-Identifier: GPL-3.0-or-later
class_name CreateTextBlockCommand
extends BoardCommand

var bounds: Rect2 = Rect2()
var text: String = ""
var font_size: float = TextBlockStore.DEFAULT_FONT_SIZE
var font_family: String = TextBlockStore.DEFAULT_FONT_FAMILY
var alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
var layout_mode: int = TextBlockStore.LAYOUT_AUTO_WIDTH
var background_color: Color = Color.TRANSPARENT
var text_color: Color = TextBlockStore.COLOR_TEXT
var base_style_flags: int = 0
var style_runs: Array[Dictionary] = []
var paragraphs: Array[Dictionary] = []
var z_order: int = 0
var created_entity_id: int = 0
var final_record: Dictionary = {}


func _init(
	new_bounds: Rect2,
	new_text: String = "",
	new_font_size: float = TextBlockStore.DEFAULT_FONT_SIZE,
	new_alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	_new_style_id: int = TextBlockStore.STYLE_PLAIN,
	new_layout_mode: int = TextBlockStore.LAYOUT_AUTO_WIDTH,
	new_background_color: Color = Color.TRANSPARENT,
	new_text_color: Color = TextBlockStore.COLOR_TEXT,
	new_z_order: int = 0,
	new_font_family: String = TextBlockStore.DEFAULT_FONT_FAMILY,
	new_base_style_flags: int = 0,
	new_style_runs: Array[Dictionary] = [],
	new_paragraphs: Array[Dictionary] = []
) -> void:
	label = NotLightL10n.text("runtime.core.create_text_block_command.cbe7ae2354")
	bounds = new_bounds
	text = new_text
	font_size = new_font_size
	font_family = new_font_family
	alignment = new_alignment
	layout_mode = new_layout_mode
	background_color = new_background_color
	text_color = new_text_color
	base_style_flags = new_base_style_flags
	style_runs = new_style_runs.duplicate(true)
	paragraphs = new_paragraphs.duplicate(true)
	z_order = new_z_order


func set_final_state(record: Dictionary, final_bounds_value: Rect2) -> void:
	final_record = record.duplicate(true)
	bounds = final_bounds_value
	text = str(record.get("text", text))
	font_size = float(record.get("font_size", font_size))
	font_family = str(record.get("font_family", font_family))
	alignment = clampi(int(record.get("alignment", int(alignment))), HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_RIGHT) as HorizontalAlignment
	layout_mode = clampi(int(record.get("layout_mode", layout_mode)), TextBlockStore.LAYOUT_AUTO_WIDTH, TextBlockStore.LAYOUT_FIXED_WIDTH)
	background_color = Color.from_string(str(record.get("background_color", background_color.to_html(true))), background_color)
	text_color = Color.from_string(str(record.get("text_color", text_color.to_html(true))), text_color)
	base_style_flags = int(record.get("base_style_flags", base_style_flags))
	style_runs = (record.get("style_runs", style_runs) as Array).duplicate(true)
	paragraphs = (record.get("paragraphs", paragraphs) as Array).duplicate(true)


func execute(runtime: BoardRuntime) -> bool:
	if runtime == null:
		return false
	runtime.begin_change_batch()
	if created_entity_id > 0:
		if not runtime.restore_entity(created_entity_id, BoardEntityTypes.TEXT, bounds, 0.0, z_order, BoardTransformStore.FLAG_VISIBLE):
			runtime.end_change_batch()
			return false
	else:
		created_entity_id = runtime.create_entity(BoardEntityTypes.TEXT, bounds, 0.0, z_order, BoardTransformStore.FLAG_VISIBLE)
		if created_entity_id <= 0:
			runtime.end_change_batch()
			return false
	var added: bool = runtime.model.text_blocks.add_block(
		created_entity_id,
		text,
		font_size,
		alignment,
		TextBlockStore.STYLE_PLAIN,
		layout_mode,
		background_color,
		text_color,
		font_family,
		base_style_flags,
		style_runs,
		paragraphs
	)
	if added and not final_record.is_empty():
		var restored_record: Dictionary = final_record.duplicate(true)
		restored_record["entity_id"] = str(created_entity_id)
		added = runtime.model.text_blocks.apply_record(created_entity_id, restored_record)
	if not added:
		runtime.remove_entity(created_entity_id)
	runtime.end_change_batch()
	return added


func undo(runtime: BoardRuntime) -> bool:
	return runtime != null and created_entity_id > 0 and runtime.remove_entity(created_entity_id)
