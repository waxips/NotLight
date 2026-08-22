# SPDX-License-Identifier: GPL-3.0-or-later
class_name PdfRenderWorker
extends RefCounted

const OP_PROBE: String = "probe"
const OP_RENDER: String = "render"

var _thread: Thread = Thread.new()
var _mutex: Mutex = Mutex.new()
var _semaphore: Semaphore = Semaphore.new()
var _running: bool = false
var _queue: Array[Dictionary] = []
var _queued_keys: Dictionary = {}
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
	_queued_keys.clear()
	_mutex.unlock()
	_semaphore.post()
	if _thread.is_started():
		_thread.wait_to_finish()


func request_probe(cache_key: String, asset_id: String, source_path: String, priority: int = 0) -> bool:
	return _enqueue({
		"operation": OP_PROBE,
		"cache_key": cache_key,
		"asset_id": asset_id,
		"source_path": _native_path(source_path),
		"priority": priority,
	})


func request_render(
	cache_key: String,
	asset_id: String,
	source_path: String,
	page_index: int,
	maximum_dimension: int,
	output_path: String,
	priority: int = 0
) -> bool:
	return _enqueue({
		"operation": OP_RENDER,
		"cache_key": cache_key,
		"asset_id": asset_id,
		"source_path": _native_path(source_path),
		"page_index": maxi(0, page_index),
		"maximum_dimension": clampi(maximum_dimension, 128, 4096),
		"output_path": _native_path(output_path),
		"priority": priority,
	})


func promote_pending(cache_key: String, priority: int) -> void:
	if cache_key.is_empty():
		return
	_mutex.lock()
	var target_index: int = -1
	for index: int in range(_queue.size()):
		var queued_job: Dictionary = _queue[index] as Dictionary
		if str(queued_job.get("cache_key", "")) == cache_key:
			target_index = index
			break
	if target_index >= 0:
		var job: Dictionary = _queue[target_index] as Dictionary
		if priority > int(job.get("priority", 0)):
			_queue.remove_at(target_index)
			job["priority"] = priority
			_insert_by_priority(job)
	_mutex.unlock()


func poll_results(maximum_count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_mutex.lock()
	var take_count: int = mini(maxi(1, maximum_count), _results.size())
	for _index: int in range(take_count):
		result.append(_results.pop_front())
	_mutex.unlock()
	return result


func is_pending(cache_key: String) -> bool:
	_mutex.lock()
	var pending: bool = _queued_keys.has(cache_key)
	_mutex.unlock()
	return pending


func pending_work_count() -> int:
	_mutex.lock()
	var count: int = _queued_keys.size() + _results.size()
	_mutex.unlock()
	return count


func _enqueue(job: Dictionary) -> bool:
	var cache_key: String = str(job.get("cache_key", "")).strip_edges()
	var asset_id: String = str(job.get("asset_id", "")).strip_edges()
	var source_path: String = str(job.get("source_path", "")).strip_edges()
	if cache_key.is_empty() or asset_id.is_empty() or source_path.is_empty():
		return false
	_mutex.lock()
	if not _running or _queued_keys.has(cache_key):
		_mutex.unlock()
		return false
	_queued_keys[cache_key] = true
	_insert_by_priority(job.duplicate(true))
	_mutex.unlock()
	_semaphore.post()
	return true


func _insert_by_priority(job: Dictionary) -> void:
	var priority: int = int(job.get("priority", 0))
	var insert_index: int = _queue.size()
	for index: int in range(_queue.size()):
		var queued_job: Dictionary = _queue[index] as Dictionary
		if int(queued_job.get("priority", 0)) < priority:
			insert_index = index
			break
	_queue.insert(insert_index, job)


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
		var result: Dictionary = _execute_job(job)
		var cache_key: String = str(job.get("cache_key", ""))
		_mutex.lock()
		_queued_keys.erase(cache_key)
		_results.append(result)
		_mutex.unlock()


func _execute_job(job: Dictionary) -> Dictionary:
	var operation: String = str(job.get("operation", ""))
	if operation == OP_PROBE:
		return _probe(job)
	if operation == OP_RENDER:
		return _render(job)
	return _error_result(job, NotLightL10n.text("runtime.workers.pdf_render_worker.e48cec63ba"))


func _probe(job: Dictionary) -> Dictionary:
	var output: Array[String] = []
	var source_path: String = str(job.get("source_path", ""))
	var code: int = OS.execute(
		PopplerTools.pdfinfo_path(),
		PackedStringArray([source_path]),
		output,
		true,
		false
	)
	if code != 0:
		var diagnostic: String = str(output[0]) if not output.is_empty() else ""
		var diagnostic_lower: String = diagnostic.to_lower()
		var error_kind: String = "process_failed"
		if code == -1:
			error_kind = "tool_missing"
		elif diagnostic_lower.find("password") >= 0:
			error_kind = "encrypted"
		return _error_result(job, NotLightL10n.text("runtime.workers.pdf_render_worker.8439a79d62") % code, error_kind)
	return {
		"operation": OP_PROBE,
		"cache_key": str(job.get("cache_key", "")),
		"asset_id": str(job.get("asset_id", "")),
		"output": str(output[0]) if not output.is_empty() else "",
		"error": "",
	}


func _render(job: Dictionary) -> Dictionary:
	var output_path: String = str(job.get("output_path", ""))
	if output_path.is_empty():
		return _error_result(job, NotLightL10n.text("runtime.workers.pdf_render_worker.e025eca9c7"))
	if FileAccess.file_exists(output_path):
		return _render_success(job, output_path)
	var output_prefix: String = output_path.get_basename()
	var page_number: int = maxi(1, int(job.get("page_index", 0)) + 1)
	var maximum_dimension: int = clampi(int(job.get("maximum_dimension", 768)), 128, 4096)
	var output: Array[String] = []
	var arguments: PackedStringArray = PackedStringArray([
		"-png",
		"-f", str(page_number),
		"-l", str(page_number),
		"-singlefile",
		"-scale-to", str(maximum_dimension),
		str(job.get("source_path", "")),
		output_prefix,
	])
	var code: int = OS.execute(PopplerTools.pdftoppm_path(), arguments, output, true, false)
	if code != 0:
		_remove_partial_output(output_path)
		return _error_result(
			job,
			NotLightL10n.text("runtime.workers.pdf_render_worker.e7fd9616a1") % code,
			"tool_missing" if code == -1 else "process_failed"
		)
	if not FileAccess.file_exists(output_path):
		return _error_result(job, NotLightL10n.text("runtime.workers.pdf_render_worker.b8945e39e4"))
	return _render_success(job, output_path)


func _remove_partial_output(output_path: String) -> void:
	if output_path.is_empty() or not FileAccess.file_exists(output_path):
		return
	DirAccess.remove_absolute(output_path)


func _render_success(job: Dictionary, output_path: String) -> Dictionary:
	return {
		"operation": OP_RENDER,
		"cache_key": str(job.get("cache_key", "")),
		"asset_id": str(job.get("asset_id", "")),
		"page_index": maxi(0, int(job.get("page_index", 0))),
		"maximum_dimension": int(job.get("maximum_dimension", 768)),
		"output_path": output_path,
		"error": "",
	}


func _error_result(job: Dictionary, message: String, error_kind: String = "") -> Dictionary:
	return {
		"operation": str(job.get("operation", "")),
		"cache_key": str(job.get("cache_key", "")),
		"asset_id": str(job.get("asset_id", "")),
		"page_index": maxi(0, int(job.get("page_index", 0))),
		"error": message,
		"error_kind": error_kind,
	}


func _native_path(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path
