# SPDX-License-Identifier: GPL-3.0-or-later
class_name FileHashWorker
extends RefCounted

# Generic serial SHA-256 worker for durable local files. The worker deliberately
# owns a small bounded queue and hashes in fixed-size chunks so large files never
# block the main thread and never require loading the whole payload into memory.
const MAX_PENDING_JOBS: int = 4
const HASH_CHUNK_BYTES: int = 4 * 1024 * 1024

var _thread: Thread = Thread.new()
var _mutex: Mutex = Mutex.new()
var _semaphore: Semaphore = Semaphore.new()
var _running: bool = false
var _queue: Array[Dictionary] = []
var _queued_keys: Dictionary = {}
var _cancelled_keys: Dictionary = {}
var _results: Array[Dictionary] = []


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
	_mutex.unlock()


func request(job_key: String, source_path: String) -> bool:
	var clean_key: String = job_key.strip_edges()
	var clean_path: String = source_path.strip_edges()
	if clean_key.is_empty() or clean_path.is_empty():
		return false
	_mutex.lock()
	if not _running or _queued_keys.has(clean_key) or _queued_keys.size() + _results.size() >= MAX_PENDING_JOBS:
		_mutex.unlock()
		return false
	_queued_keys[clean_key] = true
	_cancelled_keys.erase(clean_key)
	_queue.append({
		"job_key": clean_key,
		"source_path": _native_path(clean_path),
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


func is_pending(job_key: String) -> bool:
	_mutex.lock()
	var pending: bool = _queued_keys.has(job_key.strip_edges())
	_mutex.unlock()
	return pending


func pending_work_count() -> int:
	_mutex.lock()
	var count: int = _queued_keys.size() + _results.size()
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
		var result: Dictionary = _hash_file(job)
		var job_key: String = str(job.get("job_key", ""))
		_mutex.lock()
		_queued_keys.erase(job_key)
		_cancelled_keys.erase(job_key)
		if _running:
			_results.append(result)
		_mutex.unlock()


func _hash_file(job: Dictionary) -> Dictionary:
	var job_key: String = str(job.get("job_key", ""))
	var source_path: String = str(job.get("source_path", ""))
	if _should_cancel(job_key):
		return _result(job_key, "", 0, "", true)
	var file: FileAccess = FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		return _result(job_key, "", 0, NotLightL10n.text("runtime.worker.asset_hash.open_failed"), false)
	var byte_size: int = int(file.get_length())
	if byte_size <= 0:
		file.close()
		return _result(job_key, "", byte_size, NotLightL10n.text("runtime.worker.asset_hash.empty"), false)
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		file.close()
		return _result(job_key, "", byte_size, NotLightL10n.text("runtime.worker.asset_hash.init_failed"), false)
	while file.get_position() < byte_size:
		if _should_cancel(job_key):
			file.close()
			return _result(job_key, "", byte_size, "", true)
		var remaining: int = int(byte_size - file.get_position())
		var chunk: PackedByteArray = file.get_buffer(mini(HASH_CHUNK_BYTES, remaining))
		if chunk.is_empty() or context.update(chunk) != OK:
			file.close()
			return _result(job_key, "", byte_size, NotLightL10n.text("runtime.worker.asset_hash.update_failed"), false)
	file.close()
	if _should_cancel(job_key):
		return _result(job_key, "", byte_size, "", true)
	var digest: PackedByteArray = context.finish()
	if digest.size() != 32:
		return _result(job_key, "", byte_size, NotLightL10n.text("runtime.worker.asset_hash.digest_invalid"), false)
	return _result(job_key, digest.hex_encode().to_lower(), byte_size, "", false)


func _should_cancel(job_key: String) -> bool:
	_mutex.lock()
	var cancelled: bool = not _running or _cancelled_keys.has(job_key)
	_mutex.unlock()
	return cancelled


func _result(job_key: String, hash_sha256: String, byte_size: int, error: String, cancelled: bool) -> Dictionary:
	return {
		"job_key": job_key,
		"hash_sha256": hash_sha256,
		"byte_size": byte_size,
		"error": error,
		"cancelled": cancelled,
	}


func _native_path(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path
