# SPDX-License-Identifier: GPL-3.0-or-later
class_name NoteSaveWorker
extends RefCounted

# Serializes user-authored Markdown to a private BlobStore staging path and
# computes SHA-256 off the main thread. Requests are bounded and carry immutable
# byte buffers so editor churn can never create an unbounded file/job queue.
const MAX_PENDING_JOBS: int = 4
const HASH_CHUNK_BYTES: int = 1024 * 1024

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


func request(job_key: String, temp_path: String, bytes: PackedByteArray) -> bool:
	var clean_key: String = job_key.strip_edges()
	var clean_path: String = temp_path.strip_edges()
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
		"temp_path": _native_path(clean_path),
		"bytes": bytes,
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


func poll_results(maximum_count: int = 2) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	_mutex.lock()
	var take_count: int = mini(maxi(1, maximum_count), _results.size())
	for _index: int in range(take_count):
		output.append(_results.pop_front())
	_mutex.unlock()
	return output


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
		var result: Dictionary = _write_and_hash(job)
		var job_key: String = str(job.get("job_key", ""))
		_mutex.lock()
		_queued_keys.erase(job_key)
		_cancelled_keys.erase(job_key)
		if _running:
			_results.append(result)
		_mutex.unlock()


func _write_and_hash(job: Dictionary) -> Dictionary:
	var job_key: String = str(job.get("job_key", ""))
	var temp_path: String = str(job.get("temp_path", ""))
	var bytes: PackedByteArray = job.get("bytes", PackedByteArray()) as PackedByteArray
	if _should_cancel(job_key):
		return _result(job_key, temp_path, "", 0, "", true)
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _result(job_key, temp_path, "", 0, NotLightL10n.text("runtime.worker.note_save.create_failed"), false)
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		file.close()
		return _result(job_key, temp_path, "", 0, NotLightL10n.text("runtime.worker.note_save.hash_init_failed"), false)
	var offset: int = 0
	while offset < bytes.size():
		if _should_cancel(job_key):
			file.close()
			_remove_file(temp_path)
			return _result(job_key, temp_path, "", bytes.size(), "", true)
		var end: int = mini(bytes.size(), offset + HASH_CHUNK_BYTES)
		var chunk: PackedByteArray = bytes.slice(offset, end)
		if context.update(chunk) != OK:
			file.close()
			_remove_file(temp_path)
			return _result(job_key, temp_path, "", bytes.size(), NotLightL10n.text("runtime.worker.note_save.hash_update_failed"), false)
		file.store_buffer(chunk)
		if file.get_error() != OK:
			file.close()
			_remove_file(temp_path)
			return _result(job_key, temp_path, "", bytes.size(), NotLightL10n.text("runtime.worker.note_save.write_failed"), false)
		offset = end
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		_remove_file(temp_path)
		return _result(job_key, temp_path, "", bytes.size(), NotLightL10n.text("runtime.worker.note_save.flush_failed"), false)
	var digest: PackedByteArray = context.finish()
	if digest.size() != 32:
		_remove_file(temp_path)
		return _result(job_key, temp_path, "", bytes.size(), NotLightL10n.text("runtime.worker.note_save.digest_invalid"), false)
	return _result(job_key, temp_path, digest.hex_encode().to_lower(), bytes.size(), "", false)


func _should_cancel(job_key: String) -> bool:
	_mutex.lock()
	var cancelled: bool = not _running or _cancelled_keys.has(job_key)
	_mutex.unlock()
	return cancelled


func _result(job_key: String, temp_path: String, hash_sha256: String, byte_size: int, error: String, cancelled: bool) -> Dictionary:
	return {
		"job_key": job_key,
		"temp_path": temp_path,
		"hash_sha256": hash_sha256,
		"byte_size": byte_size,
		"error": error,
		"cancelled": cancelled,
	}


func _native_path(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
