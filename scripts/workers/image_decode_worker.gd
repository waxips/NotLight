# SPDX-License-Identifier: GPL-3.0-or-later
class_name ImageDecodeWorker
extends RefCounted

var _thread: Thread = Thread.new()
var _mutex: Mutex = Mutex.new()
var _semaphore: Semaphore = Semaphore.new()
var _running: bool = false
var _queue: Array[Dictionary] = []
var _queued_keys: Dictionary = {}
var _results: Array[Dictionary] = []


func start() -> void:
	if _running:
		return
	_running = true
	_thread.start(_thread_loop)


func stop() -> void:
	_mutex.lock()
	_running = false
	_queue.clear()
	_queued_keys.clear()
	_mutex.unlock()
	_semaphore.post()
	if _thread.is_started():
		_thread.wait_to_finish()


func request(cache_key: String, asset_id: String, source_path: String, maximum_dimension: int) -> bool:
	if cache_key.is_empty() or asset_id.is_empty() or source_path.is_empty():
		return false
	_mutex.lock()
	if _queued_keys.has(cache_key):
		_mutex.unlock()
		return false
	_queued_keys[cache_key] = true
	_queue.append({
		"cache_key": cache_key,
		"asset_id": asset_id,
		"source_path": source_path,
		"maximum_dimension": maxi(64, maximum_dimension),
	})
	_mutex.unlock()
	_semaphore.post()
	return true


func poll_results(maximum_count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var safe_count: int = maxi(1, maximum_count)
	_mutex.lock()
	var take_count: int = mini(safe_count, _results.size())
	for _index: int in range(take_count):
		result.append(_results.pop_front())
	_mutex.unlock()
	return result


func is_pending(cache_key: String) -> bool:
	_mutex.lock()
	var pending: bool = _queued_keys.has(cache_key)
	_mutex.unlock()
	return pending


func pending_count() -> int:
	_mutex.lock()
	var count: int = _queued_keys.size()
	_mutex.unlock()
	return count


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
		var result: Dictionary = _decode(job)
		var cache_key: String = str(job.get("cache_key", ""))
		_mutex.lock()
		_queued_keys.erase(cache_key)
		_results.append(result)
		_mutex.unlock()


func _decode(job: Dictionary) -> Dictionary:
	var source_path: String = str(job.get("source_path", ""))
	var maximum_dimension: int = maxi(64, int(job.get("maximum_dimension", 1024)))
	var image: Image = Image.load_from_file(source_path)
	if image == null or image.is_empty():
		return {
			"cache_key": str(job.get("cache_key", "")),
			"asset_id": str(job.get("asset_id", "")),
			"error": NotLightL10n.text("runtime.workers.image_decode_worker.215856a3b5"),
		}
	var intrinsic_size: Vector2i = Vector2i(image.get_width(), image.get_height())
	if intrinsic_size.x <= 0 or intrinsic_size.y <= 0:
		return {
			"cache_key": str(job.get("cache_key", "")),
			"asset_id": str(job.get("asset_id", "")),
			"error": NotLightL10n.text("runtime.workers.image_decode_worker.addbfb7115"),
		}
	var largest_dimension: int = maxi(intrinsic_size.x, intrinsic_size.y)
	if largest_dimension > maximum_dimension:
		var scale: float = float(maximum_dimension) / float(largest_dimension)
		var target_size: Vector2i = Vector2i(
			maxi(1, int(round(float(intrinsic_size.x) * scale))),
			maxi(1, int(round(float(intrinsic_size.y) * scale)))
		)
		image.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
	if not image.has_mipmaps() and maxi(image.get_width(), image.get_height()) >= 256:
		image.generate_mipmaps()
	return {
		"cache_key": str(job.get("cache_key", "")),
		"asset_id": str(job.get("asset_id", "")),
		"image": image,
		"intrinsic_size": intrinsic_size,
		"decoded_size": Vector2i(image.get_width(), image.get_height()),
		"error": "",
	}
