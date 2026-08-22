# SPDX-License-Identifier: GPL-3.0-or-later
class_name NotePortalStore
extends BoardDataStore

signal portal_added(entity_id: int)
signal portal_changed(entity_id: int)
signal portal_removed(entity_id: int)
signal cleared

const STORE_ID: StringName = &"note_portals"
const VIEW_PREVIEW: int = 0
const VIEW_SOURCE: int = 1
const VIEW_SPLIT: int = 2
const VIEW_WORKSPACE: int = 3
const MAX_WORKSPACE_TABS: int = 12
const DEFAULT_VIEW_MODE: int = VIEW_PREVIEW

var entity_ids: PackedInt64Array = PackedInt64Array()
var note_ids: PackedStringArray = PackedStringArray()
var view_modes: PackedInt32Array = PackedInt32Array()
var scroll_offsets: PackedFloat32Array = PackedFloat32Array()
var workspace_tabs: Array[PackedStringArray] = []
var workspace_active_indices: PackedInt32Array = PackedInt32Array()
var revisions: PackedInt64Array = PackedInt64Array()
var _index_by_id: Dictionary = {}
var _store_revision: int = 0


func _init() -> void:
	super(STORE_ID)


func add_portal(entity_id: int, note_id: String, view_mode: int = DEFAULT_VIEW_MODE, scroll_offset: float = 0.0) -> bool:
	if entity_id <= 0 or _index_by_id.has(entity_id):
		return false
	var clean_note_id: String = note_id.strip_edges()
	if clean_note_id.is_empty():
		return false
	var index: int = entity_ids.size()
	entity_ids.append(entity_id)
	note_ids.append(clean_note_id)
	view_modes.append(clampi(view_mode, VIEW_PREVIEW, VIEW_WORKSPACE))
	scroll_offsets.append(maxf(0.0, scroll_offset))
	workspace_tabs.append(PackedStringArray([clean_note_id]) if view_mode == VIEW_WORKSPACE else PackedStringArray())
	workspace_active_indices.append(0)
	revisions.append(1)
	_index_by_id[entity_id] = index
	_store_revision += 1
	portal_added.emit(entity_id)
	return true


func contains(entity_id: int) -> bool:
	return _index_by_id.has(entity_id)


func size() -> int:
	return entity_ids.size()


func get_index(entity_id: int) -> int:
	return int(_index_by_id.get(entity_id, -1))


func get_note_id(entity_id: int) -> String:
	var index: int = get_index(entity_id)
	return note_ids[index] if index >= 0 else ""


func get_view_mode(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	return int(view_modes[index]) if index >= 0 else DEFAULT_VIEW_MODE


func set_view_mode(entity_id: int, view_mode: int) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var safe_mode: int = clampi(view_mode, VIEW_PREVIEW, VIEW_WORKSPACE)
	if int(view_modes[index]) == safe_mode:
		return true
	view_modes[index] = safe_mode
	_touch(index, entity_id)
	return true


func get_scroll_offset(entity_id: int) -> float:
	var index: int = get_index(entity_id)
	return float(scroll_offsets[index]) if index >= 0 else 0.0


func set_scroll_offset(entity_id: int, scroll_offset: float) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var safe_offset: float = maxf(0.0, scroll_offset)
	if is_equal_approx(float(scroll_offsets[index]), safe_offset):
		return true
	scroll_offsets[index] = safe_offset
	_touch(index, entity_id)
	return true


func get_workspace_tabs(entity_id: int) -> PackedStringArray:
	var index: int = get_index(entity_id)
	return workspace_tabs[index].duplicate() if index >= 0 else PackedStringArray()


func get_workspace_active_index(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	if index < 0:
		return 0
	return clampi(int(workspace_active_indices[index]), 0, maxi(0, workspace_tabs[index].size() - 1))


func set_workspace_state(entity_id: int, tabs: PackedStringArray, active_index: int) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var normalized: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	for raw_id: String in tabs:
		var note_id: String = raw_id.strip_edges()
		if note_id.is_empty() or seen.has(note_id):
			continue
		seen[note_id] = true
		normalized.append(note_id)
		if normalized.size() >= MAX_WORKSPACE_TABS:
			break
	if normalized.is_empty():
		normalized.append(note_ids[index])
	var safe_active: int = clampi(active_index, 0, normalized.size() - 1)
	var changed: bool = workspace_tabs[index] != normalized or int(workspace_active_indices[index]) != safe_active
	var active_note_id: String = normalized[safe_active]
	if note_ids[index] != active_note_id:
		note_ids[index] = active_note_id
		changed = true
	if not changed:
		return true
	workspace_tabs[index] = normalized
	workspace_active_indices[index] = safe_active
	_touch(index, entity_id)
	return true


func add_workspace_tab(entity_id: int, note_id: String, make_active: bool = true) -> bool:
	var index: int = get_index(entity_id)
	var clean_id: String = note_id.strip_edges()
	if index < 0 or clean_id.is_empty():
		return false
	var tabs: PackedStringArray = workspace_tabs[index].duplicate()
	var existing: int = tabs.find(clean_id)
	if existing < 0:
		if tabs.size() >= MAX_WORKSPACE_TABS:
			return false
		tabs.append(clean_id)
		existing = tabs.size() - 1
	return set_workspace_state(entity_id, tabs, existing if make_active else get_workspace_active_index(entity_id))


func close_workspace_tab(entity_id: int, tab_index: int) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var tabs: PackedStringArray = workspace_tabs[index].duplicate()
	if tab_index < 0 or tab_index >= tabs.size() or tabs.size() <= 1:
		return false
	var active: int = get_workspace_active_index(entity_id)
	tabs.remove_at(tab_index)
	if tab_index < active:
		active -= 1
	elif tab_index == active:
		active = mini(active, tabs.size() - 1)
	return set_workspace_state(entity_id, tabs, active)


func get_record(entity_id: int) -> Dictionary:
	var index: int = get_index(entity_id)
	if index < 0:
		return {}
	return {
		"entity_id": str(entity_ids[index]),
		# Keep the canonical Library reference under asset_id so the existing
		# BoardDocumentSchema asset-reference collector protects note deletion.
		"asset_id": note_ids[index],
		"view_mode": int(view_modes[index]),
		"scroll_offset": float(scroll_offsets[index]),
		"workspace_tabs": _tabs_to_array(workspace_tabs[index]),
		"workspace_active_index": int(workspace_active_indices[index]),
	}


func capture_record(entity_id: int) -> Dictionary:
	return get_record(entity_id)


func restore_record(record: Dictionary) -> bool:
	var entity_id: int = int(str(record.get("entity_id", "0")))
	var note_id: String = str(record.get("asset_id", record.get("note_id", ""))).strip_edges()
	if entity_id <= 0 or note_id.is_empty():
		return false
	var added: bool = add_portal(
		entity_id,
		note_id,
		int(record.get("view_mode", DEFAULT_VIEW_MODE)),
		float(record.get("scroll_offset", 0.0))
	)
	if not added:
		return false
	if get_view_mode(entity_id) == VIEW_WORKSPACE:
		var tabs: PackedStringArray = PackedStringArray()
		var raw_tabs: Variant = record.get("workspace_tabs", [])
		if raw_tabs is Array:
			for raw_id: Variant in raw_tabs as Array:
				tabs.append(str(raw_id))
		set_workspace_state(entity_id, tabs, int(record.get("workspace_active_index", 0)))
	return true


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
		note_ids[index] = note_ids[last_index]
		view_modes[index] = view_modes[last_index]
		scroll_offsets[index] = scroll_offsets[last_index]
		workspace_tabs[index] = workspace_tabs[last_index]
		workspace_active_indices[index] = workspace_active_indices[last_index]
		revisions[index] = revisions[last_index]
		_index_by_id[int(entity_ids[index])] = index
	entity_ids.resize(last_index)
	note_ids.resize(last_index)
	view_modes.resize(last_index)
	scroll_offsets.resize(last_index)
	workspace_tabs.resize(last_index)
	workspace_active_indices.resize(last_index)
	revisions.resize(last_index)
	_index_by_id.erase(entity_id)
	_store_revision += 1
	portal_removed.emit(entity_id)
	return true


func clear() -> void:
	if entity_ids.is_empty():
		return
	entity_ids = PackedInt64Array()
	note_ids = PackedStringArray()
	view_modes = PackedInt32Array()
	scroll_offsets = PackedFloat32Array()
	workspace_tabs = []
	workspace_active_indices = PackedInt32Array()
	revisions = PackedInt64Array()
	_index_by_id.clear()
	_store_revision += 1
	cleared.emit()


func serialize() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.resize(entity_ids.size())
	for index: int in range(entity_ids.size()):
		result[index] = {
			"entity_id": str(entity_ids[index]),
			"asset_id": note_ids[index],
			"view_mode": int(view_modes[index]),
			"scroll_offset": float(scroll_offsets[index]),
			"workspace_tabs": _tabs_to_array(workspace_tabs[index]),
			"workspace_active_index": int(workspace_active_indices[index]),
		}
	return result


func deserialize(records: Array) -> void:
	clear()
	for raw_record: Variant in records:
		if raw_record is Dictionary:
			restore_record(raw_record as Dictionary)
	_store_revision = 0


func _tabs_to_array(tabs: PackedStringArray) -> Array[String]:
	var output: Array[String] = []
	output.resize(tabs.size())
	for index: int in range(tabs.size()):
		output[index] = tabs[index]
	return output


func get_store_revision() -> int:
	return _store_revision


func _touch(index: int, entity_id: int) -> void:
	revisions[index] = int(revisions[index]) + 1
	_store_revision += 1
	portal_changed.emit(entity_id)
