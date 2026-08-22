# SPDX-License-Identifier: GPL-3.0-or-later
class_name CreateNotePortalCommand
extends BoardCommand

var bounds: Rect2 = Rect2()
var note_id: String = ""
var view_mode: int = NotePortalStore.DEFAULT_VIEW_MODE
var z_order: int = 0
var created_entity_id: int = 0


func _init(new_bounds: Rect2, new_note_id: String, new_view_mode: int = NotePortalStore.DEFAULT_VIEW_MODE, new_z_order: int = 0) -> void:
	label = NotLightL10n.text("runtime.core.create_note_portal_command.3d4e64f1e8")
	bounds = new_bounds
	note_id = new_note_id.strip_edges()
	view_mode = clampi(new_view_mode, NotePortalStore.VIEW_PREVIEW, NotePortalStore.VIEW_WORKSPACE)
	z_order = new_z_order


func execute(runtime: BoardRuntime) -> bool:
	if runtime == null or note_id.is_empty():
		return false
	runtime.begin_change_batch()
	if created_entity_id > 0:
		if not runtime.restore_entity(
			created_entity_id,
			BoardEntityTypes.NOTE_PORTAL,
			bounds,
			0.0,
			z_order,
			BoardTransformStore.FLAG_VISIBLE
		):
			runtime.end_change_batch()
			return false
	else:
		created_entity_id = runtime.create_entity(
			BoardEntityTypes.NOTE_PORTAL,
			bounds,
			0.0,
			z_order,
			BoardTransformStore.FLAG_VISIBLE
		)
		if created_entity_id <= 0:
			runtime.end_change_batch()
			return false
	var added: bool = runtime.model.note_portals.add_portal(created_entity_id, note_id, view_mode)
	if not added:
		runtime.remove_entity(created_entity_id)
	runtime.end_change_batch()
	return added


func undo(runtime: BoardRuntime) -> bool:
	return runtime != null and created_entity_id > 0 and runtime.remove_entity(created_entity_id)
