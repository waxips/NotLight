# SPDX-License-Identifier: GPL-3.0-or-later
class_name PdfMediaService
extends Node

signal document_ready(asset_id: String, metadata: Dictionary)
signal page_ready(asset_id: String, page_index: int)
signal page_failed(asset_id: String, page_index: int, message: String)
signal preparation_failed(asset_id: String, message: String)
signal variant_state_changed(asset_id: String, state: Dictionary)
signal display_variant_changed(asset_id: String, path: String, variant_name: String)

const TIER_THUMBNAIL: int = 320
const TIER_SMALL: int = 768
const TIER_MEDIUM: int = 1536
const TIER_LARGE: int = 3072
const TIERS: PackedInt32Array = [TIER_THUMBNAIL, TIER_SMALL, TIER_MEDIUM, TIER_LARGE]
const MAX_PENDING_JOBS: int = 32
const MAX_BACKGROUND_PENDING_JOBS: int = 28
const DEFAULT_MEMORY_LIMIT_BYTES: int = 256 * 1024 * 1024
const MAX_UPLOADS_PER_FRAME: int = 2
const VARIANT_ORIGINAL: String = "original"
const VARIANT_OPTIMIZED: String = "optimized"

var library: AssetLibraryService
var memory_limit_bytes: int = DEFAULT_MEMORY_LIMIT_BYTES
var max_uploads_per_frame: int = MAX_UPLOADS_PER_FRAME
var _worker: PdfRenderWorker = PdfRenderWorker.new()
var _entries: Dictionary = {}
var _document_info: Dictionary = {}
var _failure_messages: Dictionary = {}
var _failed_page_keys: Dictionary = {}
var _failed_probe_assets: Dictionary = {}
var _access_counter: int = 0
var _memory_bytes: int = 0
var _tools_checked: bool = false
var _tools_available: bool = false
var _poppler_version: String = ""
var _worker_started: bool = false


func _ready() -> void:
	_worker_started = _worker.start()
	set_process(false)


func _exit_tree() -> void:
	_worker.stop()


func configure(asset_library: AssetLibraryService) -> void:
	library = asset_library
	if library != null:
		if not library.library_changed.is_connected(_on_library_changed):
			library.library_changed.connect(_on_library_changed)
		if not library.import_finished.is_connected(_on_import_finished):
			library.import_finished.connect(_on_import_finished)


func _process(_delta: float) -> void:
	var results: Array[Dictionary] = _worker.poll_results(max_uploads_per_frame)
	for result: Dictionary in results:
		_apply_worker_result(result)
	if not results.is_empty():
		_evict_if_needed()
	if _worker.pending_work_count() == 0:
		set_process(false)


func tools_available() -> bool:
	if not _worker_started:
		return false
	_ensure_tools_checked()
	return _tools_available


func status_text() -> String:
	if not _worker_started:
		return NotLightL10n.text("pdf.error.worker_unavailable")
	_ensure_tools_checked()
	if not _tools_available:
		return NotLightL10n.text("pdf.error.poppler_missing")
	return _poppler_version if not _poppler_version.is_empty() else NotLightL10n.text("pdf.status.available")


func set_memory_limit_megabytes(value: int) -> void:
	memory_limit_bytes = maxi(64, value) * 1024 * 1024
	_evict_if_needed()


func set_upload_budget(value: int) -> void:
	max_uploads_per_frame = clampi(value, 1, 8)


func ensure_document(asset_id: String, priority: int = 0) -> Dictionary:
	var clean_id: String = asset_id.strip_edges()
	if clean_id.is_empty() or library == null:
		return {}
	if not _worker_started:
		var worker_error: String = NotLightL10n.text("pdf.error.worker_unavailable")
		_record_failure(clean_id, worker_error)
		preparation_failed.emit(clean_id, worker_error)
		return {"ok": false, "error": worker_error}
	var cached: Dictionary = get_document_info(clean_id)
	if bool(cached.get("ok", false)) and int(cached.get("page_count", 0)) > 0:
		return cached
	if _failed_probe_assets.has(clean_id):
		return {"ok": false, "error": str(_failed_probe_assets.get(clean_id, NotLightL10n.text("pdf.error.metadata")))}
	if not tools_available():
		var message: String = NotLightL10n.text("pdf.error.poppler_missing")
		_record_failure(clean_id, message)
		preparation_failed.emit(clean_id, message)
		return {"ok": false, "error": message}
	var record: Dictionary = library.get_asset(clean_id)
	if record.is_empty() or int(record.get("kind", AssetKinds.OTHER)) != AssetKinds.PDF:
		return {"ok": false, "error": NotLightL10n.text("pdf.error.not_pdf")}
	var source_path: String = resolve_display_path(clean_id)
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		var source_error: String = NotLightL10n.text("pdf.error.source_unavailable")
		_record_failure(clean_id, source_error)
		preparation_failed.emit(clean_id, source_error)
		return {"ok": false, "error": source_error}
	var key: String = "probe|%s" % clean_id
	if _worker.is_pending(key):
		if priority > 0:
			_worker.promote_pending(key, priority)
		set_process(true)
	else:
		var pending_count: int = _worker.pending_work_count()
		if pending_count < MAX_PENDING_JOBS and (priority > 0 or pending_count < MAX_BACKGROUND_PENDING_JOBS):
			if _worker.request_probe(key, clean_id, source_path, priority):
				set_process(true)
	return cached if not cached.is_empty() else {"ok": true, "pending": true, "page_count": 0, "page_size": Vector2i(595, 842)}


func get_document_info(asset_id: String) -> Dictionary:
	var clean_id: String = asset_id.strip_edges()
	if clean_id.is_empty():
		return {}
	if _document_info.has(clean_id):
		return (_document_info[clean_id] as Dictionary).duplicate(true)
	if library == null:
		return {}
	var record: Dictionary = library.get_asset(clean_id)
	if record.is_empty() or int(record.get("kind", AssetKinds.OTHER)) != AssetKinds.PDF:
		return {}
	var metadata: Dictionary = record.get("metadata", {}) as Dictionary
	var pdf: Dictionary = metadata.get("pdf", {}) as Dictionary
	if pdf.is_empty():
		return {}
	var info: Dictionary = _normalized_info(pdf)
	_document_info[clean_id] = info
	return info.duplicate(true)


func get_page_count(asset_id: String) -> int:
	return maxi(0, int(get_document_info(asset_id).get("page_count", 0)))


func get_page_size(asset_id: String) -> Vector2i:
	var info: Dictionary = get_document_info(asset_id)
	var value: Variant = info.get("page_size", Vector2i(595, 842))
	return value as Vector2i if value is Vector2i else Vector2i(595, 842)


func get_failure_message(asset_id: String) -> String:
	return str(_failure_messages.get(asset_id, ""))


func get_variant_state(asset_id: String) -> Dictionary:
	if library == null:
		return {}
	var clean_id: String = asset_id.strip_edges()
	var asset: Dictionary = library.get_asset(clean_id)
	if asset.is_empty() or int(asset.get("kind", AssetKinds.OTHER)) != AssetKinds.PDF:
		return {}
	return _ensure_pdf_state(clean_id, asset).duplicate(true)


func has_variant(asset_id: String, variant_name: String) -> bool:
	var state: Dictionary = get_variant_state(asset_id)
	return _variant_is_usable(state, variant_name)


func preferred_variant(asset_id: String) -> String:
	return str(get_variant_state(asset_id).get("preferred_variant", VARIANT_ORIGINAL))


func resolve_display_path(asset_id: String) -> String:
	if library == null:
		return ""
	var clean_id: String = asset_id.strip_edges()
	var asset: Dictionary = library.get_asset(clean_id)
	if asset.is_empty() or int(asset.get("kind", AssetKinds.OTHER)) != AssetKinds.PDF:
		return ""
	var state: Dictionary = _ensure_pdf_state(clean_id, asset)
	var preferred: String = str(state.get("preferred_variant", VARIANT_ORIGINAL))
	if _variant_is_usable(state, preferred):
		return _variant_path(state, preferred)
	if _variant_is_usable(state, VARIANT_ORIGINAL):
		return _variant_path(state, VARIANT_ORIGINAL)
	return library.resolve_asset_path(clean_id)


func display_blob_hash(asset_id: String) -> String:
	var state: Dictionary = get_variant_state(asset_id)
	var preferred: String = str(state.get("preferred_variant", VARIANT_ORIGINAL))
	if not _variant_is_usable(state, preferred):
		preferred = VARIANT_ORIGINAL
	return str(_variant_record(state, preferred).get("hash_sha256", "")).strip_edges().to_lower()


func set_preferred_variant(asset_id: String, variant_name: String) -> bool:
	if library == null:
		return false
	var clean_id: String = asset_id.strip_edges()
	var clean_variant: String = variant_name.strip_edges().to_lower()
	if clean_id.is_empty() or (clean_variant != VARIANT_ORIGINAL and clean_variant != VARIANT_OPTIMIZED):
		return false
	var asset: Dictionary = library.get_asset(clean_id)
	if asset.is_empty() or int(asset.get("kind", AssetKinds.OTHER)) != AssetKinds.PDF:
		return false
	var state: Dictionary = _ensure_pdf_state(clean_id, asset)
	if not _variant_is_usable(state, clean_variant):
		return false
	state["preferred_variant"] = clean_variant
	if not _save_pdf_state(clean_id, asset, state):
		return false
	invalidate_asset(clean_id)
	variant_state_changed.emit(clean_id, state.duplicate(true))
	display_variant_changed.emit(clean_id, resolve_display_path(clean_id), clean_variant)
	return true


func register_optimized_variant(asset_id: String, variant: Dictionary) -> bool:
	if library == null:
		return false
	var clean_id: String = asset_id.strip_edges()
	var asset: Dictionary = library.get_asset(clean_id)
	if asset.is_empty() or int(asset.get("kind", AssetKinds.OTHER)) != AssetKinds.PDF:
		return false
	var state: Dictionary = _ensure_pdf_state(clean_id, asset)
	var original: Dictionary = _variant_record(state, VARIANT_ORIGINAL)
	var expected_source_hash: String = str(original.get("hash_sha256", "")).strip_edges().to_lower()
	var source_hash: String = str(variant.get("source_hash_sha256", "")).strip_edges().to_lower()
	var output_hash: String = str(variant.get("hash_sha256", "")).strip_edges().to_lower()
	var relpath: String = str(variant.get("blob_relpath", "")).strip_edges()
	var byte_size: int = int(variant.get("byte_size", 0))
	if (
		not _is_sha256(expected_source_hash)
		or source_hash != expected_source_hash
		or not _is_sha256(output_hash)
		or relpath.is_empty()
		or byte_size <= 0
	):
		return false
	var output_path: String = library.resolve_blob_relative(relpath)
	if output_path.is_empty() or not _is_nonempty_file(output_path):
		return false
	var previous: Dictionary = _variant_record(state, VARIANT_OPTIMIZED)
	var variants: Dictionary = (state.get("variants", {}) as Dictionary).duplicate(true)
	variants[VARIANT_OPTIMIZED] = variant.duplicate(true)
	state["variants"] = variants
	state["preferred_variant"] = VARIANT_OPTIMIZED
	if not _save_pdf_state(clean_id, asset, state):
		return false
	var previous_relpath: String = str(previous.get("blob_relpath", ""))
	if not previous_relpath.is_empty() and previous_relpath != relpath:
		library.delete_blob_if_unreferenced_path(previous_relpath)
	invalidate_asset(clean_id)
	variant_state_changed.emit(clean_id, state.duplicate(true))
	display_variant_changed.emit(clean_id, output_path, VARIANT_OPTIMIZED)
	return true


func delete_optimized_variant(asset_id: String) -> bool:
	if library == null:
		return false
	var clean_id: String = asset_id.strip_edges()
	var asset: Dictionary = library.get_asset(clean_id)
	if asset.is_empty() or int(asset.get("kind", AssetKinds.OTHER)) != AssetKinds.PDF:
		return false
	var state: Dictionary = _ensure_pdf_state(clean_id, asset)
	var optimized: Dictionary = _variant_record(state, VARIANT_OPTIMIZED)
	if optimized.is_empty():
		return true
	if not _variant_is_usable(state, VARIANT_ORIGINAL):
		return false
	var variants: Dictionary = (state.get("variants", {}) as Dictionary).duplicate(true)
	variants.erase(VARIANT_OPTIMIZED)
	state["variants"] = variants
	state["preferred_variant"] = VARIANT_ORIGINAL
	if not _save_pdf_state(clean_id, asset, state):
		return false
	var relpath: String = str(optimized.get("blob_relpath", ""))
	if not relpath.is_empty():
		library.delete_blob_if_unreferenced_path(relpath)
	invalidate_asset(clean_id)
	variant_state_changed.emit(clean_id, state.duplicate(true))
	display_variant_changed.emit(clean_id, resolve_display_path(clean_id), VARIANT_ORIGINAL)
	return true


func request_page(asset_id: String, page_index: int, desired_screen_extent: float = 1024.0, priority: int = 0) -> Texture2D:
	_access_counter += 1
	var clean_id: String = asset_id.strip_edges()
	if clean_id.is_empty() or library == null:
		return null
	if not _worker_started:
		_record_failure(clean_id, NotLightL10n.text("pdf.error.worker_unavailable"))
		return null
	var tier: int = tier_for_extent(desired_screen_extent)
	var safe_page: int = maxi(0, page_index)
	var page_count: int = get_page_count(clean_id)
	if page_count > 0:
		safe_page = mini(safe_page, page_count - 1)
	var key: String = _page_key(clean_id, safe_page, tier)
	var exact: Texture2D = _touch_and_get_texture(key)
	if exact != null:
		return exact
	var fallback: Texture2D = _best_cached_texture(clean_id, safe_page, tier)
	if _failed_page_keys.has(key):
		return fallback
	var document_info: Dictionary = get_document_info(clean_id)
	if bool(document_info.get("encrypted", false)):
		_record_failure(clean_id, NotLightL10n.text("pdf.error.encrypted_unsupported"))
		return fallback
	if int(document_info.get("page_count", 0)) <= 0:
		ensure_document(clean_id, priority)
		return fallback
	if _worker.is_pending(key):
		if priority > 0:
			_worker.promote_pending(key, priority)
		set_process(true)
		return fallback
	if not tools_available():
		_record_failure(clean_id, NotLightL10n.text("pdf.error.poppler_missing"))
		return fallback
	var pending_count: int = _worker.pending_work_count()
	if pending_count >= MAX_PENDING_JOBS or (priority <= 0 and pending_count >= MAX_BACKGROUND_PENDING_JOBS):
		set_process(true)
		return fallback
	var record: Dictionary = library.get_asset(clean_id)
	if record.is_empty() or int(record.get("kind", AssetKinds.OTHER)) != AssetKinds.PDF:
		_record_failure(clean_id, NotLightL10n.text("pdf.error.not_pdf"))
		return fallback
	var source_path: String = resolve_display_path(clean_id)
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		_record_failure(clean_id, NotLightL10n.text("pdf.error.source_unavailable"))
		return fallback
	var cache_path: String = _disk_cache_path(record, safe_page, tier)
	var native_dir: String = ProjectSettings.globalize_path(cache_path.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(native_dir) != OK and not DirAccess.dir_exists_absolute(native_dir):
		_record_failure(clean_id, NotLightL10n.text("pdf.error.cache_failed"))
		return fallback
	if _worker.request_render(key, clean_id, source_path, safe_page, tier, cache_path, priority):
		set_process(true)
	return fallback


func request_thumbnail(asset_id: String) -> Texture2D:
	return request_page(asset_id, 0, float(TIER_THUMBNAIL))


func invalidate_asset(asset_id: String) -> void:
	var clean_id: String = asset_id.strip_edges()
	var keys: Array[String] = []
	for raw_key: Variant in _entries.keys():
		var key: String = str(raw_key)
		if key.begins_with("%s|" % clean_id):
			keys.append(key)
	for key: String in keys:
		_remove_entry(key)
	var failed_keys: Array[String] = []
	for raw_failed_key: Variant in _failed_page_keys.keys():
		var failed_key: String = str(raw_failed_key)
		if failed_key.begins_with("%s|" % clean_id):
			failed_keys.append(failed_key)
	for failed_key: String in failed_keys:
		_failed_page_keys.erase(failed_key)
	_document_info.erase(clean_id)
	_failure_messages.erase(clean_id)
	_failed_probe_assets.erase(clean_id)


static func tier_for_extent(desired_screen_extent: float) -> int:
	var extent: float = maxf(1.0, desired_screen_extent)
	if extent <= 260.0:
		return TIER_THUMBNAIL
	if extent <= 680.0:
		return TIER_SMALL
	if extent <= 1360.0:
		return TIER_MEDIUM
	return TIER_LARGE


func _ensure_tools_checked() -> void:
	if _tools_checked:
		return
	_tools_checked = true
	_tools_available = PopplerTools.tools_available()
	_poppler_version = PopplerTools.version_line() if _tools_available else ""


func _apply_worker_result(result: Dictionary) -> void:
	var operation: String = str(result.get("operation", ""))
	var asset_id: String = str(result.get("asset_id", ""))
	var error_message: String = str(result.get("error", ""))
	var error_kind: String = str(result.get("error_kind", ""))
	if error_kind == "tool_missing":
		_tools_checked = true
		_tools_available = false
		error_message = NotLightL10n.text("pdf.error.poppler_missing")
	elif error_kind == "encrypted":
		error_message = NotLightL10n.text("pdf.error.encrypted_unsupported")
	if not error_message.is_empty():
		_record_failure(asset_id, error_message)
		if operation == PdfRenderWorker.OP_RENDER:
			var failed_key: String = str(result.get("cache_key", ""))
			if not failed_key.is_empty():
				_failed_page_keys[failed_key] = error_message
			page_failed.emit(asset_id, maxi(0, int(result.get("page_index", 0))), error_message)
		else:
			if operation == PdfRenderWorker.OP_PROBE and not asset_id.is_empty():
				_failed_probe_assets[asset_id] = error_message
			preparation_failed.emit(asset_id, error_message)
		return
	_tools_checked = true
	_tools_available = true
	if operation == PdfRenderWorker.OP_PROBE:
		_apply_probe_result(asset_id, str(result.get("output", "")))
	elif operation == PdfRenderWorker.OP_RENDER:
		_apply_render_result(result)


func _apply_probe_result(asset_id: String, output: String) -> void:
	_failed_probe_assets.erase(asset_id)
	var parsed: Dictionary = _parse_pdfinfo(output)
	if not bool(parsed.get("ok", false)):
		var message: String = str(parsed.get("error", NotLightL10n.text("pdf.error.metadata")))
		_record_failure(asset_id, message)
		preparation_failed.emit(asset_id, message)
		return
	_document_info[asset_id] = parsed.duplicate(true)
	if bool(parsed.get("encrypted", false)):
		_record_failure(asset_id, NotLightL10n.text("pdf.error.encrypted_unsupported"))
	else:
		_failure_messages.erase(asset_id)
	if library != null:
		var record: Dictionary = library.get_asset(asset_id)
		if not record.is_empty():
			var metadata: Dictionary = (record.get("metadata", {}) as Dictionary).duplicate(true)
			var pdf_metadata: Dictionary = (metadata.get("pdf", {}) as Dictionary).duplicate(true)
			pdf_metadata["page_count"] = int(parsed.get("page_count", 0))
			pdf_metadata["page_width_points"] = float(parsed.get("page_width_points", 595.0))
			pdf_metadata["page_height_points"] = float(parsed.get("page_height_points", 842.0))
			pdf_metadata["encrypted"] = bool(parsed.get("encrypted", false))
			pdf_metadata["poppler_version"] = _poppler_version
			if metadata.get("pdf", {}) != pdf_metadata:
				metadata["pdf"] = pdf_metadata
				library.update_asset_metadata(asset_id, metadata)
	document_ready.emit(asset_id, parsed.duplicate(true))


func _apply_render_result(result: Dictionary) -> void:
	var asset_id: String = str(result.get("asset_id", ""))
	var page_index: int = maxi(0, int(result.get("page_index", 0)))
	var key: String = str(result.get("cache_key", ""))
	var output_path: String = str(result.get("output_path", ""))
	var image: Image = Image.load_from_file(output_path)
	if image == null or image.is_empty():
		if not output_path.is_empty() and FileAccess.file_exists(output_path):
			DirAccess.remove_absolute(output_path)
		var message: String = NotLightL10n.text("pdf.error.render_output")
		_record_failure(asset_id, message)
		if not key.is_empty():
			_failed_page_keys[key] = message
		page_failed.emit(asset_id, page_index, message)
		return
	if not image.has_mipmaps() and maxi(image.get_width(), image.get_height()) >= 256:
		image.generate_mipmaps()
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	if texture == null:
		var texture_error: String = NotLightL10n.text("pdf.error.texture")
		_record_failure(asset_id, texture_error)
		if not key.is_empty():
			_failed_page_keys[key] = texture_error
		page_failed.emit(asset_id, page_index, texture_error)
		return
	if _entries.has(key):
		_remove_entry(key)
	_failed_page_keys.erase(key)
	var byte_estimate: int = int(ceil(float(maxi(1, image.get_width()) * maxi(1, image.get_height())) * (5.34 if image.has_mipmaps() else 4.0)))
	_entries[key] = {
		"texture": texture,
		"bytes": byte_estimate,
		"last_used": _access_counter,
		"asset_id": asset_id,
		"page_index": page_index,
	}
	_memory_bytes += byte_estimate
	_failure_messages.erase(asset_id)
	page_ready.emit(asset_id, page_index)


func _parse_pdfinfo(output: String) -> Dictionary:
	return PdfDocumentProbe.parse_pdfinfo(output, _poppler_version)


func _normalized_info(pdf: Dictionary) -> Dictionary:
	var width_points: float = maxf(1.0, float(pdf.get("page_width_points", 595.0)))
	var height_points: float = maxf(1.0, float(pdf.get("page_height_points", 842.0)))
	return {
		"ok": int(pdf.get("page_count", 0)) > 0,
		"page_count": maxi(0, int(pdf.get("page_count", 0))),
		"page_width_points": width_points,
		"page_height_points": height_points,
		"page_size": Vector2i(maxi(1, int(round(width_points))), maxi(1, int(round(height_points)))),
		"encrypted": bool(pdf.get("encrypted", false)),
		"poppler_version": str(pdf.get("poppler_version", "")),
	}


func _page_key(asset_id: String, page_index: int, tier: int) -> String:
	var hash_value: String = display_blob_hash(asset_id)
	var hash_key: String = hash_value if not hash_value.is_empty() else "nohash"
	return "%s|%s|%d|%d" % [asset_id, hash_key, page_index, tier]


func _disk_cache_path(record: Dictionary, page_index: int, tier: int) -> String:
	var asset_id: String = str(record.get("id", ""))
	var hash_value: String = display_blob_hash(asset_id)
	if hash_value.is_empty():
		hash_value = str(record.get("hash_sha256", "nohash")).to_lower()
	var hash_prefix: String = hash_value.substr(0, mini(16, hash_value.length()))
	return library.blobs.cache_path_for_asset(asset_id).path_join("pdf").path_join(hash_prefix).path_join(
		"page_%05d_%d.png" % [page_index + 1, tier]
	)


func _touch_and_get_texture(key: String) -> Texture2D:
	var value: Variant = _entries.get(key)
	if value is not Dictionary:
		return null
	var entry: Dictionary = value as Dictionary
	entry["last_used"] = _access_counter
	_entries[key] = entry
	var texture_value: Variant = entry.get("texture")
	return texture_value as Texture2D if texture_value is Texture2D else null


func _best_cached_texture(asset_id: String, page_index: int, requested_tier: int) -> Texture2D:
	var best: Texture2D = null
	var best_distance: int = 2147483647
	for tier: int in TIERS:
		var key: String = _page_key(asset_id, page_index, tier)
		var value: Variant = _entries.get(key)
		if value is not Dictionary:
			continue
		var entry: Dictionary = value as Dictionary
		var texture_value: Variant = entry.get("texture")
		if texture_value is not Texture2D:
			continue
		var distance: int = absi(tier - requested_tier)
		if distance < best_distance or (distance == best_distance and tier > requested_tier):
			best_distance = distance
			best = texture_value as Texture2D
			entry["last_used"] = _access_counter
			_entries[key] = entry
	return best


func _ensure_pdf_state(_asset_id: String, asset: Dictionary) -> Dictionary:
	var metadata: Dictionary = asset.get("metadata", {}) as Dictionary
	var state: Dictionary = (metadata.get("pdf", {}) as Dictionary).duplicate(true)
	var variants: Dictionary = (state.get("variants", {}) as Dictionary).duplicate(true)
	# The catalogue primary blob is always the canonical PDF original. Rebuild the
	# derived metadata record if an old/portable record ever disagrees with it.
	var primary_relpath: String = str(asset.get("blob_relpath", "")).strip_edges()
	var primary_hash: String = str(asset.get("hash_sha256", "")).strip_edges().to_lower()
	var original: Dictionary = _variant_record({"variants": variants}, VARIANT_ORIGINAL)
	if (
		str(original.get("blob_relpath", "")).strip_edges() != primary_relpath
		or str(original.get("hash_sha256", "")).strip_edges().to_lower() != primary_hash
	):
		if not primary_relpath.is_empty():
			variants[VARIANT_ORIGINAL] = {
				"blob_relpath": primary_relpath,
				"hash_sha256": primary_hash,
				"byte_size": int(asset.get("byte_size", 0)),
				"extension": str(asset.get("extension", "pdf")).strip_edges().to_lower(),
				"created_at_unix": int(asset.get("imported_at_unix", asset.get("created_at_unix", 0))),
			}
	state["variants"] = variants
	var preferred: String = str(state.get("preferred_variant", VARIANT_ORIGINAL)).strip_edges().to_lower()
	if preferred != VARIANT_ORIGINAL and preferred != VARIANT_OPTIMIZED:
		preferred = VARIANT_ORIGINAL
	if preferred == VARIANT_OPTIMIZED and not _variant_is_usable(state, VARIANT_OPTIMIZED):
		preferred = VARIANT_ORIGINAL
	state["preferred_variant"] = preferred
	return state


func _save_pdf_state(asset_id: String, asset: Dictionary, state: Dictionary) -> bool:
	if library == null:
		return false
	var metadata: Dictionary = (asset.get("metadata", {}) as Dictionary).duplicate(true)
	metadata["pdf"] = state.duplicate(true)
	return library.update_asset_metadata(asset_id, metadata)


func _variant_record(state: Dictionary, variant_name: String) -> Dictionary:
	var variants: Dictionary = state.get("variants", {}) as Dictionary
	var raw: Variant = variants.get(variant_name, {})
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


func _variant_path(state: Dictionary, variant_name: String) -> String:
	if library == null:
		return ""
	var record: Dictionary = _variant_record(state, variant_name)
	var relative_path: String = str(record.get("blob_relpath", "")).strip_edges()
	return library.resolve_blob_relative(relative_path) if not relative_path.is_empty() else ""


func _variant_is_usable(state: Dictionary, variant_name: String) -> bool:
	var record: Dictionary = _variant_record(state, variant_name)
	if record.is_empty() or int(record.get("byte_size", 0)) <= 0:
		return false
	if variant_name == VARIANT_OPTIMIZED:
		var original_hash: String = str(_variant_record(state, VARIANT_ORIGINAL).get("hash_sha256", "")).strip_edges().to_lower()
		var source_hash: String = str(record.get("source_hash_sha256", "")).strip_edges().to_lower()
		if not _is_sha256(original_hash) or source_hash != original_hash:
			return false
	var path: String = _variant_path(state, variant_name)
	return not path.is_empty() and FileAccess.file_exists(path)


func _is_nonempty_file(path: String) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var size: int = int(file.get_length())
	file.close()
	return size > 0


func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in range(value.length()):
		var codepoint: int = value.unicode_at(index)
		var is_digit: bool = codepoint >= 48 and codepoint <= 57
		var is_hex_letter: bool = codepoint >= 97 and codepoint <= 102
		if not is_digit and not is_hex_letter:
			return false
	return true


func _record_failure(asset_id: String, message: String) -> void:
	var clean_id: String = asset_id.strip_edges()
	if clean_id.is_empty():
		return
	_failure_messages[clean_id] = message


func _remove_entry(key: String) -> void:
	var value: Variant = _entries.get(key)
	if value is Dictionary:
		_memory_bytes = maxi(0, _memory_bytes - maxi(0, int((value as Dictionary).get("bytes", 0))))
	_entries.erase(key)


func _evict_if_needed() -> void:
	if _memory_bytes <= memory_limit_bytes:
		return
	var candidates: Array[Dictionary] = []
	for raw_key: Variant in _entries.keys():
		var key: String = str(raw_key)
		var entry: Dictionary = _entries[key] as Dictionary
		candidates.append({"key": key, "last_used": int(entry.get("last_used", 0))})
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("last_used", 0)) < int(right.get("last_used", 0))
	)
	for candidate: Dictionary in candidates:
		if _memory_bytes <= memory_limit_bytes:
			break
		_remove_entry(str(candidate.get("key", "")))


func _on_import_finished(asset_id: String, _duplicate: bool) -> void:
	if library == null:
		return
	var record: Dictionary = library.get_asset(asset_id)
	if not record.is_empty() and int(record.get("kind", AssetKinds.OTHER)) == AssetKinds.PDF:
		ensure_document(asset_id)


func _on_library_changed() -> void:
	if library == null:
		return
	var stale_ids: Array[String] = []
	for raw_id: Variant in _document_info.keys():
		var asset_id: String = str(raw_id)
		if library.get_asset(asset_id).is_empty():
			stale_ids.append(asset_id)
	for asset_id: String in stale_ids:
		invalidate_asset(asset_id)
