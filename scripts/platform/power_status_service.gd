# SPDX-License-Identifier: GPL-3.0-or-later
class_name PowerStatusService
extends Node

signal status_updated(snapshot: Dictionary)

const POLL_INTERVAL_SECONDS: float = 30.0
const QUERY_TIMEOUT_MSEC: int = 4500
const OUTPUT_LIMIT_BYTES: int = 8 * 1024

var _settings: AppSettingsStore
var _provider: PowerStatusProvider
var _runner: SidecarProcessRunner = SidecarProcessRunner.new()
var _active: bool = false
var _query_running: bool = false
var _elapsed: float = POLL_INTERVAL_SECONDS
var _snapshot: Dictionary = {"supported": false, "present": false, "percent": -1, "charging": false}


func _ready() -> void:
	if OS.has_feature("windows"):
		_provider = WindowsPowerStatusProvider.new()
	else:
		_provider = PowerStatusProvider.new()
	set_process(false)


func _exit_tree() -> void:
	_runner.cancel()
	_runner.close()


func configure(settings_store: AppSettingsStore) -> void:
	if _settings != null and _settings.settings_changed.is_connected(_on_settings_changed):
		_settings.settings_changed.disconnect(_on_settings_changed)
	_settings = settings_store
	if _settings != null and not _settings.settings_changed.is_connected(_on_settings_changed):
		_settings.settings_changed.connect(_on_settings_changed)
	_refresh_processing()


func set_monitoring_active(value: bool) -> void:
	if _active == value:
		return
	_active = value
	_elapsed = POLL_INTERVAL_SECONDS
	if not _active and _query_running:
		_runner.cancel()
	_refresh_processing()


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func _process(delta: float) -> void:
	if _query_running:
		_poll_query()
		return
	_elapsed += maxf(0.0, delta)
	if _elapsed >= POLL_INTERVAL_SECONDS:
		_elapsed = 0.0
		_start_query()


func _start_query() -> void:
	if not _should_monitor() or _provider == null or not _provider.is_supported():
		return
	if not _runner.start(_provider.executable_path(), _provider.arguments(), QUERY_TIMEOUT_MSEC, OUTPUT_LIMIT_BYTES):
		_snapshot = {"supported": true, "present": false, "percent": -1, "charging": false}
		status_updated.emit(snapshot())
		return
	_query_running = true


func _poll_query() -> void:
	var result: Dictionary = _runner.poll()
	if not bool(result.get("finished", false)):
		return
	_query_running = false
	if bool(result.get("cancelled", false)):
		_refresh_processing()
		return
	if bool(result.get("timed_out", false)):
		_snapshot = {"supported": true, "present": false, "percent": -1, "charging": false}
	else:
		_snapshot = _provider.parse_output(str(result.get("stdout", "")), str(result.get("stderr", "")), int(result.get("exit_code", -1)))
	status_updated.emit(snapshot())
	_refresh_processing()


func _on_settings_changed(_settings_snapshot: Dictionary) -> void:
	_elapsed = POLL_INTERVAL_SECONDS
	if not _should_monitor() and _query_running:
		_runner.cancel()
	_refresh_processing()


func _should_monitor() -> bool:
	return (
		_active
		and _settings != null
		and _settings.show_battery
		and _provider != null
		and _provider.is_supported()
	)


func _refresh_processing() -> void:
	set_process(_query_running or _should_monitor())
