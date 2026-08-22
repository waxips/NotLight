# SPDX-License-Identifier: GPL-3.0-or-later
class_name NoteRepository
extends Node

signal notes_changed
signal folders_changed
signal note_changed(note_id: String)
signal note_content_saved(note_id: String, revision: int)
signal note_content_loaded(note_id: String, content: String)
signal note_content_load_failed(note_id: String, message: String)
signal relation_index_changed
signal note_error(message: String)

const NOTE_METADATA_KEY: String = "notlight_note"
const NOTE_METADATA_SCHEMA_VERSION: int = 2
const MAX_LINK_ALIASES: int = 64
const MAX_NOTE_BYTES: int = AssetImportContentValidator.MAX_NOTE_BYTES
const MAX_EXPLICIT_LINKS: int = 4096
const MAX_INDEXED_NOTES: int = 20000
const MAX_TOTAL_TEXTUAL_LINKS: int = 240000
const CACHE_BYTE_BUDGET: int = 16 * 1024 * 1024
const CACHE_ENTRY_BUDGET: int = 48

var library: AssetLibraryService
var _worker: NoteSaveWorker = NoteSaveWorker.new()
var _worker_ready: bool = false
var _index_worker: NoteIndexWorker = NoteIndexWorker.new()
var _index_worker_ready: bool = false
var _read_worker: NoteReadWorker = NoteReadWorker.new()
var _read_worker_ready: bool = false
var _read_inflight_by_id: Dictionary = {}
var _save_revision_by_id: Dictionary = {}
var _inflight_by_id: Dictionary = {}
var _pending_content_by_id: Dictionary = {}
var _dirty_content_by_id: Dictionary = {}
var _content_cache: Dictionary = {}
var _cache_stamp: Dictionary = {}
var _cache_bytes: int = 0
var _stamp_counter: int = 0
var _title_to_ids: Dictionary = {}
var _alias_to_ids: Dictionary = {}
var _textual_links_by_id: Dictionary = {}
var _raw_textual_targets_by_id: Dictionary = {}
var _indexed_hash_by_id: Dictionary = {}
var _indexed_excerpts_by_id: Dictionary = {}
var _indexed_board_preview_by_id: Dictionary = {}
var _index_waiting_ids: PackedStringArray = PackedStringArray()
var _index_waiting_head: int = 0
var _index_waiting_lookup: Dictionary = {}
var _index_inflight_by_id: Dictionary = {}
var _total_raw_target_count: int = 0
var _explicit_links_by_id: Dictionary = {}
var _backlinks_by_id: Dictionary = {}
var _last_error: String = ""


func _ready() -> void:
	_worker_ready = _worker.start()
	_index_worker_ready = _index_worker.start()
	_read_worker_ready = _read_worker.start()
	set_process(_worker_ready or _index_worker_ready or _read_worker_ready)


func _exit_tree() -> void:
	# Stop the save worker before the final synchronous flush. This prevents a
	# worker from writing/removing the same staging path while shutdown persistence
	# promotes the latest cached revision.
	_worker.stop()
	_worker_ready = false
	flush_pending_saves()
	_index_worker.stop()
	_read_worker.stop()


func configure(asset_library: AssetLibraryService) -> void:
	if library != null:
		if library.library_changed.is_connected(_on_library_changed):
			library.library_changed.disconnect(_on_library_changed)
		if library.folders_changed.is_connected(_on_library_folders_changed):
			library.folders_changed.disconnect(_on_library_folders_changed)
	library = asset_library
	if library != null:
		if not library.library_changed.is_connected(_on_library_changed):
			library.library_changed.connect(_on_library_changed)
		if not library.folders_changed.is_connected(_on_library_folders_changed):
			library.folders_changed.connect(_on_library_folders_changed)
	_rebuild_metadata_indices()
	_schedule_missing_indices()


func get_last_error() -> String:
	return _last_error


func list_notes(query: String = "", folder_id: String = AssetLibraryService.FOLDER_ANY) -> Array[Dictionary]:
	if library == null:
		return []
	return library.list_assets(query, AssetKinds.NOTE, folder_id)


func list_folders() -> Array[Dictionary]:
	return library.list_folders() if library != null else []


func folder_path(folder_id: String) -> String:
	if library == null:
		return ""
	return library.folder_path(folder_id)


func get_folder(folder_id: String) -> Dictionary:
	if library == null or library.catalog == null:
		return {}
	return library.catalog.get_folder(folder_id)


func create_folder(name: String, parent_id: String = "") -> String:
	_clear_error()
	if library == null or not library.is_available():
		_fail(NotLightL10n.text("runtime.portable.notlight_portable_package_service.88945df9d2"))
		return ""
	var record: Dictionary = library.create_folder(name, parent_id)
	if record.is_empty():
		_fail(library.get_last_error())
		return ""
	return str(record.get("id", ""))


func rename_folder(folder_id: String, name: String) -> bool:
	_clear_error()
	if library == null or not library.rename_folder(folder_id, name):
		_fail(library.get_last_error() if library != null else NotLightL10n.text("runtime.portable.notlight_portable_package_service.88945df9d2"))
		return false
	return true


func delete_folder(folder_id: String) -> bool:
	_clear_error()
	if library == null or not library.delete_folder(folder_id):
		_fail(library.get_last_error() if library != null else NotLightL10n.text("runtime.portable.notlight_portable_package_service.88945df9d2"))
		return false
	return true


func move_note(note_id: String, folder_id: String) -> bool:
	_clear_error()
	if not contains(note_id):
		_fail(NotLightL10n.text("runtime.notes.note_repository.e36e17e4e4"))
		return false
	if library == null or not library.move_asset(note_id, folder_id):
		_fail(library.get_last_error() if library != null else NotLightL10n.text("runtime.portable.notlight_portable_package_service.88945df9d2"))
		return false
	note_changed.emit(note_id)
	return true


func contains(note_id: String) -> bool:
	if library == null:
		return false
	var asset: Dictionary = library.get_asset(note_id.strip_edges())
	return not asset.is_empty() and int(asset.get("kind", AssetKinds.OTHER)) == AssetKinds.NOTE


func get_note(note_id: String) -> Dictionary:
	if not contains(note_id):
		return {}
	return library.get_asset(note_id)


func has_cached_content(note_id: String) -> bool:
	return _content_cache.has(note_id.strip_edges())


func peek_cached_content(note_id: String) -> String:
	var clean_id: String = note_id.strip_edges()
	if not _content_cache.has(clean_id):
		return ""
	_touch_cache(clean_id)
	return str(_content_cache[clean_id])


func peek_board_preview(note_id: String) -> Array[Dictionary]:
	var clean_id: String = note_id.strip_edges()
	if clean_id.is_empty():
		return []
	# Board rendering is deliberately derived-cache only. _put_cache() and the
	# index worker both maintain this snapshot, so a retained render rebuild never
	# parses Markdown on the main thread merely because a portal becomes visible.
	var raw: Variant = _indexed_board_preview_by_id.get(clean_id, [])
	if raw is not Array:
		return []
	var output: Array[Dictionary] = []
	for value: Variant in raw as Array:
		if value is Dictionary:
			output.append((value as Dictionary).duplicate(true))
	return output


func peek_cached_excerpt(note_id: String, max_characters: int = 360) -> String:
	var clean_id: String = note_id.strip_edges()
	var content: String = peek_cached_content(clean_id)
	var safe_limit: int = clampi(max_characters, 32, 2000)
	if content.is_empty():
		return str(_indexed_excerpts_by_id.get(clean_id, "")).left(safe_limit)
	var lines: PackedStringArray = content.split("\n", false)
	var output: PackedStringArray = PackedStringArray()
	for line: String in lines:
		var clean: String = line.strip_edges()
		if clean.is_empty() or clean.begins_with("---"):
			continue
		while clean.begins_with("#") or clean.begins_with(">"):
			clean = clean.substr(1).strip_edges()
		if clean.begins_with("- [ ] ") or clean.begins_with("- [x] ") or clean.begins_with("- [X] "):
			clean = clean.substr(6).strip_edges()
		elif clean.begins_with("- ") or clean.begins_with("* ") or clean.begins_with("+ "):
			clean = clean.substr(2).strip_edges()
		clean = NoteInlineMarkup.strip_markup(clean)
		if not clean.is_empty():
			output.append(clean)
		if " ".join(output).length() >= safe_limit:
			break
	var excerpt: String = " ".join(output).strip_edges()
	return excerpt.left(safe_limit)


func create_note(title: String = "", initial_content: String = "", folder_id: String = "") -> String:
	_clear_error()
	if library == null or not library.is_available():
		_fail(NotLightL10n.text("runtime.portable.notlight_portable_package_service.88945df9d2"))
		return ""
	var effective_title: String = title if not title.strip_edges().is_empty() else NotLightL10n.text("notes.default_title")
	var clean_title: String = _sanitize_title(effective_title)
	var bytes: PackedByteArray = _validated_bytes(initial_content)
	if bytes.is_empty() and not _last_error.is_empty():
		return ""
	var temp_path: String = library.blobs.make_temp_path(AssetId.make_temporary_id("note-create"))
	var staged: Dictionary = _write_sync(temp_path, bytes)
	if staged.is_empty():
		return ""
	var commit: Dictionary = library.blobs.commit_preverified_temp(
		temp_path,
		str(staged.get("hash_sha256", "")),
		"md",
		int(staged.get("byte_size", 0))
	)
	if commit.is_empty():
		_fail(library.blobs.get_last_error())
		return ""
	var note_id: String = AssetId.make_uuid()
	var now: int = int(Time.get_unix_time_from_system())
	var record: Dictionary = {
		"id": note_id,
		"hash_sha256": str(staged.get("hash_sha256", "")),
		"blob_relpath": str(commit.get("relative_path", "")),
		"display_name": clean_title,
		"original_filename": "%s.md" % _safe_filename_base(clean_title),
		"extension": "md",
		"kind": AssetKinds.NOTE,
		"byte_size": int(staged.get("byte_size", 0)),
		"folder_id": folder_id,
		"created_at_unix": now,
		"imported_at_unix": now,
		"updated_at_unix": now,
		"metadata": _default_note_metadata(),
	}
	_indexed_hash_by_id[note_id] = str(staged.get("hash_sha256", ""))
	if not library.register_managed_asset(record):
		_indexed_hash_by_id.erase(note_id)
		if not bool(commit.get("reused", false)):
			library.blobs.delete_blob(str(record.get("blob_relpath", "")))
		_fail(library.get_last_error())
		return ""
	_put_cache(note_id, initial_content)
	_refresh_textual_links(note_id, initial_content)
	_refresh_resource_embeds(note_id, initial_content)
	_indexed_excerpts_by_id[note_id] = peek_cached_excerpt(note_id, NoteIndexWorker.MAX_EXCERPT_CHARS)
	note_changed.emit(note_id)
	return note_id


func rename_note(note_id: String, title: String) -> bool:
	_clear_error()
	if not contains(note_id):
		_fail(NotLightL10n.text("runtime.notes.note_repository.e36e17e4e4"))
		return false
	var clean_title: String = _sanitize_title(title)
	var current: Dictionary = get_note(note_id)
	var old_title: String = str(current.get("display_name", "")).strip_edges()
	if clean_title == old_title:
		return true
	var original_metadata: Dictionary = (current.get("metadata", {}) as Dictionary).duplicate(true)
	var metadata: Dictionary = original_metadata.duplicate(true)
	var note_meta: Dictionary = _normalized_note_metadata(metadata.get(NOTE_METADATA_KEY, {}))
	var aliases: PackedStringArray = _normalize_title_aliases(note_meta.get("link_aliases", []))
	if not old_title.is_empty() and not aliases.has(old_title):
		aliases.append(old_title)
		while aliases.size() > MAX_LINK_ALIASES:
			aliases.remove_at(0)
	note_meta["link_aliases"] = aliases
	metadata[NOTE_METADATA_KEY] = note_meta
	if not library.update_asset_metadata(note_id, metadata):
		_fail(library.get_last_error())
		return false
	if not library.rename_asset(note_id, clean_title):
		var rename_error: String = library.get_last_error()
		if not library.update_asset_metadata(note_id, original_metadata):
			var rollback_error: String = library.get_last_error()
			_fail(NotLightL10n.text("runtime.notes.rollback_failed") % [rename_error, rollback_error])
			return false
		_fail(rename_error)
		return false
	# AssetLibraryService emits library_changed synchronously. The repository
	# rebuilds title resolution there; only the note-specific signal is needed here.
	note_changed.emit(note_id)
	return true


func read_content(note_id: String) -> String:
	_clear_error()
	var clean_id: String = note_id.strip_edges()
	if not contains(clean_id):
		_fail(NotLightL10n.text("runtime.notes.note_repository.e36e17e4e4"))
		return ""
	if _content_cache.has(clean_id):
		_touch_cache(clean_id)
		return str(_content_cache[clean_id])
	return _read_content_sync(clean_id)


func request_content_load(note_id: String) -> bool:
	_clear_error()
	var clean_id: String = note_id.strip_edges()
	if not contains(clean_id):
		_fail_content_load(clean_id, NotLightL10n.text("runtime.notes.note_repository.e36e17e4e4"))
		return false
	if _content_cache.has(clean_id):
		_touch_cache(clean_id)
		note_content_loaded.emit(clean_id, str(_content_cache[clean_id]))
		return true
	if _read_inflight_by_id.has(clean_id):
		return true
	if not _read_worker_ready:
		var fallback_content: String = _read_content_sync(clean_id, false)
		if not _last_error.is_empty():
			var fallback_error: String = _last_error
			_last_error = ""
			_fail_content_load(clean_id, fallback_error)
			return false
		note_content_loaded.emit(clean_id, fallback_content)
		return true
	var asset: Dictionary = library.get_asset(clean_id)
	var path: String = library.resolve_asset_path(clean_id)
	var hash_sha256: String = str(asset.get("hash_sha256", "")).to_lower()
	var byte_size: int = int(asset.get("byte_size", -1))
	if path.is_empty() or hash_sha256.length() != 64 or byte_size < 0 or byte_size > MAX_NOTE_BYTES:
		_fail_content_load(clean_id, NotLightL10n.text("runtime.notes.note_repository.5c8409f289"))
		return false
	var job_key: String = "read:%s:%s" % [clean_id, hash_sha256.left(12)]
	if not _read_worker.request(job_key, clean_id, path, hash_sha256, byte_size):
		_fail_content_load(clean_id, NotLightL10n.text("runtime.notes.note_repository.f8bff59887"))
		return false
	_read_inflight_by_id[clean_id] = {"job_key": job_key, "hash_sha256": hash_sha256}
	return true


func cancel_content_load(note_id: String) -> void:
	var clean_id: String = note_id.strip_edges()
	if not _read_inflight_by_id.has(clean_id):
		return
	var inflight: Dictionary = _read_inflight_by_id[clean_id] as Dictionary
	_read_worker.cancel(str(inflight.get("job_key", "")))
	_read_inflight_by_id.erase(clean_id)


func request_save(note_id: String, content: String) -> bool:
	_clear_error()
	var clean_id: String = note_id.strip_edges()
	if not contains(clean_id):
		_fail(NotLightL10n.text("runtime.notes.note_repository.e36e17e4e4"))
		return false
	var bytes: PackedByteArray = _validated_bytes(content)
	if bytes.is_empty() and not _last_error.is_empty():
		return false
	_put_cache(clean_id, content)
	_refresh_textual_links(clean_id, content)
	_refresh_resource_embeds(clean_id, content)
	_dirty_content_by_id[clean_id] = true
	if not _worker_ready:
		var revision: int = int(_save_revision_by_id.get(clean_id, 0)) + 1
		_save_revision_by_id[clean_id] = revision
		if not _commit_content_sync(clean_id, bytes):
			return false
		_dirty_content_by_id.erase(clean_id)
		note_content_saved.emit(clean_id, revision)
		note_changed.emit(clean_id)
		return true
	_pending_content_by_id[clean_id] = content
	if not _inflight_by_id.has(clean_id):
		_start_pending_save(clean_id)
	return true


func flush_pending_saves() -> bool:
	var ids: Dictionary = {}
	for raw_id: Variant in _dirty_content_by_id.keys():
		ids[str(raw_id)] = true
	for raw_id: Variant in _pending_content_by_id.keys():
		ids[str(raw_id)] = true
	for raw_id: Variant in _inflight_by_id.keys():
		ids[str(raw_id)] = true
	var success: bool = true
	for raw_id: Variant in ids.keys():
		var note_id: String = str(raw_id)
		if _inflight_by_id.has(note_id):
			var inflight: Dictionary = _inflight_by_id[note_id] as Dictionary
			_worker.cancel(str(inflight.get("job_key", "")))
			var temp_path: String = str(inflight.get("temp_path", ""))
			library.blobs.remove_temp(temp_path)
			_inflight_by_id.erase(note_id)
		var content: String = str(_pending_content_by_id.get(note_id, _content_cache.get(note_id, "")))
		_pending_content_by_id.erase(note_id)
		if not contains(note_id):
			continue
		var bytes: PackedByteArray = _validated_bytes(content)
		if bytes.is_empty() and not _last_error.is_empty():
			success = false
			continue
		if not _commit_content_sync(note_id, bytes):
			success = false
			continue
		_dirty_content_by_id.erase(note_id)
	return success


func add_explicit_link(source_note_id: String, target_note_id: String) -> bool:
	return _set_explicit_link(source_note_id, target_note_id, true)


func remove_explicit_link(source_note_id: String, target_note_id: String) -> bool:
	return _set_explicit_link(source_note_id, target_note_id, false)


func get_outgoing_links(note_id: String) -> PackedStringArray:
	var found: Dictionary = {}
	_append_valid_links(found, _textual_links_by_id.get(note_id, PackedStringArray()))
	_append_valid_links(found, _explicit_links_by_id.get(note_id, PackedStringArray()))
	var result: PackedStringArray = PackedStringArray()
	var keys: Array = found.keys()
	keys.sort()
	for raw_key: Variant in keys:
		result.append(str(raw_key))
	return result


func get_backlinks(note_id: String) -> PackedStringArray:
	var value: Variant = _backlinks_by_id.get(note_id, PackedStringArray())
	return (value as PackedStringArray).duplicate() if value is PackedStringArray else PackedStringArray()


func relation_snapshot() -> Dictionary:
	var nodes: Array[Dictionary] = []
	var notes: Array[Dictionary] = list_notes()
	for note: Dictionary in notes:
		var note_id: String = str(note.get("id", ""))
		nodes.append({"id": note_id, "title": str(note.get("display_name", NotLightL10n.text("asset.kind.note")))})
	var edges: Array[Dictionary] = []
	for node: Dictionary in nodes:
		var source_id: String = str(node.get("id", ""))
		var textual: PackedStringArray = _valid_link_array(_textual_links_by_id.get(source_id, PackedStringArray()))
		var explicit: PackedStringArray = _valid_link_array(_explicit_links_by_id.get(source_id, PackedStringArray()))
		var targets: Dictionary = {}
		for target_id: String in textual:
			targets[target_id] = true
		for target_id: String in explicit:
			targets[target_id] = true
		var target_ids: Array = targets.keys()
		target_ids.sort()
		for raw_target: Variant in target_ids:
			var target_id: String = str(raw_target)
			if source_id == target_id or not contains(target_id):
				continue
			edges.append({
				"source": source_id,
				"target": target_id,
				"textual": textual.has(target_id),
				"explicit": explicit.has(target_id),
			})
	return {"nodes": nodes, "edges": edges}


func local_relation_snapshot(center_note_id: String, max_hops: int = 3, max_nodes: int = 2048) -> Dictionary:
	var center_id: String = center_note_id.strip_edges()
	if not contains(center_id):
		return {"nodes": [], "edges": [], "truncated": false}
	var safe_hops: int = clampi(max_hops, 1, 3)
	var safe_node_limit: int = clampi(max_nodes, 32, 4096)
	var distance_by_id: Dictionary = {center_id: 0}
	var queue: PackedStringArray = PackedStringArray([center_id])
	var head: int = 0
	var truncated: bool = false
	while head < queue.size():
		var source_id: String = queue[head]
		head += 1
		var distance: int = int(distance_by_id.get(source_id, 0))
		if distance >= safe_hops:
			continue
		var neighbors: Dictionary = {}
		_append_valid_links(neighbors, get_outgoing_links(source_id))
		_append_valid_links(neighbors, get_backlinks(source_id))
		var neighbor_ids: Array = neighbors.keys()
		neighbor_ids.sort()
		for raw_neighbor: Variant in neighbor_ids:
			var neighbor_id: String = str(raw_neighbor)
			if distance_by_id.has(neighbor_id):
				continue
			if distance_by_id.size() >= safe_node_limit:
				truncated = true
				continue
			distance_by_id[neighbor_id] = distance + 1
			queue.append(neighbor_id)
	var nodes: Array[Dictionary] = []
	for note_id: String in queue:
		var note: Dictionary = get_note(note_id)
		if note.is_empty():
			continue
		nodes.append({
			"id": note_id,
			"title": str(note.get("display_name", NotLightL10n.text("asset.kind.note"))),
			"hop": int(distance_by_id.get(note_id, 0)),
		})
	# Build only the induced local subgraph. Calling the full relation snapshot here would
	# scan the complete repository and defeat the purpose of a bounded local graph.
	var edges: Array[Dictionary] = []
	for source_id: String in queue:
		var textual: PackedStringArray = _textual_links_by_id.get(source_id, PackedStringArray()) as PackedStringArray
		var explicit: PackedStringArray = _explicit_links_by_id.get(source_id, PackedStringArray()) as PackedStringArray
		var targets: Dictionary = {}
		for target_id: String in textual:
			targets[target_id] = true
		for target_id: String in explicit:
			targets[target_id] = true
		var target_ids: Array = targets.keys()
		target_ids.sort()
		for raw_target: Variant in target_ids:
			var target_id: String = str(raw_target)
			if source_id == target_id or not distance_by_id.has(target_id):
				continue
			edges.append({
				"source": source_id,
				"target": target_id,
				"textual": textual.has(target_id),
				"explicit": explicit.has(target_id),
			})
	return {
		"nodes": nodes,
		"edges": edges,
		"center_id": center_id,
		"max_hops": safe_hops,
		"truncated": truncated,
	}


func resolve_title(target: String) -> String:
	var normalized: String = NoteLinkParser.normalize_title(target)
	if normalized.is_empty():
		return ""
	# Current titles always outrank historical aliases. This matters when two notes
	# once shared a title and one is renamed: the remaining current title becomes
	# unambiguous instead of being shadowed forever by the renamed note's alias.
	if _title_to_ids.has(normalized):
		var current_ids: PackedStringArray = _title_to_ids[normalized] as PackedStringArray
		return current_ids[0] if current_ids.size() == 1 else ""
	if not _alias_to_ids.has(normalized):
		return ""
	var alias_ids: PackedStringArray = _alias_to_ids[normalized] as PackedStringArray
	return alias_ids[0] if alias_ids.size() == 1 else ""


func _process(_delta: float) -> void:
	if _worker_ready:
		for result: Dictionary in _worker.poll_results(4):
			_finish_worker_result(result)
		for raw_id: Variant in _pending_content_by_id.keys():
			var note_id: String = str(raw_id)
			if not _inflight_by_id.has(note_id):
				_start_pending_save(note_id)
	if _index_worker_ready:
		for result: Dictionary in _index_worker.poll_results(4):
			_finish_index_result(result)
		_pump_index_queue()
	if _read_worker_ready:
		for result: Dictionary in _read_worker.poll_results(2):
			_finish_read_result(result)


func _start_pending_save(note_id: String) -> void:
	if not _worker_ready or not _pending_content_by_id.has(note_id) or _inflight_by_id.has(note_id):
		return
	var content: String = str(_pending_content_by_id[note_id])
	_pending_content_by_id.erase(note_id)
	var bytes: PackedByteArray = _validated_bytes(content)
	if bytes.is_empty() and not _last_error.is_empty():
		return
	var revision: int = int(_save_revision_by_id.get(note_id, 0)) + 1
	_save_revision_by_id[note_id] = revision
	var job_key: String = "note:%s:%d" % [note_id, revision]
	var temp_path: String = library.blobs.make_temp_path(AssetId.make_temporary_id("note-save"))
	if not _worker.request(job_key, temp_path, bytes):
		_pending_content_by_id[note_id] = content
		return
	_inflight_by_id[note_id] = {
		"job_key": job_key,
		"temp_path": temp_path,
		"revision": revision,
	}


func _finish_worker_result(result: Dictionary) -> void:
	var job_key: String = str(result.get("job_key", ""))
	var note_id: String = _note_id_for_job(job_key)
	if note_id.is_empty() or not _inflight_by_id.has(note_id):
		library.blobs.remove_temp(str(result.get("temp_path", "")))
		return
	var inflight: Dictionary = _inflight_by_id[note_id] as Dictionary
	if str(inflight.get("job_key", "")) != job_key:
		library.blobs.remove_temp(str(result.get("temp_path", "")))
		return
	_inflight_by_id.erase(note_id)
	var temp_path: String = str(result.get("temp_path", ""))
	if bool(result.get("cancelled", false)):
		library.blobs.remove_temp(temp_path)
		return
	var error: String = str(result.get("error", ""))
	if not error.is_empty():
		library.blobs.remove_temp(temp_path)
		_fail(error)
		return
	# Coalesce editor churn: if newer text arrived while this job was running, the
	# intermediate revision is discarded before BlobStore promotion.
	if _pending_content_by_id.has(note_id):
		library.blobs.remove_temp(temp_path)
		_start_pending_save(note_id)
		return
	if not contains(note_id):
		library.blobs.remove_temp(temp_path)
		return
	var commit: Dictionary = library.blobs.commit_preverified_temp(
		temp_path,
		str(result.get("hash_sha256", "")),
		"md",
		int(result.get("byte_size", 0))
	)
	if commit.is_empty():
		_fail(library.blobs.get_last_error())
		return
	if not _apply_committed_blob(note_id, result, commit):
		return
	_dirty_content_by_id.erase(note_id)
	var revision: int = int(inflight.get("revision", 0))
	note_content_saved.emit(note_id, revision)
	note_changed.emit(note_id)


func _apply_committed_blob(note_id: String, result: Dictionary, commit: Dictionary) -> bool:
	var asset: Dictionary = library.get_asset(note_id)
	if asset.is_empty():
		return false
	var old_relative_path: String = str(asset.get("blob_relpath", ""))
	var old_indexed_hash: String = str(_indexed_hash_by_id.get(note_id, ""))
	var next_hash: String = str(result.get("hash_sha256", ""))
	_indexed_hash_by_id[note_id] = next_hash
	var metadata: Dictionary = asset.get("metadata", {}) as Dictionary
	if not library.replace_asset_primary_blob(
		note_id,
		str(result.get("hash_sha256", "")),
		str(commit.get("relative_path", "")),
		int(result.get("byte_size", 0)),
		"md",
		metadata
	):
		if old_indexed_hash.is_empty():
			_indexed_hash_by_id.erase(note_id)
		else:
			_indexed_hash_by_id[note_id] = old_indexed_hash
		if not bool(commit.get("reused", false)):
			library.blobs.delete_blob(str(commit.get("relative_path", "")))
		_fail(library.get_last_error())
		return false
	var new_relative_path: String = str(commit.get("relative_path", ""))
	if not old_relative_path.is_empty() and old_relative_path != new_relative_path:
		# The catalog has already committed the new canonical reference. Delete the
		# previous content only when no asset or variant metadata still points to it.
		library.delete_blob_if_unreferenced_path(old_relative_path)
	return true


func _set_explicit_link(source_note_id: String, target_note_id: String, enabled: bool) -> bool:
	_clear_error()
	var source_id: String = source_note_id.strip_edges()
	var target_id: String = target_note_id.strip_edges()
	if source_id == target_id or not contains(source_id) or not contains(target_id):
		_fail(NotLightL10n.text("runtime.notes.note_repository.a0c8c3920a"))
		return false
	var asset: Dictionary = library.get_asset(source_id)
	var metadata: Dictionary = (asset.get("metadata", {}) as Dictionary).duplicate(true)
	var note_meta: Dictionary = _normalized_note_metadata(metadata.get(NOTE_METADATA_KEY, {}))
	var links: PackedStringArray = _normalize_link_ids(note_meta.get("explicit_links", []), source_id)
	if enabled:
		if not links.has(target_id):
			if links.size() >= MAX_EXPLICIT_LINKS:
				_fail(NotLightL10n.text("runtime.notes.note_repository.551eecfa8c"))
				return false
			links.append(target_id)
			links.sort()
	else:
		var index: int = links.find(target_id)
		if index < 0:
			return true
		links.remove_at(index)
	note_meta["explicit_links"] = links
	metadata[NOTE_METADATA_KEY] = note_meta
	if not library.update_asset_metadata(source_id, metadata):
		_fail(library.get_last_error())
		return false
	# library_changed synchronously refreshes the canonical relation index.
	note_changed.emit(source_id)
	return true


func _refresh_resource_embeds(note_id: String, content: String) -> void:
	if library == null:
		return
	library.set_note_embed_hash_references(note_id, NoteResourceEmbed.extract_hashes(content))


func _refresh_textual_links(note_id: String, content: String) -> void:
	var raw_targets: PackedStringArray = NoteLinkParser.extract_wikilink_targets(content)
	_apply_raw_textual_targets(note_id, raw_targets)


func _apply_raw_textual_targets(note_id: String, raw_targets: PackedStringArray) -> void:
	var old_targets: PackedStringArray = _raw_textual_targets_by_id.get(note_id, PackedStringArray()) as PackedStringArray
	var available: int = maxi(0, MAX_TOTAL_TEXTUAL_LINKS - (_total_raw_target_count - old_targets.size()))
	var bounded: PackedStringArray = raw_targets.slice(0, mini(raw_targets.size(), available))
	_total_raw_target_count = maxi(0, _total_raw_target_count - old_targets.size()) + bounded.size()
	_raw_textual_targets_by_id[note_id] = bounded
	_resolve_textual_links_for_note(note_id)


func _resolve_textual_links_for_note(note_id: String) -> bool:
	var resolved: PackedStringArray = PackedStringArray()
	var raw_targets: PackedStringArray = _raw_textual_targets_by_id.get(note_id, PackedStringArray()) as PackedStringArray
	for target: String in raw_targets:
		var target_id: String = resolve_title(target)
		if not target_id.is_empty() and target_id != note_id and not resolved.has(target_id):
			resolved.append(target_id)
	resolved.sort()
	var previous: PackedStringArray = _textual_links_by_id.get(note_id, PackedStringArray()) as PackedStringArray
	if previous == resolved:
		return false
	_textual_links_by_id[note_id] = resolved
	_rebuild_backlinks()
	relation_index_changed.emit()
	return true


func _resolve_all_textual_links() -> void:
	var changed: bool = false
	for raw_id: Variant in _raw_textual_targets_by_id.keys():
		var note_id: String = str(raw_id)
		var resolved: PackedStringArray = PackedStringArray()
		var raw_targets: PackedStringArray = _raw_textual_targets_by_id.get(note_id, PackedStringArray()) as PackedStringArray
		for target: String in raw_targets:
			var target_id: String = resolve_title(target)
			if not target_id.is_empty() and target_id != note_id and not resolved.has(target_id):
				resolved.append(target_id)
		resolved.sort()
		var previous: PackedStringArray = _textual_links_by_id.get(note_id, PackedStringArray()) as PackedStringArray
		if previous != resolved:
			_textual_links_by_id[note_id] = resolved
			changed = true
	if changed:
		_rebuild_backlinks()
		relation_index_changed.emit()


func _rebuild_metadata_indices() -> void:
	var previous_titles: Dictionary = _title_to_ids
	var previous_aliases: Dictionary = _alias_to_ids
	var previous_explicit: Dictionary = _explicit_links_by_id
	var next_titles: Dictionary = {}
	var next_aliases: Dictionary = {}
	var next_explicit: Dictionary = {}
	if library == null:
		_title_to_ids = {}
		_alias_to_ids = {}
		_explicit_links_by_id.clear()
		_textual_links_by_id.clear()
		_raw_textual_targets_by_id.clear()
		_indexed_hash_by_id.clear()
		_indexed_excerpts_by_id.clear()
		_indexed_board_preview_by_id.clear()
		_backlinks_by_id.clear()
		_total_raw_target_count = 0
		return
	var valid_ids: Dictionary = {}
	var notes: Array[Dictionary] = list_notes()
	for note: Dictionary in notes:
		var note_id: String = str(note.get("id", ""))
		if note_id.is_empty():
			continue
		valid_ids[note_id] = true
		var normalized_title: String = NoteLinkParser.normalize_title(str(note.get("display_name", "")))
		if not normalized_title.is_empty():
			var ids: PackedStringArray = next_titles.get(normalized_title, PackedStringArray()) as PackedStringArray
			ids.append(note_id)
			ids.sort()
			next_titles[normalized_title] = ids
		var metadata: Dictionary = note.get("metadata", {}) as Dictionary
		var note_meta: Dictionary = _normalized_note_metadata(metadata.get(NOTE_METADATA_KEY, {}))
		for alias: String in _normalize_title_aliases(note_meta.get("link_aliases", [])):
			var normalized_alias: String = NoteLinkParser.normalize_title(alias)
			if normalized_alias.is_empty():
				continue
			var alias_ids: PackedStringArray = next_aliases.get(normalized_alias, PackedStringArray()) as PackedStringArray
			if not alias_ids.has(note_id):
				alias_ids.append(note_id)
				alias_ids.sort()
				next_aliases[normalized_alias] = alias_ids
		next_explicit[note_id] = _normalize_link_ids(note_meta.get("explicit_links", []), note_id)
	_title_to_ids = next_titles
	_alias_to_ids = next_aliases
	_explicit_links_by_id = next_explicit
	_prune_note_indices(valid_ids)
	var title_index_changed: bool = previous_titles != _title_to_ids or previous_aliases != _alias_to_ids
	var explicit_index_changed: bool = previous_explicit != _explicit_links_by_id
	if title_index_changed:
		_resolve_all_textual_links()
	else:
		_rebuild_backlinks()
	if explicit_index_changed:
		relation_index_changed.emit()
	_schedule_missing_indices(notes)


func _prune_note_indices(valid_ids: Dictionary) -> void:
	var old_raw_count: int = 0
	for raw_id: Variant in _raw_textual_targets_by_id.keys():
		var note_id: String = str(raw_id)
		if valid_ids.has(note_id):
			old_raw_count += (_raw_textual_targets_by_id[note_id] as PackedStringArray).size()
			continue
		_raw_textual_targets_by_id.erase(note_id)
		_textual_links_by_id.erase(note_id)
		_indexed_hash_by_id.erase(note_id)
		_indexed_excerpts_by_id.erase(note_id)
		_indexed_board_preview_by_id.erase(note_id)
		_index_waiting_lookup.erase(note_id)
		_pending_content_by_id.erase(note_id)
		_dirty_content_by_id.erase(note_id)
		_save_revision_by_id.erase(note_id)
		if _content_cache.has(note_id):
			_cache_bytes = maxi(0, _cache_bytes - str(_content_cache[note_id]).to_utf8_buffer().size())
			_content_cache.erase(note_id)
			_cache_stamp.erase(note_id)
		if _inflight_by_id.has(note_id):
			var save_inflight: Dictionary = _inflight_by_id[note_id] as Dictionary
			_worker.cancel(str(save_inflight.get("job_key", "")))
			_inflight_by_id.erase(note_id)
		if _read_inflight_by_id.has(note_id):
			var read_inflight: Dictionary = _read_inflight_by_id[note_id] as Dictionary
			_read_worker.cancel(str(read_inflight.get("job_key", "")))
			_read_inflight_by_id.erase(note_id)
		if _index_inflight_by_id.has(note_id):
			var inflight: Dictionary = _index_inflight_by_id[note_id] as Dictionary
			_index_worker.cancel(str(inflight.get("job_key", "")))
			_index_inflight_by_id.erase(note_id)
	_total_raw_target_count = old_raw_count
	var compact_waiting: PackedStringArray = PackedStringArray()
	for index: int in range(_index_waiting_head, _index_waiting_ids.size()):
		var note_id: String = _index_waiting_ids[index]
		if valid_ids.has(note_id) and _index_waiting_lookup.has(note_id):
			compact_waiting.append(note_id)
	_index_waiting_ids = compact_waiting
	_index_waiting_head = 0


func _schedule_missing_indices(notes: Array[Dictionary] = []) -> void:
	if not _index_worker_ready or library == null:
		return
	var source_notes: Array[Dictionary] = notes
	if source_notes.is_empty():
		source_notes = list_notes()
	var considered: int = 0
	for note: Dictionary in source_notes:
		if considered >= MAX_INDEXED_NOTES:
			break
		considered += 1
		var note_id: String = str(note.get("id", ""))
		var hash_sha256: String = str(note.get("hash_sha256", "")).to_lower()
		if note_id.is_empty() or hash_sha256.is_empty():
			continue
		if str(_indexed_hash_by_id.get(note_id, "")) == hash_sha256:
			continue
		_schedule_index(note_id)


func _schedule_index(note_id: String) -> void:
	var clean_id: String = note_id.strip_edges()
	if clean_id.is_empty() or _index_waiting_lookup.has(clean_id) or _index_inflight_by_id.has(clean_id):
		return
	if _index_waiting_count() + _index_inflight_by_id.size() >= MAX_INDEXED_NOTES:
		return
	_index_waiting_ids.append(clean_id)
	_index_waiting_lookup[clean_id] = true


func _pump_index_queue() -> void:
	if not _index_worker_ready or library == null:
		return
	while _index_waiting_head < _index_waiting_ids.size() and _index_worker.pending_work_count() < NoteIndexWorker.MAX_PENDING_JOBS:
		var note_id: String = _index_waiting_ids[_index_waiting_head]
		_index_waiting_head += 1
		var was_waiting: bool = _index_waiting_lookup.has(note_id)
		_index_waiting_lookup.erase(note_id)
		if not was_waiting or not contains(note_id) or _index_inflight_by_id.has(note_id):
			continue
		var asset: Dictionary = library.get_asset(note_id)
		var path: String = library.resolve_asset_path(note_id)
		var hash_sha256: String = str(asset.get("hash_sha256", "")).to_lower()
		if path.is_empty() or hash_sha256.is_empty():
			continue
		if str(_indexed_hash_by_id.get(note_id, "")) == hash_sha256:
			continue
		var job_key: String = "index:%s:%s" % [note_id, hash_sha256.left(12)]
		if not _index_worker.request(job_key, note_id, path, hash_sha256, int(asset.get("byte_size", -1))):
			_index_waiting_head -= 1
			_index_waiting_lookup[note_id] = true
			break
		_index_inflight_by_id[note_id] = {"job_key": job_key, "hash_sha256": hash_sha256}
	_compact_index_waiting_queue()


func _index_waiting_count() -> int:
	return maxi(0, _index_waiting_ids.size() - _index_waiting_head)


func _compact_index_waiting_queue() -> void:
	if _index_waiting_head <= 0:
		return
	if _index_waiting_head >= _index_waiting_ids.size():
		_index_waiting_ids.clear()
		_index_waiting_head = 0
		return
	if _index_waiting_head < 512 or _index_waiting_head * 2 < _index_waiting_ids.size():
		return
	_index_waiting_ids = _index_waiting_ids.slice(_index_waiting_head)
	_index_waiting_head = 0


func _finish_index_result(result: Dictionary) -> void:
	var note_id: String = str(result.get("note_id", ""))
	if note_id.is_empty() or not _index_inflight_by_id.has(note_id):
		return
	var inflight: Dictionary = _index_inflight_by_id[note_id] as Dictionary
	if str(inflight.get("job_key", "")) != str(result.get("job_key", "")):
		return
	_index_inflight_by_id.erase(note_id)
	if bool(result.get("cancelled", false)) or not contains(note_id):
		return
	var asset: Dictionary = library.get_asset(note_id)
	var current_hash: String = str(asset.get("hash_sha256", "")).to_lower()
	var result_hash: String = str(result.get("hash_sha256", "")).to_lower()
	if current_hash != result_hash:
		_schedule_index(note_id)
		return
	var error: String = str(result.get("error", ""))
	if not error.is_empty():
		# Keep the canonical note intact and simply omit corrupt derived index data.
		_indexed_hash_by_id.erase(note_id)
		return
	var targets_value: Variant = result.get("targets", PackedStringArray())
	var targets: PackedStringArray = targets_value as PackedStringArray if targets_value is PackedStringArray else PackedStringArray()
	_indexed_hash_by_id[note_id] = current_hash
	_indexed_excerpts_by_id[note_id] = str(result.get("excerpt", "")).left(NoteIndexWorker.MAX_EXCERPT_CHARS)
	var preview_value: Variant = result.get("board_preview", [])
	_indexed_board_preview_by_id[note_id] = (preview_value as Array).duplicate(true) if preview_value is Array else []
	_apply_raw_textual_targets(note_id, targets)
	var embed_hashes_value: Variant = result.get("embed_hashes", PackedStringArray())
	var embed_hashes: PackedStringArray = embed_hashes_value as PackedStringArray if embed_hashes_value is PackedStringArray else PackedStringArray()
	if library != null:
		library.set_note_embed_hash_references(note_id, embed_hashes)
	note_changed.emit(note_id)


func _finish_read_result(result: Dictionary) -> void:
	var note_id: String = str(result.get("note_id", ""))
	if note_id.is_empty() or not _read_inflight_by_id.has(note_id):
		return
	var inflight: Dictionary = _read_inflight_by_id[note_id] as Dictionary
	if str(inflight.get("job_key", "")) != str(result.get("job_key", "")):
		return
	_read_inflight_by_id.erase(note_id)
	if bool(result.get("cancelled", false)) or not contains(note_id):
		return
	# A second editor may have produced newer unsaved text while the disk read was
	# in flight. Cached authored text always wins over an older canonical read.
	if _content_cache.has(note_id):
		_touch_cache(note_id)
		note_content_loaded.emit(note_id, str(_content_cache[note_id]))
		return
	var asset: Dictionary = library.get_asset(note_id)
	var current_hash: String = str(asset.get("hash_sha256", "")).to_lower()
	var result_hash: String = str(result.get("hash_sha256", "")).to_lower()
	if current_hash != result_hash:
		request_content_load(note_id)
		return
	var error: String = str(result.get("error", ""))
	if not error.is_empty():
		_fail_content_load(note_id, error)
		return
	var content: String = str(result.get("content", ""))
	_put_cache(note_id, content)
	_refresh_textual_links(note_id, content)
	_refresh_resource_embeds(note_id, content)
	_indexed_hash_by_id[note_id] = current_hash
	_indexed_excerpts_by_id[note_id] = peek_cached_excerpt(note_id, NoteIndexWorker.MAX_EXCERPT_CHARS)
	_indexed_board_preview_by_id[note_id] = NoteBoardPreviewExtractor.extract(content)
	_cancel_index_for_note(note_id)
	note_content_loaded.emit(note_id, content)


func _read_content_sync(note_id: String, emit_general_error: bool = true) -> String:
	var asset: Dictionary = library.get_asset(note_id)
	var path: String = library.resolve_asset_path(note_id)
	if path.is_empty() or not FileAccess.file_exists(path):
		_set_read_error(NotLightL10n.text("runtime.notes.note_repository.98af09dc42"), emit_general_error)
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_set_read_error(NotLightL10n.text("runtime.notes.note_repository.0319baa9df"), emit_general_error)
		return ""
	var byte_size: int = int(file.get_length())
	var expected_byte_size: int = int(asset.get("byte_size", -1))
	if byte_size < 0 or byte_size > MAX_NOTE_BYTES or byte_size != expected_byte_size:
		file.close()
		_set_read_error(NotLightL10n.text("runtime.notes.note_repository.15208fb0b5"), emit_general_error)
		return ""
	var bytes: PackedByteArray = file.get_buffer(byte_size)
	file.close()
	if bytes.size() != byte_size or not AssetImportContentValidator._is_valid_utf8(bytes):
		_set_read_error(NotLightL10n.text("runtime.notes.note_repository.339e401a20"), emit_general_error)
		return ""
	for value: int in bytes:
		if value == 0:
			_set_read_error(NotLightL10n.text("runtime.notes.note_repository.bc1cd3502b"), emit_general_error)
			return ""
	var expected_hash: String = str(asset.get("hash_sha256", "")).to_lower()
	var actual_hash: String = _sha256_bytes(bytes)
	if expected_hash.length() != 64 or actual_hash.is_empty() or actual_hash != expected_hash:
		_set_read_error(NotLightL10n.text("runtime.notes.note_repository.f64357358a"), emit_general_error)
		return ""
	var content: String = bytes.get_string_from_utf8()
	if content.begins_with("\uFEFF"):
		content = content.substr(1)
	_put_cache(note_id, content)
	_refresh_textual_links(note_id, content)
	_refresh_resource_embeds(note_id, content)
	_indexed_hash_by_id[note_id] = expected_hash
	_indexed_excerpts_by_id[note_id] = peek_cached_excerpt(note_id, NoteIndexWorker.MAX_EXCERPT_CHARS)
	_indexed_board_preview_by_id[note_id] = NoteBoardPreviewExtractor.extract(content)
	_cancel_index_for_note(note_id)
	return content


func _sha256_bytes(bytes: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if not bytes.is_empty() and context.update(bytes) != OK:
		return ""
	var digest: PackedByteArray = context.finish()
	return digest.hex_encode().to_lower() if digest.size() == 32 else ""


func _cancel_index_for_note(note_id: String) -> void:
	_index_waiting_lookup.erase(note_id)
	if _index_inflight_by_id.has(note_id):
		var inflight: Dictionary = _index_inflight_by_id[note_id] as Dictionary
		_index_worker.cancel(str(inflight.get("job_key", "")))
		_index_inflight_by_id.erase(note_id)


func _rebuild_backlinks() -> void:
	_backlinks_by_id.clear()
	var sources: Dictionary = {}
	for raw_id: Variant in _textual_links_by_id.keys():
		sources[str(raw_id)] = true
	for raw_id: Variant in _explicit_links_by_id.keys():
		sources[str(raw_id)] = true
	for raw_source: Variant in sources.keys():
		var source_id: String = str(raw_source)
		for target_id: String in get_outgoing_links(source_id):
			if not contains(target_id):
				continue
			var backlinks: PackedStringArray = _backlinks_by_id.get(target_id, PackedStringArray()) as PackedStringArray
			if not backlinks.has(source_id):
				backlinks.append(source_id)
				backlinks.sort()
			_backlinks_by_id[target_id] = backlinks


func _on_library_changed() -> void:
	_rebuild_metadata_indices()
	notes_changed.emit()


func _on_library_folders_changed() -> void:
	folders_changed.emit()


func _validated_bytes(content: String) -> PackedByteArray:
	var bytes: PackedByteArray = content.to_utf8_buffer()
	if bytes.size() > MAX_NOTE_BYTES:
		_fail(NotLightL10n.text("runtime.notes.note_repository.9a93695afe"))
		return PackedByteArray()
	for value: int in bytes:
		if value == 0:
			_fail(NotLightL10n.text("runtime.notes.note_repository.6fdf0552eb"))
			return PackedByteArray()
	return bytes


func _commit_content_sync(note_id: String, bytes: PackedByteArray) -> bool:
	var temp_path: String = library.blobs.make_temp_path(AssetId.make_temporary_id("note-flush"))
	var staged: Dictionary = _write_sync(temp_path, bytes)
	if staged.is_empty():
		return false
	var commit: Dictionary = library.blobs.commit_preverified_temp(
		temp_path,
		str(staged.get("hash_sha256", "")),
		"md",
		int(staged.get("byte_size", 0))
	)
	if commit.is_empty():
		_fail(library.blobs.get_last_error())
		return false
	return _apply_committed_blob(note_id, staged, commit)


func _write_sync(temp_path: String, bytes: PackedByteArray) -> Dictionary:
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		_fail(NotLightL10n.text("runtime.notes.note_repository.ee28f1ba8a"))
		return {}
	# Godot 4.4 HashingContext.update() rejects a zero-length PackedByteArray.
	# Empty Markdown is valid canonical content, so an empty revision is hashed by
	# start() -> finish() without an update call (the standard SHA-256 of zero bytes).
	if not bytes.is_empty() and context.update(bytes) != OK:
		_fail(NotLightL10n.text("runtime.notes.note_repository.7ca41bc81e"))
		return {}
	var digest: PackedByteArray = context.finish()
	if digest.size() != 32:
		_fail(NotLightL10n.text("runtime.notes.note_repository.293e525363"))
		return {}
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		_fail(NotLightL10n.text("runtime.notes.note_repository.abf6d84763"))
		return {}
	if not bytes.is_empty():
		file.store_buffer(bytes)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		library.blobs.remove_temp(temp_path)
		_fail(NotLightL10n.text("runtime.notes.note_repository.8e3f50c53b"))
		return {}
	return {"hash_sha256": digest.hex_encode().to_lower(), "byte_size": bytes.size()}


func _normalized_note_metadata(raw: Variant) -> Dictionary:
	var source: Dictionary = raw as Dictionary if raw is Dictionary else {}
	return {
		"schema_version": NOTE_METADATA_SCHEMA_VERSION,
		"explicit_links": _normalize_link_ids(source.get("explicit_links", []), ""),
		"link_aliases": _normalize_title_aliases(source.get("link_aliases", [])),
	}


func _default_note_metadata() -> Dictionary:
	return {NOTE_METADATA_KEY: {"schema_version": NOTE_METADATA_SCHEMA_VERSION, "explicit_links": PackedStringArray(), "link_aliases": PackedStringArray()}}


func _normalize_title_aliases(raw: Variant) -> PackedStringArray:
	var values: Array = []
	if raw is Array:
		values = raw as Array
	elif raw is PackedStringArray:
		for packed_value: String in raw as PackedStringArray:
			values.append(packed_value)
	var result: PackedStringArray = PackedStringArray()
	var normalized_seen: Dictionary = {}
	for value: Variant in values:
		var alias: String = str(value).strip_edges().left(180)
		var normalized: String = NoteLinkParser.normalize_title(alias)
		if alias.is_empty() or normalized.is_empty() or normalized_seen.has(normalized):
			continue
		normalized_seen[normalized] = true
		result.append(alias)
		if result.size() >= MAX_LINK_ALIASES:
			break
	return result


func _normalize_link_ids(raw: Variant, source_id: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var values: Array = []
	if raw is Array:
		values = raw as Array
	elif raw is PackedStringArray:
		for packed_id: String in (raw as PackedStringArray):
			values.append(packed_id)
	for raw_id: Variant in values:
		var note_id: String = str(raw_id).strip_edges()
		if note_id.is_empty() or note_id == source_id or result.has(note_id):
			continue
		result.append(note_id)
		if result.size() >= MAX_EXPLICIT_LINKS:
			break
	result.sort()
	return result


func _valid_link_array(raw_links: Variant) -> PackedStringArray:
	var found: Dictionary = {}
	_append_valid_links(found, raw_links)
	var result: PackedStringArray = PackedStringArray()
	var keys: Array = found.keys()
	keys.sort()
	for raw_key: Variant in keys:
		result.append(str(raw_key))
	return result


func _append_valid_links(found: Dictionary, raw: Variant) -> void:
	if raw is not PackedStringArray:
		return
	for note_id: String in (raw as PackedStringArray):
		if contains(note_id):
			found[note_id] = true


func _put_cache(note_id: String, content: String) -> void:
	var previous: String = str(_content_cache.get(note_id, ""))
	_indexed_board_preview_by_id[note_id] = NoteBoardPreviewExtractor.extract(content)
	_cache_bytes -= previous.to_utf8_buffer().size()
	_content_cache[note_id] = content
	_cache_bytes += content.to_utf8_buffer().size()
	_touch_cache(note_id)
	_trim_cache()


func _touch_cache(note_id: String) -> void:
	_stamp_counter += 1
	_cache_stamp[note_id] = _stamp_counter


func _trim_cache() -> void:
	while _content_cache.size() > CACHE_ENTRY_BUDGET or _cache_bytes > CACHE_BYTE_BUDGET:
		var oldest_id: String = ""
		var oldest_stamp: int = 0x7FFFFFFF
		for raw_id: Variant in _cache_stamp.keys():
			var note_id: String = str(raw_id)
			if _inflight_by_id.has(note_id) or _pending_content_by_id.has(note_id):
				continue
			var stamp: int = int(_cache_stamp[note_id])
			if stamp < oldest_stamp:
				oldest_stamp = stamp
				oldest_id = note_id
		if oldest_id.is_empty():
			break
		_cache_bytes -= str(_content_cache.get(oldest_id, "")).to_utf8_buffer().size()
		_content_cache.erase(oldest_id)
		_cache_stamp.erase(oldest_id)


func _sanitize_title(title: String) -> String:
	var clean: String = title.replace("\n", " ").replace("\r", " ").strip_edges().left(160)
	return clean if not clean.is_empty() else NotLightL10n.text("notes.new")


func _safe_filename_base(title: String) -> String:
	var clean: String = title.strip_edges()
	for character: String in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		clean = clean.replace(character, "-")
	clean = clean.strip_edges().left(120)
	return clean if not clean.is_empty() else "note"


func _note_id_for_job(job_key: String) -> String:
	if not job_key.begins_with("note:"):
		return ""
	var parts: PackedStringArray = job_key.split(":", false, 2)
	return parts[1] if parts.size() >= 2 else ""


func _clear_error() -> void:
	_last_error = ""


func _set_read_error(message: String, emit_general_error: bool) -> void:
	_last_error = message
	if emit_general_error:
		note_error.emit(message)


func _fail_content_load(note_id: String, message: String) -> void:
	_last_error = message
	note_content_load_failed.emit(note_id, message)


func _fail(message: String) -> void:
	_last_error = message
	note_error.emit(message)
