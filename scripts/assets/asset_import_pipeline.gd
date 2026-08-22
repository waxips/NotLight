# SPDX-License-Identifier: GPL-3.0-or-later
class_name AssetImportPipeline
extends Node

signal import_started(job_id: String, source_path: String)
signal import_progress(job_id: String, source_path: String, progress: float)
signal import_completed(job_id: String, asset_id: String, duplicate: bool)
signal import_failed(job_id: String, source_path: String, message: String)
signal queue_changed(pending_count: int)

const MAX_PENDING_JOBS: int = 256
const COPY_PROGRESS_WEIGHT: float = 0.82
const VALIDATION_PROGRESS: float = 0.90
const HEX_DIGITS: String = "0123456789abcdef"

var catalog: AssetCatalog
var blob_store: AssetBlobStore
var _queue: Array[Dictionary] = []
var _active: Dictionary = {}
var _bytes_total: int = 0
var _bytes_done: int = 0
var _last_progress: float = -1.0
var _last_error: String = ""
var _staging_worker: AssetImportStagingWorker = AssetImportStagingWorker.new()
var _validation_worker: AssetImportValidationWorker = AssetImportValidationWorker.new()
var _workers_ready: bool = false


func _ready() -> void:
	var staging_ready: bool = _staging_worker.start()
	var validation_ready: bool = _validation_worker.start()
	_workers_ready = staging_ready and validation_ready
	if not _workers_ready:
		# Stop whichever worker did start so a partially initialized pipeline cannot
		# keep a hidden background thread alive while reporting itself unavailable.
		_staging_worker.stop()
		_validation_worker.stop()
	set_process(false)


func _exit_tree() -> void:
	# Workers own every heavy file handle. Cancel first, then join them before any
	# staging cleanup so exit can never delete a file that a worker is still using.
	var active_id: String = str(_active.get("id", ""))
	if not active_id.is_empty():
		_staging_worker.cancel(active_id)
		_validation_worker.cancel(active_id)
	_staging_worker.stop()
	_validation_worker.stop()
	_cleanup_active_files()
	_cleanup_queued_managed_sources()
	_queue.clear()
	_active.clear()


func configure(asset_catalog: AssetCatalog, store: AssetBlobStore) -> void:
	catalog = asset_catalog
	blob_store = store


func get_last_error() -> String:
	return _last_error


func enqueue_files(paths: PackedStringArray, folder_id: String = "") -> PackedStringArray:
	_last_error = ""
	var job_ids: PackedStringArray = PackedStringArray()
	var first_error: String = ""
	for source_path: String in paths:
		var job_id: String = enqueue_file(source_path, folder_id)
		if not job_id.is_empty():
			job_ids.append(job_id)
		elif first_error.is_empty() and not _last_error.is_empty():
			first_error = _last_error
	_last_error = first_error
	return job_ids


func enqueue_preflight_requests(requests: Array[Dictionary], folder_id: String = "") -> PackedStringArray:
	_last_error = ""
	var job_ids: PackedStringArray = PackedStringArray()
	var first_error: String = ""
	for request: Dictionary in requests:
		var source_path: String = str(request.get("source_path", ""))
		var job_id: String = enqueue_file(
			source_path,
			folder_id,
			"",
			str(request.get("filename", source_path.get_file())),
			false,
			str(request.get("hash_sha256", "")),
			int(request.get("byte_size", -1)),
			int(request.get("expected_kind", AssetKinds.ANY))
		)
		if not job_id.is_empty():
			job_ids.append(job_id)
		elif first_error.is_empty() and not _last_error.is_empty():
			first_error = _last_error
	_last_error = first_error
	return job_ids


func enqueue_file(
	source_path: String,
	folder_id: String = "",
	display_name_override: String = "",
	original_filename_override: String = "",
	cleanup_source: bool = false,
	expected_source_hash: String = "",
	expected_source_size: int = -1,
	expected_kind: int = AssetKinds.ANY
) -> String:
	_last_error = ""
	if catalog == null or blob_store == null:
		_last_error = NotLightL10n.text("library.import.error.pipeline_unavailable")
		return ""
	if not _workers_ready:
		_last_error = NotLightL10n.text("library.import.error.validator_unavailable")
		return ""
	var clean_source: String = source_path.strip_edges()
	if clean_source.is_empty() or not FileAccess.file_exists(clean_source):
		_last_error = NotLightL10n.text("library.import.reject.missing")
		return ""
	if pending_count() >= MAX_PENDING_JOBS:
		_last_error = NotLightL10n.text("library.import.error.queue_full", {"count": MAX_PENDING_JOBS})
		return ""
	var original_filename: String = original_filename_override.strip_edges()
	if original_filename.is_empty():
		original_filename = clean_source.get_file()
	var extension: String = original_filename.get_extension().to_lower()
	var inferred_kind: int = AssetImportCapabilities.kind_for_extension(extension)
	var safe_kind: int = inferred_kind if expected_kind == AssetKinds.ANY else expected_kind
	if inferred_kind == AssetKinds.OTHER or not AssetImportCapabilities.is_importable_kind(safe_kind):
		_last_error = AssetImportCapabilities.rejection_message(
			ImportCandidateResult.REJECTION_UNSUPPORTED_EXTENSION,
			extension
		)
		return ""
	if inferred_kind != safe_kind:
		_last_error = AssetImportCapabilities.rejection_message(ImportCandidateResult.REJECTION_KIND_MISMATCH, extension)
		return ""
	var clean_expected_hash: String = expected_source_hash.strip_edges().to_lower()
	if not clean_expected_hash.is_empty() and not _is_sha256(clean_expected_hash):
		_last_error = NotLightL10n.text("library.import.error.preflight_invalid")
		return ""
	if expected_source_size < -1:
		_last_error = NotLightL10n.text("library.import.error.preflight_invalid")
		return ""
	var job_id: String = AssetId.make_temporary_id("import")
	_queue.append({
		"id": job_id,
		"source_path": clean_source,
		"folder_id": folder_id,
		"display_name_override": display_name_override.strip_edges(),
		"original_filename_override": original_filename,
		"cleanup_source": cleanup_source,
		"expected_source_hash": clean_expected_hash,
		"expected_source_size": expected_source_size,
		"expected_kind": safe_kind,
		"extension": extension,
		"phase": "queued",
		"cancel_requested": false,
	})
	set_process(true)
	queue_changed.emit(pending_count())
	return job_id


func cancel_all() -> void:
	_cleanup_queued_managed_sources()
	_queue.clear()
	if not _active.is_empty():
		var job_id: String = str(_active.get("id", ""))
		_active["cancel_requested"] = true
		var phase: String = str(_active.get("phase", ""))
		if phase == "staging":
			_staging_worker.cancel(job_id)
		elif phase == "validating":
			_validation_worker.cancel(job_id)
		else:
			_fail_active(NotLightL10n.text("library.import.error.cancelled"))
	if _active.is_empty():
		set_process(false)
	queue_changed.emit(pending_count())


func pending_count() -> int:
	return _queue.size() + (0 if _active.is_empty() else 1)


func remaining_capacity() -> int:
	return maxi(0, MAX_PENDING_JOBS - pending_count())


func _process(_delta: float) -> void:
	_poll_staging_progress()
	_poll_staging_results()
	_poll_validation_results()
	if _active.is_empty():
		if _queue.is_empty():
			set_process(false)
			return
		_start_next()


func _start_next() -> void:
	if not _active.is_empty() or _queue.is_empty():
		return
	_active = _queue.pop_front()
	_active["phase"] = "staging"
	var source_path: String = str(_active.get("source_path", ""))
	var job_id: String = str(_active.get("id", ""))
	if not FileAccess.file_exists(source_path):
		_fail_active(NotLightL10n.text("library.import.reject.missing"))
		return
	var temp_path: String = blob_store.make_temp_path(job_id)
	blob_store.remove_temp(temp_path)
	_active["temp_path"] = temp_path
	_bytes_total = 0
	_bytes_done = 0
	_last_progress = -1.0
	if not _staging_worker.request(job_id, source_path, temp_path):
		_fail_active(NotLightL10n.text("library.import.error.validator_busy"))
		return
	import_started.emit(job_id, source_path)
	_emit_progress_value(0.0)


func _poll_staging_progress() -> void:
	for update: Dictionary in _staging_worker.poll_progress():
		if _active.is_empty() or str(_active.get("phase", "")) != "staging":
			continue
		if str(update.get("job_key", "")) != str(_active.get("id", "")):
			continue
		_bytes_done = maxi(0, int(update.get("bytes_done", 0)))
		_bytes_total = maxi(0, int(update.get("byte_size", 0)))
		var ratio: float = 0.0 if _bytes_total <= 0 else clampf(float(_bytes_done) / float(_bytes_total), 0.0, 1.0)
		_emit_progress_value(ratio * COPY_PROGRESS_WEIGHT)


func _poll_staging_results() -> void:
	for worker_result: Dictionary in _staging_worker.poll_results(2):
		if _active.is_empty():
			continue
		var job_id: String = str(worker_result.get("job_key", ""))
		if job_id != str(_active.get("id", "")) or str(_active.get("phase", "")) != "staging":
			continue
		_bytes_total = maxi(0, int(worker_result.get("byte_size", 0)))
		_bytes_done = maxi(0, int(worker_result.get("bytes_done", _bytes_total)))
		if bool(worker_result.get("cancelled", false)) or bool(_active.get("cancel_requested", false)):
			_fail_active(NotLightL10n.text("library.import.error.cancelled"))
			continue
		var error_code: String = str(worker_result.get("error_code", ""))
		if not error_code.is_empty():
			_fail_active(_staging_error_message(error_code))
			continue
		var hash_sha256: String = str(worker_result.get("hash_sha256", "")).strip_edges().to_lower()
		if not _is_sha256(hash_sha256):
			_fail_active(NotLightL10n.text("library.import.reject.hash_failed"))
			continue
		_active["hash_sha256"] = hash_sha256
		var expected_hash: String = str(_active.get("expected_source_hash", ""))
		var expected_size: int = int(_active.get("expected_source_size", -1))
		if not expected_hash.is_empty() and expected_hash != hash_sha256:
			_fail_active(AssetImportCapabilities.rejection_message(ImportCandidateResult.REJECTION_SOURCE_CHANGED))
			continue
		if expected_size >= 0 and expected_size != _bytes_total:
			_fail_active(AssetImportCapabilities.rejection_message(ImportCandidateResult.REJECTION_SOURCE_CHANGED))
			continue
		_request_final_validation()


func _request_final_validation() -> void:
	if _active.is_empty():
		return
	var job_id: String = str(_active.get("id", ""))
	var source_path: String = str(_active.get("source_path", ""))
	var temp_path: String = str(_active.get("temp_path", ""))
	var candidate: Dictionary = {
		"source_path": temp_path,
		"filename": str(_active.get("original_filename_override", source_path.get_file())),
		"extension": str(_active.get("extension", "")),
		"expected_kind": int(_active.get("expected_kind", AssetKinds.OTHER)),
	}
	if not _validation_worker.request_batch(job_id, [candidate], true):
		_fail_active(NotLightL10n.text("library.import.error.validator_busy"))
		return
	_active["phase"] = "validating"
	_emit_progress_value(VALIDATION_PROGRESS)


func _poll_validation_results() -> void:
	for worker_result: Dictionary in _validation_worker.poll_results(4):
		if _active.is_empty():
			continue
		var job_id: String = str(worker_result.get("job_key", ""))
		if job_id != str(_active.get("id", "")) or str(_active.get("phase", "")) != "validating":
			continue
		if bool(worker_result.get("cancelled", false)) or bool(_active.get("cancel_requested", false)):
			_fail_active(NotLightL10n.text("library.import.error.cancelled"))
			continue
		var values: Variant = worker_result.get("results", [])
		if values is not Array or (values as Array).is_empty() or (values as Array)[0] is not Dictionary:
			_fail_active(NotLightL10n.text("library.import.error.validation_result"))
			continue
		var validation: Dictionary = (values as Array)[0] as Dictionary
		if not bool(validation.get("valid", false)):
			var code: String = str(validation.get("rejection_code", ImportCandidateResult.REJECTION_INVALID_CONTENT))
			var detail: String = str(validation.get("technical_detail", ""))
			_fail_active(AssetImportCapabilities.rejection_message(code, str(_active.get("extension", "")), detail))
			continue
		var expected_kind: int = int(_active.get("expected_kind", AssetKinds.OTHER))
		if int(validation.get("detected_kind", AssetKinds.OTHER)) != expected_kind:
			_fail_active(AssetImportCapabilities.rejection_message(ImportCandidateResult.REJECTION_KIND_MISMATCH))
			continue
		# Re-hash the exact private staging file in the validation worker. The copy
		# worker already fingerprinted bytes while writing; this second off-main-thread
		# fingerprint proves the persisted staging bytes still match before promotion.
		var staged_hash: String = str(validation.get("hash_sha256", "")).strip_edges().to_lower()
		var staged_size: int = int(validation.get("byte_size", -1))
		if staged_hash != str(_active.get("hash_sha256", "")) or staged_size != _bytes_total:
			_fail_active(NotLightL10n.text("library.import.error.staging_changed"))
			continue
		_commit_validated_active()


func _commit_validated_active() -> void:
	if _active.is_empty():
		return
	var source_path: String = str(_active.get("source_path", ""))
	var job_id: String = str(_active.get("id", ""))
	var folder_id: String = str(_active.get("folder_id", ""))
	var temp_path: String = str(_active.get("temp_path", ""))
	var hash_sha256: String = str(_active.get("hash_sha256", ""))
	var original_filename: String = str(_active.get("original_filename_override", source_path.get_file())).strip_edges()
	var extension: String = str(_active.get("extension", original_filename.get_extension())).to_lower()
	var kind: int = int(_active.get("expected_kind", AssetKinds.OTHER))
	var duplicate_record: Dictionary = {}
	if kind != AssetKinds.NOTE:
		duplicate_record = catalog.find_asset_by_hash(hash_sha256)
	if not duplicate_record.is_empty():
		var duplicate_id: String = str(duplicate_record.get("id", ""))
		var existing_blob: String = str(duplicate_record.get("blob_relpath", ""))
		if blob_store.blob_exists(existing_blob):
			blob_store.remove_temp(temp_path)
			import_progress.emit(job_id, source_path, 1.0)
			import_completed.emit(job_id, duplicate_id, true)
			_clear_active()
			return
		var repair_commit: Dictionary = blob_store.commit_preverified_temp(temp_path, hash_sha256, extension, _bytes_total)
		if repair_commit.is_empty():
			_fail_active(blob_store.get_last_error())
			return
		var repaired_path: String = str(repair_commit.get("relative_path", ""))
		if not catalog.repair_blob_location(duplicate_id, repaired_path, _bytes_total, extension):
			if not bool(repair_commit.get("reused", false)):
				blob_store.delete_blob(repaired_path)
			_fail_active(catalog.get_last_error())
			return
		import_progress.emit(job_id, source_path, 1.0)
		import_completed.emit(job_id, duplicate_id, true)
		_clear_active()
		return
	var commit: Dictionary = blob_store.commit_preverified_temp(temp_path, hash_sha256, extension, _bytes_total)
	if commit.is_empty():
		_fail_active(blob_store.get_last_error())
		return
	var now: int = int(Time.get_unix_time_from_system())
	var display_name: String = str(_active.get("display_name_override", "")).strip_edges()
	if display_name.is_empty():
		display_name = original_filename.get_basename()
	if display_name.strip_edges().is_empty():
		display_name = original_filename
	var asset_id: String = AssetId.make_uuid()
	var record: Dictionary = {
		"id": asset_id,
		"hash_sha256": hash_sha256,
		"blob_relpath": str(commit.get("relative_path", "")),
		"display_name": display_name,
		"original_filename": original_filename,
		"extension": extension,
		"kind": kind,
		"byte_size": _bytes_total,
		"folder_id": folder_id,
		"created_at_unix": now,
		"imported_at_unix": now,
		"metadata": {},
	}
	if not catalog.add_asset(record):
		if not bool(commit.get("reused", false)):
			blob_store.delete_blob(str(record.get("blob_relpath", "")))
		_fail_active(catalog.get_last_error())
		return
	import_progress.emit(job_id, source_path, 1.0)
	import_completed.emit(job_id, asset_id, false)
	_clear_active()


func _emit_progress_value(progress: float) -> void:
	if _active.is_empty():
		return
	var safe_progress: float = clampf(progress, 0.0, 1.0)
	if _last_progress >= 0.0 and absf(safe_progress - _last_progress) < 0.005 and safe_progress < 1.0:
		return
	_last_progress = safe_progress
	import_progress.emit(str(_active.get("id", "")), str(_active.get("source_path", "")), safe_progress)


func _staging_error_message(error_code: String) -> String:
	match error_code:
		"open_source":
			return NotLightL10n.text("library.import.error.open_source")
		"empty":
			return NotLightL10n.text("library.import.reject.empty")
		"create_staging":
			return NotLightL10n.text("library.import.error.create_staging")
		"read_source":
			return NotLightL10n.text("library.import.error.read_source")
		"write_staging":
			return NotLightL10n.text("library.import.error.write_staging")
		"hash_failed":
			return NotLightL10n.text("library.import.reject.hash_failed")
		_:
			return NotLightL10n.text("library.import.error.staging")


func _fail_active(message: String) -> void:
	var job_id: String = str(_active.get("id", ""))
	var source_path: String = str(_active.get("source_path", ""))
	var temp_path: String = str(_active.get("temp_path", ""))
	if not job_id.is_empty():
		_staging_worker.cancel(job_id)
		_validation_worker.cancel(job_id)
	if not temp_path.is_empty():
		blob_store.remove_temp(temp_path)
	_last_error = message
	import_failed.emit(job_id, source_path, message)
	_clear_active()


func _clear_active() -> void:
	var cleanup_source: bool = bool(_active.get("cleanup_source", false))
	var source_path: String = str(_active.get("source_path", ""))
	if cleanup_source and not source_path.is_empty() and FileAccess.file_exists(source_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(source_path))
	_active.clear()
	_bytes_total = 0
	_bytes_done = 0
	_last_progress = -1.0
	queue_changed.emit(pending_count())
	if _queue.is_empty():
		set_process(false)


func _cleanup_active_files() -> void:
	if _active.is_empty():
		return
	var temp_path: String = str(_active.get("temp_path", ""))
	if blob_store != null and not temp_path.is_empty():
		blob_store.remove_temp(temp_path)
	var cleanup_source: bool = bool(_active.get("cleanup_source", false))
	var source_path: String = str(_active.get("source_path", ""))
	if cleanup_source and not source_path.is_empty() and FileAccess.file_exists(source_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(source_path))


func _cleanup_queued_managed_sources() -> void:
	for job: Dictionary in _queue:
		if not bool(job.get("cleanup_source", false)):
			continue
		var source_path: String = str(job.get("source_path", ""))
		if not source_path.is_empty() and FileAccess.file_exists(source_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(source_path))


func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in range(value.length()):
		if HEX_DIGITS.find(value.substr(index, 1).to_lower()) < 0:
			return false
	return true
