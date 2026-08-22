# SPDX-License-Identifier: GPL-3.0-or-later
class_name AppAudioService
extends Node

signal bundled_tracks_changed(tracks: Array[Dictionary])
signal library_tracks_changed(tracks: Array[Dictionary])
signal background_track_changed(selection: Dictionary)
signal ducking_changed(active: bool)

const FOREGROUND_MEDIA_GROUP: StringName = &"notlight_foreground_media"
const BACKGROUND_MUSIC_DIR: String = "res://assets/audio/background"
const SUPPORTED_EXTENSIONS: Array[String] = ["ogg", "mp3", "wav"]
const FEATURE_REFERENCE_OWNER: String = "app.background_music"
const SILENT_DB: float = -60.0
const DUCK_ATTACK_PER_SECOND: float = 14.0
const DUCK_RELEASE_PER_SECOND: float = 4.0

var settings: AppSettingsStore
var library: AssetLibraryService
var audio_media: AudioMediaService

var _background_player: AudioStreamPlayer
var _bundled_tracks: Array[Dictionary] = []
var _active_track_path: String = ""
var _active_asset_id: String = ""
var _registered_asset_id: String = ""
var _ducking: bool = false
var _duck_gain: float = 1.0


func _ready() -> void:
	_background_player = AudioStreamPlayer.new()
	_background_player.name = "BackgroundMusic"
	_background_player.finished.connect(_on_background_finished)
	add_child(_background_player)
	set_process(false)


func configure(settings_store: AppSettingsStore) -> void:
	if settings != null and settings.settings_changed.is_connected(_on_settings_changed):
		settings.settings_changed.disconnect(_on_settings_changed)
	settings = settings_store
	if settings != null and not settings.settings_changed.is_connected(_on_settings_changed):
		settings.settings_changed.connect(_on_settings_changed)
	refresh_bundled_tracks()
	if settings != null:
		_apply_settings(settings.get_snapshot())
	set_process(true)


func configure_library(library_service: AssetLibraryService, audio_service: AudioMediaService) -> void:
	if library != null and library.library_changed.is_connected(_on_library_changed):
		library.library_changed.disconnect(_on_library_changed)
	if audio_media != null and audio_media.playback_ready.is_connected(_on_audio_playback_ready):
		audio_media.playback_ready.disconnect(_on_audio_playback_ready)
	if audio_media != null and audio_media.playback_variant_changed.is_connected(_on_audio_playback_variant_changed):
		audio_media.playback_variant_changed.disconnect(_on_audio_playback_variant_changed)
	library = library_service
	audio_media = audio_service
	if library != null and not library.library_changed.is_connected(_on_library_changed):
		library.library_changed.connect(_on_library_changed)
	if audio_media != null and not audio_media.playback_ready.is_connected(_on_audio_playback_ready):
		audio_media.playback_ready.connect(_on_audio_playback_ready)
	if audio_media != null and not audio_media.playback_variant_changed.is_connected(_on_audio_playback_variant_changed):
		audio_media.playback_variant_changed.connect(_on_audio_playback_variant_changed)
	_sync_library_reference()
	library_tracks_changed.emit(get_library_tracks())
	if settings != null:
		_apply_background_selection(settings.get_snapshot())


func get_bundled_tracks() -> Array[Dictionary]:
	return _bundled_tracks.duplicate(true)


func get_library_tracks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if library == null or not library.is_available():
		return result
	for asset: Dictionary in library.list_assets("", AssetKinds.AUDIO):
		var asset_id: String = str(asset.get("id", "")).strip_edges()
		if asset_id.is_empty():
			continue
		result.append({
			"asset_id": asset_id,
			"name": str(asset.get("display_name", asset_id)).strip_edges(),
			"extension": str(asset.get("extension", "")).to_lower(),
		})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("name", "")).naturalnocasecmp_to(str(right.get("name", ""))) < 0
	)
	return result


func active_track_path() -> String:
	return _active_track_path


func active_asset_id() -> String:
	return _active_asset_id


func is_ducking() -> bool:
	return _ducking


func apply_live_levels() -> void:
	if settings == null:
		return
	_apply_master_level(settings.audio_master_enabled, settings.audio_master_volume)
	_apply_background_gain()


func refresh_bundled_tracks() -> void:
	var next_tracks: Array[Dictionary] = []
	# ResourceLoader is used instead of raw filesystem enumeration so the same
	# author-bundled resource names remain discoverable after PCK export.
	for file_name: String in ResourceLoader.list_directory(BACKGROUND_MUSIC_DIR):
		if file_name.begins_with("."):
			continue
		var extension: String = file_name.get_extension().to_lower()
		if not SUPPORTED_EXTENSIONS.has(extension):
			continue
		var resource_path: String = BACKGROUND_MUSIC_DIR.path_join(file_name)
		if not ResourceLoader.exists(resource_path):
			continue
		next_tracks.append({
			"path": resource_path,
			"name": _display_name_for_track(file_name),
		})
	next_tracks.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("name", "")).naturalnocasecmp_to(str(right.get("name", ""))) < 0
	)
	_bundled_tracks = next_tracks
	bundled_tracks_changed.emit(get_bundled_tracks())
	if settings != null:
		_sync_library_reference()
		_apply_background_selection(settings.get_snapshot())


func _process(delta: float) -> void:
	var foreground_active: bool = _has_audible_foreground_media()
	if foreground_active != _ducking:
		_ducking = foreground_active
		ducking_changed.emit(_ducking)
	var target_gain: float = 0.0 if _ducking else 1.0
	var speed: float = DUCK_ATTACK_PER_SECOND if target_gain < _duck_gain else DUCK_RELEASE_PER_SECOND
	var next_gain: float = move_toward(_duck_gain, target_gain, maxf(0.0, delta) * speed)
	if not is_equal_approx(next_gain, _duck_gain):
		_duck_gain = next_gain
		_apply_background_gain()


func _on_settings_changed(snapshot: Dictionary) -> void:
	_apply_settings(snapshot)


func _apply_settings(snapshot: Dictionary) -> void:
	_apply_master_level(
		bool(snapshot.get("audio_master_enabled", true)),
		clampf(float(snapshot.get("audio_master_volume", AppSettingsStore.DEFAULT_AUDIO_MASTER_VOLUME)), 0.0, 1.0)
	)
	_sync_library_reference()
	_apply_background_selection(snapshot)
	_apply_background_gain()


func _apply_master_level(enabled: bool, volume: float) -> void:
	var master_index: int = AudioServer.get_bus_index(&"Master")
	if master_index < 0:
		return
	var normalized: float = clampf(volume, 0.0, 1.0)
	AudioServer.set_bus_mute(master_index, not enabled or normalized <= 0.0001)
	AudioServer.set_bus_volume_db(master_index, linear_to_db(maxf(normalized, 0.0001)))


func _apply_background_selection(snapshot: Dictionary) -> void:
	if _background_player == null:
		return
	var music_enabled: bool = bool(snapshot.get("background_music_enabled", false))
	if not music_enabled:
		_background_player.stop()
		return
	var requested_asset_id: String = str(snapshot.get("background_music_asset_id", "")).strip_edges()
	var requested_path: String = str(snapshot.get("background_music_track", "")).strip_edges()
	var selection: Dictionary = _resolve_selection(requested_path, requested_asset_id)
	var source: String = str(selection.get("source", ""))
	var selected_path: String = str(selection.get("path", ""))
	var selected_asset_id: String = str(selection.get("asset_id", ""))
	if source == "library":
		if selected_asset_id != _active_asset_id or not _active_track_path.is_empty() or _background_player.stream == null:
			_load_library_track(selected_asset_id)
	elif source == "bundled":
		if selected_path != _active_track_path or not _active_asset_id.is_empty() or _background_player.stream == null:
			_load_bundled_track(selected_path)
	else:
		_clear_background_track(selection)
	if _background_player.stream == null:
		_background_player.stop()
		return
	if not _background_player.has_stream_playback():
		_background_player.play()


func _resolve_selection(requested_path: String, requested_asset_id: String) -> Dictionary:
	if not requested_asset_id.is_empty():
		var requested_asset: Dictionary = library.get_asset(requested_asset_id) if library != null else {}
		if not requested_asset.is_empty() and int(requested_asset.get("kind", AssetKinds.OTHER)) == AssetKinds.AUDIO:
			return {"source": "library", "asset_id": requested_asset_id}
		return {"source": "missing_library", "asset_id": requested_asset_id}
	if not requested_path.is_empty():
		for record: Dictionary in _bundled_tracks:
			if str(record.get("path", "")) == requested_path:
				return {"source": "bundled", "path": requested_path}
		return {"source": "missing_bundled", "path": requested_path}
	if not _bundled_tracks.is_empty():
		return {"source": "bundled", "path": str(_bundled_tracks[0].get("path", ""))}
	var library_tracks: Array[Dictionary] = get_library_tracks()
	if not library_tracks.is_empty():
		return {"source": "library", "asset_id": str(library_tracks[0].get("asset_id", ""))}
	return {"source": "none"}


func _load_bundled_track(resource_path: String) -> void:
	_background_player.stop()
	_background_player.stream = null
	_active_track_path = resource_path
	_active_asset_id = ""
	if resource_path.is_empty():
		background_track_changed.emit({"source": "none"})
		return
	var loaded: Resource = load(resource_path)
	var stream: AudioStream = loaded as AudioStream
	if stream == null:
		_active_track_path = ""
		background_track_changed.emit({"source": "missing_bundled", "path": resource_path})
		return
	_background_player.stream = stream
	background_track_changed.emit({"source": "bundled", "path": _active_track_path})


func _load_library_track(asset_id: String) -> void:
	_background_player.stop()
	_background_player.stream = null
	_active_track_path = ""
	_active_asset_id = asset_id.strip_edges()
	if _active_asset_id.is_empty() or audio_media == null:
		background_track_changed.emit({"source": "missing_library", "asset_id": _active_asset_id})
		return
	var stream: AudioStream = audio_media.load_stream(_active_asset_id)
	if stream == null:
		# AudioMediaService may be preparing a compatibility Vorbis cache in the
		# background. playback_ready will retry this exact stable asset_id.
		background_track_changed.emit({"source": "library_preparing", "asset_id": _active_asset_id})
		return
	_background_player.stream = stream
	background_track_changed.emit({"source": "library", "asset_id": _active_asset_id})


func _clear_background_track(selection: Dictionary) -> void:
	if _background_player.stream != null or not _active_track_path.is_empty() or not _active_asset_id.is_empty():
		_background_player.stop()
		_background_player.stream = null
	_active_track_path = ""
	_active_asset_id = ""
	background_track_changed.emit(selection.duplicate(true))


func _apply_background_gain() -> void:
	if _background_player == null:
		return
	var music_volume: float = AppSettingsStore.DEFAULT_BACKGROUND_MUSIC_VOLUME
	if settings != null:
		music_volume = clampf(settings.background_music_volume, 0.0, 1.0)
	_background_player.volume_linear = music_volume * clampf(_duck_gain, 0.0, 1.0)


func _sync_library_reference() -> void:
	if library == null or not library.is_available() or settings == null:
		return
	var effective_asset_id: String = _effective_library_asset_id()
	if effective_asset_id == _registered_asset_id:
		return
	_registered_asset_id = effective_asset_id
	var refs: PackedStringArray = PackedStringArray()
	if not effective_asset_id.is_empty():
		refs.append(effective_asset_id)
	library.set_feature_asset_references(
		FEATURE_REFERENCE_OWNER,
		refs,
		NotLightL10n.text("settings.audio.background_title")
	)


func _effective_library_asset_id() -> String:
	if library == null or not library.is_available() or settings == null:
		return ""
	var requested_asset_id: String = settings.background_music_asset_id.strip_edges()
	if not requested_asset_id.is_empty():
		var requested_asset: Dictionary = library.get_asset(requested_asset_id)
		if not requested_asset.is_empty() and int(requested_asset.get("kind", AssetKinds.OTHER)) == AssetKinds.AUDIO:
			return requested_asset_id
		return ""
	# Automatic mode is ephemeral while music is disabled. Do not pin or prepare a
	# random first Library audio asset until automatic background playback is active.
	if not settings.background_music_enabled:
		return ""
	# An explicit bundled selection, including a currently missing bundled resource,
	# must never be replaced by a Library asset behind the user's back.
	if not settings.background_music_track.strip_edges().is_empty() or not _bundled_tracks.is_empty():
		return ""
	var library_tracks: Array[Dictionary] = get_library_tracks()
	if library_tracks.is_empty():
		return ""
	return str(library_tracks[0].get("asset_id", "")).strip_edges()


func _has_audible_foreground_media() -> bool:
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	for node: Node in tree.get_nodes_in_group(FOREGROUND_MEDIA_GROUP):
		if node == null or not is_instance_valid(node):
			continue
		if node is AudioStreamPlayer:
			var audio_player: AudioStreamPlayer = node as AudioStreamPlayer
			if audio_player == _background_player:
				continue
			if audio_player.has_stream_playback() and not audio_player.stream_paused and audio_player.volume_db > SILENT_DB:
				return true
		elif node is VideoStreamPlayer:
			var video_player: VideoStreamPlayer = node as VideoStreamPlayer
			if video_player.is_playing() and not video_player.paused and video_player.volume > 0.001:
				return true
	return false


func _on_background_finished() -> void:
	if settings == null or _background_player == null or _background_player.stream == null:
		return
	if settings.background_music_enabled:
		_background_player.play()


func _on_library_changed() -> void:
	_sync_library_reference()
	library_tracks_changed.emit(get_library_tracks())
	if settings != null:
		_apply_background_selection(settings.get_snapshot())


func _on_audio_playback_ready(asset_id: String, _playback_path: String) -> void:
	if settings == null or asset_id != _effective_library_asset_id():
		return
	_apply_background_selection(settings.get_snapshot())


func _on_audio_playback_variant_changed(asset_id: String, _playback_path: String, _variant_name: String) -> void:
	if settings == null or asset_id != _effective_library_asset_id():
		return
	# Preferred Library variants are user-controlled. Reload from the media service
	# so background playback follows the same original/optimized choice as the rest
	# of NotLight instead of pinning a stale filesystem path.
	_active_asset_id = ""
	_apply_background_selection(settings.get_snapshot())


func _display_name_for_track(file_name: String) -> String:
	var label: String = file_name.get_basename().replace("_", " ").replace("-", " ").strip_edges()
	while label.contains("  "):
		label = label.replace("  ", " ")
	return label.capitalize() if not label.is_empty() else file_name
