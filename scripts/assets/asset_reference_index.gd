# SPDX-License-Identifier: GPL-3.0-or-later
class_name AssetReferenceIndex
extends RefCounted

var _boards_by_asset: Dictionary = {}
var _assets_by_board: Dictionary = {}
var _board_names: Dictionary = {}
var _notes_by_asset: Dictionary = {}
var _assets_by_note: Dictionary = {}
var _external_owners_by_asset: Dictionary = {}
var _assets_by_external_owner: Dictionary = {}
var _external_owner_labels: Dictionary = {}


func rebuild(repository: BoardRepository) -> void:
	_boards_by_asset.clear()
	_assets_by_board.clear()
	_board_names.clear()
	if repository == null:
		return
	var boards: Array[Dictionary] = repository.list_boards()
	for metadata: Dictionary in boards:
		set_board_metadata(metadata)


func set_board_metadata(metadata: Dictionary) -> bool:
	var board_id: String = str(metadata.get("id", "")).strip_edges()
	if board_id.is_empty():
		return false
	var board_name: String = str(metadata.get("name", NotLightL10n.text("modules.library.board_fallback"))).strip_edges()
	if board_name.is_empty():
		board_name = NotLightL10n.text("modules.library.board_fallback")
	var next_refs: PackedStringArray = _normalized_refs(metadata.get("asset_refs", []))
	var previous_refs: PackedStringArray = PackedStringArray()
	if _assets_by_board.has(board_id):
		previous_refs = (_assets_by_board[board_id] as PackedStringArray).duplicate()
	var previous_name: String = str(_board_names.get(board_id, ""))
	if previous_name == board_name and _packed_strings_equal(previous_refs, next_refs):
		return false
	_remove_board_from_reverse_index(board_id, previous_refs)
	_assets_by_board[board_id] = next_refs
	_board_names[board_id] = board_name
	for asset_id: String in next_refs:
		var board_ids: PackedStringArray = PackedStringArray()
		if _boards_by_asset.has(asset_id):
			board_ids = (_boards_by_asset[asset_id] as PackedStringArray).duplicate()
		if not board_ids.has(board_id):
			board_ids.append(board_id)
			board_ids.sort()
		_boards_by_asset[asset_id] = board_ids
	return true


func remove_board(board_id: String) -> bool:
	var clean_id: String = board_id.strip_edges()
	if clean_id.is_empty() or not _assets_by_board.has(clean_id):
		# A board with no asset refs may still have a cached display name.
		if _board_names.has(clean_id):
			_board_names.erase(clean_id)
			return true
		return false
	var previous_refs: PackedStringArray = (_assets_by_board[clean_id] as PackedStringArray).duplicate()
	_remove_board_from_reverse_index(clean_id, previous_refs)
	_assets_by_board.erase(clean_id)
	_board_names.erase(clean_id)
	return true


func is_used(asset_id: String) -> bool:
	return usage_count(asset_id) > 0


func usage_count(asset_id: String) -> int:
	return board_usage_count(asset_id) + note_embed_usage_count(asset_id) + external_usage_count(asset_id)


func board_usage_count(asset_id: String) -> int:
	return (_boards_by_asset[asset_id] as PackedStringArray).size() if _boards_by_asset.has(asset_id) else 0


func note_embed_usage_count(asset_id: String) -> int:
	return (_notes_by_asset[asset_id] as PackedStringArray).size() if _notes_by_asset.has(asset_id) else 0


func external_usage_count(asset_id: String) -> int:
	return (_external_owners_by_asset[asset_id] as PackedStringArray).size() if _external_owners_by_asset.has(asset_id) else 0


func external_labels_for(asset_id: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if not _external_owners_by_asset.has(asset_id):
		return result
	for owner_id: String in (_external_owners_by_asset[asset_id] as PackedStringArray):
		var label: String = str(_external_owner_labels.get(owner_id, owner_id)).strip_edges()
		if not label.is_empty():
			result.append(label)
	result.sort()
	return result


func set_external_refs(owner_id: String, asset_ids: PackedStringArray, label: String = "") -> bool:
	var clean_owner: String = owner_id.strip_edges()
	if clean_owner.is_empty():
		return false
	var next_refs: PackedStringArray = _normalized_refs(asset_ids)
	var previous_refs: PackedStringArray = PackedStringArray()
	if _assets_by_external_owner.has(clean_owner):
		previous_refs = (_assets_by_external_owner[clean_owner] as PackedStringArray).duplicate()
	var clean_label: String = label.strip_edges()
	var previous_label: String = str(_external_owner_labels.get(clean_owner, ""))
	if _packed_strings_equal(previous_refs, next_refs) and previous_label == clean_label:
		return false
	_remove_external_owner_from_reverse_index(clean_owner, previous_refs)
	if next_refs.is_empty():
		_assets_by_external_owner.erase(clean_owner)
		_external_owner_labels.erase(clean_owner)
		return true
	_assets_by_external_owner[clean_owner] = next_refs
	_external_owner_labels[clean_owner] = clean_label if not clean_label.is_empty() else clean_owner
	for asset_id: String in next_refs:
		var owners: PackedStringArray = PackedStringArray()
		if _external_owners_by_asset.has(asset_id):
			owners = (_external_owners_by_asset[asset_id] as PackedStringArray).duplicate()
		if not owners.has(clean_owner):
			owners.append(clean_owner)
			owners.sort()
		_external_owners_by_asset[asset_id] = owners
	return true


func remove_external_refs(owner_id: String) -> bool:
	var clean_owner: String = owner_id.strip_edges()
	if clean_owner.is_empty() or not _assets_by_external_owner.has(clean_owner):
		return false
	var previous_refs: PackedStringArray = (_assets_by_external_owner[clean_owner] as PackedStringArray).duplicate()
	_remove_external_owner_from_reverse_index(clean_owner, previous_refs)
	_assets_by_external_owner.erase(clean_owner)
	_external_owner_labels.erase(clean_owner)
	return true


func referenced_asset_ids() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	for raw_key: Variant in _boards_by_asset.keys():
		seen[str(raw_key)] = true
	for raw_key: Variant in _notes_by_asset.keys():
		seen[str(raw_key)] = true
	for raw_key: Variant in _external_owners_by_asset.keys():
		seen[str(raw_key)] = true
	var keys: Array = seen.keys()
	keys.sort()
	for raw_key: Variant in keys:
		result.append(str(raw_key))
	return result


func set_note_embed_refs(note_id: String, asset_ids: PackedStringArray) -> bool:
	var clean_note_id: String = note_id.strip_edges()
	if clean_note_id.is_empty():
		return false
	var next_refs: PackedStringArray = _normalized_refs(asset_ids)
	var previous_refs: PackedStringArray = PackedStringArray()
	if _assets_by_note.has(clean_note_id):
		previous_refs = (_assets_by_note[clean_note_id] as PackedStringArray).duplicate()
	if _packed_strings_equal(previous_refs, next_refs):
		return false
	_remove_note_from_reverse_index(clean_note_id, previous_refs)
	_assets_by_note[clean_note_id] = next_refs
	for asset_id: String in next_refs:
		var note_ids: PackedStringArray = PackedStringArray()
		if _notes_by_asset.has(asset_id):
			note_ids = (_notes_by_asset[asset_id] as PackedStringArray).duplicate()
		if not note_ids.has(clean_note_id):
			note_ids.append(clean_note_id)
			note_ids.sort()
		_notes_by_asset[asset_id] = note_ids
	return true


func remove_note_embed_refs(note_id: String) -> bool:
	var clean_note_id: String = note_id.strip_edges()
	if clean_note_id.is_empty() or not _assets_by_note.has(clean_note_id):
		return false
	var previous_refs: PackedStringArray = (_assets_by_note[clean_note_id] as PackedStringArray).duplicate()
	_remove_note_from_reverse_index(clean_note_id, previous_refs)
	_assets_by_note.erase(clean_note_id)
	return true


func note_ids_for(asset_id: String) -> PackedStringArray:
	if not _notes_by_asset.has(asset_id):
		return PackedStringArray()
	return (_notes_by_asset[asset_id] as PackedStringArray).duplicate()


func board_ids_for(asset_id: String) -> PackedStringArray:
	if not _boards_by_asset.has(asset_id):
		return PackedStringArray()
	return (_boards_by_asset[asset_id] as PackedStringArray).duplicate()


func board_names_for(asset_id: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for board_id: String in board_ids_for(asset_id):
		result.append(str(_board_names.get(board_id, board_id)))
	return result


func board_entries_for(asset_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for board_id: String in board_ids_for(asset_id):
		result.append({
			"id": board_id,
			"name": str(_board_names.get(board_id, board_id)),
		})
	return result


func _normalized_refs(raw_refs: Variant) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if raw_refs is PackedStringArray:
		for asset_id: String in (raw_refs as PackedStringArray):
			var clean_id: String = asset_id.strip_edges()
			if not clean_id.is_empty() and not result.has(clean_id):
				result.append(clean_id)
	elif raw_refs is Array:
		for raw_asset_id: Variant in (raw_refs as Array):
			var clean_id: String = str(raw_asset_id).strip_edges()
			if not clean_id.is_empty() and not result.has(clean_id):
				result.append(clean_id)
	result.sort()
	return result


func _remove_board_from_reverse_index(board_id: String, refs: PackedStringArray) -> void:
	for asset_id: String in refs:
		if not _boards_by_asset.has(asset_id):
			continue
		var board_ids: PackedStringArray = (_boards_by_asset[asset_id] as PackedStringArray).duplicate()
		var index: int = board_ids.find(board_id)
		if index >= 0:
			board_ids.remove_at(index)
		if board_ids.is_empty():
			_boards_by_asset.erase(asset_id)
		else:
			_boards_by_asset[asset_id] = board_ids


func _remove_note_from_reverse_index(note_id: String, refs: PackedStringArray) -> void:
	for asset_id: String in refs:
		if not _notes_by_asset.has(asset_id):
			continue
		var note_ids: PackedStringArray = (_notes_by_asset[asset_id] as PackedStringArray).duplicate()
		var index: int = note_ids.find(note_id)
		if index >= 0:
			note_ids.remove_at(index)
		if note_ids.is_empty():
			_notes_by_asset.erase(asset_id)
		else:
			_notes_by_asset[asset_id] = note_ids


func _remove_external_owner_from_reverse_index(owner_id: String, refs: PackedStringArray) -> void:
	for asset_id: String in refs:
		if not _external_owners_by_asset.has(asset_id):
			continue
		var owners: PackedStringArray = (_external_owners_by_asset[asset_id] as PackedStringArray).duplicate()
		var index: int = owners.find(owner_id)
		if index >= 0:
			owners.remove_at(index)
		if owners.is_empty():
			_external_owners_by_asset.erase(asset_id)
		else:
			_external_owners_by_asset[asset_id] = owners


func _packed_strings_equal(left: PackedStringArray, right: PackedStringArray) -> bool:
	if left.size() != right.size():
		return false
	for index: int in range(left.size()):
		if left[index] != right[index]:
			return false
	return true
