# SPDX-License-Identifier: GPL-3.0-or-later
class_name FormulaImageLoadWorker
extends RefCounted

const MAX_PENDING_JOBS: int = 4
const MAX_IMAGE_PIXELS: int = 16 * 1024 * 1024
const MAX_SVG_BYTES: int = 4 * 1024 * 1024
const FALLBACK_SVG_EXTENT: float = 512.0
const MIN_SVG_SCALE: float = 0.05
const MAX_SVG_SCALE: float = 32.0
const ALPHA_TRIM_PADDING_MIN: int = 48
const ALPHA_TRIM_PADDING_MAX: int = 128
const ALPHA_TRIM_PADDING_RATIO: float = 0.08

var _thread: Thread = Thread.new()
var _mutex: Mutex = Mutex.new()
var _semaphore: Semaphore = Semaphore.new()
var _running: bool = false
var _queue: Array[Dictionary] = []
var _pending_keys: Dictionary = {}
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
	_mutex.unlock()
	_semaphore.post()
	if _thread.is_started():
		_thread.wait_to_finish()
	_mutex.lock()
	_pending_keys.clear()
	_results.clear()
	_mutex.unlock()


func request_svg(cache_key: String, svg_path: String, target_extent: int) -> bool:
	var clean_key: String = cache_key.strip_edges()
	var clean_path: String = svg_path.strip_edges()
	if clean_key.is_empty() or clean_path.is_empty():
		return false
	_mutex.lock()
	if not _running or _pending_keys.has(clean_key) or _pending_keys.size() + _results.size() >= MAX_PENDING_JOBS:
		_mutex.unlock()
		return false
	_pending_keys[clean_key] = true
	_queue.append({
		"cache_key": clean_key,
		"svg_path": _native_path(clean_path),
		"target_extent": clampi(target_extent, 160, 2048),
	})
	_mutex.unlock()
	_semaphore.post()
	return true


func poll_results(maximum_count: int = 1) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	_mutex.lock()
	var count: int = mini(maxi(1, maximum_count), _results.size())
	for _index: int in range(count):
		output.append(_results.pop_front())
	_mutex.unlock()
	return output


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
		var result: Dictionary = _load_svg(job)
		var key: String = str(job.get("cache_key", ""))
		_mutex.lock()
		_pending_keys.erase(key)
		if _running:
			_results.append(result)
		_mutex.unlock()


func _load_svg(job: Dictionary) -> Dictionary:
	var key: String = str(job.get("cache_key", ""))
	var path: String = str(job.get("svg_path", ""))
	var target_extent: int = int(job.get("target_extent", 512))
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"cache_key": key, "image": null, "error": NotLightL10n.text("runtime.worker.formula_svg.open_failed")}
	var size_bytes: int = int(file.get_length())
	if size_bytes <= 0 or size_bytes > MAX_SVG_BYTES:
		file.close()
		return {"cache_key": key, "image": null, "error": NotLightL10n.text("runtime.worker.formula_svg.invalid_size")}
	var bytes: PackedByteArray = file.get_buffer(size_bytes)
	file.close()
	if bytes.size() != size_bytes:
		return {"cache_key": key, "image": null, "error": NotLightL10n.text("runtime.worker.formula_svg.read_failed")}

	var svg_text: String = bytes.get_string_from_utf8()
	var logical_size: Vector2 = _svg_logical_size(svg_text)
	var logical_extent: float = maxf(logical_size.x, logical_size.y)
	if logical_extent <= 0.0:
		logical_extent = FALLBACK_SVG_EXTENT
	var scale: float = clampf(float(target_extent) / logical_extent, MIN_SVG_SCALE, MAX_SVG_SCALE)
	if logical_size.x > 0.0 and logical_size.y > 0.0:
		var predicted_pixels: float = logical_size.x * scale * logical_size.y * scale
		if predicted_pixels > float(MAX_IMAGE_PIXELS):
			scale *= sqrt(float(MAX_IMAGE_PIXELS) / predicted_pixels)
			scale = maxf(scale, MIN_SVG_SCALE)

	var image: Image = Image.new()
	var load_error: Error = image.load_svg_from_buffer(bytes, scale)
	if load_error != OK or image.is_empty():
		return {"cache_key": key, "image": null, "error": NotLightL10n.text("runtime.worker.formula_svg.raster_failed")}
	var width: int = image.get_width()
	var height: int = image.get_height()
	if width <= 0 or height <= 0 or int(width) * int(height) > MAX_IMAGE_PIXELS:
		return {"cache_key": key, "image": null, "error": NotLightL10n.text("runtime.worker.formula_svg.invalid_dimensions")}

	# Typst/MiTeX SVGs intentionally contain a page margin. Raster resolution is
	# also independent from logical UI size, so carrying that transparent page
	# area into every texture produces uneven visual offsets and can make tall
	# derivations appear clipped when a consumer fits the full raster rectangle.
	# Trim only transparent pixels, then keep a small bounded safety pad for
	# antialiasing/accents. Canonical LaTeX and the cached SVG stay untouched.
	var used: Rect2i = image.get_used_rect()
	if used.size.x > 0 and used.size.y > 0:
		var padding: int = clampi(int(round(float(target_extent) * ALPHA_TRIM_PADDING_RATIO)), ALPHA_TRIM_PADDING_MIN, ALPHA_TRIM_PADDING_MAX)
		var left: int = maxi(0, used.position.x - padding)
		var top: int = maxi(0, used.position.y - padding)
		var right: int = mini(width, used.position.x + used.size.x + padding)
		var bottom: int = mini(height, used.position.y + used.size.y + padding)
		var region: Rect2i = Rect2i(left, top, maxi(1, right - left), maxi(1, bottom - top))
		if region.size.x < width or region.size.y < height:
			var cropped: Image = image.get_region(region)
			if not cropped.is_empty():
				image = cropped
				width = image.get_width()
				height = image.get_height()
	return {"cache_key": key, "image": image, "error": ""}


func _svg_logical_size(svg_text: String) -> Vector2:
	var viewbox_index: int = svg_text.find("viewBox=")
	if viewbox_index < 0:
		return Vector2.ZERO
	var quote_index: int = viewbox_index + 8
	if quote_index >= svg_text.length():
		return Vector2.ZERO
	var quote_code: int = svg_text.unicode_at(quote_index)
	if quote_code != 34 and quote_code != 39:
		return Vector2.ZERO
	var quote: String = svg_text.substr(quote_index, 1)
	var end_index: int = svg_text.find(quote, quote_index + 1)
	if end_index <= quote_index + 1:
		return Vector2.ZERO
	var values: PackedStringArray = svg_text.substr(quote_index + 1, end_index - quote_index - 1).replace(",", " ").split(" ", false)
	if values.size() < 4:
		return Vector2.ZERO
	var width: float = values[2].to_float()
	var height: float = values[3].to_float()
	if not is_finite(width) or not is_finite(height) or width <= 0.0 or height <= 0.0:
		return Vector2.ZERO
	return Vector2(width, height)


func _native_path(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path
