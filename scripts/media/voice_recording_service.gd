# SPDX-License-Identifier: GPL-3.0-or-later
class_name VoiceRecordingService
extends Node

signal recording_started
signal recording_stopped(job_id: String, duration_seconds: float)
signal recording_cancelled
signal recording_failed(message: String)
signal voice_import_finished(job_id: String, asset_id: String, duration_seconds: float, duplicate: bool)
signal voice_import_failed(job_id: String, message: String)

const RECORD_BUS_NAME: String = "NotLight Voice Capture"
const RECORDINGS_DIR: String = "user://notlight/recordings"

var library: AssetLibraryService
var _record_effect: AudioEffectRecord
var _microphone_player: AudioStreamPlayer
var _record_bus_index: int = -1
var _recording_started_msec: int = 0
var _pending_temp_paths: Dictionary = {}
var _pending_durations: Dictionary = {}
var _last_failure_needs_microphone_attention: bool = false


func configure(asset_library: AssetLibraryService) -> void:
	library = asset_library
	if library != null:
		if not library.import_job_finished.is_connected(_on_import_job_finished):
			library.import_job_finished.connect(_on_import_job_finished)
		if not library.import_job_failed.is_connected(_on_import_job_failed):
			library.import_job_failed.connect(_on_import_job_failed)


func is_recording() -> bool:
	return _record_effect != null and _record_effect.is_recording_active()


func elapsed_seconds() -> float:
	if not is_recording() or _recording_started_msec <= 0:
		return 0.0
	return maxf(0.0, float(Time.get_ticks_msec() - _recording_started_msec) / 1000.0)


func audio_input_enabled() -> bool:
	return bool(ProjectSettings.get_setting_with_override(&"audio/driver/enable_input"))


func needs_microphone_attention() -> bool:
	return _last_failure_needs_microphone_attention


func can_open_system_microphone_settings() -> bool:
	# Godot 4.4 does not expose a Windows microphone permission prompt API.
	# Windows desktop access is managed by the OS privacy page instead.
	return OS.get_name() == "Windows"


func open_system_microphone_settings() -> bool:
	if OS.get_name() != "Windows":
		return false
	return OS.shell_open("ms-settings:privacy-microphone") == OK


func start_recording() -> bool:
	if is_recording():
		return true
	if library == null:
		_recording_failed(NotLightL10n.text("voice.error.library_unavailable"))
		return false
	if not audio_input_enabled():
		_recording_failed(NotLightL10n.text("voice.error.input_disabled"), true)
		return false
	if not _ensure_record_bus():
		_recording_failed(NotLightL10n.text("voice.error.input_setup"), true)
		return false
	if _microphone_player == null:
		_microphone_player = AudioStreamPlayer.new()
		_microphone_player.name = "VoiceMicrophoneCapture"
		_microphone_player.stream = AudioStreamMicrophone.new()
		_microphone_player.bus = RECORD_BUS_NAME
		add_child(_microphone_player)
	_microphone_player.play()
	_record_effect.set_recording_active(true)
	_last_failure_needs_microphone_attention = false
	_recording_started_msec = Time.get_ticks_msec()
	recording_started.emit()
	return true


func stop_recording() -> String:
	if not is_recording() or _record_effect == null:
		return ""
	# Snapshot the current sample, then stop capture. Godot's microphone
	# recording example uses this ordering; get_recording() returns the captured
	# AudioStreamWAV while disabling recording immediately afterwards prevents
	# any further accumulation before we persist/import the note.
	var recording: AudioStreamWAV = _record_effect.get_recording()
	_record_effect.set_recording_active(false)
	if _microphone_player != null:
		_microphone_player.stop()
	var duration: float = maxf(0.0, recording.get_length() if recording != null else 0.0)
	_recording_started_msec = 0
	if recording == null or duration < 0.08:
		_recording_failed(NotLightL10n.text("voice.error.too_short"))
		return ""
	if not _recording_has_signal(recording):
		_recording_failed(NotLightL10n.text("voice.error.no_signal"), true)
		return ""
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RECORDINGS_DIR)) != OK:
		_recording_failed(NotLightL10n.text("voice.error.temp_dir"))
		return ""
	var stamp: String = Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var path: String = RECORDINGS_DIR.path_join("voice_%s_%d.wav" % [stamp, Time.get_ticks_msec()])
	var save_error: Error = recording.save_to_wav(path)
	if save_error != OK or not FileAccess.file_exists(path):
		_recording_failed(NotLightL10n.text("voice.error.save"))
		return ""
	var jobs: PackedStringArray = library.import_files(PackedStringArray([path]))
	if jobs.is_empty():
		_delete_temp(path)
		_recording_failed(library.get_last_error() if not library.get_last_error().is_empty() else NotLightL10n.text("voice.error.import"))
		return ""
	var job_id: String = jobs[0]
	_pending_temp_paths[job_id] = path
	_pending_durations[job_id] = duration
	recording_stopped.emit(job_id, duration)
	return job_id


func cancel_recording() -> void:
	if _record_effect != null and _record_effect.is_recording_active():
		_record_effect.set_recording_active(false)
	if _microphone_player != null:
		_microphone_player.stop()
	_recording_started_msec = 0
	recording_cancelled.emit()


func _ensure_record_bus() -> bool:
	_record_bus_index = AudioServer.get_bus_index(RECORD_BUS_NAME)
	if _record_bus_index < 0:
		AudioServer.add_bus()
		_record_bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_record_bus_index, RECORD_BUS_NAME)
	if _record_bus_index < 0:
		return false
	AudioServer.set_bus_mute(_record_bus_index, true)
	for effect_index: int in range(AudioServer.get_bus_effect_count(_record_bus_index)):
		var existing: AudioEffect = AudioServer.get_bus_effect(_record_bus_index, effect_index)
		if existing is AudioEffectRecord:
			_record_effect = existing as AudioEffectRecord
			return true
	_record_effect = AudioEffectRecord.new()
	_record_effect.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(_record_bus_index, _record_effect, 0)
	return AudioServer.get_bus_effect(_record_bus_index, 0) == _record_effect


func _recording_has_signal(recording: AudioStreamWAV) -> bool:
	if recording == null:
		return false
	var data: PackedByteArray = recording.data
	if data.is_empty():
		return false
	# AudioEffectRecord is configured to 16-bit PCM. Sample the buffer rather than
	# scanning every byte so a long voice note is still O(1) at commit time. OS
	# privacy blocks on desktop commonly yield exact digital silence.
	if recording.format == AudioStreamWAV.FORMAT_16_BITS:
		var sample_count: int = int(data.size() / 2)
		var stride_samples: int = maxi(1, int(ceil(float(sample_count) / 4096.0)))
		var sample_index: int = 0
		while sample_index < sample_count:
			if absi(data.decode_s16(sample_index * 2)) > 4:
				return true
			sample_index += stride_samples
		return false
	# Defensive fallback if the record effect format changes in a future build.
	var byte_stride: int = maxi(1, int(ceil(float(data.size()) / 4096.0)))
	for byte_index: int in range(0, data.size(), byte_stride):
		if data[byte_index] != 0:
			return true
	return false


func _on_import_job_finished(job_id: String, asset_id: String, duplicate: bool) -> void:
	if not _pending_temp_paths.has(job_id):
		return
	var duration: float = float(_pending_durations.get(job_id, 0.0))
	var path: String = str(_pending_temp_paths.get(job_id, ""))
	_pending_temp_paths.erase(job_id)
	_pending_durations.erase(job_id)
	_delete_temp(path)
	voice_import_finished.emit(job_id, asset_id, duration, duplicate)


func _on_import_job_failed(job_id: String, _source_path: String, message: String) -> void:
	if not _pending_temp_paths.has(job_id):
		return
	var path: String = str(_pending_temp_paths.get(job_id, ""))
	_pending_temp_paths.erase(job_id)
	_pending_durations.erase(job_id)
	_delete_temp(path)
	voice_import_failed.emit(job_id, message)


func _recording_failed(message: String, microphone_attention: bool = false) -> void:
	_recording_started_msec = 0
	_last_failure_needs_microphone_attention = microphone_attention
	recording_failed.emit(message)


func _delete_temp(path: String) -> void:
	if not path.is_empty() and FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
