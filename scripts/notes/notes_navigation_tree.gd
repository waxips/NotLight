# SPDX-License-Identifier: GPL-3.0-or-later
class_name NotesNavigationTree
extends Tree

signal note_open_requested(note_id: String, open_in_new_tab: bool)
signal note_selected(note_id: String)
signal folder_selected(folder_id: String)
signal note_move_requested(note_id: String, folder_id: String)
signal note_rename_requested(note_id: String, title: String)
signal folder_rename_requested(folder_id: String, name: String)

const KIND_FOLDER: String = "folder"
const KIND_NOTE: String = "note"
const ROOT_ALL: String = AssetLibraryService.FOLDER_ANY
const ROOT_UNFILED: String = ""
const MAX_TREE_DEPTH: int = 24

var repository: NoteRepository
var _query: String = ""
var _selected_note_id: String = ""
var _selected_folder_id: String = ROOT_ALL
var _folder_icon: Texture2D
var _note_icon: Texture2D
var _item_by_note_id: Dictionary = {}
var _item_by_folder_id: Dictionary = {}
var _collapsed_by_folder_id: Dictionary = {}
var _suppress_collapse_capture_once: bool = false


func _ready() -> void:
	theme_type_variation = "NoteNavigationTree"
	hide_root = true
	columns = 1
	select_mode = Tree.SELECT_ROW
	allow_reselect = true
	allow_rmb_select = true
	scroll_horizontal_enabled = false
	drop_mode_flags = Tree.DROP_MODE_ON_ITEM
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_folder_icon = load("res://assets/icons/folder.svg") as Texture2D
	_note_icon = load("res://assets/icons/note.svg") as Texture2D
	item_selected.connect(_on_item_selected)
	item_activated.connect(_on_item_activated)
	item_edited.connect(_on_item_edited)


func configure(note_repository: NoteRepository) -> void:
	repository = note_repository
	refresh()


func set_query(query: String) -> void:
	var clean: String = query.strip_edges()
	if _query == clean:
		return
	if _query.is_empty() and not clean.is_empty():
		_capture_folder_collapse_state()
	elif not _query.is_empty() and clean.is_empty():
		_suppress_collapse_capture_once = true
	_query = clean
	refresh()


func set_selected_note(note_id: String) -> void:
	_selected_note_id = note_id.strip_edges()
	var raw_item: Variant = _item_by_note_id.get(_selected_note_id, null)
	if raw_item is TreeItem:
		var item: TreeItem = raw_item as TreeItem
		item.select(0)
		scroll_to_item(item, true)


func selected_folder_id() -> String:
	return _selected_folder_id


func refresh() -> void:
	if _query.is_empty() and not _suppress_collapse_capture_once:
		_capture_folder_collapse_state()
	_suppress_collapse_capture_once = false
	clear()
	_item_by_note_id.clear()
	_item_by_folder_id.clear()
	if repository == null:
		return
	var root: TreeItem = create_item()

	var notes: Array[Dictionary] = repository.list_notes(_query, AssetLibraryService.FOLDER_ANY)
	var visible_folder_ids: Dictionary = _visible_folder_ids_for_notes(notes) if not _query.is_empty() else {}
	var folders: Array[Dictionary] = repository.list_folders()
	var children_by_parent: Dictionary = {}
	for folder: Dictionary in folders:
		var folder_id: String = str(folder.get("id", ""))
		if not _query.is_empty() and not visible_folder_ids.has(folder_id):
			continue
		var parent_id: String = str(folder.get("parent_id", ""))
		var bucket: Array = children_by_parent.get(parent_id, []) as Array
		bucket.append(folder)
		children_by_parent[parent_id] = bucket
	_sort_folder_groups(children_by_parent)
	_append_folder_branch(root, "", children_by_parent, 0)

	var notes_by_folder: Dictionary = {}
	for note: Dictionary in notes:
		var folder_id: String = str(note.get("folder_id", ""))
		var bucket: Array = notes_by_folder.get(folder_id, []) as Array
		bucket.append(note)
		notes_by_folder[folder_id] = bucket
	for raw_bucket: Variant in notes_by_folder.values():
		if raw_bucket is Array:
			(raw_bucket as Array).sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
				return str(left.get("display_name", "")).naturalnocasecmp_to(str(right.get("display_name", ""))) < 0
			)

	# Root notes are real unfiled notes, matching a conventional file explorer:
	# actual folders first, then root-level notes. No duplicate virtual branches.
	_append_notes_to_parent(root, notes_by_folder.get("", []) as Array)
	for raw_folder_id: Variant in _item_by_folder_id.keys():
		var folder_id: String = str(raw_folder_id)
		_append_notes_to_parent(_item_by_folder_id[folder_id] as TreeItem, notes_by_folder.get(folder_id, []) as Array)

	if not _query.is_empty():
		_expand_result_ancestors()
	if not _selected_note_id.is_empty():
		set_selected_note(_selected_note_id)
	elif _item_by_folder_id.has(_selected_folder_id):
		var selected_folder_item: TreeItem = _item_by_folder_id[_selected_folder_id] as TreeItem
		selected_folder_item.select(0)


func _visible_folder_ids_for_notes(notes: Array[Dictionary]) -> Dictionary:
	var visible: Dictionary = {}
	if repository == null:
		return visible
	for note: Dictionary in notes:
		var folder_id: String = str(note.get("folder_id", ""))
		var depth: int = 0
		while not folder_id.is_empty() and depth < MAX_TREE_DEPTH:
			if visible.has(folder_id):
				break
			visible[folder_id] = true
			var folder: Dictionary = repository.get_folder(folder_id)
			if folder.is_empty():
				break
			folder_id = str(folder.get("parent_id", ""))
			depth += 1
	return visible


func _make_folder_item(parent: TreeItem, title: String, folder_id: String) -> TreeItem:
	var item: TreeItem = create_item(parent)
	item.set_text(0, title)
	item.set_icon(0, _folder_icon)
	item.set_metadata(0, {"kind": KIND_FOLDER, "id": folder_id})
	item.set_tooltip_text(0, title)
	if _collapsed_by_folder_id.has(folder_id):
		item.collapsed = bool(_collapsed_by_folder_id[folder_id])
	return item


func _make_note_item(parent: TreeItem, note: Dictionary) -> TreeItem:
	var note_id: String = str(note.get("id", ""))
	var title: String = str(note.get("display_name", NotLightL10n.text("notes.untitled")))
	var item: TreeItem = create_item(parent)
	item.set_text(0, title)
	item.set_icon(0, _note_icon)
	item.set_metadata(0, {"kind": KIND_NOTE, "id": note_id, "folder_id": str(note.get("folder_id", ""))})
	item.set_tooltip_text(0, title)
	_item_by_note_id[note_id] = item
	return item


func _append_folder_branch(parent_item: TreeItem, parent_id: String, groups: Dictionary, depth: int) -> void:
	if depth >= MAX_TREE_DEPTH:
		return
	var raw_children: Variant = groups.get(parent_id, [])
	if raw_children is not Array:
		return
	for raw_folder: Variant in raw_children as Array:
		if raw_folder is not Dictionary:
			continue
		var folder: Dictionary = raw_folder as Dictionary
		var folder_id: String = str(folder.get("id", ""))
		if folder_id.is_empty():
			continue
		var item: TreeItem = _make_folder_item(parent_item, str(folder.get("name", NotLightL10n.text("notes.folder.untitled"))), folder_id)
		_item_by_folder_id[folder_id] = item
		_append_folder_branch(item, folder_id, groups, depth + 1)


func _append_notes_to_parent(parent: TreeItem, raw_notes: Array) -> void:
	for raw_note: Variant in raw_notes:
		if raw_note is Dictionary:
			_make_note_item(parent, raw_note as Dictionary)


func _sort_folder_groups(groups: Dictionary) -> void:
	for raw_key: Variant in groups.keys():
		var raw_group: Variant = groups[raw_key]
		if raw_group is Array:
			(raw_group as Array).sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
				return str(left.get("name", "")).naturalnocasecmp_to(str(right.get("name", ""))) < 0
			)


func _capture_folder_collapse_state() -> void:
	for raw_folder_id: Variant in _item_by_folder_id.keys():
		var raw_item: Variant = _item_by_folder_id[raw_folder_id]
		if raw_item is TreeItem:
			_collapsed_by_folder_id[str(raw_folder_id)] = (raw_item as TreeItem).collapsed


func _expand_result_ancestors() -> void:
	for raw_item: Variant in _item_by_note_id.values():
		if raw_item is not TreeItem:
			continue
		var current: TreeItem = raw_item as TreeItem
		while current != null:
			current.collapsed = false
			current = current.get_parent()


func _on_item_selected() -> void:
	var item: TreeItem = get_selected()
	if item == null:
		return
	var metadata: Dictionary = _metadata(item)
	var kind: String = str(metadata.get("kind", ""))
	if kind == KIND_NOTE:
		_selected_note_id = str(metadata.get("id", ""))
		_selected_folder_id = str(metadata.get("folder_id", ROOT_UNFILED))
		folder_selected.emit(_selected_folder_id)
		note_selected.emit(_selected_note_id)
	elif kind == KIND_FOLDER:
		_selected_folder_id = str(metadata.get("id", ROOT_ALL))
		folder_selected.emit(_selected_folder_id)


func _on_item_activated() -> void:
	var item: TreeItem = get_selected()
	if item == null:
		return
	var metadata: Dictionary = _metadata(item)
	if str(metadata.get("kind", "")) != KIND_NOTE:
		item.collapsed = not item.collapsed
		return
	note_open_requested.emit(str(metadata.get("id", "")), false)


func _on_item_edited() -> void:
	var item: TreeItem = get_edited()
	if item == null or get_edited_column() != 0:
		return
	var metadata: Dictionary = _metadata(item)
	var clean_name: String = item.get_text(0).strip_edges()
	if clean_name.is_empty():
		refresh()
		return
	var kind: String = str(metadata.get("kind", ""))
	var record_id: String = str(metadata.get("id", ""))
	if record_id.is_empty():
		refresh()
		return
	if kind == KIND_NOTE:
		note_rename_requested.emit(record_id, clean_name)
	elif kind == KIND_FOLDER:
		folder_rename_requested.emit(record_id, clean_name)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_F2 and get_selected() != null:
			edit_selected(true)
			accept_event()
			return
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if not mouse.pressed:
			return
		var item: TreeItem = get_item_at_position(mouse.position)
		if item == null:
			return
		var metadata: Dictionary = _metadata(item)
		if str(metadata.get("kind", "")) != KIND_NOTE:
			return
		var note_id: String = str(metadata.get("id", ""))
		if mouse.button_index == MOUSE_BUTTON_MIDDLE:
			note_open_requested.emit(note_id, true)
			accept_event()
		elif mouse.button_index == MOUSE_BUTTON_LEFT and (mouse.ctrl_pressed or mouse.meta_pressed):
			note_open_requested.emit(note_id, true)
			accept_event()


func _get_drag_data(at_position: Vector2) -> Variant:
	var item: TreeItem = get_item_at_position(at_position)
	if item == null:
		return null
	var metadata: Dictionary = _metadata(item)
	if str(metadata.get("kind", "")) != KIND_NOTE:
		return null
	var note_id: String = str(metadata.get("id", ""))
	if note_id.is_empty():
		return null
	var preview: PanelContainer = PanelContainer.new()
	preview.theme_type_variation = "NoteDragPreviewPanel"
	var label: Label = Label.new()
	label.text = item.get_text(0)
	label.theme_type_variation = "BodyLabel"
	label.custom_minimum_size = Vector2(150.0, 34.0)
	preview.add_child(label)
	set_drag_preview(preview)
	return {"kind": KIND_NOTE, "note_id": note_id}


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	drop_mode_flags = Tree.DROP_MODE_ON_ITEM
	if data is not Dictionary:
		return false
	var payload: Dictionary = data as Dictionary
	if str(payload.get("kind", "")) != KIND_NOTE:
		return false
	var item: TreeItem = get_item_at_position(at_position)
	if item == null:
		# Dropping onto empty explorer space moves a note to the repository root.
		return true
	var metadata: Dictionary = _metadata(item)
	return str(metadata.get("kind", "")) == KIND_FOLDER


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(at_position, data):
		return
	var payload: Dictionary = data as Dictionary
	var item: TreeItem = get_item_at_position(at_position)
	var folder_id: String = ""
	if item != null:
		var metadata: Dictionary = _metadata(item)
		folder_id = str(metadata.get("id", ""))
	note_move_requested.emit(str(payload.get("note_id", "")), folder_id)


func _metadata(item: TreeItem) -> Dictionary:
	var raw: Variant = item.get_metadata(0)
	return raw as Dictionary if raw is Dictionary else {}
