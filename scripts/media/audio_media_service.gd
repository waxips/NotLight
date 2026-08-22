# SPDX-License-Identifier: GPL-3.0-or-later
class_name AudioMediaService
extends Node

signal metadata_ready(asset_id: String, metadata: Dictionary)
signal waveform_ready(asset_id: String)
signal playback_ready(asset_id: String, playback_path: String)
signal preparation_failed(asset_id: String, message: String)
signal optimization_started(asset_id: String)
signal optimization_progress(asset_id: String, progress: float, message: String)
signal optimization_completed(asset_id: String, optimized_path: String, saved_bytes: int)
signal optimization_failed(asset_id: String, message: String)
signal variant_state_changed(asset_id: String, state: Dictionary)
signal playback_variant_changed(asset_id: String, playback_path: String, variant_name: String)

const META_FILE: String = "audio_meta.json"
const WAVEFORM_FILE: String = "audio_waveform.png"
const PLAYBACK_FILE: String = "audio_playback.ogg"
const PLAYBACK_TEMP_FILE: String = "audio_playback.part.ogg"
const WAVEFORM_TEMP_FILE: String = "audio_waveform.part.png"
const OPTIMIZE_WORKING_FILE: String = "audio_optimized.working.ogg"
const OPTIMIZE_PROGRESS_FILE: String = "audio_optimize_progress.txt"
const VARIANT_ORIGINAL: String = "original"
const VARIANT_OPTIMIZED: String = "optimized"
const NATIVE_EXTENSIONS: Array[String] = ["wav", "mp3", "ogg"]
const MAX_WAVEFORM_TEXTURES: int = 64

var library: AssetLibraryService
var _metadata_cache: Dictionary = {}
var _waveform_cache: Dictionary = {}
var _waveform_cache_order: PackedStringArray = PackedStringArray()
var _waveform_texture_queue: PackedStringArray = PackedStringArray()
var _waveform_texture_queued: Dictionary = {}
var _queue_asset_ids: PackedStringArray = PackedStringArray()
var _queued_request_flags: Dictionary = {}
var _failed_request_flags: Dictionary = {}
var _active_asset_id: String = ""
var _active_request_flags: int = 0
var _active_stage: int = 0
var _active_pid: int = -1
var _active_optimization_input: String = ""
var _active_optimization_working: String = ""
var _active_optimization_progress_file: String = ""
var _active_optimization_duration: float = 0.0
var _active_optimization_last_progress: float = -1.0
var _ffmpeg_available_state: int = -1
var _ffprobe_available_state: int = -1

const STAGE_NONE: int = 0
const STAGE_TRANSCODE: int = 1
const STAGE_WAVEFORM: int = 2
const STAGE_OPTIMIZE: int = 3

const REQUEST_PLAYBACK: int = 1
const REQUEST_WAVEFORM: int = 2
const REQUEST_OPTIMIZE: int = 4


func _ready() -> void:
	set_process(false)


func _exit_tree() -> void:
	# FFmpeg is intentionally launched as an independent child so the main loop
	# never blocks on audio derivation. Stop that child on application teardown
	# and discard its staging output; only completed files are ever promoted to
	# the stable cache names.
	if _active_pid > 0 and OS.is_process_running(_active_pid):
		OS.kill(_active_pid)
	_remove_partial_stage_output(_active_stage)
	_remove_file(_active_optimization_working)
	_remove_file(_active_optimization_progress_file)
	_active_pid = -1
	_active_stage = STAGE_NONE


func configure(asset_library: AssetLibraryService) -> void:
	library = asset_library
	if library != null and not library.import_finished.is_connected(_on_library_import_finished):
		library.import_finished.connect(_on_library_import_finished)


func tools_available() -> bool:
	return _ffmpeg_available() and _ffprobe_available()


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
	if asset.is_empty() or int(asset.get("kind", AssetKinds.OTHER)) != AssetKinds.AUDIO:
		return {}
	var state: Dictionary = _ensure_audio_state(clean_id, asset)
	var source_path: String = _variant_path(state, VARIANT_ORIGINAL)
	if source_path.is_empty():
		source_path = library.resolve_asset_path(clean_id)
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		return {"ok": false, "error": NotLightL10n.text("audio.error.source_unavailable")}
	var metadata: Dictionary = FFmpegTools.probe(source_path, false) if _ffprobe_available() else {}
	if metadata.is_empty() or not bool(metadata.get("ok", false)):
		metadata = {
			"ok": true,
			"duration": 0.0,
			"size": int(asset.get("byte_size", 0)),
			"bitrate": 0,
			"format": str(asset.get("extension", "")),
			"audio_codec": "",
			"sample_rate": 0,
			"channels": 0,
		}
	metadata["asset_id"] = clean_id
	metadata["source_path"] = source_path
	metadata["source_size"] = _variant_size(state, VARIANT_ORIGINAL)
	metadata["optimized_path"] = _variant_path(state, VARIANT_OPTIMIZED)
	metadata["optimized_size"] = _variant_size(state, VARIANT_OPTIMIZED)
	metadata["preferred_variant"] = str(state.get("preferred_variant", VARIANT_ORIGINAL))
	# Cache codec metadata before resolving playback. In particular an .ogg file
	# can contain Opus; AudioStreamOggVorbis must not be handed that source as if
	# every OGG container were natively playable.
	_metadata_cache[clean_id] = metadata.duplicate(true)
	metadata["playback_path"] = resolve_playback_path(clean_id, false)
	_metadata_cache[clean_id] = metadata.duplicate(true)
	_save_metadata_file(clean_id, metadata)
	metadata_ready.emit(clean_id, metadata.duplicate(true))
	return metadata


func ensure_asset(asset_id: String) -> Dictionary:
	var metadata: Dictionary = get_metadata(asset_id)
	# Board placement needs metadata and the retained waveform only. Playback
	# transcodes are requested lazily by the player, not by merely seeing a card.
	request_prepare(asset_id, false, true)
	return metadata


func get_variant_state(asset_id: String) -> Dictionary:
	if library == null:
		return {}
	var clean_id: String = asset_id.strip_edges()
	var asset: Dictionary = library.get_asset(clean_id)
	if asset.is_empty() or int(asset.get("kind", AssetKinds.OTHER)) != AssetKinds.AUDIO:
		return {}
	return _ensure_audio_state(clean_id, asset).duplicate(true)


func has_variant(asset_id: String, variant_name: String) -> bool:
	var state: Dictionary = get_variant_state(asset_id)
	return not _variant_path(state, variant_name).is_empty()


func preferred_variant(asset_id: String) -> String:
	return str(get_variant_state(asset_id).get("preferred_variant", VARIANT_ORIGINAL))


func set_preferred_variant(asset_id: String, variant_name: String) -> bool:
	if library == null:
		return false
	var clean_id: String = asset_id.strip_edges()
	var clean_variant: String = variant_name.strip_edges().to_lower()
	if clean_id.is_empty() or (clean_variant != VARIANT_ORIGINAL and clean_variant != VARIANT_OPTIMIZED):
		return false
	var asset: Dictionary = library.get_asset(clean_id)
	if asset.is_empty() or int(asset.get("kind", AssetKinds.OTHER)) != AssetKinds.AUDIO:
		return false
	var state: Dictionary = _ensure_audio_state(clean_id, asset)
	if _variant_path(state, clean_variant).is_empty():
		return false
	state["preferred_variant"] = clean_variant
	if not _save_audio_state(clean_id, asset, state):
		return false
	_invalidate_metadata(clean_id)
	var playback_path: String = resolve_playback_path(clean_id, false)
	variant_state_changed.emit(clean_id, state.duplicate(true))
	playback_variant_changed.emit(clean_id, playback_path, clean_variant)
	return true


func delete_original_variant(asset_id: String) -> bool:
	if library == null:
		return false
	var clean_id: String = asset_id.strip_edges()
	if is_optimizing(clean_id):
		return false
	var asset: Dictionary = library.get_asset(clean_id)
	if asset.is_empty() or int(asset.get("kind", AssetKinds.OTHER)) != AssetKinds.AUDIO:
		return false
	var state: Dictionary = _ensure_audio_state(clean_id, asset)
	var original: Dictionary = _variant_record(state, VARIANT_ORIGINAL)
	var optimized: Dictionary = _variant_record(state, VARIANT_OPTIMIZED)
	# Never delete the only durable copy. Deleting the original is a storage
	# operation, not merely a playback preference change, so a verified optimized
	# variant must already exist and become the catalog's primary blob atomically.
	if original.is_empty() or optimized.is_empty():
		return false
	var optimized_relpath: String = str(optimized.get("blob_relpath", ""))
	var optimized_hash: String = str(optimized.get("hash_sha256", ""))
	var optimized_size: int = int(optimized.get("byte_size", 0))
	if optimized_relpath.is_empty() or optimized_hash.is_empty() or optimized_size <= 0:
		return false
	var optimized_path: String = library.resolve_blob_relative(optimized_relpath)
	if optimized_path.is_empty() or not _is_nonempty_file(optimized_path):
		return false

	var metadata: Dictionary = asset.get("metadata", {}) as Dictionary
	var variants: Dictionary = state.get("variants", {}) as Dictionary
	variants.erase(VARIANT_ORIGINAL)
	state["variants"] = variants
	state["preferred_variant"] = VARIANT_OPTIMIZED
	metadata["audio"] = state.duplicate(true)
	var old_original_relpath: String = str(original.get("blob_relpath", ""))
	if not library.replace_asset_primary_blob(
		clean_id,
		optimized_hash,
		optimized_relpath,
		optimized_size,
		str(optimized.get("extension", "ogg")),
		metadata
	):
		return false
	if not old_original_relpath.is_empty() and old_original_relpath != optimized_relpath:
		library.delete_blob_if_unreferenced_path(old_original_relpath)
	_remove_file(playback_cache_path(clean_id))
	_invalidate_metadata(clean_id)
	variant_state_changed.emit(clean_id, state.duplicate(true))
	playback_variant_changed.emit(clean_id, optimized_path, VARIANT_OPTIMIZED)
	return true


func delete_optimized_variant(asset_id: String) -> bool:
	if library == null:
		return false
	var clean_id: String = asset_id.strip_edges()
	if is_optimizing(clean_id):
		return false
	var asset: Dictionary = library.get_asset(clean_id)
	if asset.is_empty() or int(asset.get("kind", AssetKinds.OTHER)) != AssetKinds.AUDIO:
		return false
	var state: Dictionary = _ensure_audio_state(clean_id, asset)
	var optimized: Dictionary = _variant_record(state, VARIANT_OPTIMIZED)
	if optimized.is_empty():
		return true
	var original: Dictionary = _variant_record(state, VARIANT_ORIGINAL)
	if original.is_empty():
		return false
	var variants: Dictionary = state.get("variants", {}) as Dictionary
	variants.erase(VARIANT_OPTIMIZED)
	state["variants"] = variants
	state["preferred_variant"] = VARIANT_ORIGINAL
	if not _save_audio_state(clean_id, asset, state):
		return false
	var relpath: String = str(optimized.get("blob_relpath", ""))
	if not relpath.is_empty():
		library.delete_blob_if_unreferenced_path(relpath)
	_invalidate_metadata(clean_id)
	variant_state_changed.emit(clean_id, state.duplicate(true))
	playback_variant_changed.emit(clean_id, resolve_playback_path(clean_id, false), VARIANT_ORIGINAL)
	return true


func enqueue_optimization(asset_id: String) -> bool:
	var clean_id: String = asset_id.strip_edges()
	if clean_id.is_empty() or library == null:
		return false
	if not tools_available():
		optimization_failed.emit(clean_id, NotLightL10n.text("audio.optimize.tools_missing"))
		return false
	var asset: Dictionary = library.get_asset(clean_id)
	if asset.is_empty() or int(asset.get("kind", AssetKinds.OTHER)) != AssetKinds.AUDIO:
		return false
	var state: Dictionary = _ensure_audio_state(clean_id, asset)
	# Once the user explicitly discards the original, do not generation-loss
	# transcode the compressed copy again. This also prevents the catalog primary
	# blob from drifting away from the durable variant state.
	if _variant_path(state, VARIANT_ORIGINAL).is_empty():
		return false
	if clean_id == _active_asset_id and (_active_request_flags & REQUEST_OPTIMIZE) != 0:
		return false
	if (int(_queued_request_flags.get(clean_id, 0)) & REQUEST_OPTIMIZE) != 0:
		return false
	_clear_failed_flag(clean_id, REQUEST_OPTIMIZE)
	_enqueue_request_flags(clean_id, REQUEST_OPTIMIZE)
	return true


func is_optimizing(asset_id: String = "") -> bool:
	var clean_id: String = asset_id.strip_edges()
	if clean_id.is_empty():
		if not _active_asset_id.is_empty() and (_active_request_flags & REQUEST_OPTIMIZE) != 0:
			return true
		for queued_id: String in _queue_asset_ids:
			if (int(_queued_request_flags.get(queued_id, 0)) & REQUEST_OPTIMIZE) != 0:
				return true
		return false
	if clean_id == _active_asset_id:
		return (_active_request_flags & REQUEST_OPTIMIZE) != 0
	return (int(_queued_request_flags.get(clean_id, 0)) & REQUEST_OPTIMIZE) != 0


func resolve_playback_path(asset_id: String, request_if_missing: bool = true) -> String:
	if library == null:
		return ""
	var clean_id: String = asset_id.strip_edges()
	var asset: Dictionary = library.get_asset(clean_id)
	if asset.is_empty() or int(asset.get("kind", AssetKinds.OTHER)) != AssetKinds.AUDIO:
		return ""
	var state: Dictionary = _ensure_audio_state(clean_id, asset)
	var preferred: String = str(state.get("preferred_variant", VARIANT_ORIGINAL))
	if preferred == VARIANT_OPTIMIZED:
		var optimized_path: String = _variant_path(state, VARIANT_OPTIMIZED)
		if _is_nonempty_file(optimized_path):
			return optimized_path

	var source_path: String = _variant_path(state, VARIANT_ORIGINAL)
	if source_path.is_empty():
		source_path = library.resolve_asset_path(clean_id)
	var extension: String = str(asset.get("extension", source_path.get_extension())).to_lower()
	if FileAccess.file_exists(source_path) and not _requires_compatibility_playback(asset, source_path):
		return source_path

	# Unsupported containers/codecs use a disposable Vorbis compatibility cache.
	# This is deliberately separate from the durable user-requested optimized
	# variant stored in the Library catalog.
	var derived: String = playback_cache_path(clean_id)
	if _is_nonempty_file(derived):
		return derived
	if FileAccess.file_exists(derived):
		_remove_file(derived)
	if request_if_missing:
		request_prepare(asset_id, true, false)
	# Any source that reached this point has been classified as runtime-incompatible
	# (including Opus-in-OGG). Never hand it to a decoder merely because its file
	# extension appears in the native container allow-list.
	return ""


func load_stream(asset_id: String) -> AudioStream:
	var clean_id: String = asset_id.strip_edges()
	var path: String = resolve_playback_path(clean_id, true)
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var extension: String = path.get_extension().to_lower()
	var stream: AudioStream = null
	match extension:
		"wav":
			stream = AudioStreamWAV.load_from_file(path)
		"mp3":
			stream = AudioStreamMP3.load_from_file(path)
		"ogg":
			stream = AudioStreamOggVorbis.load_from_file(path)
	if stream != null:
		return stream

	var derived_path: String = playback_cache_path(clean_id)
	if path == derived_path:
		# A cache file can be non-empty yet fail the decoder (disk corruption, manual
		# edits, old development builds). Discard only the disposable derivative and
		# schedule a clean rebuild; the authoritative Library blob is untouched.
		_remove_file(derived_path)
		_clear_failed_flag(clean_id, REQUEST_PLAYBACK)
		request_prepare(clean_id, true, false)
	elif extension == "ogg":
		# OGG is a container. If ffprobe metadata was unavailable/inconclusive and
		# the Vorbis runtime loader rejects the source, treat it as requiring the
		# same derived-Vorbis path used for known Opus-in-OGG assets.
		var metadata: Dictionary = _metadata_cache.get(clean_id, {}) as Dictionary
		metadata["audio_codec"] = "runtime_loader_failed"
		_metadata_cache[clean_id] = metadata
		_clear_failed_flag(clean_id, REQUEST_PLAYBACK)
		request_prepare(clean_id, true, false)
	return null


func get_waveform(asset_id: String, request_if_missing: bool = true) -> Texture2D:
	var clean_id: String = asset_id.strip_edges()
	if clean_id.is_empty():
		return null
	if _waveform_cache.has(clean_id):
		return _waveform_cache[clean_id] as Texture2D
	if not request_if_missing or library == null:
		return null
	var asset: Dictionary = library.get_asset(clean_id)
	if asset.is_empty() or int(asset.get("kind", AssetKinds.OTHER)) != AssetKinds.AUDIO:
		return null
	# Retained renderers may call this from _draw(). Keep that path strictly
	# in-memory: disk existence checks and source validation happen later in the
	# service process, one queued asset at a time.
	_enqueue_request_flags(clean_id, REQUEST_WAVEFORM)
	return null


func request_prepare(
	asset_id: String,
	prepare_playback: bool = true,
	prepare_waveform: bool = true
) -> void:
	var clean_id: String = asset_id.strip_edges()
	if clean_id.is_empty() or library == null:
		return
	var asset: Dictionary = library.get_asset(clean_id)
	if asset.is_empty() or int(asset.get("kind", AssetKinds.OTHER)) != AssetKinds.AUDIO:
		return
	var source_path: String = library.resolve_asset_path(clean_id)
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		return
	var request_flags: int = 0
	if prepare_playback and _needs_derived_playback(asset, source_path) and not FileAccess.file_exists(playback_cache_path(clean_id)):
		request_flags |= REQUEST_PLAYBACK
	if prepare_waveform and not FileAccess.file_exists(waveform_cache_path(clean_id)):
		request_flags |= REQUEST_WAVEFORM
	_enqueue_request_flags(clean_id, request_flags)


func _enqueue_request_flags(asset_id: String, request_flags: int) -> void:
	if asset_id.is_empty() or request_flags == 0:
		return
	var failed_flags: int = int(_failed_request_flags.get(asset_id, 0))
	request_flags &= ~failed_flags
	if request_flags == 0:
		return
	if asset_id == _active_asset_id:
		_active_request_flags |= request_flags
		set_process(true)
		return
	if _queued_request_flags.has(asset_id):
		_queued_request_flags[asset_id] = int(_queued_request_flags[asset_id]) | request_flags
		set_process(true)
		return
	_queue_asset_ids.append(asset_id)
	_queued_request_flags[asset_id] = request_flags
	set_process(true)


func playback_cache_path(asset_id: String) -> String:
	return _cache_dir(asset_id).path_join(PLAYBACK_FILE)


func waveform_cache_path(asset_id: String) -> String:
	return _cache_dir(asset_id).path_join(WAVEFORM_FILE)


func get_developer_diagnostics_snapshot() -> Dictionary:
	# Pure in-memory gauges only: diagnostics must never probe tools or touch disk.
	return {
		"audio_prepare_queue": _queue_asset_ids.size(),
		"audio_waveform_load_queue": _waveform_texture_queue.size(),
		"audio_waveform_cache": _waveform_cache.size(),
		"audio_active_stage": _active_stage,
		"audio_active_request_flags": _active_request_flags,
		"audio_ffmpeg_state": _ffmpeg_available_state,
		"audio_ffprobe_state": _ffprobe_available_state,
	}


func _process(_delta: float) -> void:
	if _active_pid > 0:
		if OS.is_process_running(_active_pid):
			if _active_stage == STAGE_OPTIMIZE:
				_read_optimization_progress()
			return
		var exit_code: int = OS.get_process_exit_code(_active_pid)
		_finish_active_stage(exit_code)
		return
	if not _active_asset_id.is_empty():
		_start_required_stage()
		return
	# Decode at most one derived waveform texture per frame. A board can reveal
	# many audio cards at once after a zoom/pan; loading every cached PNG from
	# _draw() would turn that reveal into a synchronous main-thread burst.
	if _load_next_waveform_texture():
		return
	_start_next_asset()
	if _active_asset_id.is_empty():
		set_process(false)
		return
	_start_required_stage()


func _queue_waveform_texture_load(asset_id: String) -> void:
	if asset_id.is_empty() or _waveform_cache.has(asset_id):
		return
	if _waveform_texture_queued.has(asset_id):
		set_process(true)
		return
	_waveform_texture_queue.append(asset_id)
	_waveform_texture_queued[asset_id] = true
	set_process(true)


func _load_next_waveform_texture() -> bool:
	if _waveform_texture_queue.is_empty():
		return false
	var asset_id: String = _waveform_texture_queue[0]
	_waveform_texture_queue.remove_at(0)
	_waveform_texture_queued.erase(asset_id)
	if _waveform_cache.has(asset_id):
		return true
	var path: String = waveform_cache_path(asset_id)
	if not FileAccess.file_exists(path):
		return true
	var image: Image = Image.new()
	if image.load(path) != OK or image.is_empty():
		# A stale/corrupt derived image should not be retried every frame. Remove
		# it and suppress this optional waveform request for the current session;
		# a future application run can derive it again from the source asset.
		_remove_file(path)
		var failed_flags: int = int(_failed_request_flags.get(asset_id, 0))
		_failed_request_flags[asset_id] = failed_flags | REQUEST_WAVEFORM
		return true
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_store_waveform_texture(asset_id, texture)
	waveform_ready.emit(asset_id)
	return true


func _store_waveform_texture(asset_id: String, texture: Texture2D) -> void:
	if asset_id.is_empty() or texture == null:
		return
	_remove_waveform_cache_order_entry(asset_id)
	while _waveform_cache.size() >= MAX_WAVEFORM_TEXTURES and not _waveform_cache_order.is_empty():
		var evicted_id: String = _waveform_cache_order[0]
		_waveform_cache_order.remove_at(0)
		_waveform_cache.erase(evicted_id)
	_waveform_cache[asset_id] = texture
	_waveform_cache_order.append(asset_id)


func _remove_waveform_cache_order_entry(asset_id: String) -> void:
	if asset_id.is_empty() or _waveform_cache_order.is_empty():
		return
	for index: int in range(_waveform_cache_order.size()):
		if _waveform_cache_order[index] == asset_id:
			_waveform_cache_order.remove_at(index)
			return


func _start_next_asset() -> void:
	if _queue_asset_ids.is_empty():
		return
	_active_asset_id = _queue_asset_ids[0]
	_queue_asset_ids.remove_at(0)
	_active_request_flags = int(_queued_request_flags.get(_active_asset_id, 0))
	_queued_request_flags.erase(_active_asset_id)
	_active_stage = STAGE_NONE
	_active_pid = -1


func _start_required_stage() -> void:
	if library == null or _active_asset_id.is_empty():
		_clear_active()
		return
	var asset: Dictionary = library.get_asset(_active_asset_id)
	if asset.is_empty() or int(asset.get("kind", AssetKinds.OTHER)) != AssetKinds.AUDIO:
		_fail_active_requests(_active_request_flags, NotLightL10n.text("audio.error.source_unavailable"), true)
		_clear_active()
		return
	var state: Dictionary = _ensure_audio_state(_active_asset_id, asset)
	var original_source_path: String = _variant_path(state, VARIANT_ORIGINAL)
	var source_path: String = original_source_path
	if source_path.is_empty():
		source_path = library.resolve_asset_path(_active_asset_id)
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		var notify_missing_source: bool = (_active_request_flags & REQUEST_PLAYBACK) != 0 or (_active_request_flags & REQUEST_OPTIMIZE) != 0
		_fail_active_requests(_active_request_flags, NotLightL10n.text("audio.error.source_unavailable"), notify_missing_source)
		_clear_active()
		return
	if not _ensure_cache_dir(_active_asset_id):
		var notify_cache_failure: bool = (_active_request_flags & REQUEST_PLAYBACK) != 0 or (_active_request_flags & REQUEST_OPTIMIZE) != 0
		_fail_active_requests(_active_request_flags, NotLightL10n.text("audio.error.cache_failed"), notify_cache_failure)
		_clear_active()
		return

	# Manual durable compression owns this single FFmpeg lane first. Playback and
	# waveform requests for the same asset remain queued and continue after the
	# optimized variant is committed, avoiding concurrent encoders on laptops.
	if (_active_request_flags & REQUEST_OPTIMIZE) != 0:
		if original_source_path.is_empty() or not FileAccess.file_exists(original_source_path):
			_active_request_flags &= ~REQUEST_OPTIMIZE
			optimization_failed.emit(_active_asset_id, NotLightL10n.text("audio.optimize.original_required"))
			_start_required_stage()
			return
		_start_optimization(original_source_path)
		return

	var needs_playback: bool = _requires_compatibility_playback(asset, source_path) and not FileAccess.file_exists(playback_cache_path(_active_asset_id))
	var needs_waveform: bool = not FileAccess.file_exists(waveform_cache_path(_active_asset_id))
	if (_active_request_flags & REQUEST_PLAYBACK) != 0:
		if needs_playback:
			_start_transcode(source_path)
			return
		_active_request_flags &= ~REQUEST_PLAYBACK
		playback_ready.emit(_active_asset_id, resolve_playback_path(_active_asset_id, false))
	if (_active_request_flags & REQUEST_WAVEFORM) != 0:
		if needs_waveform:
			_start_waveform(source_path)
			return
		_active_request_flags &= ~REQUEST_WAVEFORM
		_queue_waveform_texture_load(_active_asset_id)
	if _active_request_flags == 0:
		_clear_active()


func _start_transcode(source_path: String) -> void:
	_active_stage = STAGE_TRANSCODE
	var output_path: String = _stage_temp_path(STAGE_TRANSCODE)
	_remove_file(output_path)
	var args: PackedStringArray = PackedStringArray([
		"-y", "-v", "error", "-threads", "1", "-i", ProjectSettings.globalize_path(source_path),
		"-vn", "-c:a", "libvorbis", "-q:a", "5",
		ProjectSettings.globalize_path(output_path),
	])
	_active_pid = OS.create_process(FFmpegTools.ffmpeg_path(), args, false)
	if _active_pid <= 0:
		_ffmpeg_available_state = 0
		_active_stage = STAGE_NONE
		_fail_active_requests(REQUEST_PLAYBACK, NotLightL10n.text("audio.error.ffmpeg_start"), true)
		_start_required_stage()
	else:
		_ffmpeg_available_state = 1


func _start_waveform(source_path: String) -> void:
	_active_stage = STAGE_WAVEFORM
	var output_path: String = _stage_temp_path(STAGE_WAVEFORM)
	_remove_file(output_path)
	var args: PackedStringArray = PackedStringArray([
		"-y", "-v", "error", "-threads", "1", "-i", ProjectSettings.globalize_path(source_path),
		"-filter_complex", "aformat=channel_layouts=mono,showwavespic=s=768x96:colors=white",
		"-frames:v", "1", ProjectSettings.globalize_path(output_path),
	])
	_active_pid = OS.create_process(FFmpegTools.ffmpeg_path(), args, false)
	if _active_pid <= 0:
		_ffmpeg_available_state = 0
		_active_stage = STAGE_NONE
		_fail_active_requests(REQUEST_WAVEFORM, "", false)
		_start_required_stage()
	else:
		_ffmpeg_available_state = 1


func _start_optimization(source_path: String) -> void:
	_active_stage = STAGE_OPTIMIZE
	_active_optimization_input = source_path
	_active_optimization_working = _cache_dir(_active_asset_id).path_join(OPTIMIZE_WORKING_FILE)
	_active_optimization_progress_file = _cache_dir(_active_asset_id).path_join(OPTIMIZE_PROGRESS_FILE)
	_active_optimization_last_progress = -1.0
	var metadata: Dictionary = get_metadata(_active_asset_id)
	_active_optimization_duration = float(metadata.get("duration", 0.0))
	_remove_file(_active_optimization_working)
	_remove_file(_active_optimization_progress_file)
	var args: PackedStringArray = PackedStringArray([
		"-hide_banner", "-loglevel", "error", "-nostdin", "-y",
		"-i", ProjectSettings.globalize_path(source_path),
		"-vn", "-c:a", "libvorbis", "-q:a", "4", "-threads:a", "1",
		"-progress", ProjectSettings.globalize_path(_active_optimization_progress_file),
		"-nostats", ProjectSettings.globalize_path(_active_optimization_working),
	])
	_active_pid = OS.create_process(FFmpegTools.ffmpeg_path(), args, false)
	if _active_pid <= 0:
		_ffmpeg_available_state = 0
		_active_stage = STAGE_NONE
		_fail_active_requests(REQUEST_OPTIMIZE, "", false)
		optimization_failed.emit(_active_asset_id, NotLightL10n.text("audio.optimize.start_failed"))
		_start_required_stage()
		return
	_ffmpeg_available_state = 1
	optimization_started.emit(_active_asset_id)
	optimization_progress.emit(_active_asset_id, 0.0, NotLightL10n.text("audio.optimize.preparing"))


func _read_optimization_progress() -> void:
	if _active_optimization_progress_file.is_empty() or not FileAccess.file_exists(_active_optimization_progress_file):
		return
	var file: FileAccess = FileAccess.open(_active_optimization_progress_file, FileAccess.READ)
	if file == null:
		return
	var out_time: float = 0.0
	for line: String in file.get_as_text().split("\n"):
		if line.begins_with("out_time="):
			out_time = _timecode_to_seconds(line.trim_prefix("out_time="))
	var progress: float = 0.0
	if _active_optimization_duration > 0.0:
		progress = clampf(out_time / _active_optimization_duration, 0.0, 0.995)
	if _active_optimization_last_progress < 0.0 or absf(progress - _active_optimization_last_progress) >= 0.005:
		_active_optimization_last_progress = progress
		optimization_progress.emit(
			_active_asset_id,
			progress,
			NotLightL10n.text("audio.optimize.progress", {"percent": int(round(progress * 100.0))})
		)


func _finish_optimization_stage(exit_code: int) -> void:
	var finished_id: String = _active_asset_id
	var input_size: int = _file_size(_active_optimization_input)
	var output_size: int = _file_size(_active_optimization_working)
	if exit_code != 0 or output_size <= 0:
		_cleanup_optimization_files()
		_active_request_flags &= ~REQUEST_OPTIMIZE
		_failed_request_flags[finished_id] = int(_failed_request_flags.get(finished_id, 0)) | REQUEST_OPTIMIZE
		optimization_failed.emit(finished_id, NotLightL10n.text("audio.optimize.ffmpeg_failed", {"code": exit_code}))
		_start_required_stage()
		return
	if input_size > 0 and output_size >= input_size:
		_cleanup_optimization_files()
		_active_request_flags &= ~REQUEST_OPTIMIZE
		optimization_failed.emit(finished_id, NotLightL10n.text("audio.optimize.not_smaller"))
		_start_required_stage()
		return
	var verification: Dictionary = FFmpegTools.probe(_active_optimization_working, false)
	if not bool(verification.get("ok", false)):
		_cleanup_optimization_files()
		_active_request_flags &= ~REQUEST_OPTIMIZE
		optimization_failed.emit(finished_id, NotLightL10n.text("audio.optimize.verify_failed"))
		_start_required_stage()
		return
	var result_duration: float = float(verification.get("duration", 0.0))
	if _active_optimization_duration > 0.0 and result_duration < _active_optimization_duration * 0.98:
		_cleanup_optimization_files()
		_active_request_flags &= ~REQUEST_OPTIMIZE
		optimization_failed.emit(finished_id, NotLightL10n.text("audio.optimize.incomplete"))
		_start_required_stage()
		return

	var asset_before: Dictionary = library.get_asset(finished_id)
	var state_before: Dictionary = _ensure_audio_state(finished_id, asset_before)
	var existing_size: int = _variant_size(state_before, VARIANT_OPTIMIZED)
	if existing_size > 0 and output_size >= existing_size:
		_cleanup_optimization_files()
		_active_request_flags &= ~REQUEST_OPTIMIZE
		optimization_failed.emit(finished_id, NotLightL10n.text("audio.optimize.existing_smaller"))
		_start_required_stage()
		return
	var hash_sha256: String = _hash_file_sha256(_active_optimization_working)
	if hash_sha256.is_empty():
		_cleanup_optimization_files()
		_active_request_flags &= ~REQUEST_OPTIMIZE
		optimization_failed.emit(finished_id, NotLightL10n.text("audio.optimize.hash_failed"))
		_start_required_stage()
		return
	var commit: Dictionary = library.blobs.commit_temp(_active_optimization_working, hash_sha256, "ogg")
	if commit.is_empty():
		_cleanup_optimization_files()
		_active_request_flags &= ~REQUEST_OPTIMIZE
		optimization_failed.emit(finished_id, library.blobs.get_last_error())
		_start_required_stage()
		return
	_remove_file(_active_optimization_progress_file)

	var asset: Dictionary = library.get_asset(finished_id)
	var state: Dictionary = _ensure_audio_state(finished_id, asset)
	var variants: Dictionary = state.get("variants", {}) as Dictionary
	var previous_optimized: Dictionary = _variant_record(state, VARIANT_OPTIMIZED)
	variants[VARIANT_OPTIMIZED] = {
		"blob_relpath": str(commit.get("relative_path", "")),
		"hash_sha256": hash_sha256,
		"byte_size": output_size,
		"extension": "ogg",
		"codec": str(verification.get("audio_codec", "vorbis")),
		"created_at_unix": int(Time.get_unix_time_from_system()),
		"profile": "balanced",
	}
	state["variants"] = variants
	state["preferred_variant"] = VARIANT_OPTIMIZED
	if not _save_audio_state(finished_id, asset, state):
		library.blobs.delete_blob(str(commit.get("relative_path", "")))
		_active_request_flags &= ~REQUEST_OPTIMIZE
		_reset_optimization_state()
		optimization_failed.emit(finished_id, NotLightL10n.text("audio.optimize.register_failed"))
		_start_required_stage()
		return
	var old_relpath: String = str(previous_optimized.get("blob_relpath", ""))
	if not old_relpath.is_empty() and old_relpath != str(commit.get("relative_path", "")):
		library.delete_blob_if_unreferenced_path(old_relpath)

	var original_size: int = _variant_size(state, VARIANT_ORIGINAL)
	var saved_bytes: int = maxi(0, original_size - output_size)
	_remove_file(playback_cache_path(finished_id))
	_invalidate_metadata(finished_id)
	_active_request_flags &= ~REQUEST_OPTIMIZE
	_clear_failed_flag(finished_id, REQUEST_OPTIMIZE)
	var state_copy: Dictionary = state.duplicate(true)
	_reset_optimization_state()
	var final_path: String = resolve_playback_path(finished_id, false)
	optimization_progress.emit(finished_id, 1.0, NotLightL10n.text("audio.optimize.done"))
	variant_state_changed.emit(finished_id, state_copy)
	playback_variant_changed.emit(finished_id, final_path, VARIANT_OPTIMIZED)
	optimization_completed.emit(finished_id, final_path, saved_bytes)
	_start_required_stage()


func _finish_active_stage(exit_code: int) -> void:
	var finished_stage: int = _active_stage
	_active_pid = -1
	_active_stage = STAGE_NONE
	if finished_stage == STAGE_OPTIMIZE:
		_finish_optimization_stage(exit_code)
		return
	var stage_succeeded: bool = exit_code == 0 and _promote_stage_output(finished_stage)
	if not stage_succeeded:
		_remove_partial_stage_output(finished_stage)
		if finished_stage == STAGE_WAVEFORM:
			# Waveforms are decoration. A failed image derivation must never poison
			# a later playback request for the same asset.
			_fail_active_requests(REQUEST_WAVEFORM, "", false)
		else:
			var message: String = (
				NotLightL10n.text("audio.error.ffmpeg_exit", {"code": exit_code})
				if exit_code != 0
				else NotLightL10n.text("audio.error.ffmpeg_output")
			)
			_fail_active_requests(REQUEST_PLAYBACK, message, true)
		_start_required_stage()
		return
	if finished_stage == STAGE_TRANSCODE:
		_active_request_flags &= ~REQUEST_PLAYBACK
		playback_ready.emit(_active_asset_id, resolve_playback_path(_active_asset_id, false))
	elif finished_stage == STAGE_WAVEFORM:
		_active_request_flags &= ~REQUEST_WAVEFORM
		_waveform_cache.erase(_active_asset_id)
		_remove_waveform_cache_order_entry(_active_asset_id)
		_queue_waveform_texture_load(_active_asset_id)
	_start_required_stage()


func _stage_temp_path(stage: int) -> String:
	if _active_asset_id.is_empty():
		return ""
	match stage:
		STAGE_TRANSCODE:
			return _cache_dir(_active_asset_id).path_join(PLAYBACK_TEMP_FILE)
		STAGE_WAVEFORM:
			return _cache_dir(_active_asset_id).path_join(WAVEFORM_TEMP_FILE)
		_:
			return ""


func _stage_final_path(stage: int) -> String:
	if _active_asset_id.is_empty():
		return ""
	match stage:
		STAGE_TRANSCODE:
			return playback_cache_path(_active_asset_id)
		STAGE_WAVEFORM:
			return waveform_cache_path(_active_asset_id)
		_:
			return ""


func _promote_stage_output(stage: int) -> bool:
	var temporary_path: String = _stage_temp_path(stage)
	var final_path: String = _stage_final_path(stage)
	if temporary_path.is_empty() or final_path.is_empty() or not _is_nonempty_file(temporary_path):
		return false
	_remove_file(final_path)
	var rename_error: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary_path),
		ProjectSettings.globalize_path(final_path)
	)
	if rename_error != OK:
		return false
	return _is_nonempty_file(final_path)


func _remove_partial_stage_output(stage: int) -> void:
	_remove_file(_stage_temp_path(stage))


func _remove_file(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _is_nonempty_file(path: String) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	return file != null and file.get_length() > 0


func _on_library_import_finished(asset_id: String, _duplicate: bool) -> void:
	if library == null:
		return
	var asset: Dictionary = library.get_asset(asset_id)
	if not asset.is_empty() and int(asset.get("kind", AssetKinds.OTHER)) == AssetKinds.AUDIO:
		_metadata_cache.erase(asset_id)
		_failed_request_flags.erase(asset_id)
		# Library import itself stays cheap. Derived playback/waveform work starts
		# only when the asset is placed on a board or a player explicitly asks for it.


func _needs_derived_playback(asset: Dictionary, source_path: String) -> bool:
	return _requires_compatibility_playback(asset, source_path)


func _requires_compatibility_playback(asset: Dictionary, source_path: String) -> bool:
	var extension: String = str(asset.get("extension", source_path.get_extension())).to_lower()
	if not NATIVE_EXTENSIONS.has(extension):
		return true
	if extension != "ogg":
		return false
	# Godot's runtime loader here is AudioStreamOggVorbis. An .ogg container
	# reported by ffprobe as Opus/another codec needs a disposable Vorbis bridge.
	var asset_id: String = str(asset.get("id", ""))
	var metadata: Dictionary = _metadata_cache.get(asset_id, {}) as Dictionary
	var codec: String = str(metadata.get("audio_codec", "")).to_lower()
	return not codec.is_empty() and codec != "vorbis"


func _ensure_audio_state(asset_id: String, asset: Dictionary) -> Dictionary:
	var metadata: Dictionary = asset.get("metadata", {}) as Dictionary
	var state: Dictionary = metadata.get("audio", {}) as Dictionary
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
		metadata["audio"] = state
	if not state.has("preferred_variant"):
		state["preferred_variant"] = VARIANT_OPTIMIZED if variants.has(VARIANT_OPTIMIZED) else VARIANT_ORIGINAL
	return state


func _save_audio_state(asset_id: String, asset: Dictionary, state: Dictionary) -> bool:
	if library == null:
		return false
	var metadata: Dictionary = asset.get("metadata", {}) as Dictionary
	metadata["audio"] = state.duplicate(true)
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


func _invalidate_metadata(asset_id: String) -> void:
	_metadata_cache.erase(asset_id)
	var path: String = _metadata_path(asset_id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _cleanup_optimization_files() -> void:
	_remove_file(_active_optimization_working)
	_remove_file(_active_optimization_progress_file)
	_reset_optimization_state()


func _reset_optimization_state() -> void:
	_active_optimization_input = ""
	_active_optimization_working = ""
	_active_optimization_progress_file = ""
	_active_optimization_duration = 0.0
	_active_optimization_last_progress = -1.0


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


func _ffmpeg_available() -> bool:
	if _ffmpeg_available_state < 0:
		_ffmpeg_available_state = 1 if FFmpegTools.is_ffmpeg_available() else 0
	return _ffmpeg_available_state == 1


func _ffprobe_available() -> bool:
	if _ffprobe_available_state < 0:
		_ffprobe_available_state = 1 if FFmpegTools.is_ffprobe_available() else 0
	return _ffprobe_available_state == 1


func _cache_dir(asset_id: String) -> String:
	if library == null:
		return ""
	return library.blobs.cache_path_for_asset(asset_id)


func _ensure_cache_dir(asset_id: String) -> bool:
	var path: String = _cache_dir(asset_id)
	if path.is_empty():
		return false
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path)) == OK


func _metadata_path(asset_id: String) -> String:
	return _cache_dir(asset_id).path_join(META_FILE)


func _load_metadata_file(asset_id: String) -> Dictionary:
	var path: String = _metadata_path(asset_id)
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _save_metadata_file(asset_id: String, metadata: Dictionary) -> void:
	if not _ensure_cache_dir(asset_id):
		return
	var file: FileAccess = FileAccess.open(_metadata_path(asset_id), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(metadata, "  "))


func _fail_active_requests(request_flags: int, message: String, notify_user: bool) -> void:
	if _active_asset_id.is_empty() or request_flags == 0:
		return
	var failed_flags: int = int(_failed_request_flags.get(_active_asset_id, 0))
	_failed_request_flags[_active_asset_id] = failed_flags | request_flags
	_active_request_flags &= ~request_flags
	if notify_user and not message.is_empty():
		preparation_failed.emit(_active_asset_id, message)


func _clear_failed_flag(asset_id: String, request_flag: int) -> void:
	if asset_id.is_empty() or request_flag == 0 or not _failed_request_flags.has(asset_id):
		return
	var next_flags: int = int(_failed_request_flags.get(asset_id, 0)) & ~request_flag
	if next_flags == 0:
		_failed_request_flags.erase(asset_id)
	else:
		_failed_request_flags[asset_id] = next_flags


func _clear_active() -> void:
	_active_asset_id = ""
	_active_request_flags = 0
	_active_stage = STAGE_NONE
	_active_pid = -1
	_reset_optimization_state()
	if _queue_asset_ids.is_empty() and _waveform_texture_queue.is_empty():
		set_process(false)
