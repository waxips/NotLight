# SPDX-License-Identifier: GPL-3.0-or-later
class_name AssetImportValidationWorker
extends RefCounted

# One persistent worker thread is deliberately shared by a whole validation
# batch. This keeps external probes off the scene tree without creating one OS
# thread per selected file. Batches and file counts are hard-bounded.
const MAX_PENDING_BATCHES: int = 2
const MAX_FILES_PER_BATCH: int = 256
const HASH_CHUNK_BYTES: int = 4 * 1024 * 1024

var _thread: Thread = Thread.new()
var _mutex: Mutex = Mutex.new()
var _semaphore: Semaphore = Semaphore.new()
var _running: bool = false
var _queue: Array[Dictionary] = []
var _queued_keys: Dictionary = {}
var _cancelled_keys: Dictionary = {}
var _results: Array[Dictionary] = []
var _progress: Array[Dictionary] = []


func start() -> bool:
	if _running:
		return true
	_running = true
	var start_error: Error = _thread.start(_thread_loop)
	if start_error != OK:
		_running = false
		return false
	return true


func stop() -> void:
	_mutex.lock()
	_running = false
	_queue.clear()
	_cancelled_keys.clear()
	_mutex.unlock()
	_semaphore.post()
	if _thread.is_started():
		_thread.wait_to_finish()
	_mutex.lock()
	_queued_keys.clear()
	_results.clear()
	_progress.clear()
	_mutex.unlock()


func request_batch(job_key: String, candidates: Array[Dictionary], compute_hash: bool) -> bool:
	var clean_key: String = job_key.strip_edges()
	if clean_key.is_empty() or candidates.is_empty() or candidates.size() > MAX_FILES_PER_BATCH:
		return false
	var safe_candidates: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		var source_path: String = str(candidate.get("source_path", "")).strip_edges()
		if source_path.is_empty():
			continue
		safe_candidates.append({
			"source_path": source_path,
			"filename": str(candidate.get("filename", source_path.get_file())),
			"extension": str(candidate.get("extension", source_path.get_extension())).strip_edges().trim_prefix(".").to_lower(),
			"expected_kind": int(candidate.get("expected_kind", AssetKinds.ANY)),
		})
	if safe_candidates.is_empty():
		return false
	_mutex.lock()
	if not _running or _queued_keys.has(clean_key) or _queued_keys.size() + _results.size() >= MAX_PENDING_BATCHES:
		_mutex.unlock()
		return false
	_queued_keys[clean_key] = true
	_cancelled_keys.erase(clean_key)
	_queue.append({
		"job_key": clean_key,
		"candidates": safe_candidates,
		"compute_hash": compute_hash,
	})
	_mutex.unlock()
	_semaphore.post()
	return true


func cancel(job_key: String) -> bool:
	var clean_key: String = job_key.strip_edges()
	if clean_key.is_empty():
		return false
	_mutex.lock()
	var pending: bool = _queued_keys.has(clean_key)
	if pending:
		_cancelled_keys[clean_key] = true
	_mutex.unlock()
	return pending


func poll_results(maximum_count: int = 1) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	_mutex.lock()
	var take_count: int = mini(maxi(1, maximum_count), _results.size())
	for _index: int in range(take_count):
		output.append(_results.pop_front())
	_mutex.unlock()
	return output


func poll_progress(maximum_count: int = 16) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	_mutex.lock()
	var take_count: int = mini(maxi(1, maximum_count), _progress.size())
	for _index: int in range(take_count):
		output.append(_progress.pop_front())
	_mutex.unlock()
	return output


func is_pending(job_key: String) -> bool:
	_mutex.lock()
	var pending: bool = _queued_keys.has(job_key.strip_edges())
	_mutex.unlock()
	return pending


func pending_batch_count() -> int:
	_mutex.lock()
	var count: int = _queued_keys.size()
	_mutex.unlock()
	return count


func _thread_loop() -> void:
	while true:
		_semaphore.wait()
		var job: Dictionary = {}
		_mutex.lock()
		if not _running:
			_mutex.unlock()
			break
		if not _queue.is_empty():
			job = _queue.pop_front()
		_mutex.unlock()
		if job.is_empty():
			continue
		var result: Dictionary = _process_batch(job)
		var job_key: String = str(job.get("job_key", ""))
		_mutex.lock()
		_queued_keys.erase(job_key)
		_cancelled_keys.erase(job_key)
		if _running:
			_results.append(result)
		_mutex.unlock()


func _process_batch(job: Dictionary) -> Dictionary:
	var job_key: String = str(job.get("job_key", ""))
	var candidates_value: Variant = job.get("candidates", [])
	var candidates: Array[Dictionary] = []
	if candidates_value is Array:
		for value: Variant in candidates_value as Array:
			if value is Dictionary:
				candidates.append((value as Dictionary).duplicate(true))
	var compute_hash: bool = bool(job.get("compute_hash", false))
	var results: Array[Dictionary] = []
	var total: int = candidates.size()
	for index: int in range(total):
		if _should_cancel(job_key):
			return {"job_key": job_key, "results": results, "cancelled": true, "error": ""}
		var candidate: Dictionary = candidates[index]
		var source_path: String = str(candidate.get("source_path", ""))
		var extension: String = str(candidate.get("extension", ""))
		var expected_kind: int = int(candidate.get("expected_kind", AssetKinds.ANY))
		var cancel_check: Callable = Callable(self, "_should_cancel").bind(job_key)
		# Emit the active candidate before hashing/probing so a single large file does
		# not leave preflight looking frozen at an anonymous 0/N. This still reports
		# the number of completed candidates (index), not a fabricated byte percent.
		_push_progress(job_key, index, total, source_path)
		var inferred_kind: int = AssetImportCapabilities.kind_for_extension(extension)
		var safe_kind: int = inferred_kind if expected_kind == AssetKinds.ANY else expected_kind
		var classification_matches: bool = (
			inferred_kind != AssetKinds.OTHER
			and AssetImportCapabilities.is_importable_kind(safe_kind)
			and inferred_kind == safe_kind
		)
		var hash_result: Dictionary = {}
		if compute_hash and classification_matches:
			# Fingerprint first. Validation that follows therefore describes a file
			# version at or after the captured hash; any later mutation is detected
			# when the importer re-hashes its private staging copy.
			hash_result = _hash_file(job_key, source_path)
			if bool(hash_result.get("cancelled", false)):
				return {"job_key": job_key, "results": results, "cancelled": true, "error": ""}
			if str(hash_result.get("hash_sha256", "")).is_empty():
				var hash_rejection: Dictionary = AssetImportContentValidator.rejection(
					source_path,
					str(candidate.get("filename", source_path.get_file())),
					extension,
					safe_kind,
					str(hash_result.get("rejection_code", ImportCandidateResult.REJECTION_HASH_FAILED)),
					str(hash_result.get("error", ""))
				)
				hash_rejection["byte_size"] = int(hash_result.get("byte_size", 0))
				results.append(hash_rejection)
				_push_progress(job_key, index + 1, total, source_path)
				continue
		var validation: Dictionary = AssetImportCapabilities.validate_candidate(
			source_path,
			expected_kind,
			extension,
			cancel_check
		)
		validation["filename"] = str(candidate.get("filename", source_path.get_file()))
		if compute_hash and bool(validation.get("valid", false)) and classification_matches:
			validation["hash_sha256"] = str(hash_result.get("hash_sha256", ""))
			validation["byte_size"] = int(hash_result.get("byte_size", validation.get("byte_size", 0)))
		results.append(validation)
		_push_progress(job_key, index + 1, total, source_path)
	return {"job_key": job_key, "results": results, "cancelled": false, "error": ""}


func _hash_file(job_key: String, source_path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		return {"hash_sha256": "", "byte_size": 0, "error": NotLightL10n.text("runtime.worker.asset_hash.open_failed"), "rejection_code": ImportCandidateResult.REJECTION_MISSING, "cancelled": false}
	var byte_size: int = int(file.get_length())
	if byte_size <= 0:
		file.close()
		return {"hash_sha256": "", "byte_size": byte_size, "error": NotLightL10n.text("runtime.worker.asset_hash.empty"), "rejection_code": ImportCandidateResult.REJECTION_EMPTY, "cancelled": false}
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		file.close()
		return {"hash_sha256": "", "byte_size": byte_size, "error": NotLightL10n.text("runtime.worker.asset_hash.init_failed"), "rejection_code": ImportCandidateResult.REJECTION_HASH_FAILED, "cancelled": false}
	while file.get_position() < byte_size:
		if _should_cancel(job_key):
			file.close()
			return {"hash_sha256": "", "byte_size": byte_size, "error": "", "cancelled": true}
		var remaining: int = int(byte_size - file.get_position())
		var chunk: PackedByteArray = file.get_buffer(mini(HASH_CHUNK_BYTES, remaining))
		if chunk.is_empty() or context.update(chunk) != OK:
			file.close()
			return {"hash_sha256": "", "byte_size": byte_size, "error": NotLightL10n.text("runtime.worker.asset_hash.update_failed"), "rejection_code": ImportCandidateResult.REJECTION_HASH_FAILED, "cancelled": false}
	file.close()
	var digest: PackedByteArray = context.finish()
	if digest.size() != 32:
		return {"hash_sha256": "", "byte_size": byte_size, "error": NotLightL10n.text("runtime.worker.asset_hash.digest_invalid"), "rejection_code": ImportCandidateResult.REJECTION_HASH_FAILED, "cancelled": false}
	return {"hash_sha256": digest.hex_encode().to_lower(), "byte_size": byte_size, "error": "", "cancelled": false}


func _push_progress(job_key: String, completed: int, total: int, source_path: String) -> void:
	_mutex.lock()
	if _running:
		_progress.append({
			"job_key": job_key,
			"completed": completed,
			"total": total,
			"source_path": source_path,
		})
	_mutex.unlock()


func _should_cancel(job_key: String) -> bool:
	_mutex.lock()
	var cancelled: bool = not _running or _cancelled_keys.has(job_key)
	_mutex.unlock()
	return cancelled
