# SPDX-License-Identifier: GPL-3.0-or-later
class_name CreateFormulaCommand
extends BoardCommand

var bounds: Rect2 = Rect2()
var source_latex: String = ""
var display_mode: int = FormulaStore.DEFAULT_DISPLAY_MODE
var font_scale: float = FormulaStore.DEFAULT_FONT_SCALE
var foreground: Color = FormulaStore.DEFAULT_FOREGROUND
var z_order: int = 0
var created_entity_id: int = 0


func _init(
	new_bounds: Rect2,
	new_source_latex: String,
	new_display_mode: int = FormulaStore.DEFAULT_DISPLAY_MODE,
	new_font_scale: float = FormulaStore.DEFAULT_FONT_SCALE,
	new_foreground: Color = FormulaStore.DEFAULT_FOREGROUND,
	new_z_order: int = 0
) -> void:
	label = NotLightL10n.text("command.formula.create")
	bounds = Rect2(new_bounds.position, Vector2(maxf(36.0, new_bounds.size.x), maxf(28.0, new_bounds.size.y)))
	source_latex = FormulaStore.normalize_source(new_source_latex)
	display_mode = FormulaStore.normalize_display_mode(new_display_mode)
	font_scale = clampf(new_font_scale, FormulaStore.MIN_FONT_SCALE, FormulaStore.MAX_FONT_SCALE)
	foreground = new_foreground
	z_order = new_z_order


func execute(runtime: BoardRuntime) -> bool:
	if runtime == null or source_latex.strip_edges().is_empty():
		return false
	runtime.begin_change_batch()
	if created_entity_id > 0:
		if not runtime.restore_entity(created_entity_id, BoardEntityTypes.FORMULA, bounds, 0.0, z_order, BoardTransformStore.FLAG_VISIBLE):
			runtime.end_change_batch()
			return false
	else:
		created_entity_id = runtime.create_entity(BoardEntityTypes.FORMULA, bounds, 0.0, z_order, BoardTransformStore.FLAG_VISIBLE)
		if created_entity_id <= 0:
			runtime.end_change_batch()
			return false
	var added: bool = runtime.model.formulas.add_formula(created_entity_id, source_latex, display_mode, font_scale, foreground)
	if not added:
		runtime.remove_entity(created_entity_id)
	runtime.end_change_batch()
	return added


func undo(runtime: BoardRuntime) -> bool:
	return runtime != null and created_entity_id > 0 and runtime.remove_entity(created_entity_id)
