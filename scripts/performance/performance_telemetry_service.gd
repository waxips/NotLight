# SPDX-License-Identifier: GPL-3.0-or-later
class_name PerformanceTelemetryService
extends Node

signal sample_updated(sample: Dictionary)
signal developer_recording_state_changed(active: bool, path: String)
signal developer_diagnostics_error(message: String)

const FPS_SAMPLE_INTERVAL: float = 0.20
const WINDOWS_PROBE_MIN_INTERVAL: float = 1.5
const PROBE_TIMEOUT_SECONDS: float = 8.0
const DIAGNOSTICS_DIR: String = "user://notlight/diagnostics"
const DIAGNOSTICS_TRACE_SCHEMA: String = "notlight.diagnostics.trace.v1"
const DIAGNOSTICS_REPORT_SCHEMA: String = "notlight.diagnostics.report.v1"
const DIAGNOSTICS_FLUSH_INTERVAL_MSEC: int = 5000

var settings: AppSettingsStore
var _fps_timer: Timer
var _system_timer: Timer
var _last_sample: Dictionary = {}
var _probe_pid: int = -1
var _probe_path: String = ""
var _probe_started_msec: int = 0
var _previous_cpu_seconds: float = -1.0
var _previous_cpu_timestamp_msec: int = 0
var _monitoring_active: bool = false
var _developer_enabled: bool = false
var _developer_counters: Dictionary = {}
var _developer_timings_usec: Dictionary = {}
var _developer_timing_counts: Dictionary = {}
var _developer_timing_max_usec: Dictionary = {}
var _developer_gauges: Dictionary = {}
var _developer_session_counters: Dictionary = {}
var _developer_session_timing_max_usec: Dictionary = {}
var _developer_last_sample_frame: int = 0
var _developer_last_sample_msec: int = 0
var _developer_session_started_msec: int = 0
var _developer_frame_delta_sum_ms: float = 0.0
var _developer_frame_delta_max_ms: float = 0.0
var _developer_frame_delta_count: int = 0
var _developer_session_frame_delta_max_ms: float = 0.0
var _developer_context_provider: Callable = Callable()
var _recording_file: FileAccess
var _recording_path: String = ""
var _recording_started_msec: int = 0
var _recording_last_flush_msec: int = 0


func _ready() -> void:
	_fps_timer = Timer.new()
	_fps_timer.name = "PerformanceFpsTimer"
	_fps_timer.one_shot = false
	_fps_timer.wait_time = FPS_SAMPLE_INTERVAL
	_fps_timer.timeout.connect(_sample_fps)
	add_child(_fps_timer)

	_system_timer = Timer.new()
	_system_timer.name = "PerformanceSystemTimer"
	_system_timer.one_shot = false
	_system_timer.wait_time = 1.0
	_system_timer.timeout.connect(_sample_system)
	add_child(_system_timer)
	set_process(true)


func configure(settings_store: AppSettingsStore) -> void:
	settings = settings_store
	if settings != null and not settings.settings_changed.is_connected(_on_settings_changed):
		settings.settings_changed.connect(_on_settings_changed)
	_apply_settings()


func set_monitoring_active(active: bool) -> void:
	if _monitoring_active == active:
		return
	_monitoring_active = active
	if not _monitoring_active:
		_fps_timer.stop()
		_system_timer.stop()
		_developer_counters.clear()
		_developer_timings_usec.clear()
		_developer_timing_counts.clear()
		_developer_timing_max_usec.clear()
		_developer_gauges.clear()
		stop_developer_recording()
		_clear_developer_sample_fields()
		if _probe_pid > 0 and OS.is_process_running(_probe_pid):
			OS.kill(_probe_pid)
		_probe_pid = -1
		_cleanup_probe_file()
		return
	_apply_settings()
	_sample_fps()
	_sample_system()


func snapshot() -> Dictionary:
	return _last_sample.duplicate(true)


func set_developer_context_provider(provider: Callable) -> void:
	_developer_context_provider = provider


func developer_diagnostics_enabled() -> bool:
	return _monitoring_active and _developer_enabled


func record_developer_counter(key: StringName, amount: int = 1) -> void:
	if not developer_diagnostics_enabled() or key == StringName():
		return
	var clean_key: String = String(key)
	_developer_counters[clean_key] = int(_developer_counters.get(clean_key, 0)) + amount
	_developer_session_counters[clean_key] = int(_developer_session_counters.get(clean_key, 0)) + amount


func record_developer_timing_usec(key: StringName, elapsed_usec: int) -> void:
	if not developer_diagnostics_enabled() or key == StringName():
		return
	var clean_key: String = String(key)
	var clean_elapsed: int = maxi(0, elapsed_usec)
	_developer_timings_usec[clean_key] = int(_developer_timings_usec.get(clean_key, 0)) + clean_elapsed
	_developer_timing_counts[clean_key] = int(_developer_timing_counts.get(clean_key, 0)) + 1
	_developer_timing_max_usec[clean_key] = maxi(int(_developer_timing_max_usec.get(clean_key, 0)), clean_elapsed)
	_developer_session_timing_max_usec[clean_key] = maxi(
		int(_developer_session_timing_max_usec.get(clean_key, 0)),
		clean_elapsed
	)


func set_developer_gauge(key: StringName, value: float) -> void:
	if not developer_diagnostics_enabled() or key == StringName():
		return
	_developer_gauges[String(key)] = value


func is_developer_recording() -> bool:
	return _recording_file != null and _recording_file.is_open()


func current_developer_recording_path() -> String:
	return ProjectSettings.globalize_path(_recording_path) if not _recording_path.is_empty() else ""


func diagnostics_folder_absolute() -> String:
	return ProjectSettings.globalize_path(DIAGNOSTICS_DIR)


func prepare_diagnostics_folder() -> String:
	return diagnostics_folder_absolute() if _ensure_diagnostics_directory() else ""


func developer_recording_elapsed_seconds() -> float:
	if not is_developer_recording() or _recording_started_msec <= 0:
		return 0.0
	return float(maxi(0, Time.get_ticks_msec() - _recording_started_msec)) / 1000.0


func reset_developer_session() -> void:
	_developer_counters.clear()
	_developer_timings_usec.clear()
	_developer_timing_counts.clear()
	_developer_timing_max_usec.clear()
	_developer_gauges.clear()
	_developer_session_counters.clear()
	_developer_session_timing_max_usec.clear()
	_reset_developer_frame_interval()
	_developer_session_frame_delta_max_ms = 0.0
	_developer_session_started_msec = Time.get_ticks_msec()
	_developer_last_sample_frame = int(Engine.get_process_frames())
	_developer_last_sample_msec = _developer_session_started_msec
	_clear_developer_sample_fields()


func save_developer_report() -> String:
	if not developer_diagnostics_enabled():
		_emit_diagnostics_error(NotLightL10n.text("developer.diagnostics.disabled"))
		return ""
	if not _ensure_diagnostics_directory():
		return ""
	_merge_developer_context()
	var file_name: String = "notlight_report_%s.txt" % _diagnostics_timestamp_for_filename()
	var user_path: String = DIAGNOSTICS_DIR.path_join(file_name)
	var file: FileAccess = FileAccess.open(user_path, FileAccess.WRITE)
	if file == null:
		_emit_diagnostics_error(NotLightL10n.text("developer.diagnostics.report_create_failed") % user_path)
		return ""
	var sample: Dictionary = snapshot()
	var metadata: Dictionary = _diagnostics_metadata()
	file.store_line(NotLightL10n.text("developer.diagnostics.report.title"))
	file.store_line(NotLightL10n.text("developer.diagnostics.report.schema") % DIAGNOSTICS_REPORT_SCHEMA)
	file.store_line(NotLightL10n.text("developer.diagnostics.report.created") % str(metadata.get("created_at_local", "")))
	file.store_line(NotLightL10n.text("developer.diagnostics.report.project") % str(metadata.get("project", "")))
	file.store_line(NotLightL10n.text("developer.diagnostics.report.build") % str(metadata.get("build", "")))
	file.store_line(NotLightL10n.text("developer.diagnostics.report.godot") % str(metadata.get("godot_version", "")))
	file.store_line(NotLightL10n.text("developer.diagnostics.report.os") % str(metadata.get("os", "")))
	file.store_line(NotLightL10n.text("developer.diagnostics.report.cpu") % [
		str(metadata.get("cpu", "")),
		int(metadata.get("cpu_cores", 0)),
	])
	file.store_line("")
	file.store_line(NotLightL10n.text("developer.diagnostics.report.metric_notes"))
	file.store_line(NotLightL10n.text("developer.diagnostics.report.note_rates"))
	file.store_line(NotLightL10n.text("developer.diagnostics.report.note_max"))
	file.store_line(NotLightL10n.text("developer.diagnostics.report.note_lod"))
	file.store_line("")
	file.store_line(NotLightL10n.text("developer.diagnostics.report.metadata_json"))
	file.store_line(JSON.stringify(metadata))
	file.store_line("")
	file.store_line(NotLightL10n.text("developer.diagnostics.report.current_snapshot"))
	for key: String in _sorted_dictionary_keys(sample):
		file.store_line("%s = %s" % [key, _diagnostic_value_to_text(sample.get(key))])
	file.store_line("")
	file.store_line(NotLightL10n.text("developer.diagnostics.report.machine_snapshot"))
	file.store_line(JSON.stringify(sample))
	file.close()
	return ProjectSettings.globalize_path(user_path)


func start_developer_recording() -> String:
	if is_developer_recording():
		return current_developer_recording_path()
	if not developer_diagnostics_enabled():
		_emit_diagnostics_error(NotLightL10n.text("developer.diagnostics.disabled"))
		return ""
	if not _ensure_diagnostics_directory():
		return ""
	# A trace should describe exactly the interaction the user is about to record.
	# Reset session maxima/counters here so an old hitch from before pressing Record
	# cannot be mistaken for a hitch inside this trace.
	reset_developer_session()
	var file_name: String = "notlight_trace_%s.txt" % _diagnostics_timestamp_for_filename()
	_recording_path = DIAGNOSTICS_DIR.path_join(file_name)
	_recording_file = FileAccess.open(_recording_path, FileAccess.WRITE)
	if _recording_file == null:
		var failed_path: String = _recording_path
		_recording_path = ""
		_emit_diagnostics_error(NotLightL10n.text("developer.diagnostics.trace_create_failed") % failed_path)
		return ""
	_recording_started_msec = Time.get_ticks_msec()
	_recording_last_flush_msec = _recording_started_msec
	var metadata: Dictionary = _diagnostics_metadata()
	metadata["schema"] = DIAGNOSTICS_TRACE_SCHEMA
	metadata["sample_interval_seconds"] = FPS_SAMPLE_INTERVAL
	_recording_file.store_line(NotLightL10n.text("developer.diagnostics.trace.header"))
	_recording_file.store_line(NotLightL10n.text("developer.diagnostics.trace.rates"))
	_recording_file.store_line(JSON.stringify({"meta": metadata}))
	_merge_developer_context()
	_append_recording_sample(snapshot())
	_recording_file.flush()
	developer_recording_state_changed.emit(true, current_developer_recording_path())
	return current_developer_recording_path()


func stop_developer_recording() -> String:
	if _recording_file == null:
		return current_developer_recording_path()
	var absolute_path: String = current_developer_recording_path()
	if _recording_file.is_open():
		_recording_file.store_line(JSON.stringify({
			"end": {
				"elapsed_msec": maxi(0, Time.get_ticks_msec() - _recording_started_msec),
				"ended_at_local": Time.get_datetime_string_from_system(false, false),
			}
		}))
		_recording_file.flush()
		_recording_file.close()
	_recording_file = null
	_recording_path = ""
	_recording_started_msec = 0
	_recording_last_flush_msec = 0
	developer_recording_state_changed.emit(false, absolute_path)
	return absolute_path


func metric_supported(metric: String) -> bool:
	match metric:
		"fps", "ram", "vram":
			return true
		"cpu":
			return OS.get_name() == "Windows"
		"gpu":
			return false
		_:
			return false


func _process(delta: float) -> void:
	if developer_diagnostics_enabled():
		_record_developer_frame_delta(delta)
	if _probe_pid <= 0:
		return
	if OS.is_process_running(_probe_pid):
		if Time.get_ticks_msec() - _probe_started_msec > int(PROBE_TIMEOUT_SECONDS * 1000.0):
			OS.kill(_probe_pid)
			_finish_windows_probe(false)
		return
	_finish_windows_probe(true)


func _exit_tree() -> void:
	stop_developer_recording()
	if _probe_pid > 0 and OS.is_process_running(_probe_pid):
		OS.kill(_probe_pid)
	_probe_pid = -1
	_cleanup_probe_file()


func _on_settings_changed(_snapshot: Dictionary) -> void:
	_apply_settings()


func _apply_settings() -> void:
	var was_developer_enabled: bool = _developer_enabled
	_developer_enabled = settings.developer_diagnostics_enabled if settings != null else false
	# Settings can change between FPS samples. Never carry partial interval counts
	# across that boundary because their per-frame rate would be misleading.
	_developer_counters.clear()
	_developer_timings_usec.clear()
	_developer_timing_counts.clear()
	_developer_timing_max_usec.clear()
	_reset_developer_frame_interval()
	if not _developer_enabled:
		stop_developer_recording()
		_developer_gauges.clear()
		_developer_session_counters.clear()
		_developer_session_timing_max_usec.clear()
		_developer_session_frame_delta_max_ms = 0.0
		_developer_session_started_msec = 0
		_clear_developer_sample_fields()
	elif not was_developer_enabled:
		reset_developer_session()
	_developer_last_sample_frame = int(Engine.get_process_frames())
	_developer_last_sample_msec = Time.get_ticks_msec()
	if not _monitoring_active:
		_fps_timer.stop()
		_system_timer.stop()
		return
	var show_fps: bool = (settings.show_fps or settings.developer_diagnostics_enabled) if settings != null else true
	var show_system: bool = true
	if settings != null:
		# Developer reports should remain self-contained even when the ordinary HUD
		# counters are hidden. Keep the slower system sampler active only while the
		# opt-in diagnostics mode is enabled.
		show_system = (
			settings.developer_diagnostics_enabled
			or settings.show_ram
			or settings.show_cpu
			or settings.show_gpu
			or settings.show_vram
		)
	if show_fps:
		_fps_timer.wait_time = FPS_SAMPLE_INTERVAL
		if _fps_timer.is_stopped():
			_fps_timer.start()
	else:
		_fps_timer.stop()
	if show_system:
		var interval: float = settings.monitor_interval_seconds if settings != null else 1.0
		_system_timer.wait_time = clampf(interval, 0.5, 5.0)
		if _system_timer.is_stopped():
			_system_timer.start()
	else:
		_system_timer.stop()


func _sample_fps() -> void:
	if not _monitoring_active:
		return
	var fps: float = float(Performance.get_monitor(Performance.TIME_FPS))
	_last_sample["fps"] = fps
	_last_sample["frame_ms"] = 1000.0 / fps if fps > 0.001 else 0.0
	_last_sample["process_ms"] = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_last_sample["physics_process_ms"] = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_last_sample["timestamp_msec"] = Time.get_ticks_msec()
	_sample_developer_metrics()
	_merge_developer_context()
	var current_snapshot: Dictionary = snapshot()
	sample_updated.emit(current_snapshot)
	_append_recording_sample(current_snapshot)


func _sample_system() -> void:
	if not _monitoring_active:
		return
	var uses_windows_process_probe: bool = (
		OS.get_name() == "Windows"
		and settings != null
		and (settings.developer_diagnostics_enabled or settings.show_cpu or settings.show_ram)
	)
	# On Windows the asynchronous platform probe reports the process WorkingSet64,
	# which is the user-facing "RAM process" metric. Do not overwrite that stable
	# value every timer tick with Godot's allocator-only static-memory counter while
	# a new probe is in flight; doing so made the HUD oscillate between two different
	# definitions of memory usage. Before the first probe result, static memory is a
	# bounded fallback only.
	if not uses_windows_process_probe or not _last_sample.has("ram_bytes"):
		var ram_bytes: int = OS.get_static_memory_usage()
		if ram_bytes <= 0:
			ram_bytes = int(Performance.get_monitor(Performance.MEMORY_STATIC))
		_last_sample["ram_bytes"] = maxi(0, ram_bytes)
	_last_sample["vram_bytes"] = maxi(0, int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)))
	_last_sample["cpu_percent"] = float(_last_sample.get("cpu_percent", -1.0))
	_last_sample["gpu_percent"] = -1.0
	_last_sample["timestamp_msec"] = Time.get_ticks_msec()
	_merge_developer_context()
	sample_updated.emit(snapshot())
	_maybe_start_platform_probe()


func _sample_developer_metrics() -> void:
	if not _developer_enabled:
		return
	_clear_developer_interval_sample_fields()
	var current_frame: int = int(Engine.get_process_frames())
	var current_msec: int = Time.get_ticks_msec()
	var frame_count: int = maxi(1, current_frame - _developer_last_sample_frame)
	var elapsed_msec: int = maxi(1, current_msec - _developer_last_sample_msec)
	var elapsed_seconds: float = float(elapsed_msec) / 1000.0
	_developer_last_sample_frame = current_frame
	_developer_last_sample_msec = current_msec
	_last_sample["dev_sample_frames"] = frame_count
	_last_sample["dev_sample_interval_ms"] = elapsed_msec
	var measured_frame_count: int = maxi(1, _developer_frame_delta_count)
	_last_sample["dev_frame_delta_avg_ms"] = _developer_frame_delta_sum_ms / float(measured_frame_count)
	_last_sample["dev_frame_delta_max_ms"] = _developer_frame_delta_max_ms
	_last_sample["dev_session_frame_delta_max_ms"] = _developer_session_frame_delta_max_ms
	_last_sample["dev_session_elapsed_seconds"] = (
		float(maxi(0, current_msec - _developer_session_started_msec)) / 1000.0
		if _developer_session_started_msec > 0
		else 0.0
	)
	for raw_key: Variant in _developer_counters.keys():
		var key: String = str(raw_key)
		var count: int = int(_developer_counters.get(key, 0))
		_last_sample["dev_%s_per_frame" % key] = float(count) / float(frame_count)
		_last_sample["dev_%s_per_second" % key] = float(count) / elapsed_seconds
	for raw_key: Variant in _developer_timings_usec.keys():
		var key: String = str(raw_key)
		var total_usec: int = int(_developer_timings_usec.get(key, 0))
		var timing_count: int = maxi(1, int(_developer_timing_counts.get(key, 0)))
		_last_sample["dev_%s_ms_per_frame" % key] = float(total_usec) / 1000.0 / float(frame_count)
		_last_sample["dev_%s_ms_per_second" % key] = float(total_usec) / 1000.0 / elapsed_seconds
		_last_sample["dev_%s_avg_ms" % key] = float(total_usec) / 1000.0 / float(timing_count)
		_last_sample["dev_%s_max_ms" % key] = float(int(_developer_timing_max_usec.get(key, 0))) / 1000.0
	for raw_key: Variant in _developer_gauges.keys():
		var key: String = str(raw_key)
		_last_sample["dev_%s" % key] = float(_developer_gauges.get(key, 0.0))
	for raw_key: Variant in _developer_session_counters.keys():
		var key: String = str(raw_key)
		_last_sample["dev_session_%s_total" % key] = int(_developer_session_counters.get(key, 0))
	for raw_key: Variant in _developer_session_timing_max_usec.keys():
		var key: String = str(raw_key)
		_last_sample["dev_session_%s_max_ms" % key] = float(int(_developer_session_timing_max_usec.get(key, 0))) / 1000.0
	_developer_counters.clear()
	_developer_timings_usec.clear()
	_developer_timing_counts.clear()
	_developer_timing_max_usec.clear()
	_reset_developer_frame_interval()


func _record_developer_frame_delta(delta: float) -> void:
	var frame_ms: float = maxf(0.0, delta * 1000.0)
	_developer_frame_delta_sum_ms += frame_ms
	_developer_frame_delta_max_ms = maxf(_developer_frame_delta_max_ms, frame_ms)
	_developer_frame_delta_count += 1
	_developer_session_frame_delta_max_ms = maxf(_developer_session_frame_delta_max_ms, frame_ms)
	if frame_ms >= 25.0:
		record_developer_counter(&"hitch_25ms")
	if frame_ms >= 33.0:
		record_developer_counter(&"hitch_33ms")
	if frame_ms >= 50.0:
		record_developer_counter(&"hitch_50ms")
	if frame_ms >= 100.0:
		record_developer_counter(&"hitch_100ms")


func _reset_developer_frame_interval() -> void:
	_developer_frame_delta_sum_ms = 0.0
	_developer_frame_delta_max_ms = 0.0
	_developer_frame_delta_count = 0


func _clear_developer_interval_sample_fields() -> void:
	var keys_to_remove: Array[String] = []
	for raw_key: Variant in _last_sample.keys():
		var key: String = str(raw_key)
		if not key.begins_with("dev_"):
			continue
		if (
			key.ends_with("_per_frame")
			or key.ends_with("_per_second")
			or key.ends_with("_avg_ms")
			or key.ends_with("_max_ms")
			or key in ["dev_sample_frames", "dev_sample_interval_ms"]
		):
			keys_to_remove.append(key)
	for key: String in keys_to_remove:
		_last_sample.erase(key)


func _clear_developer_sample_fields() -> void:
	var keys_to_remove: Array[String] = []
	for raw_key: Variant in _last_sample.keys():
		var key: String = str(raw_key)
		if key.begins_with("dev_"):
			keys_to_remove.append(key)
	for key: String in keys_to_remove:
		_last_sample.erase(key)


func _merge_developer_context() -> void:
	if not _developer_enabled or not _developer_context_provider.is_valid():
		return
	var raw_context: Variant = _developer_context_provider.call()
	if raw_context is not Dictionary:
		return
	var context: Dictionary = raw_context as Dictionary
	for raw_key: Variant in context.keys():
		var key: String = str(raw_key)
		if not key.begins_with("dev_"):
			key = "dev_%s" % key
		_last_sample[key] = context.get(raw_key)


func _append_recording_sample(sample: Dictionary) -> void:
	if _recording_file == null or not _recording_file.is_open():
		return
	var elapsed_msec: int = maxi(0, Time.get_ticks_msec() - _recording_started_msec)
	var record: Dictionary = sample.duplicate(true)
	record["trace_elapsed_msec"] = elapsed_msec
	_recording_file.store_line(JSON.stringify(record))
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _recording_last_flush_msec >= DIAGNOSTICS_FLUSH_INTERVAL_MSEC:
		_recording_file.flush()
		_recording_last_flush_msec = now_msec


func _ensure_diagnostics_directory() -> bool:
	var absolute_dir: String = ProjectSettings.globalize_path(DIAGNOSTICS_DIR)
	var error: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
	if error == OK or DirAccess.dir_exists_absolute(absolute_dir):
		return true
	_emit_diagnostics_error(NotLightL10n.text("developer.diagnostics.directory_create_failed") % absolute_dir)
	return false


func _diagnostics_timestamp_for_filename() -> String:
	var wall_time: String = Time.get_datetime_string_from_system(false, false).replace(":", "-").replace("T", "_")
	return "%s_%03d" % [wall_time, Time.get_ticks_msec() % 1000]


func _diagnostics_metadata() -> Dictionary:
	var version_info: Dictionary = Engine.get_version_info()
	return {
		"created_at_local": Time.get_datetime_string_from_system(false, false),
		"project": str(ProjectSettings.get_setting("application/config/name", "NotLight")),
		"build": NotLightL10n.text("developer.diagnostics.build_name"),
		"godot_version": str(version_info.get("string", "")),
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"cpu": OS.get_processor_name(),
		"cpu_cores": OS.get_processor_count(),
	}


func _sorted_dictionary_keys(source: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_key: Variant in source.keys():
		result.append(str(raw_key))
	result.sort()
	return result


func _diagnostic_value_to_text(value: Variant) -> String:
	match typeof(value):
		TYPE_FLOAT:
			return "%.4f" % float(value)
		TYPE_DICTIONARY, TYPE_ARRAY:
			return JSON.stringify(value)
		_:
			return str(value)


func _emit_diagnostics_error(message: String) -> void:
	developer_diagnostics_error.emit(message)
	push_warning(message)


func _maybe_start_platform_probe() -> void:
	if settings == null or _probe_pid > 0:
		return
	if OS.get_name() != "Windows":
		return
	if not settings.developer_diagnostics_enabled and not settings.show_cpu and not settings.show_ram:
		return
	var now: int = Time.get_ticks_msec()
	if _previous_cpu_timestamp_msec > 0 and now - _previous_cpu_timestamp_msec < int(WINDOWS_PROBE_MIN_INTERVAL * 1000.0):
		return
	_probe_path = "user://notlight/perf_probe_%d.txt" % OS.get_process_id()
	var absolute_probe: String = ProjectSettings.globalize_path(_probe_path)
	if FileAccess.file_exists(_probe_path):
		DirAccess.remove_absolute(absolute_probe)
	var script: String = (
		"$p=Get-Process -Id %d -ErrorAction SilentlyContinue; "
		+ "if($null -ne $p){('%s|%s' -f [double]$p.CPU,[long]$p.WorkingSet64) | Set-Content -LiteralPath '%s' -Encoding ascii}"
	) % [OS.get_process_id(), "{0:R}", "{1}", absolute_probe.replace("'", "''")]
	var args: PackedStringArray = PackedStringArray([
		"-NoLogo",
		"-NoProfile",
		"-NonInteractive",
		"-WindowStyle",
		"Hidden",
		"-Command",
		script,
	])
	_probe_pid = OS.create_process("powershell.exe", args, false)
	if _probe_pid <= 0:
		_probe_pid = -1
		return
	_probe_started_msec = now


func _finish_windows_probe(read_result: bool) -> void:
	_probe_pid = -1
	if not read_result or _probe_path.is_empty() or not FileAccess.file_exists(_probe_path):
		_cleanup_probe_file()
		return
	var file: FileAccess = FileAccess.open(_probe_path, FileAccess.READ)
	if file == null:
		_cleanup_probe_file()
		return
	var line: String = file.get_line().strip_edges()
	file.close()
	_cleanup_probe_file()
	var parts: PackedStringArray = line.split("|", false, 2)
	if parts.size() != 2:
		return
	var cpu_seconds: float = float(parts[0])
	var working_set: int = int(parts[1])
	var now: int = Time.get_ticks_msec()
	var cpu_percent: float = -1.0
	if _previous_cpu_seconds >= 0.0 and _previous_cpu_timestamp_msec > 0 and now > _previous_cpu_timestamp_msec:
		var elapsed_seconds: float = float(now - _previous_cpu_timestamp_msec) / 1000.0
		var cores: int = maxi(1, OS.get_processor_count())
		cpu_percent = clampf((cpu_seconds - _previous_cpu_seconds) / elapsed_seconds / float(cores) * 100.0, 0.0, 100.0)
	_previous_cpu_seconds = cpu_seconds
	_previous_cpu_timestamp_msec = now
	_last_sample["ram_bytes"] = maxi(0, working_set)
	_last_sample["cpu_percent"] = cpu_percent
	_last_sample["timestamp_msec"] = now
	sample_updated.emit(snapshot())


func _cleanup_probe_file() -> void:
	if not _probe_path.is_empty() and FileAccess.file_exists(_probe_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_probe_path))
	_probe_path = ""
