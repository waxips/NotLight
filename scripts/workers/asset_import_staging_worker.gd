# SPDX-License-Identifier: GPL-3.0-or-later
class_name AssetImportStagingWorker
extends RefCounted

# Import jobs are serialized by AssetImportPipeline. Keeping this worker to one
# outstanding job prevents a batch selection from turning into unbounded disk
# pressure while still moving copy + SHA-256 work completely off the main thread.
const MAX_PENDING_JOBS: int = 1
const COPY_CHUNK_BYTES: int = 4 * 1024 * 1024

var _thread: Thread = Thread.new()
var _mutex: Mutex = Mutex.new()
var _semaphore: Semaphore = Semaphore.new()
var _running: bool = false
var _queue: Array[Dictionary] = []
var _pending_keys: Dictionary = {}
var _cancelled_keys: Dictionary = {}
var _results: Array[Dictionary] = []
var _progress_by_key: Dictionary = {}


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
	_mutex.unlock()
	_semaphore.post()
	if _thread.is_started():
		_thread.wait_to_finish()
	_mutex.lock()
	_pending_keys.clear()
	_cancelled_keys.clear()
	_results.clear()
	_progress_by_key.clear()
	_mutex.unlock()


func request(job_key: String, source_path: String, staging_path: String) -> bool:
	var clean_key: String = job_key.strip_edges()
	var clean_source: String = source_path.strip_edges()
	var clean_staging: String = staging_path.strip_edges()
	if clean_key.is_empty() or clean_source.is_empty() or clean_staging.is_empty():
		return false
	_mutex.lock()
	if not _running or _pending_keys.has(clean_key) or _pending_keys.size() + _results.size() >= MAX_PENDING_JOBS:
		_mutex.unlock()
		return false
	_pending_keys[clean_key] = true
	_cancelled_keys.erase(clean_key)
	_progress_by_key.erase(clean_key)
	_queue.append({
		"job_key": clean_key,
		"source_path": clean_source,
		"staging_path": clean_staging,
	})
	_mutex.unlock()
	_semaphore.post()
	return true


func cancel(job_key: String) -> bool:
	var clean_key: String = job_key.strip_edges()
	if clean_key.is_empty():
		return false
	_mutex.lock()
	var pending: bool = _pending_keys.has(clean_key)
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


func poll_progress() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	_mutex.lock()
	for value: Variant in _progress_by_key.values():
		if value is Dictionary:
			output.append((value as Dictionary).duplicate(true))
	_progress_by_key.clear()
	_mutex.unlock()
	return output


func is_pending(job_key: String) -> bool:
	_mutex.lock()
	var pending: bool = _pending_keys.has(job_key.strip_edges())
	_mutex.unlock()
	return pending


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
		var result: Dictionary = _stage_file(job)
		var job_key: String = str(job.get("job_key", ""))
		_mutex.lock()
		_pending_keys.erase(job_key)
		_cancelled_keys.erase(job_key)
		_progress_by_key.erase(job_key)
		if _running:
			_results.append(result)
		_mutex.unlock()


func _stage_file(job: Dictionary) -> Dictionary:
	var job_key: String = str(job.get("job_key", ""))
	var source_path: String = str(job.get("source_path", ""))
	var staging_path: String = str(job.get("staging_path", ""))
	if _should_cancel(job_key):
		return _cancelled_result(job_key, source_path, staging_path)
	var source: FileAccess = FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return _error_result(job_key, source_path, staging_path, "open_source")
	var byte_size: int = int(source.get_length())
	if byte_size <= 0:
		source.close()
		return _error_result(job_key, source_path, staging_path, "empty", byte_size)
	var staging: FileAccess = FileAccess.open(staging_path, FileAccess.WRITE)
	if staging == null:
		source.close()
		return _error_result(job_key, source_path, staging_path, "create_staging", byte_size)
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		source.close()
		staging.close()
		return _error_result(job_key, source_path, staging_path, "hash_failed", byte_size)
	var bytes_done: int = 0
	_push_progress(job_key, source_path, bytes_done, byte_size)
	while bytes_done < byte_size:
		if _should_cancel(job_key):
			source.close()
			staging.close()
			return _cancelled_result(job_key, source_path, staging_path, byte_size, bytes_done)
		var remaining: int = byte_size - bytes_done
		var chunk: PackedByteArray = source.get_buffer(mini(COPY_CHUNK_BYTES, remaining))
		if chunk.is_empty():
			source.close()
			staging.close()
			return _error_result(job_key, source_path, staging_path, "read_source", byte_size, bytes_done)
		if context.update(chunk) != OK:
			source.close()
			staging.close()
			return _error_result(job_key, source_path, staging_path, "hash_failed", byte_size, bytes_done)
		if not staging.store_buffer(chunk):
			source.close()
			staging.close()
			return _error_result(job_key, source_path, staging_path, "write_staging", byte_size, bytes_done)
		bytes_done += chunk.size()
		_push_progress(job_key, source_path, bytes_done, byte_size)
	source.close()
	staging.flush()
	var flush_error: Error = staging.get_error()
	staging.close()
	if flush_error != OK:
		return _error_result(job_key, source_path, staging_path, "write_staging", byte_size, bytes_done)
	if bytes_done != byte_size:
		return _error_result(job_key, source_path, staging_path, "read_source", byte_size, bytes_done)
	var digest: PackedByteArray = context.finish()
	if digest.size() != 32:
		return _error_result(job_key, source_path, staging_path, "hash_failed", byte_size, bytes_done)
	return {
		"job_key": job_key,
		"source_path": source_path,
		"staging_path": staging_path,
		"byte_size": byte_size,
		"bytes_done": bytes_done,
		"hash_sha256": digest.hex_encode().to_lower(),
		"cancelled": false,
		"error_code": "",
	}


func _push_progress(job_key: String, source_path: String, bytes_done: int, byte_size: int) -> void:
	_mutex.lock()
	if _running:
		# Coalesce by job instead of appending one record per copied chunk. This is a
		# deliberately bounded latest-value channel even for multi-gigabyte files.
		_progress_by_key[job_key] = {
			"job_key": job_key,
			"source_path": source_path,
			"bytes_done": bytes_done,
			"byte_size": byte_size,
		}
	_mutex.unlock()


func _should_cancel(job_key: String) -> bool:
	_mutex.lock()
	var cancelled: bool = not _running or _cancelled_keys.has(job_key)
	_mutex.unlock()
	return cancelled


func _cancelled_result(
	job_key: String,
	source_path: String,
	staging_path: String,
	byte_size: int = 0,
	bytes_done: int = 0
) -> Dictionary:
	return {
		"job_key": job_key,
		"source_path": source_path,
		"staging_path": staging_path,
		"byte_size": byte_size,
		"bytes_done": bytes_done,
		"hash_sha256": "",
		"cancelled": true,
		"error_code": "",
	}


func _error_result(
	job_key: String,
	source_path: String,
	staging_path: String,
	error_code: String,
	byte_size: int = 0,
	bytes_done: int = 0
) -> Dictionary:
	return {
		"job_key": job_key,
		"source_path": source_path,
		"staging_path": staging_path,
		"byte_size": byte_size,
		"bytes_done": bytes_done,
		"hash_sha256": "",
		"cancelled": false,
		"error_code": error_code,
	}
