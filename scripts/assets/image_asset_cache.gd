# SPDX-License-Identifier: GPL-3.0-or-later
class_name ImageAssetCache
extends Node

signal texture_ready(asset_id: String)
signal texture_failed(asset_id: String, message: String)
signal cache_changed

const TIER_THUMBNAIL: int = 256
const TIER_SMALL: int = 768
const TIER_MEDIUM: int = 1536
const TIER_LARGE: int = 3072
const MAX_UPLOADS_PER_FRAME: int = 3
const MAX_PENDING_DECODE_REQUESTS: int = 32
const DEFAULT_MEMORY_LIMIT_BYTES: int = 512 * 1024 * 1024
const TIERS: PackedInt32Array = [TIER_THUMBNAIL, TIER_SMALL, TIER_MEDIUM, TIER_LARGE]

var library: AssetLibraryService
var telemetry: PerformanceTelemetryService
var memory_limit_bytes: int = DEFAULT_MEMORY_LIMIT_BYTES
var max_uploads_per_frame: int = MAX_UPLOADS_PER_FRAME
var _worker: ImageDecodeWorker = ImageDecodeWorker.new()
var _entries: Dictionary = {}
var _intrinsic_sizes: Dictionary = {}
var _failure_messages: Dictionary = {}
var _access_counter: int = 0
var _memory_bytes: int = 0


func _ready() -> void:
	_worker.start()
	set_process(false)


func _exit_tree() -> void:
	_worker.stop()


func _process(_delta: float) -> void:
	var results: Array[Dictionary] = _worker.poll_results(max_uploads_per_frame)
	for result: Dictionary in results:
		if _apply_decode_result(result) and telemetry != null:
			telemetry.record_developer_counter(&"image_uploads")
	if not results.is_empty():
		_evict_if_needed()
	if _worker.pending_work_count() == 0:
		set_process(false)


func configure(asset_library: AssetLibraryService) -> void:
	library = asset_library
	if library != null and not library.library_changed.is_connected(_on_library_changed):
		library.library_changed.connect(_on_library_changed)


func configure_telemetry(telemetry_service: PerformanceTelemetryService) -> void:
	telemetry = telemetry_service


func set_upload_budget(value: int) -> void:
	max_uploads_per_frame = clampi(value, 1, 16)


func set_memory_limit_megabytes(value: int) -> void:
	memory_limit_bytes = maxi(64, value) * 1024 * 1024
	_evict_if_needed()


func request_texture(asset_id: String, desired_screen_extent: float = 1024.0) -> Texture2D:
	_access_counter += 1
	if telemetry != null:
		telemetry.record_developer_counter(&"image_requests")
	var clean_id: String = asset_id.strip_edges()
	if clean_id.is_empty() or library == null:
		return null
	var tier: int = tier_for_extent(desired_screen_extent)
	var key: String = _cache_key(clean_id, tier)
	var exact_texture: Texture2D = _touch_and_get_texture(key)
	if exact_texture != null:
		return exact_texture
	var fallback_texture: Texture2D = _best_cached_texture(clean_id, tier)
	if _worker.is_pending(key):
		set_process(true)
		return fallback_texture
	if _failure_messages.has(clean_id):
		return fallback_texture
	if _worker.pending_work_count() >= MAX_PENDING_DECODE_REQUESTS:
		set_process(true)
		return fallback_texture
	var record: Dictionary = library.get_asset(clean_id)
	if record.is_empty():
		_record_failure(clean_id, NotLightL10n.text("runtime.ui.board_screen.3b9f1609f0"))
		return fallback_texture
	if int(record.get("kind", AssetKinds.OTHER)) != AssetKinds.IMAGE:
		_record_failure(clean_id, NotLightL10n.text("runtime.assets.image_asset_cache.271a75ef01"))
		return fallback_texture
	var path: String = library.resolve_asset_path(clean_id)
	if path.is_empty() or not FileAccess.file_exists(path):
		_record_failure(clean_id, NotLightL10n.text("runtime.assets.image_asset_cache.123468c6f7"))
		return fallback_texture
	_failure_messages.erase(clean_id)
	if _worker.request(key, clean_id, path, tier):
		set_process(true)
	return fallback_texture


func _touch_and_get_texture(key: String) -> Texture2D:
	var existing: Variant = _entries.get(key)
	if existing is not Dictionary:
		return null
	var entry: Dictionary = existing as Dictionary
	entry["last_used"] = _access_counter
	_entries[key] = entry
	var texture_value: Variant = entry.get("texture")
	if texture_value is Texture2D:
		return texture_value as Texture2D
	return null


func _best_cached_texture(asset_id: String, requested_tier: int) -> Texture2D:
	var best_texture: Texture2D = null
	var best_distance: int = 2147483647
	for candidate_tier: int in TIERS:
		var key: String = _cache_key(asset_id, candidate_tier)
		var existing: Variant = _entries.get(key)
		if existing is not Dictionary:
			continue
		var entry: Dictionary = existing as Dictionary
		var texture_value: Variant = entry.get("texture")
		if texture_value is not Texture2D:
			continue
		var distance: int = absi(candidate_tier - requested_tier)
		# Prefer a larger cached tier at equal distance: downsampling is less
		# visually distracting than temporarily upscaling a tiny thumbnail.
		if distance < best_distance or (distance == best_distance and candidate_tier > requested_tier):
			best_distance = distance
			best_texture = texture_value as Texture2D
			entry["last_used"] = _access_counter
			_entries[key] = entry
	return best_texture


func request_metadata(asset_id: String) -> void:
	request_texture(asset_id, float(TIER_THUMBNAIL))


func get_intrinsic_size(asset_id: String) -> Vector2i:
	var value: Variant = _intrinsic_sizes.get(asset_id)
	if value is Vector2i:
		return value as Vector2i
	return Vector2i.ZERO


func get_failure_message(asset_id: String) -> String:
	return str(_failure_messages.get(asset_id, ""))


func has_failure(asset_id: String) -> bool:
	return not get_failure_message(asset_id).is_empty()


func invalidate_asset(asset_id: String) -> void:
	var keys_to_remove: Array[String] = []
	for raw_key: Variant in _entries.keys():
		var key: String = str(raw_key)
		if key.begins_with("%s|" % asset_id):
			keys_to_remove.append(key)
	for key: String in keys_to_remove:
		_remove_entry(key)
	_intrinsic_sizes.erase(asset_id)
	_failure_messages.erase(asset_id)
	cache_changed.emit()


func clear_memory_cache() -> void:
	_entries.clear()
	_intrinsic_sizes.clear()
	_failure_messages.clear()
	_memory_bytes = 0
	cache_changed.emit()


func get_memory_bytes() -> int:
	return _memory_bytes


static func tier_for_extent(desired_screen_extent: float) -> int:
	var extent: float = maxf(1.0, desired_screen_extent)
	if extent <= 220.0:
		return TIER_THUMBNAIL
	if extent <= 640.0:
		return TIER_SMALL
	if extent <= 1280.0:
		return TIER_MEDIUM
	return TIER_LARGE


func _apply_decode_result(result: Dictionary) -> bool:
	var key: String = str(result.get("cache_key", ""))
	var asset_id: String = str(result.get("asset_id", ""))
	var error_message: String = str(result.get("error", ""))
	if not error_message.is_empty():
		_record_failure(asset_id, error_message)
		return false
	var image_value: Variant = result.get("image")
	if image_value is not Image:
		_record_failure(asset_id, NotLightL10n.text("runtime.assets.image_asset_cache.cbdd1ff48c"))
		return false
	var image: Image = image_value as Image
	if image.is_empty():
		_record_failure(asset_id, NotLightL10n.text("runtime.assets.image_asset_cache.881110e876"))
		return false
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	if texture == null:
		_record_failure(asset_id, NotLightL10n.text("runtime.assets.image_asset_cache.51659559b6"))
		return false
	var decoded_size: Vector2i = result.get("decoded_size", Vector2i(image.get_width(), image.get_height())) as Vector2i
	var pixel_count: int = maxi(1, decoded_size.x) * maxi(1, decoded_size.y)
	var byte_estimate: int = int(ceil(float(pixel_count) * (5.34 if image.has_mipmaps() else 4.0)))
	if _entries.has(key):
		_remove_entry(key)
	_entries[key] = {
		"texture": texture,
		"bytes": byte_estimate,
		"last_used": _access_counter,
		"asset_id": asset_id,
	}
	_memory_bytes += byte_estimate
	var intrinsic_size: Vector2i = result.get("intrinsic_size", decoded_size) as Vector2i
	_intrinsic_sizes[asset_id] = intrinsic_size
	_failure_messages.erase(asset_id)
	texture_ready.emit(asset_id)
	return true


func _record_failure(asset_id: String, message: String) -> void:
	var clean_id: String = asset_id.strip_edges()
	if clean_id.is_empty():
		return
	var previous: String = str(_failure_messages.get(clean_id, ""))
	_failure_messages[clean_id] = message
	if previous != message:
		texture_failed.emit(clean_id, message)


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


func _remove_entry(key: String) -> void:
	var existing: Variant = _entries.get(key)
	if existing is Dictionary:
		_memory_bytes = maxi(0, _memory_bytes - int((existing as Dictionary).get("bytes", 0)))
	_entries.erase(key)


func _cache_key(asset_id: String, tier: int) -> String:
	return "%s|%d" % [asset_id, tier]


func _on_library_changed() -> void:
	_failure_messages.clear()
	if library == null:
		cache_changed.emit()
		return
	var missing_asset_ids: Dictionary = {}
	for raw_key: Variant in _entries.keys():
		var key: String = str(raw_key)
		var entry: Dictionary = _entries[key] as Dictionary
		var asset_id: String = str(entry.get("asset_id", ""))
		if not asset_id.is_empty() and library.get_asset(asset_id).is_empty():
			missing_asset_ids[asset_id] = true
	for raw_asset_id: Variant in missing_asset_ids.keys():
		invalidate_asset(str(raw_asset_id))
	cache_changed.emit()
