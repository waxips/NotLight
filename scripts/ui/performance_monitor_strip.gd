# SPDX-License-Identifier: GPL-3.0-or-later
class_name PerformanceMonitorStrip
extends HBoxContainer

signal visibility_layout_changed

var settings: AppSettingsStore
var telemetry: PerformanceTelemetryService
var power_status: PowerStatusService
var _battery_present: bool = false
var _labels: Dictionary = {}
var _separators: Array[VSeparator] = []
var _maximum_width: float = INF


func _ready() -> void:
	add_theme_constant_override("separation", 5)
	_build_metric("fps", NotLightL10n.text("performance.fps"))
	_build_metric("ram", NotLightL10n.text("performance.ram"))
	_build_metric("cpu", NotLightL10n.text("performance.cpu"))
	_build_metric("gpu", NotLightL10n.text("performance.gpu"))
	_build_metric("vram", NotLightL10n.text("performance.vram"))
	_build_metric("battery", "BAT")


func configure(settings_store: AppSettingsStore, telemetry_service: PerformanceTelemetryService, power_service: PowerStatusService = null) -> void:
	settings = settings_store
	telemetry = telemetry_service
	if power_status != null and power_status.status_updated.is_connected(_on_power_status_updated):
		power_status.status_updated.disconnect(_on_power_status_updated)
	power_status = power_service
	if settings != null and not settings.settings_changed.is_connected(_on_settings_changed):
		settings.settings_changed.connect(_on_settings_changed)
	if telemetry != null and not telemetry.sample_updated.is_connected(_on_sample_updated):
		telemetry.sample_updated.connect(_on_sample_updated)
	if power_status != null and not power_status.status_updated.is_connected(_on_power_status_updated):
		power_status.status_updated.connect(_on_power_status_updated)
	_refresh_visibility()
	if telemetry != null:
		_on_sample_updated(telemetry.snapshot())
	if power_status != null:
		_on_power_status_updated(power_status.snapshot())


func set_maximum_width(value: float) -> void:
	var clean: float = maxf(0.0, value)
	if is_equal_approx(_maximum_width, clean):
		return
	_maximum_width = clean
	_refresh_visibility()


func _build_metric(key: String, fallback_text: String) -> void:
	if not _labels.is_empty():
		var separator: VSeparator = VSeparator.new()
		separator.custom_minimum_size = Vector2(2.0, 24.0)
		add_child(separator)
		_separators.append(separator)
	var label: Label = Label.new()
	label.text = fallback_text
	label.theme_type_variation = "CaptionStrongLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(64.0, 34.0)
	add_child(label)
	_labels[key] = label


func _on_settings_changed(_snapshot: Dictionary) -> void:
	_refresh_visibility()


func _on_sample_updated(sample: Dictionary) -> void:
	_set_text("fps", NotLightL10n.text("monitor.fps", {"value": int(round(float(sample.get("fps", 0.0))))}))
	_set_text("ram", NotLightL10n.text("monitor.ram", {"value": _format_bytes(int(sample.get("ram_bytes", 0)))}))
	_set_optional_percent("cpu", float(sample.get("cpu_percent", -1.0)))
	_set_optional_percent("gpu", float(sample.get("gpu_percent", -1.0)))
	_set_text("vram", NotLightL10n.text("monitor.vram", {"value": _format_bytes(int(sample.get("vram_bytes", 0)))}))


func _on_power_status_updated(snapshot: Dictionary) -> void:
	_battery_present = bool(snapshot.get("present", false))
	if _battery_present:
		var percent: int = clampi(int(snapshot.get("percent", -1)), 0, 100)
		var suffix: String = " ⚡" if bool(snapshot.get("charging", false)) else ""
		_set_text("battery", NotLightL10n.text("monitor.battery", {"value": percent, "suffix": suffix}))
	else:
		_set_text("battery", NotLightL10n.text("monitor.battery_unavailable"))
	_refresh_visibility()


func _set_optional_percent(key: String, value: float) -> void:
	if value < 0.0:
		_set_text(key, NotLightL10n.text("ui.format.unavailable_named") % key.to_upper())
		var unsupported_label: Label = _labels.get(key) as Label
		if unsupported_label != null:
			NotLightL10n.bind_tooltip(unsupported_label, "settings.monitors.unsupported")
		return
	var label: Label = _labels.get(key) as Label
	if label != null:
		label.tooltip_text = ""
	var translation_key: String = "monitor.%s" % key
	_set_text(key, NotLightL10n.text(translation_key, {"value": "%.0f" % value}))


func _set_text(key: String, value: String) -> void:
	var label: Label = _labels.get(key) as Label
	if label != null:
		label.text = value


func _refresh_visibility() -> void:
	if settings == null:
		visible = false
		visibility_layout_changed.emit()
		return
	var keys: Array[String] = ["fps", "ram", "cpu", "gpu", "vram", "battery"]
	var enabled: Dictionary = {
		"fps": settings.show_fps,
		"ram": settings.show_ram,
		"cpu": settings.show_cpu,
		"gpu": settings.show_gpu,
		"vram": settings.show_vram,
		"battery": settings.show_battery and _battery_present,
	}
	# Keep user preferences intact; only compact the strip visually when the
	# current viewport cannot fit every metric. Lower-priority metrics collapse
	# first while FPS remains whenever it was requested.
	var visible_keys: Array[String] = []
	for key: String in keys:
		if bool(enabled.get(key, false)):
			visible_keys.append(key)
	var estimated_width: float = float(visible_keys.size()) * 70.0 + float(maxi(0, visible_keys.size() - 1)) * 7.0
	var removal_order: Array[String] = ["gpu", "vram", "cpu", "battery", "ram"]
	for removable: String in removal_order:
		if estimated_width <= _maximum_width or not visible_keys.has(removable):
			continue
		visible_keys.erase(removable)
		estimated_width = float(visible_keys.size()) * 70.0 + float(maxi(0, visible_keys.size() - 1)) * 7.0
	for key: String in keys:
		var label: Label = _labels.get(key) as Label
		if label != null:
			label.visible = visible_keys.has(key)
	var separator_index: int = 0
	var have_previous: bool = false
	for index: int in range(keys.size()):
		if index > 0:
			var separator: VSeparator = _separators[separator_index]
			separator_index += 1
			separator.visible = have_previous and visible_keys.has(keys[index])
		if visible_keys.has(keys[index]):
			have_previous = true
	visible = not visible_keys.is_empty()
	visibility_layout_changed.emit()


func _format_bytes(value: int) -> String:
	var bytes: float = float(maxi(0, value))
	if bytes >= 1073741824.0:
		return NotLightL10n.text("ui.format.bytes_gb") % (bytes / 1073741824.0)
	if bytes >= 1048576.0:
		return NotLightL10n.text("ui.format.bytes_mb") % (bytes / 1048576.0)
	if bytes >= 1024.0:
		return NotLightL10n.text("ui.format.bytes_kb") % (bytes / 1024.0)
	return NotLightL10n.text("ui.format.bytes_b") % int(bytes)
