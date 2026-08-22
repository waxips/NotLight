# SPDX-License-Identifier: GPL-3.0-or-later
class_name AssetImportPreflightService
extends Node

signal preflight_started(request_id: String, total_count: int)
signal preflight_progress(request_id: String, completed_count: int, total_count: int, source_path: String)
signal preflight_completed(request_id: String, results: Array)
signal preflight_cancelled(request_id: String)
signal preflight_failed(request_id: String, message: String)

const MAX_FILES_PER_PREFLIGHT: int = AssetImportValidationWorker.MAX_FILES_PER_BATCH

var catalog: AssetCatalog
var blob_store: AssetBlobStore
var _worker: AssetImportValidationWorker = AssetImportValidationWorker.new()
var _active_request_id: String = ""
var _last_error: String = ""
var _worker_ready: bool = false


func _ready() -> void:
	_worker_ready = _worker.start()
	if not _worker_ready:
		_last_error = NotLightL10n.text("library.preflight.error.worker")
	set_process(false)


func _exit_tree() -> void:
	_worker.stop()
	_worker_ready = false


func configure(asset_catalog: AssetCatalog, store: AssetBlobStore) -> void:
	catalog = asset_catalog
	blob_store = store


func request(paths: PackedStringArray) -> String:
	_last_error = ""
	if not _worker_ready:
		_last_error = NotLightL10n.text("library.preflight.error.worker")
		return ""
	if catalog == null or blob_store == null:
		_last_error = NotLightL10n.text("library.preflight.error.unavailable")
		return ""
	if not _active_request_id.is_empty():
		_last_error = NotLightL10n.text("library.preflight.error.busy")
		return ""
	if paths.is_empty():
		return ""
	if paths.size() > MAX_FILES_PER_PREFLIGHT:
		_last_error = NotLightL10n.text("library.preflight.error.too_many", {"count": MAX_FILES_PER_PREFLIGHT})
		return ""
	var candidates: Array[Dictionary] = []
	for path: String in paths:
		var clean_path: String = path.strip_edges()
		if clean_path.is_empty():
			continue
		var extension: String = clean_path.get_extension().to_lower()
		candidates.append({
			"source_path": clean_path,
			"filename": clean_path.get_file(),
			"extension": extension,
			"expected_kind": AssetImportCapabilities.kind_for_extension(extension),
		})
	if candidates.is_empty():
		return ""
	var request_id: String = AssetId.make_temporary_id("preflight")
	if not _worker.request_batch(request_id, candidates, true):
		_last_error = NotLightL10n.text("library.preflight.error.worker")
		return ""
	_active_request_id = request_id
	set_process(true)
	preflight_started.emit(request_id, candidates.size())
	return request_id


func cancel(request_id: String = "") -> bool:
	if _active_request_id.is_empty():
		return false
	var clean_id: String = request_id.strip_edges()
	if not clean_id.is_empty() and clean_id != _active_request_id:
		return false
	return _worker.cancel(_active_request_id)


func is_busy() -> bool:
	return not _active_request_id.is_empty()


func get_last_error() -> String:
	return _last_error


func _process(_delta: float) -> void:
	for update: Dictionary in _worker.poll_progress(32):
		var request_id: String = str(update.get("job_key", ""))
		if request_id != _active_request_id:
			continue
		preflight_progress.emit(
			request_id,
			int(update.get("completed", 0)),
			int(update.get("total", 0)),
			str(update.get("source_path", ""))
		)
	for worker_result: Dictionary in _worker.poll_results(2):
		var request_id: String = str(worker_result.get("job_key", ""))
		if request_id != _active_request_id:
			continue
		if bool(worker_result.get("cancelled", false)):
			_active_request_id = ""
			set_process(false)
			preflight_cancelled.emit(request_id)
			return
		var error: String = str(worker_result.get("error", ""))
		if not error.is_empty():
			_active_request_id = ""
			set_process(false)
			preflight_failed.emit(request_id, error)
			return
		var results: Array[ImportCandidateResult] = []
		var values: Variant = worker_result.get("results", [])
		if values is Array:
			for raw: Variant in values as Array:
				if raw is not Dictionary:
					continue
				results.append(ImportCandidateResult.from_worker_dictionary(raw as Dictionary))
		_enrich_duplicate_states(results)
		_active_request_id = ""
		set_process(false)
		preflight_completed.emit(request_id, results)
		return
	if _active_request_id.is_empty():
		set_process(false)


func _enrich_duplicate_states(results: Array[ImportCandidateResult]) -> void:
	var seen_hashes: Dictionary = {}
	for candidate: ImportCandidateResult in results:
		if candidate == null or not candidate.valid or candidate.hash_sha256.is_empty():
			continue
		if candidate.expected_kind == AssetKinds.NOTE:
			continue
		if seen_hashes.has(candidate.hash_sha256):
			candidate.duplicate = true
			candidate.duplicate_in_batch = true
			candidate.repair_existing = false
			continue
		seen_hashes[candidate.hash_sha256] = true
		_enrich_duplicate_state(candidate)


func _enrich_duplicate_state(candidate: ImportCandidateResult) -> void:
	if candidate == null or not candidate.valid or candidate.hash_sha256.is_empty():
		return
	if candidate.expected_kind == AssetKinds.NOTE:
		return
	var existing: Dictionary = catalog.find_asset_by_hash(candidate.hash_sha256)
	if existing.is_empty():
		return
	candidate.existing_asset_id = str(existing.get("id", ""))
	var relative_path: String = str(existing.get("blob_relpath", ""))
	if blob_store.blob_exists(relative_path):
		candidate.duplicate = true
		candidate.repair_existing = false
	else:
		# Keep it importable: the normal importer repairs a catalog record whose
		# content-addressed primary blob is missing.
		candidate.duplicate = false
		candidate.repair_existing = true
