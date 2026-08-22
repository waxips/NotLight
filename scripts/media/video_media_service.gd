# SPDX-License-Identifier: GPL-3.0-or-later
class_name VideoMediaService
extends Node

signal metadata_ready(asset_id: String, metadata: Dictionary)
signal thumbnail_ready(asset_id: String)
signal optimization_started(asset_id: String)
signal optimization_progress(asset_id: String, progress: float, message: String)
signal optimization_completed(asset_id: String, optimized_path: String, saved_bytes: int)
signal optimization_failed(asset_id: String, message: String)
signal variant_state_changed(asset_id: String, state: Dictionary)
signal playback_variant_changed(asset_id: String, playback_path: String, variant_name: String)

const META_FILE: String = "video_meta.json"
const THUMB_FILE: String = "video_thumb.jpg"
const WORKING_FILE: String = "video_optimized.working.mp4"
const PROGRESS_FILE: String = "video_progress.txt"
const VARIANT_ORIGINAL: String = "original"
const VARIANT_OPTIMIZED: String = "optimized"

var library: AssetLibraryService
var settings: AppSettingsStore
var _metadata_cache: Dictionary = {}
var _thumbnail_cache: Dictionary = {}

# DOD-style queue: job attributes are parallel arrays and only one expensive
# encode is active at a time. This keeps memory/CPU behavior predictable.
var _queue_asset_ids: PackedStringArray = PackedStringArray()
var _queue_profiles: PackedStringArray = PackedStringArray()

var _active_asset_id: String = ""
var _active_profile: String = ""
var _active_input: String = ""
var _active_working: String = ""
var _active_progress_file: String = ""
var _active_duration: float = 0.0
var _active_pid: int = -1
var _active_last_progress: float = -1.0


func _ready() -> void:
	set_process(false)


func configure(asset_library: AssetLibraryService, app_settings: AppSettingsStore = null) -> void:
	library = asset_library
	settings = app_settings
	if library != null and not library.import_finished.is_connected(_on_library_import_finished):
		library.import_finished.connect(_on_library_import_finished)


func _exit_tree() -> void:
	cancel_active(false)


func _on_library_import_finished(asset_id: String, duplicate: bool) -> void:
	if duplicate or settings == null or not settings.auto_optimize_video or library == null:
		return
	var asset: Dictionary = library.get_asset(asset_id)
	if asset.is_empty() or int(asset.get("kind", AssetKinds.OTHER)) != AssetKinds.VIDEO:
		return
	enqueue_optimization(asset_id, "auto")


func tools_available() -> bool:
	return FFmpegTools.is_ffmpeg_available() and FFmpegTools.is_ffprobe_available()


func ffmpeg_status_text() -> String:
	if not tools_available():
		return NotLightL10n.text("runtime.media.video_media_service.30299e12cd")
	var version: String = FFmpegTools.version_line("ffmpeg")
	return version if not version.is_empty() else NotLightL10n.text("runtime.media.video_media_service.055bbc68a7")


func get_metadata(asset_id: String, force_refresh: bool = false) -> Dictionary:
	var clean_id: String = asset_id.strip_edges()
	if clean_id.is_empty() or library == null:
		return {}
	if not force_refresh and _metadata_cache.has(clean_id):
		return (_metadata_cache[clean_id] as Dictionary).duplicate(true)
	var cached: Dictionary = _load_metadata_file(clean_id)
	if not force_refresh and not cached.is_empty():
		_metadata_cache[clean_id] = cached
		return cached.duplicate(true)
	var asset: Dictionary = library.get_asset(clean_id)
	if asset.is_empty() or int(asset.get("kind", AssetKinds.OTHER)) != AssetKinds.VIDEO:
		return {}
	var state: Dictionary = _ensure_video_state(clean_id, asset)
	var source_path: String = _variant_path(state, VARIANT_ORIGINAL)
	if source_path.is_empty():
		source_path = resolve_playback_path(clean_id)
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		return {"ok": false, "error": NotLightL10n.text("runtime.ui.video_player_overlay.d8c705b0ae")}
	var metadata: Dictionary = FFmpegTools.probe(source_path)
	if not bool(metadata.get("ok", false)):
		return metadata
	metadata["asset_id"] = clean_id
	metadata["source_path"] = source_path
	metadata["source_size"] = _variant_size(state, VARIANT_ORIGINAL)
	metadata["optimized_path"] = _variant_path(state, VARIANT_OPTIMIZED)
	metadata["optimized_size"] = _variant_size(state, VARIANT_OPTIMIZED)
	metadata["preferred_variant"] = str(state.get("preferred_variant", VARIANT_ORIGINAL))
	metadata["playback_path"] = resolve_playback_path(clean_id)
	_metadata_cache[clean_id] = metadata.duplicate(true)
	_save_metadata_file(clean_id, metadata)
	metadata_ready.emit(clean_id, metadata.duplicate(true))
	return metadata


func get_thumbnail(asset_id: String) -> Texture2D:
	var clean_id: String = asset_id.strip_edges()
	if clean_id.is_empty():
		return null
	if _thumbnail_cache.has(clean_id):
		return _thumbnail_cache[clean_id] as Texture2D
	var path: String = thumbnail_path(clean_id)
	if not FileAccess.file_exists(path):
		_generate_thumbnail(clean_id)
	if not FileAccess.file_exists(path):
		return null
	var image: Image = Image.new()
	var error: Error = image.load(path)
	if error != OK or image.is_empty():
		return null
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_thumbnail_cache[clean_id] = texture
	thumbnail_ready.emit(clean_id)
	return texture


func ensure_asset(asset_id: String) -> Dictionary:
	var metadata: Dictionary = get_metadata(asset_id)
	if bool(metadata.get("ok", false)):
		get_thumbnail(asset_id)
	return metadata


func get_variant_state(asset_id: String) -> Dictionary:
	if library == null:
		return {}
	var asset: Dictionary = library.get_asset(asset_id)
	if asset.is_empty() or int(asset.get("kind", AssetKinds.OTHER)) != AssetKinds.VIDEO:
		return {}
	return _ensure_video_state(asset_id, asset).duplicate(true)


func has_variant(asset_id: String, variant_name: String) -> bool:
	var state: Dictionary = get_variant_state(asset_id)
	return not _variant_path(state, variant_name).is_empty()


func resolve_playback_path(asset_id: String, requested_variant: String = "") -> String:
	if library == null:
		return ""
	var asset: Dictionary = library.get_asset(asset_id)
	if asset.is_empty():
		return ""
	var state: Dictionary = _ensure_video_state(asset_id, asset)
	var preferred: String = requested_variant.strip_edges().to_lower()
	if preferred.is_empty():
		preferred = str(state.get("preferred_variant", VARIANT_ORIGINAL))
	var candidate: String = _variant_path(state, preferred)
	if not candidate.is_empty() and FileAccess.file_exists(candidate):
		return candidate
	for fallback: String in [VARIANT_OPTIMIZED, VARIANT_ORIGINAL]:
		candidate = _variant_path(state, fallback)
		if not candidate.is_empty() and FileAccess.file_exists(candidate):
			return candidate
	return library.resolve_asset_path(asset_id)


func preferred_variant(asset_id: String) -> String:
	return str(get_variant_state(asset_id).get("preferred_variant", VARIANT_ORIGINAL))


func set_preferred_variant(asset_id: String, variant_name: String) -> bool:
	var clean_variant: String = variant_name.strip_edges().to_lower()
	if clean_variant != VARIANT_ORIGINAL and clean_variant != VARIANT_OPTIMIZED:
		return false
	var asset: Dictionary = library.get_asset(asset_id) if library != null else {}
	if asset.is_empty():
		return false
	var state: Dictionary = _ensure_video_state(asset_id, asset)
	if _variant_path(state, clean_variant).is_empty():
		return false
	state["preferred_variant"] = clean_variant
	if not _save_video_state(asset_id, asset, state):
		return false
	_invalidate_metadata(asset_id)
	var path: String = resolve_playback_path(asset_id)
	variant_state_changed.emit(asset_id, state.duplicate(true))
	playback_variant_changed.emit(asset_id, path, clean_variant)
	return true


func delete_original_variant(asset_id: String) -> bool:
	if library == null:
		return false
	var asset: Dictionary = library.get_asset(asset_id)
	if asset.is_empty():
		return false
	var state: Dictionary = _ensure_video_state(asset_id, asset)
	var original: Dictionary = _variant_record(state, VARIANT_ORIGINAL)
	var optimized: Dictionary = _variant_record(state, VARIANT_OPTIMIZED)
	if original.is_empty() or optimized.is_empty():
		return false
	var metadata: Dictionary = asset.get("metadata", {}) as Dictionary
	var variants: Dictionary = state.get("variants", {}) as Dictionary
	variants.erase(VARIANT_ORIGINAL)
	state["variants"] = variants
	state["preferred_variant"] = VARIANT_OPTIMIZED
	metadata["video"] = state
	var old_original_relpath: String = str(original.get("blob_relpath", ""))
	if not library.replace_asset_primary_blob(
		asset_id,
		str(optimized.get("hash_sha256", "")),
		str(optimized.get("blob_relpath", "")),
		int(optimized.get("byte_size", 0)),
		str(optimized.get("extension", "mp4")),
		metadata
	):
		return false
	# The old blob becomes intentionally unreferenced. Deleting it here is safe
	# for the normal content-addressed catalog; integrity cleanup is a fallback.
	if not old_original_relpath.is_empty() and old_original_relpath != str(optimized.get("blob_relpath", "")):
		library.delete_blob_if_unreferenced_path(old_original_relpath)
	_invalidate_metadata(asset_id)
	variant_state_changed.emit(asset_id, state.duplicate(true))
	playback_variant_changed.emit(asset_id, resolve_playback_path(asset_id), VARIANT_OPTIMIZED)
	return true


func delete_optimized_variant(asset_id: String) -> bool:
	if library == null:
		return false
	var asset: Dictionary = library.get_asset(asset_id)
	if asset.is_empty():
		return false
	var state: Dictionary = _ensure_video_state(asset_id, asset)
	var optimized: Dictionary = _variant_record(state, VARIANT_OPTIMIZED)
	if optimized.is_empty():
		return true
	var original: Dictionary = _variant_record(state, VARIANT_ORIGINAL)
	if original.is_empty():
		# Optimized is the only durable copy; never delete the last version.
		return false
	var relpath: String = str(optimized.get("blob_relpath", ""))
	var variants: Dictionary = state.get("variants", {}) as Dictionary
	variants.erase(VARIANT_OPTIMIZED)
	state["variants"] = variants
	state["preferred_variant"] = VARIANT_ORIGINAL
	if not _save_video_state(asset_id, asset, state):
		return false
	if not relpath.is_empty():
		library.delete_blob_if_unreferenced_path(relpath)
	_invalidate_metadata(asset_id)
	variant_state_changed.emit(asset_id, state.duplicate(true))
	playback_variant_changed.emit(asset_id, resolve_playback_path(asset_id), VARIANT_ORIGINAL)
	return true


func thumbnail_path(asset_id: String) -> String:
	return _asset_cache_dir(asset_id).path_join(THUMB_FILE)


func enqueue_optimization(asset_id: String, profile: String = "balanced") -> bool:
	var clean_id: String = asset_id.strip_edges()
	if clean_id.is_empty() or library == null:
		return false
	if not tools_available():
		optimization_failed.emit(clean_id, NotLightL10n.text("runtime.media.video_media_service.c4a492d55c"))
		return false
	if clean_id == _active_asset_id or _queue_asset_ids.has(clean_id):
		return false
	var asset: Dictionary = library.get_asset(clean_id)
	if asset.is_empty() or int(asset.get("kind", AssetKinds.OTHER)) != AssetKinds.VIDEO:
		return false
	var metadata: Dictionary = get_metadata(clean_id)
	if not bool(metadata.get("ok", false)):
		optimization_failed.emit(clean_id, str(metadata.get("error", NotLightL10n.text("runtime.media.video_media_service.6414a88532"))))
		return false
	_queue_asset_ids.append(clean_id)
	_queue_profiles.append(_normalize_profile(profile))
	set_process(true)
	return true


func cancel(asset_id: String) -> bool:
	var clean_id: String = asset_id.strip_edges()
	if clean_id == _active_asset_id:
		cancel_active(true)
		return true
	var index: int = _queue_asset_ids.find(clean_id)
	if index < 0:
		return false
	_queue_asset_ids.remove_at(index)
	_queue_profiles.remove_at(index)
	optimization_failed.emit(clean_id, NotLightL10n.text("runtime.media.video_media_service.7404791911"))
	return true


func cancel_active(notify: bool = true) -> void:
	var cancelled_id: String = _active_asset_id
	if _active_pid > 0 and OS.is_process_running(_active_pid):
		OS.kill(_active_pid)
	_cleanup_active_files()
	_reset_active()
	if notify and not cancelled_id.is_empty():
		optimization_failed.emit(cancelled_id, NotLightL10n.text("runtime.media.video_media_service.7404791911"))


func is_optimizing(asset_id: String = "") -> bool:
	if asset_id.strip_edges().is_empty():
		return _active_pid > 0 or not _queue_asset_ids.is_empty()
	return _active_asset_id == asset_id or _queue_asset_ids.has(asset_id)


func _process(_delta: float) -> void:
	if _active_pid <= 0:
		_start_next()
		if _active_pid <= 0 and _queue_asset_ids.is_empty():
			set_process(false)
		return
	_read_progress()
	if _active_pid > 0 and not OS.is_process_running(_active_pid):
		var exit_code: int = OS.get_process_exit_code(_active_pid)
		_finish_active(exit_code)


func _start_next() -> void:
	if _queue_asset_ids.is_empty():
		return
	_active_asset_id = _queue_asset_ids[0]
	_active_profile = _queue_profiles[0]
	_queue_asset_ids.remove_at(0)
	_queue_profiles.remove_at(0)

	# Re-encoding always starts from the original when it still exists. This
	# avoids generation loss after the user tries several compression profiles.
	_active_input = resolve_playback_path(_active_asset_id, VARIANT_ORIGINAL)
	if _active_input.is_empty():
		_active_input = resolve_playback_path(_active_asset_id)
	var metadata: Dictionary = get_metadata(_active_asset_id, true)
	_active_duration = float(metadata.get("duration", 0.0))
	_ensure_asset_cache_dir(_active_asset_id)
	_active_working = _asset_cache_dir(_active_asset_id).path_join(WORKING_FILE)
	_active_progress_file = _asset_cache_dir(_active_asset_id).path_join(PROGRESS_FILE)
	_cleanup_active_files()

	var arguments: PackedStringArray = _build_optimization_args(
		_active_input,
		_active_working,
		_active_progress_file,
		metadata,
		_active_profile
	)
	_active_pid = OS.create_process(FFmpegTools.ffmpeg_path(), arguments, false)
	if _active_pid <= 0:
		var failed_id: String = _active_asset_id
		_reset_active()
		optimization_failed.emit(failed_id, NotLightL10n.text("runtime.media.video_media_service.84a59a3a9f"))
		return
	optimization_started.emit(_active_asset_id)
	optimization_progress.emit(_active_asset_id, 0.0, NotLightL10n.text("runtime.media.video_media_service.0d5dda7c6e"))


func _build_optimization_args(
	input_path: String,
	output_path: String,
	progress_path: String,
	metadata: Dictionary,
	profile: String
) -> PackedStringArray:
	# H.264 is deliberate in Stage 7: the bundled EIRTeam decoder already plays
	# it reliably, so the optimized derivative must first be a drop-in playback
	# replacement. HEVC can be reintroduced later as an optional codec profile.
	var crf: String = "25"
	var preset: String = "fast"
	var audio_bitrate: String = "112k"
	var max_height: int = 1080
	if profile == "quality":
		crf = "21"
		preset = "medium"
		audio_bitrate = "160k"
		max_height = 0
	elif profile == "small":
		crf = "28"
		preset = "fast"
		audio_bitrate = "96k"
		max_height = 1080
	elif profile == "auto":
		var height: int = int(metadata.get("height", 0))
		var bitrate: int = int(metadata.get("bitrate", 0))
		# Auto is intentionally storage-oriented. Low-bitrate sources are often
		# already compressed, so a stronger CRF is required to get a meaningful
		# saving; the original remains available for quality comparison.
		if bitrate <= 0:
			crf = "26"
		elif bitrate < 2500000:
			crf = "28"
		elif bitrate < 6000000:
			crf = "26"
		else:
			crf = "24"
		max_height = 1080 if height > 1080 else 0

	var thread_count: int = 0
	var cpu_mode: int = int(AppSettingsStore.CompressionCpuMode.ECO)
	if settings != null:
		cpu_mode = int(settings.compression_cpu_mode)
	var processors: int = maxi(1, OS.get_processor_count())
	if cpu_mode == int(AppSettingsStore.CompressionCpuMode.ECO):
		# Eco deliberately trades time for temperature: one x264 worker plus one
		# lookahead worker keeps long laptop encodes much calmer than auto threads.
		thread_count = 1
		preset = "veryfast"
	elif cpu_mode == int(AppSettingsStore.CompressionCpuMode.BALANCED):
		thread_count = clampi(int(ceil(float(processors) * 0.25)), 2, 4)
		if preset == "medium":
			preset = "fast"
	# MAXIMUM leaves FFmpeg/libx264 thread auto-detection enabled.

	var arguments: PackedStringArray = PackedStringArray([
		"-hide_banner", "-loglevel", "error", "-nostdin", "-y",
		"-i", _native_path(input_path),
		"-map", "0:v:0", "-map", "0:a?",
		"-c:v", "libx264", "-preset", preset, "-crf", crf,
		"-pix_fmt", "yuv420p",
	])
	if thread_count > 0:
		arguments.append_array(PackedStringArray([
			"-threads:v", str(thread_count),
			"-x264-params", "threads=%d:lookahead_threads=1" % thread_count,
			"-filter_threads", "1",
		]))
	var input_height: int = int(metadata.get("height", 0))
	if max_height > 0 and input_height > max_height:
		arguments.append_array(PackedStringArray(["-vf", "scale=-2:%d" % max_height]))
	arguments.append_array(PackedStringArray([
		"-c:a", "aac", "-b:a", audio_bitrate,
		"-threads:a", "1" if thread_count > 0 else "0",
		"-movflags", "+faststart",
		"-progress", _native_path(progress_path),
		"-nostats",
		_native_path(output_path),
	]))
	return arguments


func _read_progress() -> void:
	if _active_progress_file.is_empty() or not FileAccess.file_exists(_active_progress_file):
		return
	var file: FileAccess = FileAccess.open(_active_progress_file, FileAccess.READ)
	if file == null:
		return
	var out_time: float = 0.0
	for line: String in file.get_as_text().split("\n"):
		if line.begins_with("out_time="):
			out_time = _timecode_to_seconds(line.trim_prefix("out_time="))
	var progress: float = 0.0
	if _active_duration > 0.0:
		progress = clampf(out_time / _active_duration, 0.0, 0.995)
	if _active_last_progress < 0.0 or absf(progress - _active_last_progress) >= 0.005:
		_active_last_progress = progress
		optimization_progress.emit(_active_asset_id, progress, NotLightL10n.text("runtime.media.video_media_service.900b054889") % int(round(progress * 100.0)))


func _finish_active(exit_code: int) -> void:
	var finished_id: String = _active_asset_id
	var input_size: int = _file_size(_active_input)
	var output_size: int = _file_size(_active_working)
	if exit_code != 0 or output_size <= 0:
		_cleanup_active_files()
		_reset_active()
		optimization_failed.emit(finished_id, NotLightL10n.text("runtime.media.video_media_service.318e10e577") % exit_code)
		return
	if input_size > 0 and output_size >= input_size:
		_cleanup_active_files()
		_reset_active()
		optimization_failed.emit(finished_id, NotLightL10n.text("audio.optimize.not_smaller"))
		return
	var verification: Dictionary = FFmpegTools.probe(_active_working)
	if not bool(verification.get("ok", false)):
		_cleanup_active_files()
		_reset_active()
		optimization_failed.emit(finished_id, NotLightL10n.text("runtime.media.video_media_service.7208c06e76"))
		return
	var result_duration: float = float(verification.get("duration", 0.0))
	if _active_duration > 0.0 and result_duration < _active_duration * 0.98:
		_cleanup_active_files()
		_reset_active()
		optimization_failed.emit(finished_id, NotLightL10n.text("runtime.media.video_media_service.421f413157"))
		return

	# Не заменяем уже существующую компактную версию на более тяжёлую при
	# автоматических/обычных профилях. Профиль quality оставляем как явное
	# пользовательское исключение: он может намеренно пожертвовать размером.
	var existing_asset: Dictionary = library.get_asset(finished_id)
	var existing_state: Dictionary = _ensure_video_state(finished_id, existing_asset)
	var existing_optimized_size: int = _variant_size(existing_state, VARIANT_OPTIMIZED)
	if _active_profile != "quality" and existing_optimized_size > 0 and output_size >= existing_optimized_size:
		_cleanup_active_files()
		_reset_active()
		optimization_failed.emit(finished_id, NotLightL10n.text("audio.optimize.existing_smaller"))
		return

	var hash_sha256: String = _hash_file_sha256(_active_working)
	if hash_sha256.is_empty():
		_cleanup_active_files()
		_reset_active()
		optimization_failed.emit(finished_id, NotLightL10n.text("runtime.media.video_media_service.25a0080a17"))
		return
	var commit: Dictionary = library.blobs.commit_temp(_active_working, hash_sha256, "mp4")
	if commit.is_empty():
		_cleanup_active_files()
		_reset_active()
		optimization_failed.emit(finished_id, library.blobs.get_last_error())
		return
	if FileAccess.file_exists(_active_progress_file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_active_progress_file))

	var asset: Dictionary = library.get_asset(finished_id)
	var state: Dictionary = _ensure_video_state(finished_id, asset)
	var variants: Dictionary = state.get("variants", {}) as Dictionary
	var previous_optimized: Dictionary = _variant_record(state, VARIANT_OPTIMIZED)
	variants[VARIANT_OPTIMIZED] = {
		"blob_relpath": str(commit.get("relative_path", "")),
		"hash_sha256": hash_sha256,
		"byte_size": output_size,
		"extension": "mp4",
		"codec": str(verification.get("video_codec", "h264")),
		"created_at_unix": int(Time.get_unix_time_from_system()),
		"profile": _active_profile,
	}
	state["variants"] = variants
	state["preferred_variant"] = VARIANT_OPTIMIZED
	if not _save_video_state(finished_id, asset, state):
		library.blobs.delete_blob(str(commit.get("relative_path", "")))
		_reset_active()
		optimization_failed.emit(finished_id, NotLightL10n.text("runtime.media.video_media_service.f9d6259cb3"))
		return
	var old_relpath: String = str(previous_optimized.get("blob_relpath", ""))
	if not old_relpath.is_empty() and old_relpath != str(commit.get("relative_path", "")):
		library.delete_blob_if_unreferenced_path(old_relpath)

	var original_size: int = _variant_size(state, VARIANT_ORIGINAL)
	var saved_bytes: int = maxi(0, original_size - output_size)
	_invalidate_metadata(finished_id)
	var final_path: String = resolve_playback_path(finished_id)
	var state_copy: Dictionary = state.duplicate(true)
	_reset_active()
	optimization_progress.emit(finished_id, 1.0, NotLightL10n.text("common.done"))
	variant_state_changed.emit(finished_id, state_copy)
	playback_variant_changed.emit(finished_id, final_path, VARIANT_OPTIMIZED)
	optimization_completed.emit(finished_id, final_path, saved_bytes)


func _generate_thumbnail(asset_id: String) -> bool:
	if not tools_available() or library == null:
		return false
	var source_path: String = resolve_playback_path(asset_id)
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		return false
	_ensure_asset_cache_dir(asset_id)
	var metadata: Dictionary = get_metadata(asset_id)
	var duration_value: float = float(metadata.get("duration", 0.0))
	var seek_seconds: float = minf(1.0, maxf(0.0, duration_value * 0.10))
	var arguments: PackedStringArray = PackedStringArray([
		"-hide_banner", "-loglevel", "error", "-nostdin", "-y",
		"-ss", "%.3f" % seek_seconds,
		"-i", _native_path(source_path),
		"-frames:v", "1",
		"-vf", "scale=640:-2:force_original_aspect_ratio=decrease",
		"-q:v", "3",
		_native_path(thumbnail_path(asset_id)),
	])
	var output: Array = []
	var code: int = OS.execute(FFmpegTools.ffmpeg_path(), arguments, output, true, false)
	return code == 0 and FileAccess.file_exists(thumbnail_path(asset_id))


func _ensure_video_state(asset_id: String, asset: Dictionary) -> Dictionary:
	var metadata: Dictionary = asset.get("metadata", {}) as Dictionary
	var state: Dictionary = metadata.get("video", {}) as Dictionary
	var variants: Dictionary = state.get("variants", {}) as Dictionary
	if not variants.has(VARIANT_ORIGINAL) and not variants.has(VARIANT_OPTIMIZED):
		var primary_relpath: String = str(asset.get("blob_relpath", ""))
		if not primary_relpath.is_empty():
			variants[VARIANT_ORIGINAL] = {
				"blob_relpath": primary_relpath,
				"hash_sha256": str(asset.get("hash_sha256", "")),
				"byte_size": int(asset.get("byte_size", 0)),
				"extension": str(asset.get("extension", "")),
				"created_at_unix": int(asset.get("imported_at_unix", asset.get("created_at_unix", 0))),
			}
		state["variants"] = variants
		state["preferred_variant"] = VARIANT_ORIGINAL
		metadata["video"] = state
		# Legacy assets are upgraded lazily in memory. We persist the state only
		# when a real variant/preference change happens, avoiding UI refresh loops.
	if not state.has("preferred_variant"):
		state["preferred_variant"] = VARIANT_OPTIMIZED if variants.has(VARIANT_OPTIMIZED) else VARIANT_ORIGINAL
	return state


func _save_video_state(asset_id: String, asset: Dictionary, state: Dictionary) -> bool:
	var metadata: Dictionary = asset.get("metadata", {}) as Dictionary
	metadata["video"] = state.duplicate(true)
	return library.update_asset_metadata(asset_id, metadata)


func _variant_record(state: Dictionary, variant_name: String) -> Dictionary:
	var variants: Dictionary = state.get("variants", {}) as Dictionary
	var raw: Variant = variants.get(variant_name, {})
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


func _variant_path(state: Dictionary, variant_name: String) -> String:
	if library == null:
		return ""
	var record: Dictionary = _variant_record(state, variant_name)
	var relative_path: String = str(record.get("blob_relpath", ""))
	if relative_path.is_empty():
		return ""
	return library.resolve_blob_relative(relative_path)


func _variant_size(state: Dictionary, variant_name: String) -> int:
	return int(_variant_record(state, variant_name).get("byte_size", 0))


func _asset_cache_dir(asset_id: String) -> String:
	if library != null:
		return library.blobs.cache_path_for_asset(asset_id)
	return "user://notlight/library/cache".path_join(asset_id)


func _ensure_asset_cache_dir(asset_id: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_asset_cache_dir(asset_id)))


func _metadata_path(asset_id: String) -> String:
	return _asset_cache_dir(asset_id).path_join(META_FILE)


func _load_metadata_file(asset_id: String) -> Dictionary:
	var path: String = _metadata_path(asset_id)
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _save_metadata_file(asset_id: String, metadata: Dictionary) -> void:
	_ensure_asset_cache_dir(asset_id)
	var file: FileAccess = FileAccess.open(_metadata_path(asset_id), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(metadata, "\t"))


func _invalidate_metadata(asset_id: String) -> void:
	_metadata_cache.erase(asset_id)
	var path: String = _metadata_path(asset_id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _cleanup_active_files() -> void:
	for path: String in [_active_working, _active_progress_file]:
		if not path.is_empty() and FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _reset_active() -> void:
	_active_asset_id = ""
	_active_profile = ""
	_active_input = ""
	_active_working = ""
	_active_progress_file = ""
	_active_duration = 0.0
	_active_pid = -1
	_active_last_progress = -1.0


func _file_size(path: String) -> int:
	if path.is_empty() or not FileAccess.file_exists(path):
		return 0
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	return int(file.get_length()) if file != null else 0


func _hash_file_sha256(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	const CHUNK_SIZE: int = 1024 * 1024
	while file.get_position() < file.get_length():
		var remaining: int = int(file.get_length() - file.get_position())
		if context.update(file.get_buffer(mini(CHUNK_SIZE, remaining))) != OK:
			return ""
	return context.finish().hex_encode()


func _timecode_to_seconds(value: String) -> float:
	var parts: PackedStringArray = value.split(":")
	if parts.size() != 3:
		return 0.0
	return float(parts[0]) * 3600.0 + float(parts[1]) * 60.0 + float(parts[2])


func _native_path(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path


func _normalize_profile(profile: String) -> String:
	var clean: String = profile.strip_edges().to_lower()
	return clean if ["quality", "balanced", "small", "auto"].has(clean) else "balanced"
